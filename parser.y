%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int yylex(void);
void yyerror(const char *s);

/* ---------- quadruple storage ---------- */
enum { K_BIN, K_REL, K_COPY, K_IFF, K_GOTO, K_LABEL };
typedef struct { int kind; char op[4], a1[32], a2[32], res[32]; } Quad;
Quad code[500], opt[500];
int n = 0, on = 0, tcount = 0, lcount = 0;

char *newtemp(void) { char *s = malloc(16); sprintf(s, "t%d", ++tcount); return s; }
void emit(int k, const char *op, const char *a1, const char *a2, const char *res) {
    Quad *q = &code[n++];
    q->kind = k;
    strcpy(q->op, op); strcpy(q->a1, a1); strcpy(q->a2, a2); strcpy(q->res, res);
}
char *gen_bin(const char *op, char *a, char *b) {
    char *t = newtemp();
    int rel = (op[0]=='<' || op[0]=='>' || op[0]=='=' || op[0]=='!');
    emit(rel ? K_REL : K_BIN, op, a, b, t);
    return t;
}
void label_name(char *buf, int l) { sprintf(buf, "L%d", l); }

int lbegin[50], lend[50], sp = 0;

void print_tac(Quad *c, int cnt);
void optimize(void);
void gen_target(void);
%}

%union { char *s; }
%token <s> ID NUM RELOP
%token WHILE
%type <s> expr cond
%left '+' '-'
%left '*' '/'

%%
program : stmt_list
        ;
stmt_list : stmt_list stmt
          | stmt
          ;
stmt : assign
     | while_stmt
     ;
assign : ID '=' expr ';'   { emit(K_COPY, "", $3, "", $1); }
       ;
while_stmt : WHILE '('
               { char b[32]; lbegin[sp] = ++lcount; label_name(b, lbegin[sp]);
                 emit(K_LABEL, "", "", "", b); }
             cond ')'
               { char e[32]; lend[sp] = ++lcount; label_name(e, lend[sp]);
                 emit(K_IFF, "", $4, "", e); sp++; }
             body
               { char b[32], e[32]; sp--;
                 label_name(b, lbegin[sp]); label_name(e, lend[sp]);
                 emit(K_GOTO, "", "", "", b);
                 emit(K_LABEL, "", "", "", e); }
           ;
body : '{' stmt_list '}'
     | stmt
     ;
cond : expr RELOP expr     { $$ = gen_bin($2, $1, $3); }
     ;
expr : expr '+' expr       { $$ = gen_bin("+", $1, $3); }
     | expr '-' expr       { $$ = gen_bin("-", $1, $3); }
     | expr '*' expr       { $$ = gen_bin("*", $1, $3); }
     | expr '/' expr       { $$ = gen_bin("/", $1, $3); }
     | '(' expr ')'        { $$ = $2; }
     | ID                  { $$ = $1; }
     | NUM                 { $$ = $1; }
     ;
%%

void yyerror(const char *s) { printf("Syntax error: %s\n", s); exit(1); }

/* ---------- print three-address code ---------- */
void print_tac(Quad *c, int cnt) {
    for (int i = 0; i < cnt; i++) {
        Quad *q = &c[i];
        switch (q->kind) {
            case K_BIN: case K_REL: printf("    %s = %s %s %s\n", q->res, q->a1, q->op, q->a2); break;
            case K_COPY:  printf("    %s = %s\n", q->res, q->a1); break;
            case K_IFF:   printf("    ifFalse %s goto %s\n", q->a1, q->res); break;
            case K_GOTO:  printf("    goto %s\n", q->res); break;
            case K_LABEL: printf("%s:\n", q->res); break;
        }
    }
}

/* ---------- code motion (loop-invariant hoisting) ---------- */
int is_const(const char *s) { return s[0] >= '0' && s[0] <= '9'; }

void optimize(void) {
    memcpy(opt, code, sizeof(Quad) * n);
    on = n;
    for (int i = on - 1; i >= 0; i--) {              /* inner loops first */
        if (opt[i].kind != K_LABEL) continue;
        int j = -1;
        for (int k = i + 1; k < on; k++)
            if (opt[k].kind == K_GOTO && strcmp(opt[k].res, opt[i].res) == 0) j = k;
        if (j < 0) continue;                         /* not a loop head */

        int inv[500] = {0};
        int changed = 1;
        while (changed) {
            changed = 0;
            for (int k = i + 1; k < j; k++) {
                Quad *q = &opt[k];
                if (inv[k] || (q->kind != K_BIN && q->kind != K_COPY)) continue;
                int defs = 0;                        /* defs of res inside loop */
                for (int m = i + 1; m < j; m++)
                    if ((opt[m].kind==K_BIN||opt[m].kind==K_REL||opt[m].kind==K_COPY)
                        && strcmp(opt[m].res, q->res) == 0) defs++;
                if (defs != 1) continue;
                int ok = 1;
                const char *args[2] = { q->a1, q->kind == K_BIN ? q->a2 : "" };
                for (int a = 0; a < 2 && ok; a++) {
                    if (args[a][0] == '\0' || is_const(args[a])) continue;
                    for (int m = i + 1; m < j; m++)  /* operand defined in loop? */
                        if ((opt[m].kind==K_BIN||opt[m].kind==K_REL||opt[m].kind==K_COPY)
                            && strcmp(opt[m].res, args[a]) == 0 && !inv[m]) { ok = 0; break; }
                }
                if (ok) { inv[k] = 1; changed = 1; }
            }
        }
        Quad tmp[500]; int t = 0;
        for (int k = i + 1; k < j; k++) if (inv[k]) tmp[t++] = opt[k];  /* hoisted */
        tmp[t++] = opt[i];                                              /* loop label */
        for (int k = i + 1; k < j; k++) if (!inv[k]) tmp[t++] = opt[k]; /* remaining body */
        tmp[t++] = opt[j];
        memcpy(&opt[i], tmp, sizeof(Quad) * t);
    }
}

/* ---------- target code generation ---------- */
void gen_target(void) {
    for (int i = 0; i < on; i++) {
        Quad *q = &opt[i];
        const char *ins = "";
        switch (q->kind) {
            case K_LABEL: printf("%s:\n", q->res); break;
            case K_GOTO:  printf("    JMP  %s\n", q->res); break;
            case K_IFF:   printf("    MOV  R0, %s\n    CMP  R0, #0\n    JE   %s\n", q->a1, q->res); break;
            case K_COPY:
                printf("    MOV  R0, %s%s\n    MOV  %s, R0\n", is_const(q->a1) ? "#" : "", q->a1, q->res); break;
            case K_BIN:
                ins = q->op[0]=='+' ? "ADD" : q->op[0]=='-' ? "SUB" : q->op[0]=='*' ? "MUL" : "DIV";
                printf("    MOV  R0, %s%s\n    %s  R0, %s%s\n    MOV  %s, R0\n",
                       is_const(q->a1) ? "#" : "", q->a1, ins,
                       is_const(q->a2) ? "#" : "", q->a2, q->res); break;
            case K_REL:
                ins = !strcmp(q->op,"<") ? "SETLT" : !strcmp(q->op,">") ? "SETGT" :
                      !strcmp(q->op,"<=") ? "SETLE" : !strcmp(q->op,">=") ? "SETGE" :
                      !strcmp(q->op,"==") ? "SETEQ" : "SETNE";
                printf("    MOV  R0, %s%s\n    CMP  R0, %s%s\n    %s R0\n    MOV  %s, R0\n",
                       is_const(q->a1) ? "#" : "", q->a1,
                       is_const(q->a2) ? "#" : "", q->a2, ins, q->res); break;
        }
    }
}

int main(void) {
    printf("Enter the program (end with Ctrl+D):\n");
    if (yyparse() == 0) {
        printf("\nSyntax is correct.\n");
        printf("\n===== Three-Address Code =====\n");   print_tac(code, n);
        optimize();
        printf("\n===== Optimized Code (code motion) =====\n"); print_tac(opt, on);
        printf("\n===== Target Code =====\n");          gen_target();
    }
    return 0;
}
