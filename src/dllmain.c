/* GluePad F1-infra: poll XInput + gating glue vs mundo, so LOGA.
 * Nenhum mapeamento jogavel aqui (decisao aprovada: sem tradutor
 * provisorio). Lua/F2+ entram depois; este arquivo vira a base.
 *
 * Regras respeitadas: i686 32-bit, Win32 threads (sem CRT pesado/C11),
 * enderecos em uint32_t (nada de uint64_t), strings ASCII + \0,
 * silencio total fora do glue. */

#include <windows.h>
#include <xinput.h>
#include "pad.h"
#include "screen.h"
#include "glog.h"
#include "keycap.h"
#include "glueapi.h"
#include "glue.h"

/* GLUEPAD_EXTRAINFO mora em keycap.h (carimbo F4 compartilhado). */

static HANDLE g_stopEvent = NULL;
static HANDLE g_thread = NULL;
static HINSTANCE g_hInst = NULL;
static DWORD s_lastDiag = 0;
static DWORD s_lastProbe = 0;
static DWORD s_lastSync = 0;

/* Helper do futuro: tecla sintetizada pela DLL, ja carimbada.
 * F13b: em uso (A no teclado virtual). NUNCA logar o vk. */
void GluePad_SendKeyStamped(WORD vk)
{
    INPUT in;
    INPUT out;
    ZeroMemory(&in, sizeof(in));
    in.type = INPUT_KEYBOARD;
    in.ki.wVk = vk;
    in.ki.dwExtraInfo = GLUEPAD_EXTRAINFO;
    ZeroMemory(&out, sizeof(out));
    out.type = INPUT_KEYBOARD;
    out.ki.wVk = vk;
    out.ki.dwFlags = KEYEVENTF_KEYUP;
    out.ki.dwExtraInfo = GLUEPAD_EXTRAINFO;
    SendInput(1, &in, sizeof(INPUT));
    SendInput(1, &out, sizeof(INPUT));
}

static void GluePad_Log(const char *btn, DWORD screen, int isRepeat)
{
    char buf[128];
    /* ASCII puro, sempre \0 via limite de tamanho. */
    wsprintfA(buf, "GluePad F1 btn=%s %s screen=0x%02X\r\n",
              btn, isRepeat ? "repeat" : "edge", (unsigned)screen);
    GluePad_LogRaw(buf);
}

static DWORD WINAPI GluePad_PollThread(LPVOID unused)
{
    GluePadEdge edge;
    MSG msg;
    DWORD wait;
    (void)unused;
    ZeroMemory(&edge, sizeof(edge));
    if (KeyCap_Install(g_hInst))
        GluePad_LogRaw("GluePad F1 keycap on\r\n");
    else
        GluePad_LogRaw("GluePad F1 keycap FAILED\r\n");
    GluePad_LogRaw("GluePad F1 loaded\r\n");
    {
        /* PID: o log mistura sessoes se dois jogos abrirem juntos. */
        char lbuf[64];
        wsprintfA(lbuf, "GluePad F1 pid=%u\r\n", (unsigned)GetCurrentProcessId());
        GluePad_LogRaw(lbuf);
    }

    for (;;)
    {
        /* WH_KEYBOARD_LL exige message pump na thread que instalou. */
        wait = MsgWaitForMultipleObjects(1, &g_stopEvent, FALSE, 16, QS_ALLINPUT);
        if (wait == WAIT_OBJECT_0)
            break;
        while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE))
            DispatchMessageA(&msg);

        /* Diag 1x/seg SEM gating: e assim que capturamos o valor de mundo. */
        {
            DWORD tick = GetTickCount();
            if (tick - s_lastDiag >= 1000)
            {
                DWORD scr = 0;
                int scrOk;
                int api;
                int pad = 0;
                DWORD j;
                XINPUT_STATE ds;
                char line[256];
                char snap[160];
                DWORD isw = 0;
                unsigned iswB;
                scrOk = GluePad_ReadScreenState(&scr);
                api = GluePad_ApiGlue();
                for (j = 0; j < 4; j++)
                {
                    ZeroMemory(&ds, sizeof(ds));
                    if (XInputGetState(j, &ds) == ERROR_SUCCESS) { pad = 1; break; }
                }
                GluePad_Snapshot(snap, sizeof(snap));
                iswB = GluePad_ReadU32(GLUEPAD_ADDR_ISINWORLD, &isw)
                       ? (unsigned)(isw & 0xFF) : 0xFFu;
                if (scrOk)
                    wsprintfA(line, "GluePad F1 diag screen=0x%08X api=%d pad=%d isw=0x%02X snap:%s\r\n",
                              (unsigned)scr, api, pad, iswB, snap);
                else
                    wsprintfA(line, "GluePad F1 diag screen=XX api=%d pad=%d isw=0x%02X snap:%s\r\n",
                              api, pad, iswB, snap);
                GluePad_LogRaw(line);
                s_lastDiag = tick;
            }
        }

        /* Sonda Lua 1x/2seg (leitura apenas; execucao na main thread). */
        {
            DWORD tick = GetTickCount();
            if (tick - s_lastProbe >= 2000)
            {
                Glue_TriggerProbe();
                s_lastProbe = tick;
            }
        }

        /* F12-sync 4x/seg: vigia de tela (hide-only, sem log). O gating
         * glue-vs-mundo mora dentro do Post (mundo = silencio). */
        {
            DWORD tick = GetTickCount();
            if (tick - s_lastSync >= 250)
            {
                Glue_PostSync();
                s_lastSync = tick;
            }
        }

        {
        XINPUT_STATE xs;
        WORD watched = 0;
        DWORD screen = 0;
        DWORD now;
        DWORD i;
        int connected = 0;

        /* Primeiro pad conectado (0..3). */
        for (i = 0; i < 4; i++)
        {
            ZeroMemory(&xs, sizeof(xs));
            if (XInputGetState(i, &xs) == ERROR_SUCCESS)
            {
                watched = (WORD)(xs.Gamepad.wButtons & GLUEPAD_BTN_MASK);
                connected = 1;
                break;
            }
        }
        if (!connected)
        {
            /* Sem pad: zera estado para nao gerar edge fantasma depois. */
            edge.watchedPrev = 0;
            continue;
        }

        /* Gating = byte isw (0 = glue). Fora = silencio total (reseta edge). */
        if (!GluePad_ReadScreenState(&screen) || !GluePad_IsOnGlue())
        {
            edge.watchedPrev = 0;
            continue;
        }

        now = GetTickCount();
        {
            WORD prev = edge.watchedPrev;
            WORD fired = GluePad_PollEdge(&edge, watched, now);
            WORD b;
            for (b = 1; b != 0; b = (WORD)(b << 1))
            {
                if (fired & b)
                {
                    int isRepeat = (prev & b) ? 1 : 0;
                    GluePad_Log(GluePad_BtnName(b), screen, isRepeat);
                }
            }
        }
        } /* bloco do poll dentro do for(;;) com message pump */
    }
    KeyCap_Uninstall();
    GluePad_LogRaw("GluePad F1 stopped\r\n");
    return 0;
}

BOOL WINAPI DllMain(HINSTANCE hinst, DWORD reason, LPVOID reserved)
{
    (void)hinst;
    (void)reserved;
    /* Referencia o helper do futuro para garantir que compila/linkado. */
    (void)GluePad_SendKeyStamped;

    if (reason == DLL_PROCESS_ATTACH)
    {
        DisableThreadLibraryCalls((HMODULE)hinst);
        g_hInst = (HINSTANCE)hinst;
        GluePad_LogInit();
        g_stopEvent = CreateEventA(NULL, TRUE, FALSE, NULL);
        if (!g_stopEvent)
            return FALSE;
        g_thread = CreateThread(NULL, 0, GluePad_PollThread, NULL, 0, NULL);
        if (!g_thread)
        {
            CloseHandle(g_stopEvent);
            g_stopEvent = NULL;
            return FALSE;
        }
    }
    else if (reason == DLL_PROCESS_DETACH)
    {
        if (g_stopEvent)
            SetEvent(g_stopEvent);
        if (g_thread)
        {
            WaitForSingleObject(g_thread, 2000);
            CloseHandle(g_thread);
            g_thread = NULL;
        }
        Glue_Uninstall();
        if (g_stopEvent)
        {
            CloseHandle(g_stopEvent);
            g_stopEvent = NULL;
        }
        GluePad_LogShutdown();
    }
    return TRUE;
}
