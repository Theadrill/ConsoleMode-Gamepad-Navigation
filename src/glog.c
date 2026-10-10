#include <windows.h>
#include "glog.h"

static CRITICAL_SECTION s_cs;
static LONG s_init = 0;

void GluePad_LogInit(void)
{
    if (InterlockedCompareExchange(&s_init, 1, 0) == 0)
        InitializeCriticalSection(&s_cs);
}

void GluePad_LogShutdown(void)
{
    if (InterlockedExchange(&s_init, 0) == 1)
        DeleteCriticalSection(&s_cs);
}

void GluePad_LogRaw(const char *line)
{
    char dir[MAX_PATH];
    char path[MAX_PATH];
    HANDLE h;
    DWORD written = 0;
    int locked = (s_init != 0);

    if (locked)
        EnterCriticalSection(&s_cs);

    OutputDebugStringA(line);

    if (GetTempPathA(MAX_PATH, dir))
    {
        lstrcpyA(path, dir);
        lstrcatA(path, "gluepad_f1.log");
        h = CreateFileA(path, GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE,
                        NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
        if (h != INVALID_HANDLE_VALUE)
        {
            SetFilePointer(h, 0, NULL, FILE_END);
            WriteFile(h, line, (DWORD)lstrlenA(line), &written, NULL);
            CloseHandle(h);
        }
    }

    if (locked)
        LeaveCriticalSection(&s_cs);
}
