#include "glue.h"
#include "glog.h"
#include "screen.h"
#include "keycap.h"
#include "glue_lua.h" /* GLUEPAD_LUA_NAV (gerado no build, validado luac50) */

/* Enderecos 5875 (plano, secao 3). Chamada direta: nossa DLL esta dentro
 * do processo (sem ASLR no 1.12). Leitura guardada antes de chamar. */
#define GLUEPAD_ADDR_GETCONTEXT ((unsigned long)0x7040D0UL)
#define GLUEPAD_ADDR_PUSHSTRING ((unsigned long)0x6F3890UL)
#define GLUEPAD_ADDR_GETTABLE   ((unsigned long)0x6F3A40UL)
#define GLUEPAD_ADDR_PCALL      ((unsigned long)0x6F41A0UL)
/* GLOBALSINDEX DESTE cliente = -10001 (0xFFFFD8EF): prova por disassembly —
 * lua_gettable desvia -10000 (registry: L->l_G+0x30) e -10001 (globals:
 * L+0x40, tabela DENTRO do lua_State). O -10002 do Lua stock cai no caminho
 * de upvalue, que le ci->func — NULL fora de chamada Lua (nosso caso,
 * WndProc) = crash lendo 0x07. Foi exatamente o 3o crash. */
#define GLUEPAD_GLOBALSINDEX (-10001)

typedef void *GlueL; /* lua_State* opaco */
/* Zero args: convencao irrelevante na chamada. */
typedef GlueL (*GetContextFn)(void);
/* PROVA por disassembly do WoW.exe (F2a): o Lua deste cliente e
 * thiscall/fastcall (L em ECX, 2o arg em EDX, `ret N` que limpa a stack).
 * __cdecl aqui crasha duas vezes: a funcao le ECX-lixo como L (NULL+0x28,
 * igual aos dois crashs) e a limpeza dupla de stack corrompe o ESP.
 * Mesma convencao no Interact (LUA_CFUNCTION = __fastcall). */
typedef void (__fastcall *LuaPushStringFn)(GlueL L, const char *s);
typedef void (__fastcall *LuaGetTableFn)(GlueL L, int idx);
typedef int (__fastcall *LuaPcallFn)(GlueL L, int nargs, int nresults, int errfunc);

static HWND s_hwnd = NULL;
static WNDPROC s_old = NULL;
static int s_hookedLogged = 0;
static int s_missingLogged = 0;
static DWORD s_t0 = 0;
static int s_waitLogged = 0;
static int s_armedLogged = 0;

/* F2b-1: canal de valores (leitura apenas, sem asserts, sem dialogs).
 * Layout TValue derivado do disassembly: slot = 16 bytes; tt em +0
 * (0=nil, 1=bool, 3=number, 4=string); numero (double) em +4;
 * TString*: len em +12, dados em +16. Tudo lido guardado; T1/T2 fazem
 * a prova empirica do layout antes do inventario. 1 = ligado. */
#define GLUEPAD_LUA_PROBES 1

#if GLUEPAD_LUA_PROBES
#define GLUEPAD_TT_NIL 0
#define GLUEPAD_TT_BOOL 1
#define GLUEPAD_TT_NUMBER 3
#define GLUEPAD_TT_STRING 4
#define GLUEPAD_DUMP_CAP 3800

static int Glue_RunChunk(GlueL L, const char *chunk, int nresults)
{
    LuaPushStringFn pushstring = (LuaPushStringFn)GLUEPAD_ADDR_PUSHSTRING;
    LuaGetTableFn gettable = (LuaGetTableFn)GLUEPAD_ADDR_GETTABLE;
    LuaPcallFn pcall = (LuaPcallFn)GLUEPAD_ADDR_PCALL;
    /* getglobal(L,"RunScript") = pushstring + gettable(GLOBALSINDEX) */
    pushstring(L, "RunScript");
    gettable(L, GLUEPAD_GLOBALSINDEX);
    pushstring(L, chunk);
    /* Sucesso com nresults=0: stack balanceada. Com nresults=1: +1 slot
     * por chunk (sem settop mapeado; 3 slots/boot aqui — irrelevante).
     * Falha: +1 slot (errmsg). Chunks abaixo nao erram por desenho. */
    return pcall(L, 1, nresults, 0);
}

/* Push de global (leitura direta, sem pcall): +1 slot por leitura
 * (sem settop mapeado; poucas leituras/boot — irrelevante). */
static void Glue_PushGlobal(GlueL L, const char *name)
{
    LuaPushStringFn pushstring = (LuaPushStringFn)GLUEPAD_ADDR_PUSHSTRING;
    LuaGetTableFn gettable = (LuaGetTableFn)GLUEPAD_ADDR_GETTABLE;
    pushstring(L, name);
    gettable(L, GLUEPAD_GLOBALSINDEX);
}

/* Le o slot do topo (16 bytes guardados). Retorna tt ou -1. */
static int Glue_TopTT(GlueL L, unsigned char slot[16])
{
    DWORD top = 0;
    if (!GluePad_ReadU32((unsigned long)L + 8, &top))
        return -1;
    if (!GluePad_ReadBytes((unsigned long)(top - 16), slot, 16))
        return -1;
    return (int)(slot[0] | ((unsigned)slot[1] << 8) |
                 ((unsigned)slot[2] << 16) | ((unsigned)slot[3] << 24));
}

static void Glue_LogT1(GlueL L, int rc)
{
    /* Layout PROVADO in-game (t1+t2 crus): slot 16B: tt+0,
     * valor em +8 (double 8B / ponteiro 4B). +4 e ptr de estado, ignorar.
     * t1m espera num=7. */
    char line[128];
    unsigned char slot[16];
    int tt = Glue_TopTT(L, slot);
    if (rc == 0 && tt == GLUEPAD_TT_NUMBER)
    {
        double v = 0.0;
        memcpy(&v, slot + 8, 8);
        wsprintfA(line, "GluePad F2 t1 rc=0 tt=3 num=%d\r\n", (int)v);
    }
    else
        wsprintfA(line, "GluePad F2 t1 rc=%d tt=%d\r\n", rc, tt);
    GluePad_LogRaw(line);
}

static void Glue_LogT2(GlueL L, int rc)
{
    /* TString PROVADA: len em ts+12, dados em ts+16. t2m espera abcd. */
    char line[160];
    unsigned char slot[16];
    int tt = Glue_TopTT(L, slot);
    if (rc == 0 && tt == GLUEPAD_TT_STRING)
    {
        DWORD ts = 0, len = 0;
        char sbuf[16];
        memcpy(&ts, slot + 8, 4);
        if (GluePad_ReadU32(ts + 12, &len) && len < 15 &&
            GluePad_ReadBytes(ts + 16, sbuf, len + 1))
        {
            sbuf[len] = '\0';
            wsprintfA(line, "GluePad F2 t2 rc=0 tt=4 len=%u str=%s\r\n", len, sbuf);
            GluePad_LogRaw(line);
        }
        else
        {
            wsprintfA(line, "GluePad F2 t2 rc=0 tt=4 BADLEN\r\n");
            GluePad_LogRaw(line);
        }
    }
    else
    {
        wsprintfA(line, "GluePad F2 t2 rc=%d tt=%d\r\n", rc, tt);
        GluePad_LogRaw(line);
    }
}

/* Dump religado com offsets provados (valor+8, len+12, dados+16). */
#define GLUEPAD_DUMP_ON 1

#if GLUEPAD_DUMP_ON
static void Glue_LogDump(GlueL L, int rc)
{
    unsigned char slot[16];
    int tt = Glue_TopTT(L, slot);
    if (rc == 0 && tt == GLUEPAD_TT_STRING)
    {
        DWORD ts = 0, len = 0;
        static char sbuf[GLUEPAD_DUMP_CAP + 16];
        unsigned cap;
        memcpy(&ts, slot + 8, 4);
        if (GluePad_ReadU32(ts + 12, &len))
        {
            char line[256];
            unsigned off = 0;
            cap = len < GLUEPAD_DUMP_CAP ? len : GLUEPAD_DUMP_CAP;
            if (cap > 0 && GluePad_ReadBytes(ts + 16, sbuf, cap))
            {
                sbuf[cap] = '\0';
                wsprintfA(line, "GluePad F2 dump rc=0 len=%u\r\n", len);
                GluePad_LogRaw(line);
                while (off < cap)
                {
                    unsigned n = cap - off > 200 ? 200 : cap - off;
                    memcpy(line, sbuf + off, n);
                    line[n] = '\0';
                    lstrcatA(line, "\r\n");
                    GluePad_LogRaw(line);
                    off += n;
                }
                return;
            }
        }
    }
    GluePad_LogRaw("GluePad F2 dump FAIL\r\n");
}
#endif /* GLUEPAD_DUMP_ON */

static int s_valuesDone = 0;

static void Glue_DoProbes(void)
{
    GetContextFn getctx = (GetContextFn)GLUEPAD_ADDR_GETCONTEXT;
    DWORD chk = 0;
    GlueL L;
    int rc;

    if (s_valuesDone)
        return;
    s_valuesDone = 1;

    /* Fora do WoW (endereco ilegivel): nao chama nada. */
    if (!GluePad_ReadU32(GLUEPAD_ADDR_GETCONTEXT, &chk))
    {
        GluePad_LogRaw("GluePad F2 lua noctx\r\n");
        return;
    }
    L = getctx();
    if (!L)
    {
        GluePad_LogRaw("GluePad F2 lua L=NULL\r\n");
        return;
    }
    /* Definicoes primeiro (idempotente): T3m chama GluePad_Dump(). */
    rc = Glue_RunChunk(L, GLUEPAD_LUA_NAV, 0);
    /* T1m: numero via mailbox (prova layout number). */
    rc = Glue_RunChunk(L, "GluePad_Mbox = 7", 0);
    Glue_PushGlobal(L, "GluePad_Mbox");
    Glue_LogT1(L, rc);
    /* T2m: string via mailbox (despejo cru p/ achar len/dados). */
    rc = Glue_RunChunk(L, "GluePad_Mbox = \"abcd\"", 0);
    Glue_PushGlobal(L, "GluePad_Mbox");
    Glue_LogT2(L, rc);
#if GLUEPAD_DUMP_ON
    /* T3m: inventario via mailbox (prova ponta a ponta). */
    rc = Glue_RunChunk(L, "GluePad_Mbox = GluePad_Dump()", 0);
    Glue_PushGlobal(L, "GluePad_Mbox");
    Glue_LogDump(L, rc);
#endif
}
#endif /* GLUEPAD_LUA_PROBES */

LRESULT CALLBACK Glue_WndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
{
    if (msg == GLUEPAD_WM_PROBE)
    {
#if GLUEPAD_LUA_PROBES
        Glue_DoProbes();
#endif
        return 0;
    }
    if (msg == GLUEPAD_WM_ACT)
    {
        Glue_ActIntent((int)wp);
        return 0;
    }
    return CallWindowProcA(s_old, hwnd, msg, wp, lp);
}

HWND Glue_GetHwnd(void)
{
    return s_hwnd;
}

/* Le string curta do topo (pos-pushglobal de string); "" se nao-string. */
static void Glue_TopShortStr(GlueL L, char *out, unsigned cap)
{
    unsigned char slot[16];
    int tt = Glue_TopTT(L, slot);
    out[0] = '\0';
    if (tt != GLUEPAD_TT_STRING)
        return;
    {
        DWORD ts = 0, len = 0;
        memcpy(&ts, slot + 8, 4);
        if (GluePad_ReadU32(ts + 12, &len) && len < cap &&
            GluePad_ReadBytes(ts + 16, out, len + 1))
            out[len] = '\0';
    }
}

static int Glue_CallL(const char *tag, const char *chunk)
{
    GetContextFn getctx = (GetContextFn)GLUEPAD_ADDR_GETCONTEXT;
    DWORD chk = 0;
    GlueL L;
    int rc;
    char line[192];
    /* F7-diag: todo intent registra onde o foco parou (so nome de frame).
     * defs (8KB) pula a sonda: big nao cabe o helper + query. */
    static const char *FOCUSQ =
        " if GluePad_FocusName then GluePad_Mbox = GluePad_FocusName() end";
    if (!GluePad_ReadU32(GLUEPAD_ADDR_GETCONTEXT, &chk))
        return -99;
    L = getctx();
    if (!L)
        return -99;
    if (lstrlenA(chunk) < 128)
    {
        char big[256];
        char foc[64];
        wsprintfA(big, "%s%s", chunk, FOCUSQ);
        rc = Glue_RunChunk(L, big, 0);
        Glue_PushGlobal(L, "GluePad_Mbox");
        Glue_TopShortStr(L, foc, 60);
        wsprintfA(line, "GluePad F2 nav %s rc=%d foc=%s\r\n", tag, rc, foc);
    }
    else
    {
        rc = Glue_RunChunk(L, chunk, 0);
        wsprintfA(line, "GluePad F2 nav %s rc=%d foc=-\r\n", tag, rc);
    }
    GluePad_LogRaw(line);
    return rc;
}

/* F3a: qual tela do glue? (GluePad_Screen; string curta, so nomes de
 * frame estaticos — nenhum texto/dado do usuario.) */
static void Glue_LogScr(GlueL L, int rc)
{
    unsigned char slot[16];
    static char s_last[64] = "";
    int tt = Glue_TopTT(L, slot);
    if (rc == 0 && tt == GLUEPAD_TT_STRING)
    {
        DWORD ts = 0, len = 0;
        char sbuf[64];
        char line[128];
        memcpy(&ts, slot + 8, 4);
        if (GluePad_ReadU32(ts + 12, &len) && len < 60 &&
            GluePad_ReadBytes(ts + 16, sbuf, len + 1))
        {
            unsigned i;
            sbuf[len] = '\0';
            /* Boot roda a cada intent (F3b): so loga ao trocar de tela. */
            for (i = 0; ; i++)
            {
                char a = i < 63 ? sbuf[i] : '\0';
                char b = s_last[i];
                if (a != b)
                    break;
                if (a == '\0')
                    return;
            }
            for (i = 0; i < 63 && sbuf[i]; i++)
                s_last[i] = sbuf[i];
            s_last[i] = '\0';
            wsprintfA(line, "GluePad F2 nav scr %s\r\n", sbuf);
            GluePad_LogRaw(line);
            return;
        }
    }
    GluePad_LogRaw("GluePad F2 nav scr FAIL\r\n");
}

static int s_bootDone = 0;

void Glue_BootNav(void)
{
    GetContextFn getctx = (GetContextFn)GLUEPAD_ADDR_GETCONTEXT;
    GlueL L;
    int rc;
    /* F3b: defs uma vez; boot-check a CADA intent (Lua decide: mesma
     * tela = re-mostra, outra = reconstroi, desconhecida = desarma).
     * Sem isso, A clicaria zona stale apos trocar login<->char. */
    if (!s_bootDone)
    {
        s_bootDone = 1;
        Glue_CallL("defs", GLUEPAD_LUA_NAV);
    }
    Glue_CallL("boot", "if GluePad_Boot then GluePad_Boot() end");
    /* F3a: registra a tela (LOGIN vs OTHER|frame) p/ descoberta. */
    L = getctx();
    if (!L)
        return;
    rc = Glue_RunChunk(L, "if GluePad_Screen then GluePad_Mbox = GluePad_Screen() end", 0);
    Glue_PushGlobal(L, "GluePad_Mbox");
    Glue_LogScr(L, rc);
}

void Glue_ActIntent(int intent)
{
    const char *chunk = NULL;
    const char *tag = "?";
    /* Bootstrap preguicoso + re-check por tela a cada toque (ver BootNav:
     * barato e evita zona stale). ARMED segue so para o dump. */
    Glue_BootNav();
    switch (intent)
    {
    case GLUEPAD_INT_UP: chunk = "if GluePad_Move then GluePad_Move(\"UP\") end"; tag = "UP"; break;
    case GLUEPAD_INT_DOWN: chunk = "if GluePad_Move then GluePad_Move(\"DOWN\") end"; tag = "DOWN"; break;
    case GLUEPAD_INT_LEFT: chunk = "if GluePad_Move then GluePad_Move(\"LEFT\") end"; tag = "LEFT"; break;
    case GLUEPAD_INT_RIGHT: chunk = "if GluePad_Move then GluePad_Move(\"RIGHT\") end"; tag = "RIGHT"; break;
    case GLUEPAD_INT_A: chunk = "if GluePad_Activate then GluePad_Activate() end"; tag = "A"; break;
    case GLUEPAD_INT_B: chunk = "if GluePad_Back then GluePad_Back() end"; tag = "B"; break;
    case GLUEPAD_INT_DUMP:
    {
        /* F4a: Y = fotografia a tela atual (dump sob demanda p/ descobrir
         * dialogo/realm/criacao; so nomes de frame, sem texto/dado). */
        GetContextFn getctx = (GetContextFn)GLUEPAD_ADDR_GETCONTEXT;
        GlueL L = getctx();
        int rc2;
        if (!L)
            return;
        rc2 = Glue_RunChunk(L, "GluePad_Mbox = GluePad_Dump()", 0);
        Glue_PushGlobal(L, "GluePad_Mbox");
#if GLUEPAD_DUMP_ON
        Glue_LogDump(L, rc2);
#else
        (void)rc2;
#endif
        return;
    }
    case GLUEPAD_INT_BOOT: Glue_BootNav(); return;
    default: return;
    }
    Glue_CallL(tag, chunk);
}

void Glue_TriggerProbe(void)
{
    if (!s_hwnd)
    {
        static const char *names[] = { GLUEPAD_CLASSNAME, GLUEPAD_CLASSNAME_FALLBACK };
        unsigned k;
        for (k = 0; k < sizeof(names) / sizeof(names[0]); k++)
        {
            s_hwnd = FindWindowA(names[k], NULL);
            if (s_hwnd)
                break;
        }
        if (!s_hwnd)
        {
            if (!s_missingLogged)
            {
                s_missingLogged = 1;
                GluePad_LogRaw("GluePad F2 wnd MISSING\r\n");
            }
            return;
        }
        s_old = (WNDPROC)SetWindowLongA(s_hwnd, GWL_WNDPROC, (LONG)Glue_WndProc);
        if (!s_old)
        {
            s_hwnd = NULL;
            GluePad_LogRaw("GluePad F2 wnd HOOKFAIL\r\n");
            return;
        }
        if (!s_hookedLogged)
        {
            s_hookedLogged = 1;
            GluePad_LogRaw("GluePad F2 wnd hooked\r\n");
        }
    }
    /* Prontidao (licao do crash F2a): sonda Lua em estado semi-construido
     * derruba o jogo. So sonda com cliente assentado: 20s de vida E o
     * marcador de login 0xB41DA4==3 (observado in-game). Tudo read-only. */
    {
        DWORD t = GetTickCount();
        DWORD v = 0;
        char rdy[96];
        if (s_t0 == 0)
            s_t0 = t;
        GluePad_ReadU32(0xB41DA4UL, &v);
        /* Instrumentacao: mostra o que o gate ve ate ARMAR (some depois). */
        if (!s_armedLogged)
        {
            wsprintfA(rdy, "GluePad F2 rdy age=%u mark=%u\r\n",
                      (unsigned)(t - s_t0), (unsigned)v);
            GluePad_LogRaw(rdy);
        }
        if (t - s_t0 < 20000)
            return;
        if (!GluePad_ReadU32(0xB41DA4UL, &v) || v != 3)
        {
            if (!s_waitLogged)
            {
                s_waitLogged = 1;
                GluePad_LogRaw("GluePad F2 probe WAIT\r\n");
            }
            return;
        }
        if (!s_armedLogged)
        {
            s_armedLogged = 1;
            GluePad_LogRaw("GluePad F2 probe ARMED\r\n");
        }
    }
    /* BOOT antes de PROBE (ordem FIFO): definicoes+Boot precedem o dump. */
    PostMessageA(s_hwnd, GLUEPAD_WM_ACT, GLUEPAD_INT_BOOT, 0);
    PostMessageA(s_hwnd, GLUEPAD_WM_PROBE, 0, 0);
}

void Glue_Uninstall(void)
{
    if (s_hwnd && s_old)
        SetWindowLongA(s_hwnd, GWL_WNDPROC, (LONG)s_old);
    s_hwnd = NULL;
    s_old = NULL;
}
