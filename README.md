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

## Instalação da toolchain (replicar em outra máquina Windows)

Pré-requisitos: nenhum admin necessário; só Git (Git Bash) e conexão.
Tudo abaixo foi executado e verificado nesta máquina em 2026-10-10.

1. **MinGW-w64 i686** (GCC 16.2.0, ucrt-posix-dwarf, Brecht Sanders r2):
   - Download: `winlibs-i686-posix-dwarf-gcc-16.2.0-mingw-w64ucrt-14.0.0-r2.zip`
     (267 MB) de `https://github.com/brechtsanders/winlibs_mingw/releases`
     (tag `16.2.0posix-14.0.0-ucrt-r2`).
   - Conferir SHA256 com o `.zip.sha256` da mesma release
     (`Get-FileHash -Algorithm SHA256` tem que bater).
   - Extrair para `C:\Tools\` → resulta em `C:\Tools\mingw32\bin\i686-w64-mingw32-gcc.exe`.
     (zip + sha apagados após extração para economizar ~270 MB.)
   - Por que i686 e não x86_64: o `WoW.exe` 1.12.1 é 32-bit; a DLL tem que ser 32-bit.
   - Por que portátil e não MSYS2/winget: sem admin, sem instalador, mesmo
     padrão do `C:\Tools\lua50` deste projeto-irmão.
2. **Verificação** (tem que passar igual):
   - `C:\Tools\mingw32\bin\i686-w64-mingw32-gcc.exe --version` →
     `MinGW-W64 i686-ucrt-posix-dwarf ... 16.2.0`.
   - `Test-Path C:\Tools\mingw32\i686-w64-mingw32\include\xinput.h` → `True`
     (XInput já vem no toolchain, nada extra para o gamepad).
   - Smoke test: compilar `hello.c` com `#include <xinput.h>` +
     `XInputGetState(0,&s)` linkando `-lxinput` → `hello32.exe` roda e
     retorna `1167` (`ERROR_DEVICE_NOT_CONNECTED`, esperado sem controle);
     header PE `Machine=0x014C` (i386 32-bit).
3. **MinHook** (dependência de código, não de máquina): submódulo/cópia no
   repo na hora de codar, igual ao Interact faz. Nada a instalar globalmente.
4. **Não precisa:** CMake, MSVC, Wine (testes OctoLogin usam Wine no Linux;
   aqui o teste é nativo Windows), admin.
