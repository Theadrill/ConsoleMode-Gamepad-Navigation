#ifndef GLUEPAD_SCREEN_H
#define GLUEPAD_SCREEN_H

#include <windows.h>
#include <string.h>

/* screenState @ 0xB41DA0 (premissa 8 do plano, fonte 1121-client-internals).
 * Faixa glue ASSUMIDA: 0x00..0x0B (login/realm/charselect). Mundo = acima.
 * F1 vai logar o valor bruto para validarmos a faixa in-game. */
#define GLUEPAD_SCREEN_STATE_ADDR ((volatile DWORD*)0xB41DA0UL)
#define GLUEPAD_GLUE_MAX 0x0BUL

/* Byte IsInWorld do Interact (mod que funciona nesta maquina):
 * *(char*)0xB4B424. Leitura guardada p/ corroborar o gate via Lua. */
#define GLUEPAD_ADDR_ISINWORLD ((unsigned long)0xB4B424UL)

/* 1 = em tela glue (ativo), 0 = mundo ou leitura insegura (silencio). */
int GluePad_IsOnGlue(void);

/* Le o valor bruto; retorna 1 se leu, 0 se endereco ilegel. */
int GluePad_ReadScreenState(DWORD *out);

/* Leitura guardada de DWORD arbitrario (unsigned long, nunca 64-bit).
 * Retorna 1 se leu, 0 se endereco ilegal. */
int GluePad_ReadU32(unsigned long addr, DWORD *out);

/* Leitura guardada de N bytes (teto 4096). */
int GluePad_ReadBytes(unsigned long addr, void *out, unsigned len);

#endif
