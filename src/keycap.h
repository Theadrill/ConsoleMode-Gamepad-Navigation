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

int KeyCap_Install(HINSTANCE hinst);
void KeyCap_Uninstall(void);

#endif
