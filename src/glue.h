#ifndef GLUEPAD_GLUE_H
#define GLUEPAD_GLUE_H

#include <windows.h>

/* F2a — ponte de leitura (SO observa). Subclass da janela do WoW para
 * executar Lua na main thread; thread de poll so posta a mensagem. */

#define GLUEPAD_WM_PROBE (WM_APP + 7)
#define GLUEPAD_WM_ACT (WM_APP + 8)
/* F12-sync: vigia 250ms (hide-only, sem log). Main thread compara
 * assinatura; so age se mudou (desarma/esconde, nunca mostra/move). */
#define GLUEPAD_WM_SYNC (WM_APP + 9)
void Glue_PostSync(void);
#define GLUEPAD_CLASSNAME "GxWindowClassD3d"
#define GLUEPAD_CLASSNAME_FALLBACK "GxWindowClass"

/* F8-hold: D-pad segurado repete (timer mora na janela = main thread).
 * Hook posta 1x na borda; o timer dita a cadencia ate soltar. */
#define GLUEPAD_TIMER_REPEAT 0x4744u
#define GLUEPAD_HOLD_DELAY_MS 350
#define GLUEPAD_HOLD_RATE_MS 110
void Glue_RepeatStart(HWND hwnd, int intent);
void Glue_RepeatStop(void);

/* Chamado ~1x/2seg pela thread de poll (qualquer thread). Localiza a
 * janela, instala o subclass uma vez e posta a mensagem de sonda. */
void Glue_TriggerProbe(void);

/* WndProc substituto (roda na main thread); resto vai p/ o original. */
LRESULT CALLBACK Glue_WndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp);

/* Janela do jogo (NULL ate localizar). */
HWND Glue_GetHwnd(void);

/* Bootstrap latched: definicoes + Boot (main thread). */
void Glue_BootNav(void);

/* Executa um intent (main thread). Chunks blindados: no-op sem helper. */
void Glue_ActIntent(int intent);

/* Restaura a janela no unload. */
void Glue_Uninstall(void);

#endif
