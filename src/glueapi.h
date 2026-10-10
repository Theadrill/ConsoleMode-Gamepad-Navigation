#ifndef GLUEPAD_GLUEAPI_H
#define GLUEPAD_GLUEAPI_H

/* F1c-diag: autoridade independente sobre glue vs mundo.
 * Resolve ClassicAPI.dll!IsOnGlueScreen via GetProcAddress (a ClassicAPI
 * carrega antes da nossa no dlls.txt). Chamada sem argumentos = segura
 * quanto a convenacao; o risco residual (export com outra assinatura)
 * esta documentado no .c. Retorna 1 = glue, 0 = mundo, -1 = desconhecido. */
int GluePad_ApiGlue(void);

/* Snapshot dos DWORDs vizinhos de 0xB41DA0 para achar o valor que
 * realmente distingue login de mundo. Escreve em buf (sempre \0). */
void GluePad_Snapshot(char *buf, unsigned n);

#endif
