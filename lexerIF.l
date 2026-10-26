%{
#include <string.h>
#include "y.tab.h"
%}
%%
while                   { return WHILE; }
if                      { return IF; }
else                    { return ELSE; }
true                    { yylval.s = strdup("1"); return NUM; }
false                   { yylval.s = strdup("0"); return NUM; }
"&&"                    { return AND; }
"||"                    { return OR; }
"!"                     { return NOT; }
[a-zA-Z_][a-zA-Z0-9_]*  { yylval.s = strdup(yytext); return ID; }
[0-9]+                  { yylval.s = strdup(yytext); return NUM; }
"<="|">="|"=="|"!="|"<"|">" { yylval.s = strdup(yytext); return RELOP; }
[ \t\n]+                ;
.                       { return yytext[0]; }
%%
int yywrap() { return 1; }
