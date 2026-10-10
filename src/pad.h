#ifndef GLUEPAD_PAD_H
#define GLUEPAD_PAD_H

#include <windows.h>
#include <xinput.h>

/* Botoes de interesse F1 (mascara XInput). */
#define GLUEPAD_BTN_UP    XINPUT_GAMEPAD_DPAD_UP
#define GLUEPAD_BTN_DOWN  XINPUT_GAMEPAD_DPAD_DOWN
#define GLUEPAD_BTN_LEFT  XINPUT_GAMEPAD_DPAD_LEFT
#define GLUEPAD_BTN_RIGHT XINPUT_GAMEPAD_DPAD_RIGHT
#define GLUEPAD_BTN_A     XINPUT_GAMEPAD_A
#define GLUEPAD_BTN_B     XINPUT_GAMEPAD_B
#define GLUEPAD_BTN_MASK (XINPUT_GAMEPAD_DPAD_UP | XINPUT_GAMEPAD_DPAD_DOWN | \
                          XINPUT_GAMEPAD_DPAD_LEFT | XINPUT_GAMEPAD_DPAD_RIGHT | \
                          XINPUT_GAMEPAD_A | XINPUT_GAMEPAD_B)

/* D-pad repete; A/B disparam 1x por toque (sem repeat). */
#define GLUEPAD_REPEAT_DELAY_MS 400
#define GLUEPAD_REPEAT_RATE_MS  150

typedef struct {
    WORD watchedPrev;      /* bits de GLUEPAD_BTN_MASK do poll anterior */
    DWORD pressStartTick;  /* GetTickCount do inicio do hold atual */
    DWORD lastRepeatTick;  /* ultimo repeat emitido */
} GluePadEdge;

/* Retorna mascara de botoes que geraram evento neste poll
 * (edge 0->1, mais repeats de D-pad). Atualiza o estado. */
WORD GluePad_PollEdge(GluePadEdge *st, WORD watchedNow, DWORD nowTick);

const char* GluePad_BtnName(WORD singleBtn);

#endif
