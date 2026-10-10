> [!CAUTION]
> ## REGRAS PRINCIPAIS — LEITURA OBRIGATÓRIA ANTES DE QUALQUER AÇÃO
> 1. **NÃO FAZER PUSH ENQUANTO O USUÁRIO NÃO PEDIR.** Quando pedir, fazer push **UMA VEZ SÓ** e aguardar o próximo pedido explícito para fazer push de novo. Nunca fazer push automático, em sequência ou por conta própria.
> 2. **WoW 1.12.1 build 5875 32-BIT / Lua 5.0 no glue** — a DLL tem que ser i686 (`0x014C`); o helper Lua tem que ser Lua 5.0 estrito. Nada de 64-bit, nada de sintaxe Lua 5.1+.
> 3. **AVISO DE SEGURANÇA DO WOW:** UI-level SEMPRE. Ler gamepad (XInput), filtrar input, chamar `:Click()` em botão de glue e `RunScript` no glue state — tudo permitido, mesma classe do Interact/ClassicAPI. NUNCA: unlocker Lua, automação de gameplay (cast/movimento/loot/combate), bot, patch de lógica do cliente, Warden-adjacent. `FrameScript_ExecuteBuffer` tem histórico de uso em bots — aqui ele serve SÓ para navegar em telas pré-jogo, nunca para jogar.
> 4. **IDENTIDADE VISUAL:** foco mora no próprio elemento, em linguagem Vanilla nativa (`LockHighlight` azul, caret do editbox). Zero textura custom, zero cursor flutuante. Nada de visual Retail/moderno.
> 5. **TOOLCHAINS (checagem imediata após ler este arquivo):** C → `C:\Tools\mingw32\bin\i686-w64-mingw32-gcc.exe --version` tem que responder `i686 ... 16.2.0` (receita de reinstall no README). Lua → `C:\Tools\lua50\luac50.exe -v` tem que responder `Lua 5.0.3` para validar `gluepad.lua` (NUNCA o 5.4 do PATH). Se algo faltar, seguir a receita do README; se não der, PERGUNTAR ao usuário antes de seguir.

# Contexto para IA — Mod GluePad (gamepad no glue 1.12.1)

> Cole este arquivo no início de qualquer conversa com IA para ela NÃO precisar redescobrir tudo do zero.

## 1. Ambiente fixo (não precisa re-verificar)

* **Jogo:** World of Warcraft 1.12.1 build 5875 (`WoW.exe`, 32-bit), via `VanillaFixes.exe` (loader, processo nasce suspenso). Servidor Turtle WoW (realm N'Zoth).
* **Linguagens:** C (DLL, MinGW-w64 i686) + Lua 5.0 estrito (helper `gluepad.lua` executado no glue state).
* **Pasta do jogo:** `C:\Users\rodri\OneDrive\wow\octowow\` (`WoW.exe`, `VanillaFixes.exe`, `dlls.txt`).
* **Entrega/deploy (obrigatório após TODO build):** `build.bat` compila E auto-instala em `C:\Users\rodri\OneDrive\wow\octowow\mods\GluePad.dll` (cópia automática — junction NÃO existe para arquivo, só diretório). Depois conferir que `dlls.txt` (LF puro, backup `dlls.txt.bak-gluepad`) contém a linha `mods/GluePad.dll`. Carga ocorre antes do glue — a DLL já está dentro do processo no login.
* **Log de validação F1:** `%TEMP%\gluepad_f1.log` (a DLL escreve lá + `OutputDebugString`; usuário valida abrindo o `.txt`, sem DebugView).
* **Cadeia `dlls.txt` (prova de entrega):** `SuperWoWhook.dll`, `WoWTranslate.dll`, `Interact.dll`, `ClassicAPI.dll`, `mods/OctoLogin.dll`, `transmogfix.dll`, `twloader.dll`.
* **ClassicAPI.dll 1.15.16.0 (corrigido F1c):** export PE tem SÓ `Load` — `RunScript`, `C_Glue`, `IsOnGlueScreen` etc. existem como strings/nomes Lua internos, NÃO como exports. Ponte via `GetProcAddress` para eles é impossível (`api MISSING` in-game prova); a ponte Lua continua válida SÓ via `getglobal(L,"RunScript")+pushstring+pcall` com endereços stock (a provar em F2).
* **Toolchains:** `C:\Tools\mingw32\` (GCC 16.2.0 i686-ucrt-posix-dwarf, `xinput.h` incluso) e `C:\Tools\lua50\` (`luac50.exe` 5.0.3). Sem admin, sem MSVC, sem CMake, sem Wine.
* **Repo:** [wow-login-gamepad-navigation](https://github.com/Theadrill/wow-login-gamepad-navigation), clone em `C:\PROJETOS\wow-login-gamepad-navigation`.

## 2. Estrutura do repo

```
dllmain.c      carga, fila de intenções, hook EndScene (dreno na main thread)
pad.c          poll XInput (D-pad, A, B; edge + repeat)
screen.c       lê screenState @ 0xB41DA0; gating glue vs mundo
glue.c         GetContext + RunScript-via-pcall; bootstrap do helper
maps.c         zonas, vizinhos e mapeamentos (seção 6)
gluepad.lua    helper (foco, highlight, activate, descoberta de frames)
steamfilter.c  hooks LL + INJECTED + dwExtraInfo (seção 7)
docs/plano_gluepad_dll.md  plano faseado F0–F5 (fonte da verdade do passo a passo)
```

## 3. Padrão DLL 1.12 (obrigatório seguir)

* Compilar SEMPRE i686 32-bit (`-m32` implícito no toolchain; PE `Machine=0x014C`). 64-bit não carrega.
* Template de hook = Interact: MinHook em função que recebe `lua_State*`, convenções `__fastcall`/`__thiscall`/`__stdcall` respeitadas. PROVA in-game: o Lua deste cliente é thiscall/fastcall (L em ECX) — `__cdecl` crasha; ver `glue.c`.
* Capturar L sem hook: `GetContext = 0x7040D0` → `*0xCEEF74` = `lua_State*` corrente.
* Executar Lua no glue: `getglobal(L,"RunScript") + pushstring(chunk) + pcall` (ClassicAPI registrado no glue state). Endereços Lua stock: `gettop 0x6F3070`, `pushstring 0x6F3890`, `gettable 0x6F3A40`, `pcall 0x6F41A0`. FrameScript: `Execute 0x704CD0`, `Register 0x704120`.
* **Lua só na main thread** (VM não é thread-safe): thread do pad enfileira, subclass da janela (`GxWindowClass` + mensagem custom) drena na main thread — EndScene virou alternativa (jogo roda sob `d3d9.dll`/DXVK).
* **Gating:** tudo ativo SÓ com `screenState` na faixa glue. Mundo carregou = silêncio total (o addon ConsoleModeVanilla é dono do gamepad in-game e depende do Steam Input).
* Descoberta de frames em runtime (`GetChildren()` desde `GlueParent`, filtrar `Button`/`EditBox` visíveis+habilitados, ordenar por posição). NÃO hardcodar nomes do glue custom Turtle/Octo — update deles não pode quebrar o mod. Nomes stock só como hints.

## 4. Restrições (NÃO usar)

* C: nada de 64-bit (`uint64_t` para endereços — usar `uint32_t`), nada de CRT pesado/threads C11 (usar Win32 threads), nada de exceção C++, strings Lua sempre ASCII + `\0`.
* Lua do helper: mesmas restrições do addon — NÃO usar `require`, `goto`, `//`, bitwise, `#t`, `gmatch` (usar `string.gfind`), `table.unpack` (usar `unpack`), `continue`. USAR `table.getn`, `getglobal("Nome"..i)`.
* Glue: NUNCA chamar função de gameplay (só navegação: `:Click()`, `:LockHighlight()`, `:SetFocus()`, getters). Nada destrutivo automatizado.

## 4b. Toolchains — validadores (OBRIGATÓRIO antes de compilar/validar)

* C: `i686-w64-mingw32-gcc.exe --version` → `i686 ... 16.2.0`; `xinput.h` presente; smoke test (`-lxinput`, PE `0x014C`) conforme README.
* Lua: `luac50.exe -p gluepad.lua`, exit 0 (prova 5.4-vs-5.0: 5.4 aprova `#t`, 5.0 rejeita).
* Se faltar algo: receita de reinstall no README. Sem validar em silêncio com ferramenta errada.

## 5. Pontes e referências (não re-derivar)

* **Interact** ([vargv666/Interact](https://github.com/vargv666/Interact)): template de hook MinHook + endereços fixos 5875 + ponte DLL→Lua. Funciona na máquina do usuário — prova que endereço fixo vale aqui.
* **OctoLogin** ([fmustafayaman/OctoLogin](https://github.com/fmustafayaman/OctoLogin)): padrão de entrega (`mods/*.dll` + `dlls.txt`), build MinGW i686, teste sob Wine. ATENÇÃO: ele mexe em rede (`connect`), não em UI — dele copiar SÓ entrega/build/teste.
* **ClassicAPI** (README, seção Glue): `RunScript` + `C_Glue` no glue state; CVars process-global (IPC barato glue↔mundo se um dia precisar).
* **GlueXML 1.12 real** (espelhos + testes in-game): char-select = setas+Enter+Esc nativos; login = Tab+Enter nativos; realm = só Enter; diálogos = Enter cai no Cancel.
* Frames: `CharSelectCharacterButton1..10`, `CharSelectEnterWorldButton`, `AccountLoginLoginButton/Account/Edit/PasswordEdit`, `RealmListRealmButton1..18`, `RealmListOkButton/CancelButton`, `GlueDialogButton1/2/3`.

## 6. Navegação (decisões fechadas)

* Zonas login: `CENTRO` (Account, Password, Login; foco inicial) ⇄ `CONTAS` (linhas salvas, `◀ ▶`, Clear character, Remove account) ⇄ `LINKS` (URL buttons) ⇄ `SISTEMA` (Quit). UP/DOWN dentro da zona, LEFT/RIGHT troca de zona.
* A ativa (editbox foca — digitar segue no teclado físico; botão `:Click()`). B volta de zona; **B desmapeado no login** (ESC ali quita sem confirmação).
* Char-select: setas nativas nas linhas; além da última, zona `AÇÕES` (EnterWorld, Create, Delete, Back). B volta ao login.
* **Sem hold**: tudo em 1 toque (Quit sai direto, Delete pede digitar nome = trava natural). Risco assumido pelo dono.
* Fora de escopo: realm (A confirma pré-selecionado), diálogos (Enter=Cancel), digitação pelo pad. Incluir depois = mesma DLL + 2 mapeamentos.

## 7. Bypass do Steam Input (particularidades — não quebrar)

Usuário joga com Steam Input (pad→teclado/mouse virtual). Sem filtro = ação dupla.
1. Leitura XInput é independente do mapeamento — só a saída duplica.
2. Hooks `WH_KEYBOARD_LL` + `WH_MOUSE_LL` engolem SÓ eventos injetados (`LLKHF_INJECTED`/`LLMHF_INJECTED`) enquanto em glue; físico passa intacto.
3. Teclas próprias carimbadas com `dwExtraInfo` — o hook deixa passar.
4. Mouse do Steam segue vivo como fallback; in-game os hooks saem.
5. Fallback: Steam em modo exclusivo (XInput vazio) → ler teclas virtuais como fonte.

## 8. Como trabalhar (instrução para IA — EU CODO DIRETO)

1. Implementar por fases F0–F5 do `docs/plano_gluepad_dll.md`, UMA fase por vez.
2. Parada obrigatória ao fim de cada fase: validação in-game pelo usuário (roteiros no plano) antes de commit.
3. Build sempre reproduzível via script (`build.bat`/`build.ps1`, sem MSVC). Compilar = PE `0x014C` + auto-install no `mods\` do jogo + checagem do `dlls.txt` + smoke de carga (aparecer na lista de módulos com o jogo no glue).
4. `gluepad.lua` passa em `luac50 -p` antes de qualquer teste.
5. Sem commit, sem push antes da aprovação da fase. Push só quando o usuário pedir, uma vez só.
6. Outro agente atua no repo-irmão ConsoleModeVanilla — NÃO tocar nele daqui; ponto de sincronia: a DLL dorme in-game, o addon nunca mexe em glue.

---

> [!CAUTION]
> ## REGRAS FINAIS — RECONFIRMAR NO FIM
> 1. **NÃO FAZER PUSH ENQUANTO O USUÁRIO NÃO PEDIR.** Quando pedir, fazer push **UMA VEZ SÓ**.
> 2. **WoW 1.12.1 build 5875 32-bit / Lua 5.0 no glue** — compatibilidade total.
> 3. **AVISO DE SEGURANÇA DO WOW:** UI-level sempre. Nada de unlock, bot, automação de gameplay, patch de lógica. Navegar telas pré-jogo ≠ jogar.
> 4. **IDENTIDADE VISUAL Vanilla intocável** — foco = `LockHighlight`/caret nativos.

---

## CONVERSA INICIAL PARA NÃO PRECISAR FICAR DIGITANDO TUDO DE NOVO

> Cole este bloco no início de qualquer nova conversa para restaurar o contexto completo sem precisar redescobrir nada.
> O plano/documento da sessão é sempre apontado no prompt — nunca está fixo aqui.

**Prompt de abertura:**
> "Estamos trabalhando no mod GluePad (DLL de gamepad para o glue do WoW 1.12). Leia `AI_CONTEXTO_MOD_GLUEPAD.md` para entender o mod e fixar as regras na memória. Depois leia o plano/documento indicado neste prompt para ter o contexto da frente de trabalho atual. Apresente o que entendeu e aguarde."

---

### O que a IA deve entender ao ler este arquivo (+ o plano apontado no prompt)

#### O Mod
**GluePad** — DLL i686 que dá navegação completa por gamepad no login + char-select do WoW 1.12.1 (D-pad move foco, A ativa, B volta). In-game dorme; ConsoleModeVanilla assume.

#### Estado atual
- **F0 (ponte) CONCLUÍDA:** ClassicAPI 1.15.16.0 com `RunScript` confirmado.
- **Toolchain OK:** MinGW-w64 i686 16.2.0 em `C:\Tools\mingw32`, `xinput.h` presente, smoke 32-bit + `-lxinput` passando.
- **Endereços 5875 mapeados** (GetContext, Lua stock, FrameScript, screenState) e **frames de glue levantados** (stock + descoberta runtime para o custom Turtle).
- **F1 (tradutor XInput→SendInput)** é a próxima fase, aguardando ordem.

#### Regras inegociáveis (resumo executivo)
1. **PUSH SOMENTE quando o usuário pedir, uma vez só. É a regra mais importante.**
2. DLL sempre 32-bit; helper sempre Lua 5.0 estrito (`luac50 -p` exit 0).
3. UI-level sempre — navegar, nunca jogar (sem unlock/bot/automação).
4. Lua só na main thread; gating por `screenState` (dorme in-game).
5. Identidade Vanilla intocável; sem hold (1 toque, risco assumido); B nunca quita no login.
6. Steam Input bypass só em glue (hooks INJECTED + `dwExtraInfo`); in-game intocado.
7. Parada por fase para validação in-game antes de commit.

#### Modo de operação
A IA **coda diretamente** (C + Lua do helper), fase a fase (F0–F5), valida o próprio trabalho (build + smoke + roteiro) e passa ao usuário o que é esperado acontecer no jogo para ele validar. Sem commit, sem push antes da aprovação.
