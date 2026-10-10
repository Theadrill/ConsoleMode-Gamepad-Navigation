#include "pad.h"

#define GLUEPAD_DPAD_MASK (XINPUT_GAMEPAD_DPAD_UP | XINPUT_GAMEPAD_DPAD_DOWN | \
                           XINPUT_GAMEPAD_DPAD_LEFT | XINPUT_GAMEPAD_DPAD_RIGHT)

WORD GluePad_PollEdge(GluePadEdge *st, WORD watchedNow, DWORD nowTick)
{
    WORD pressed = (WORD)((~st->watchedPrev) & watchedNow);
    WORD out = pressed;
    WORD held;

    if (pressed)
    {
        st->pressStartTick = nowTick;
        st->lastRepeatTick = nowTick;
    }

    held = (WORD)(st->watchedPrev & watchedNow);
    if (held & GLUEPAD_DPAD_MASK)
    {
        if ((nowTick - st->pressStartTick) >= GLUEPAD_REPEAT_DELAY_MS &&
            (nowTick - st->lastRepeatTick) >= GLUEPAD_REPEAT_RATE_MS)
        {
            out |= (WORD)(held & GLUEPAD_DPAD_MASK);
            st->lastRepeatTick = nowTick;
        }
    }

    /* A/B nao repetem: holds sao ignorados apos o edge. */

    st->watchedPrev = watchedNow;
    return out;
}

const char* GluePad_BtnName(WORD singleBtn)
{
    if (singleBtn & XINPUT_GAMEPAD_DPAD_UP) return "UP";
    if (singleBtn & XINPUT_GAMEPAD_DPAD_DOWN) return "DOWN";
    if (singleBtn & XINPUT_GAMEPAD_DPAD_LEFT) return "LEFT";
    if (singleBtn & XINPUT_GAMEPAD_DPAD_RIGHT) return "RIGHT";
    if (singleBtn & XINPUT_GAMEPAD_A) return "A";
    if (singleBtn & XINPUT_GAMEPAD_B) return "B";
    return "?";
}
