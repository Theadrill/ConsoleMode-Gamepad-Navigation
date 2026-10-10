#include "screen.h"

int GluePad_ReadScreenState(DWORD *out)
{
    volatile DWORD *p = GLUEPAD_SCREEN_STATE_ADDR;
    /* IsBadReadPtr e legado mas evita crash se o endereco nao estiver
     * mapeado (ex.: DLL carregada fora do WoW em teste). */
    if (IsBadReadPtr((const void*)p, sizeof(DWORD)))
        return 0;
    *out = *p;
    return 1;
}

int GluePad_IsOnGlue(void)
{
    /* Gate = byte IsInWorld do Interact (*(char*)0xB4B424), provado
     * in-game: 0x00 no login, 0x01 estavel no mundo. 0xB41DA0 como DWORD
     * le 0 nos dois — arquivado como gate (serve so p/ diagnostico). */
    DWORD v = 0;
    if (!GluePad_ReadU32(GLUEPAD_ADDR_ISINWORLD, &v))
        return 0;
    return (v & 0xFF) == 0;
}

int GluePad_ReadU32(unsigned long addr, DWORD *out)
{
    const void *p = (const void*)addr;
    if (IsBadReadPtr(p, sizeof(DWORD)))
        return 0;
    *out = *(volatile DWORD*)p;
    return 1;
}

int GluePad_ReadBytes(unsigned long addr, void *out, unsigned len)
{
    if (len == 0 || len > 4096)
        return 0;
    if (IsBadReadPtr((const void*)addr, len))
        return 0;
    memcpy(out, (const void*)addr, len);
    return 1;
}
