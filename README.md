# wow-login-gamepad-navigation (GluePad)

Navegar com o gamepad pelas telas iniciais do World of Warcraft 1.12.1
(login e seleção de personagem): D-pad move o foco entre campos e botões,
A confirma, B volta. Sem mouse, sem teclado — do boot ao "Enter World".
Dentro do jogo, o addon ConsoleModeVanilla assume 100% do gamepad;
esta DLL dorme quando o mundo carrega.

## DLLs necessárias (runtime)

| DLL | Por quê |
|---|---|
| `ClassicAPI.dll` (>= 1.15, com `RunScript`/`C_Glue`) | Ponte de execução Lua no glue state (login/char-select). Já validado: 1.15.16.0 expõe tudo que precisamos |
| `VanillaFixes` (`VanillaFixes.exe` + `dlls.txt`) | Loader: carrega esta DLL com o processo ainda suspenso, antes do jogo abrir |
| `GluePad.dll` (este projeto) | Leitura XInput + motor de foco + atuação no glue |

Build (dev): MinGW-w64 i686 + MinHook (mesmo padrão do OctoLogin/Interact).
