#include "keycap.h"
#include "screen.h"
#include "glog.h"
#include "glueapi.h"
#include "glue.h"

static HHOOK g_hook = NULL;
static int s_aDown = 0;
static int s_bDown = 0;
static int s_nohwndLogged = 0;

static int KeyCap_IsMapped(DWORD vk)
{
    return vk == (DWORD)GLUEPAD_VK_UP || vk == (DWORD)GLUEPAD_VK_DOWN ||
           vk == (DWORD)GLUEPAD_VK_LEFT || vk == (DWORD)GLUEPAD_VK_RIGHT ||
           vk == (DWORD)GLUEPAD_VK_A || vk == (DWORD)GLUEPAD_VK_B ||
           vk == (DWORD)GLUEPAD_VK_X || vk == (DWORD)GLUEPAD_VK_Y;
}

int KeyCap_IntentForVk(DWORD vk)
{
    if (vk == (DWORD)GLUEPAD_VK_UP) return GLUEPAD_INT_UP;
    if (vk == (DWORD)GLUEPAD_VK_DOWN) return GLUEPAD_INT_DOWN;
    if (vk == (DWORD)GLUEPAD_VK_LEFT) return GLUEPAD_INT_LEFT;
    if (vk == (DWORD)GLUEPAD_VK_RIGHT) return GLUEPAD_INT_RIGHT;
    if (vk == (DWORD)GLUEPAD_VK_A) return GLUEPAD_INT_A;
    if (vk == (DWORD)GLUEPAD_VK_B) return GLUEPAD_INT_B;
    return -1; /* X/Y e resto: sem intent */
}

/* F2b-2: bypass de teclado em glue. Engole TODA injetada (o storm
 * WASD/F7 do perfil Steam tambem), isenta a fisica SEMPRE e a nossa
 * futura (carimbo dwExtraInfo). Mapeadas viram intents (A/B com edge,
 * D-pad com repeat); resto some em silencio. Mundo: passa tudo. */
static LRESULT CALLBACK KeyCap_Proc(int nCode, WPARAM wParam, LPARAM lParam)
{
    if (nCode == HC_ACTION)
    {
        KBDLLHOOKSTRUCT *k = (KBDLLHOOKSTRUCT*)lParam;
        int injected = (k->flags & LLKHF_INJECTED) ? 1 : 0;
        int down = (wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN);
        DWORD screen = 0;

        if (injected && k->dwExtraInfo != GLUEPAD_EXTRAINFO &&
            GluePad_ReadScreenState(&screen) && GluePad_IsOnGlue())
        {
            char buf[160];
            const char *dir = down ? "down" : "up";
            int intent = KeyCap_IntentForVk(k->vkCode);
            HWND h = Glue_GetHwnd();
            wsprintfA(buf, "GluePad F2 key vk=0x%02X %s screen=0x%02X\r\n",
                      (unsigned)k->vkCode, dir, (unsigned)screen);
            GluePad_LogRaw(buf);
            if (h == NULL)
            {
                if (!s_nohwndLogged)
                {
                    s_nohwndLogged = 1;
                    GluePad_LogRaw("GluePad F2 act nohwnd\r\n");
                }
                /* Sem janela: nao engole (failsafe, nativo segue). */
            }
            else if (KeyCap_IsMapped(k->vkCode))
            {
                int post = 0;
                if (k->vkCode == (DWORD)GLUEPAD_VK_A)
                {
                    if (down && !s_aDown) { s_aDown = 1; post = 1; }
                    if (!down) s_aDown = 0;
                }
                else if (k->vkCode == (DWORD)GLUEPAD_VK_B)
                {
                    if (down && !s_bDown) { s_bDown = 1; post = 1; }
                    if (!down) s_bDown = 0;
                }
                else if (down && intent >= 0)
                    post = 1; /* D-pad: todo down navega (repeat ok) */
                if (post)
                    PostMessageA(h, GLUEPAD_WM_ACT, (WPARAM)intent, 0);
                return 1; /* engole: sem dupla funcao */
            }
            else
            {
                return 1; /* injetada nao-mapeada em glue: some */
            }
        }
        else if (!down)
        {
            /* Solta fora do glue reseta edge (sem fantasma ao voltar). */
            if (k->vkCode == (DWORD)GLUEPAD_VK_A) s_aDown = 0;
            if (k->vkCode == (DWORD)GLUEPAD_VK_B) s_bDown = 0;
        }
    }
    return CallNextHookEx(g_hook, nCode, wParam, lParam);
}

int KeyCap_Install(HINSTANCE hinst)
{
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
