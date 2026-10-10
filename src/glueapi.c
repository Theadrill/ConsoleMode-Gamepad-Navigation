#include <windows.h>
#include "glueapi.h"
#include "screen.h"
#include "glog.h"

/* RISCO DOCUMENTADO: "IsOnGlueScreen" foi confirmado via strings na DLL,
 * nao a assinatura. Se o export existir com outra assinatura (ex.:
 * Lua CFunction que recebe lua_State*), esta chamada pode crashar.
 * Recuperacao: remover a linha mods/GluePad.dll do dlls.txt (backup em
 * dlls.txt.bak-gluepad). Se GetProcAddress retornar NULL (nome so
 * registrado no Lua, sem export PE), nada e chamado: seguro. */
typedef int (*GlueApiFn)(void);

static GlueApiFn g_fn = NULL;
static int g_state = 0; /* 0 = nao resolvido, 1 = ok, 2 = ausente */

int GluePad_ApiGlue(void)
{
    if (g_state == 0)
    {
        HMODULE h = GetModuleHandleA("ClassicAPI.dll");
        if (h)
            g_fn = (GlueApiFn)GetProcAddress(h, "IsOnGlueScreen");
        if (g_fn)
        {
            g_state = 1;
            GluePad_LogRaw("GluePad F1 api found\r\n");
        }
        else
        {
            g_state = 2;
            GluePad_LogRaw("GluePad F1 api MISSING\r\n");
        }
    }
    if (g_state != 1)
        return -1;
    return g_fn() ? 1 : 0;
}

void GluePad_Snapshot(char *buf, unsigned n)
{
    /* Vizinhos de 0xB41DA0. "XX" = ilegivel. */
    static const unsigned long kAddrs[] = {
        0xB41D98UL, 0xB41D9CUL, 0xB41DA0UL, 0xB41DA4UL, 0xB41DA8UL, 0xB41DACUL
    };
    unsigned i;
    char *p = buf;
    unsigned left = n;
    int w;
    buf[0] = '\0';
    for (i = 0; i < sizeof(kAddrs) / sizeof(kAddrs[0]); i++)
    {
        DWORD v = 0;
        if (left < 24)
            break;
        if (GluePad_ReadU32(kAddrs[i], &v))
            w = wsprintfA(p, " %08X", (unsigned)v);
        else
            w = wsprintfA(p, " XX");
        p += w;
        left -= (unsigned)w;
    }
}
