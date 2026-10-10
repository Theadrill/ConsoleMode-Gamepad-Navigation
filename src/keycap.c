#include "keycap.h"
#include "screen.h"
#include "glog.h"
#include "glueapi.h"

static HHOOK g_hook = NULL;

static int KeyCap_IsMapped(DWORD vk)
{
    return vk == (DWORD)GLUEPAD_VK_UP || vk == (DWORD)GLUEPAD_VK_DOWN ||
           vk == (DWORD)GLUEPAD_VK_LEFT || vk == (DWORD)GLUEPAD_VK_RIGHT ||
           vk == (DWORD)GLUEPAD_VK_A || vk == (DWORD)GLUEPAD_VK_B ||
           vk == (DWORD)GLUEPAD_VK_X || vk == (DWORD)GLUEPAD_VK_Y;
}

static LRESULT CALLBACK KeyCap_Proc(int nCode, WPARAM wParam, LPARAM lParam)
{
    if (nCode == HC_ACTION)
    {
        KBDLLHOOKSTRUCT *k = (KBDLLHOOKSTRUCT*)lParam;
        int injected = (k->flags & LLKHF_INJECTED) ? 1 : 0;
        DWORD screen = 0;

        /* Gate = byte isw (0 = glue). Fora = silencio total. */
        if (GluePad_ReadScreenState(&screen) && GluePad_IsOnGlue())
        {
            /* F1c: SOMENTE injetada. Fisica nunca mais e logada
             * (privacidade: senha/testes de chat nao vao ao log).
             * Nunca engole nada. */
            if (injected)
            {
                char buf[160];
                const char *dir = (wParam == WM_KEYUP || wParam == WM_SYSKEYUP)
                                  ? "up" : "down";
                wsprintfA(buf, "GluePad F1 key vk=0x%02X %s api=%d screen=0x%02X\r\n",
                          (unsigned)k->vkCode, dir, GluePad_ApiGlue(), (unsigned)screen);
                GluePad_LogRaw(buf);
            }
        }
    }
    return CallNextHookEx(g_hook, nCode, wParam, lParam);
}

int KeyCap_Install(HINSTANCE hinst)
{
    /* IsMapped fica reservado p/ o bypass (F2); referencia p/ compilar sem warning. */
    (void)KeyCap_IsMapped;
    if (!g_hook)
        g_hook = SetWindowsHookExA(WH_KEYBOARD_LL, KeyCap_Proc, hinst, 0);
    return g_hook ? 1 : 0;
}

void KeyCap_Uninstall(void)
{
    if (g_hook)
    {
        UnhookWindowsHookEx(g_hook);
        g_hook = NULL;
    }
}
