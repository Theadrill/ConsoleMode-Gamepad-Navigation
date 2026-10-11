#ifndef GLUEPAD_KEYCAP_H
#define GLUEPAD_KEYCAP_H

#include <windows.h>

/* F1b: SOMENTE observa. Instala WH_KEYBOARD_LL e loga, nunca engole
 * (sempre CallNextHookEx). O bypass (engolir INJECTED) vem depois. */

/* Mapeamento Steam Input do dono (teclas virtuais do Deck): */
#define GLUEPAD_VK_UP    '7'  /* 0x37 */
#define GLUEPAD_VK_DOWN  '8'  /* 0x38 */
#define GLUEPAD_VK_LEFT  '9'  /* 0x39 */
#define GLUEPAD_VK_RIGHT '0'  /* 0x30 */
#define GLUEPAD_VK_A     VK_SPACE
#define GLUEPAD_VK_B     '3'
#define GLUEPAD_VK_X     '1'
#define GLUEPAD_VK_Y     '2'

/* Carimbo proprio: o hook libera o que tem este dwExtraInfo (F4).
 * Nossas teclas futuras saem carimbadas; as do Steam, nao. */
#define GLUEPAD_EXTRAINFO ((ULONG_PTR)0x47503132UL) /* "GP12" ASCII */

/* Intents de navegacao (Y = dump; X = toggle ABC/123 do teclado F13b). */
#define GLUEPAD_INT_UP    0
#define GLUEPAD_INT_DOWN  1
#define GLUEPAD_INT_LEFT  2
#define GLUEPAD_INT_RIGHT 3
#define GLUEPAD_INT_A     4
#define GLUEPAD_INT_B     5
#define GLUEPAD_INT_BOOT  6
#define GLUEPAD_INT_DUMP  7
#define GLUEPAD_INT_X     8

int KeyCap_Install(HINSTANCE hinst);
void KeyCap_Uninstall(void);

/* vk -> intent ou -1. */
int KeyCap_IntentForVk(DWORD vk);

#endif
