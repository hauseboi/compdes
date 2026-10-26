%{
#include <stdio.h>
#include <string.h>
#include "y.tab.h"
%}



%%



"while"                 { return WHILE; }
[a-zA-Z_][a-zA-Z0-9_]*  { yylval.s = strdup(yytext); return ID; }
[0-9]+                  { yylval.s = strdup(yytext); return NUM; }
"<="|">="|"=="|"!="|"<"|">" { yylval.s = strdup(yytext); return RELOP; }
[-+*/=(){};]            { return yytext[0]; }
[ \t\r\n]+              { /* skip whitespace */ }
.                       { printf("Lexical error: unknown character '%s'\n", yytext); }



%%
int yywrap() { return 1; }
