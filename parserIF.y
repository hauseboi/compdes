%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int yylex(void);
void yyerror(const char *msg);

typedef struct { char k; char r[16], a[16], op[4], b[16]; } Q;
Q c[100], o[100];                 /* c = original code, o = optimized code */
int n = 0, m = 0, ls = -1, le = -1, tc = 0, lc = 0, inv[100];
char L1[8], L2[8], E1[8], E2[8];

void add(char k, char *r, char *a, char *op, char *b) {
    c[n].k = k;
    strcpy(c[n].r, r); strcpy(c[n].a, a); strcpy(c[n].op, op); strcpy(c[n].b, b);
    n++;
}
char *bin(char *a, char *op, char *b) {
    char *t = malloc(8);
    sprintf(t, "t%d", ++tc);
    add('A', t, a, op, b);
    return t;
}
%}
%union { char *s; }
%token <s> ID NUM RELOP
%token WHILE IF ELSE AND OR NOT
%type <s> expr cond
%left OR
%left AND
%right NOT
%left '+' '-'
%left '*' '/'
%%
prog : prog stmt | stmt ;
stmt : ID '=' expr ';'      { add('A', $1, $3, "", ""); }
     | WHILE '('            { sprintf(L1, "L%d", ++lc); sprintf(L2, "L%d", ++lc);
                              add('L', L1, "", "", ""); }
       expr RELOP expr ')'  { add('F', L2, $4, $5, $6); }
       '{' prog '}'         { add('G', L1, "", "", ""); add('L', L2, "", "", ""); }
     | IF '(' cond ')'      { sprintf(E1, "L%d", ++lc); add('F', E1, $3, "", ""); }
       '{' prog '}' rest
     ;
rest : /* no else */        { add('L', E1, "", "", ""); }
     | ELSE                 { sprintf(E2, "L%d", ++lc); add('G', E2, "", "", "");
                              add('L', E1, "", "", ""); }
       '{' prog '}'         { add('L', E2, "", "", ""); }
     ;
cond : expr RELOP expr      { $$ = bin($1, $2, $3); }
     | cond AND cond        { $$ = bin($1, "&&", $3); }
     | cond OR cond         { $$ = bin($1, "||", $3); }
     | NOT cond             { $$ = bin($2, "==", "0"); }
     | '(' cond ')'         { $$ = $2; }
     ;
expr : expr '+' expr  { $$ = bin($1, "+", $3); }
     | expr '-' expr  { $$ = bin($1, "-", $3); }
     | expr '*' expr  { $$ = bin($1, "*", $3); }
     | expr '/' expr  { $$ = bin($1, "/", $3); }
     | '(' expr ')'   { $$ = $2; }
     | ID             { $$ = $1; }
     | NUM            { $$ = $1; }
     ;
%%
void yyerror(const char *msg) { printf("Syntax error\n"); exit(1); }

void show(Q *x, int cnt) {
    for (int i = 0; i < cnt; i++) {
        if (x[i].k == 'L') printf("%s:\n", x[i].r);
        else if (x[i].k == 'G') printf("    goto %s\n", x[i].r);
        else if (x[i].k == 'F' && !x[i].op[0]) printf("    ifFalse %s goto %s\n", x[i].a, x[i].r);
        else if (x[i].k == 'F') printf("    ifFalse %s %s %s goto %s\n", x[i].a, x[i].op, x[i].b, x[i].r);
        else if (x[i].op[0]) printf("    %s = %s %s %s\n", x[i].r, x[i].a, x[i].op, x[i].b);
        else printf("    %s = %s\n", x[i].r, x[i].a);
    }
}

/* ---- code motion ---- */
int isnum(char *x) { return x[0] >= '0' && x[0] <= '9'; }
int ndefs(char *x) {                       /* how often x is assigned inside the loop */
    int j, cnt = 0;
    for (j = ls + 1; j < le; j++)
        if (c[j].k == 'A' && !strcmp(c[j].r, x)) cnt++;
    return cnt;
}
int ok(char *x, int i) {                   /* is operand x unchanging at statement i? */
    int j;
    if (!x[0] || isnum(x) || ndefs(x) == 0) return 1;
    for (j = ls + 1; j < i; j++)
        if (inv[j] && !strcmp(c[j].r, x)) return 1;
    return 0;
}
void optimize() {
    int i, j;
    for (i = 0; i < n; i++)                  /* loop = a goto whose label appears earlier */
        if (c[i].k == 'G')
            for (j = 0; j < i; j++)
                if (c[j].k == 'L' && !strcmp(c[j].r, c[i].r)) { ls = j; le = i; }
    if (ls < 0 || le < 0) { for (i = 0; i < n; i++) o[m++] = c[i]; return; }
    for (i = ls + 1; i < le; i++)
        if (c[i].k == 'A' && ndefs(c[i].r) == 1 && ok(c[i].a, i) && ok(c[i].b, i)) inv[i] = 1;
    for (i = 0; i < ls; i++) o[m++] = c[i];             /* before loop */
    for (i = ls + 1; i < le; i++) if (inv[i]) o[m++] = c[i];   /* hoisted */
    o[m++] = c[ls];                                      /* loop label */
    for (i = ls + 1; i < le; i++) if (!inv[i]) o[m++] = c[i];  /* rest of body */
    for (i = le; i < n; i++) o[m++] = c[i];              /* goto + end label + after */
}

/* ---- target code ---- */
char *ins_of(char *op) {
    return !strcmp(op,"+") ? "ADD" : !strcmp(op,"-") ? "SUB" : !strcmp(op,"*") ? "MUL" :
           !strcmp(op,"/") ? "DIV" : !strcmp(op,"&&") ? "AND" : !strcmp(op,"||") ? "OR" :
           !strcmp(op,"<") ? "SETLT" : !strcmp(op,">") ? "SETGT" : !strcmp(op,"<=") ? "SETLE" :
           !strcmp(op,">=") ? "SETGE" : !strcmp(op,"==") ? "SETEQ" : "SETNE";
}
void target() {
    for (int i = 0; i < m; i++) {
        Q *p = &o[i];
        char *ins;
        if (p->k == 'L') printf("%s:\n", p->r);
        else if (p->k == 'G') printf("    JMP %s\n", p->r);
        else if (p->k == 'F' && !p->op[0])
            printf("    MOV R0, %s\n    CMP R0, 0\n    JE %s\n", p->a, p->r);
        else if (p->k == 'F') {
            ins = !strcmp(p->op, "<") ? "JGE" : !strcmp(p->op, ">") ? "JLE" :
                  !strcmp(p->op, "<=") ? "JG" : !strcmp(p->op, ">=") ? "JL" :
                  !strcmp(p->op, "==") ? "JNE" : "JE";
            printf("    MOV R0, %s\n    CMP R0, %s\n    %s %s\n", p->a, p->b, ins, p->r);
        } else if (p->op[0]) {
            ins = ins_of(p->op);
            if (!strncmp(ins, "SET", 3))
                printf("    MOV R0, %s\n    CMP R0, %s\n    %s R0\n    MOV %s, R0\n", p->a, p->b, ins, p->r);
            else
                printf("    MOV R0, %s\n    %s R0, %s\n    MOV %s, R0\n", p->a, ins, p->b, p->r);
        } else printf("    MOV R0, %s\n    MOV %s, R0\n", p->a, p->r);
    }
}

int main() {
    if (yyparse() == 0) {
        printf("Syntax OK\n\n--- Three-address code ---\n");  show(c, n);
        optimize();
        printf("\n--- Optimized code ---\n");                 show(o, m);
        printf("\n--- Target code ---\n");                     target();
    }
    return 0;
}
