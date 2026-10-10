# GluePad — Plano de implementação

DLL que dá navegação completa por gamepad nas telas pré-jogo do WoW 1.12.1
(login + char-select). D-pad move o foco, A ativa, B volta.
In-game a DLL dorme: o addon ConsoleModeVanilla é dono do gamepad lá dentro.

## 0. Decisões fechadas (não reabrir sem motivo)

- Escopo por partes, nesta ordem: login pura → char-select (fecha loop
  boot→mundo) → diálogos como overlay global → realm → criação de char.
  Sem tradutor provisório: F1 é só infra, navegação já nasce no modelo
  definitivo (descoberta runtime + foco + `:Click()`).
- Sem hold-para-confirmar: tudo em 1 toque. Riscos assumidos: Quit sai
  direto; Delete pede digitar o nome (impossível pelo pad = trava natural).
- Sem cursor customizado: o foco mora no próprio elemento, em linguagem
  Vanilla nativa (`LockHighlight` azul, caret do editbox).
- B desmapeado no login (ESC ali quita o jogo sem confirmação).

## 1. Premissas verificadas

| # | Fato | Fonte |
|---|---|---|
| 1 | Binário em execução = `WoW.exe` 1.12.1 build 5875 via `VanillaFixes.exe` | `dlls.txt` + exe locais |
| 2 | Entrega por `dlls.txt` (carga com processo suspenso, antes do glue) | OctoLogin (prova), `dlls.txt` local com 7 DLLs |
| 3 | `ClassicAPI.dll` **1.15.16.0** expõe `RunScript`, `C_Glue`, `IsOnGlueScreen`, `LoginWithSavedAccount`, `GetSavedAccounts`, `SetSavedCharacterOrder` | `strings` na DLL local |
| 4 | Glue roda em Lua 5.0 state separado do in-game; CVars são process-global | README ClassicAPI |
| 5 | `GetContext = 0x7040D0` retorna `*0xCEEF74` = `lua_State*` corrente (sem hook p/ capturar L) | OwnedCore infodump + WeirdUtils + 1121-client-internals |
| 6 | Lua 5.0 stock: `gettop 0x6F3070`, `pushstring 0x6F3890`, `gettable 0x6F3A40`, `pcall 0x6F41A0` | mesmas 3 fontes |
| 7 | FrameScript: `Execute 0x704CD0`, `RegisterFunction 0x704120` | OwnedCore infodump |
| 8 | `screenState @ 0xB41DA0` (0..0xb = login/realm/charselect…) = detecção de tela sem Lua | 1121-client-internals `docs/glue.md` |
| 9 | Char-select nativo: setas trocam (wrap), Enter entra, Esc volta (`CharacterSelect_OnKeyDown`) | fonte GlueXML 1.12 + teste in-game |
| 10 | Login nativo: Tab alterna conta/senha, Enter loga de qualquer foco, Esc quita direto | teste in-game |
| 11 | Realm: só Enter confirma (setas mortas). Diálogos: Enter = Cancel | teste in-game |
| 12 | Login real é GlueXML custom Turtle/Octo (painel Select account, botões URL) | screenshot + repo GlueXML Octo |
| 13 | Realm: `RealmListRealmButton1..18` (click=seleciona, duplo=confirma), `RealmListOkButton`, `RealmListCancelButton` | `RealmList.xml` 1.12 |
| 14 | Diálogos: `GlueDialogButton1/2/3` → `GlueDialog_OnClick` compartilhado | `GlueDialog.xml` 1.12 |
| 15 | Padrão de hook/bridge: MinHook em Lua CFunction + endereços fixos 5875 | fonte do Interact (`Game.h`/`dllmain.cpp`) |
| 16 | Toolchain C na máquina de dev: **ausente** (sem gcc/MinGW) — instalar MinGW-w64 i686 antes do build | verificado via `Get-Command`/Test-Path |

## 2. Arquitetura

```
gamepad físico ──XInput──> [thread pad] ──fila──> [hook EndScene, main thread]
                                                              │
                                              GetContext(0x7040D0) = L
                                                              │
                                    getglobal(L,"RunScript") + pushstring + pcall
                                                              │
                                              helper GluePad (Lua 5.0, no glue)
                                              descobre frames, move foco, :Click()
```

- **Por que marshal na main thread:** Lua não é thread-safe; chamada só na
  main thread (mesmo aviso do artigo dx9 sobre `FrameScript_ExecuteBuffer`).
  Padrão: hook barato (EndScene; jogo roda sob `d3d9.dll`/DXVK) drena a fila.
- **Por que via `RunScript` do ClassicAPI:** evita precisar do endereço do
  `loadbuffer`; chunk arbitrário executa no glue state direto.
- **Descoberta em runtime (não hardcodar nomes do glue custom):**
  percorrer `GetChildren()` recursivo desde `GlueParent`, coletar
  `Button`/`EditBox` visíveis + habilitados, ordenar por posição.
  Nomes stock servem só como hints de prioridade. Imune a updates da Turtle.
- **Helper único:** bootstrap injeta tabela `GluePad` uma vez
  (lista de foco, grafo de vizinhos, highlight on/off, activate);
  por input a DLL só chama `GluePad_Move("DOWN")` / `GluePad_Activate()`.
  Lógica em Lua 5.0 (testável até via console de glue).
- **Gating:** tudo (tradução + hooks de filtro, seção 5) ativo só com
  `screenState` na faixa glue. Mundo carregou = silêncio total.

## 3. Modelo de navegação (zonas)

Mesma filosofia do ConsoleMode: roteador por zonas.

| Zona | Elementos (login) |
|---|---|
| `CENTRO` | Account, Password, Login (foco inicial, caret piscando) |
| `CONTAS` | linhas salvas, `◀ ▶`, Clear character, Remove account |
| `LINKS` | Turtle, Armory, Database, Community, Discord, Cinematics, Credits |
| `SISTEMA` | Quit |

- UP/DOWN move dentro da zona (ordem por Y). LEFT/RIGHT troca de zona.
- A ativa: editbox → foca (digitar segue no teclado físico; linha de conta
  clicada preenche sozinha, nativo). Botão → `:Click()`.
- B volta à zona anterior; no login nunca quita.
- Visual: botão focado = `LockHighlight()` (azul Vanilla, igual seleção de
  personagem); editbox = caret + borda dourada. Zero textura custom.
- Char-select: setas nativas nas 10 linhas; além da última o foco cai em
  `AÇÕES` (Enter World, Create, Delete, Back). B volta ao login.
- Edge: 10+ personagens (scroll além do wrap) — D-pad nas bordas rola a lista.

## 4. Mapeamento final

| Tela | D-pad | A | B |
|---|---|---|---|
| Login | move foco (zonas) | ativa focado | zona anterior (nunca quita) |
| Char-select | troca personagem / zonas | entrar no mundo / ativa | volta ao login |

## 5. Bypass do Steam Input (particularidades registradas)

Usuário joga com Steam Input (gamepad→teclado/mouse virtual). Sem filtro,
cada toque gera ação dupla (ex: D-pad move foco + Enter do Steam loga antes
da hora). Solução 100% dentro da DLL, zero config do Steam:

1. **Leitura independente:** `XInputGetState` vê o controle físico
   independente do mapeamento — ler nunca conflita, só a saída duplica.
2. **Filtro por flag de injeção:** hooks `WH_KEYBOARD_LL` + `WH_MOUSE_LL`
   engolem **só** eventos injetados (`LLKHF_INJECTED`/`LLMHF_INJECTED`,
   que é como o Steam entrega o virtual) **enquanto em telas glue**.
   Teclado/mouse físicos passam intactos.
3. **Sem auto-sabotagem:** teclas sintetizadas pela própria DLL levam
   carimbo `dwExtraInfo`; o hook reconhece e deixa passar.
4. **Coexistência:** mouse do Steam segue vivo no glue como fallback.
5. **Gate:** entrou no mundo, hooks saem; Steam Input volta a reinar
   para o addon (que depende dele).
6. **Fallback:** se o Steam abrir o pad em modo exclusivo (XInput vazio),
   ler as teclas virtuais do Steam como fonte — arquitetura suporta as
   duas fontes sem mudar o resto.

## 6. Esqueleto de código

```
dllmain.c  carga, fila de intenções, hook EndScene (dreno na main thread)
pad.c      poll XInput (D-pad, A, B; edge detection + repeat)
screen.c   lê screenState @ 0xB41DA0; gating glue vs mundo
keycap.c   captura das teclas virtuais Steam (WH_KEYBOARD_LL + INJECTED)
glog.c     log duplo (OutputDebugString + %TEMP%\gluepad_f1.log)
glue.c     GetContext + RunScript-via-pcall; bootstrap do helper GluePad
maps.c     zonas, vizinhos e mapeamentos da seção 4
gluepad.lua helper (foco, highlight, activate, descoberta de frames)
steamfilter.c hooks LL + INJECTED + dwExtraInfo (seção 5)
```

Build: MinGW-w64 i686 (`i686-w64-mingw32-gcc`, receita no `build.sh` do
OctoLogin) + MinHook. Deploy obrigatório após todo build: `build.bat`
compila (PE `0x014C`) E auto-instala em
`C:\Users\rodri\OneDrive\wow\octowow\mods\GluePad.dll`; depois checar que
`dlls.txt` (LF puro) tem a linha `mods/GluePad.dll`. Sem junction
(não existe p/ arquivo). Validação F1 via `%TEMP%\gluepad_f1.log`.
Teste espelha o harness do OctoLogin (Wine + XInput virtual).

## 7. Fases testáveis (ordem aprovada: login → char → overlay → realm → criação)

- **F0 — Ponte (CORRIGIDA em F1c):** ClassicAPI tem os nomes como strings, mas o export PE é SÓ `Load` (verificado por parse do PE). `IsOnGlueScreen` via `GetProcAddress` = `api MISSING` in-game. Ponte Lua segue válida SÓ via `getglobal("RunScript")` no glue state (a provar em F2).
- **F1 — Infra (sem navegação jogável):** esqueleto compila i686
  (`Machine=0x014C`), carrega via `dlls.txt`, thread faz poll XInput
  (D-pad, A, B; edge + repeat) e só registra/loga quando `screenState`
  está na faixa glue; no mundo = silêncio total. `SendInput` (quando
  existir) já sai carimbado com `dwExtraInfo` próprio. Nenhum mapeamento
  provisório — nada para descartar na F2. Critério: PE `0x014C` + DLL
  visível nos módulos com jogo no glue + `%TEMP%\gluepad_f1.log` mostra
  inputs no glue e nada no mundo.
- **F1b — Fonte teclado Steam (só observa, não engole):** Deck no
  Windows não expõe XInput (vira teclado via Steam Input), então a DLL
  instala `WH_KEYBOARD_LL` com message pump e loga toda tecla INJECTED +
  física mapeada (`7/8/9/0` = D-pad, `Espaço/3/1/2` = A/B/X/Y), só em
  glue, sempre via `CallNextHookEx` (bypass/engolir vem depois).
  Critério: D-pad e botões aparecem no log com `injected=1`.
- **F1c — Autoridade do gating (só observa):** `screen=0x00` apareceu
  dentro do mundo, então a faixa `<=0x0B` está sob suspeita. A DLL chama
  `ClassicAPI!IsOnGlueScreen` via `GetProcAddress` (risco documentado em
  `glueapi.c`) e loga `api=` lado a lado + snapshot dos vizinhos de
  `0xB41DA0` + diag 1x/seg sem gating; tecla física não é mais logada.
  Critério: par login/mundo anotado no log define o gating com dado.
- **F2a — Ponte de leitura (só observa):** `0xB41DA0` arquivado como
  gate (lê 0 no login, char-select E mundo). Subclass da janela
  (`GxWindowClass`) + mensagem custom leva sondas Lua à main thread:
  `getglobal("RunScript")+pushstring+pcall` com `assert(1)`,
  `assert(IsOnGlueScreen)`, `assert(IsOnGlueScreen())`,
  `assert(GetLoginScreenState)` — só código numérico, sem `tostring`.
  Sem MinHook, sem navegação, sem engolir. Critério: `wnd hooked` +
  `lua run=0 ...` no login e no mundo; `isgluecall` 0/1 resolve o gate.
- **F2b-1 — Canal de valores + inventario (só observa):** gate agora é
  o byte `isw` (0 glue / 1 mundo, provado). `RunScript` DESCARTA retornos
  (`return 7` → nil no topo) — canal via **mailbox**: chunk grava global,
  C lê com `getglobal` direto.   Layout TValue PROVADO in-game (t1+t2 crus): slot 16B, tt+0, valor+8
  (double/ponteiro); TString len+12/dados+16. `gluepad.lua` (Lua 5.0, `luac50 -p`,
  embutido no build) inventaria `Button/EditBox` (nome+tipo+vis+pos,
  NUNCA texto de EditBox) gravando em `GluePad_Mbox` — 1x/boot, sem
  asserts, sem dialogs. Critério: `t1 tt=3 num=7`, `t2 str=abcd`,
  `dump N=...`.
  RESULTADO in-game: `t1 num=7`, `t2 str=abcd` (canal provado), inventario
  N=286 frames (nomes stock RealmList*/GlueDialog*/AddonList* confirmados,
  posicoes GetTop/GetLeft ok). 1.12: `IsVisible` devolve 1 ou nil —
  inventario v2 registra SO visivel (some o ruido escondido).
- **F2b-2 — Navegacao do login (vale tudo):** `gluepad.lua` vira nucleo
  (zonas empiricas CENTRO/CONTAS/LINKS/SISTEMA, `LockHighlight`/caret,
  UP/DOWN com wrap, LEFT/RIGHT troca, A `:Click()`, B volta sem quitar,
  X/Y reservados). Bypass de teclado em glue: engole TODA injetada
  (menos carimbo proprio), fisica intacta, mouse intacto; A/B com edge,
  D-pad com repeat; intents via `WM_APP+8` (main thread); chunks
  blindados (`if` sem helper = no-op). Mundo: passa tudo (gate isw).
  Critério: login navegavel vendo o azul + A/B certos, sem mouse.
  PROVADO in-game (movimento): D-pad move foco (caret + hover-glow),
  bootstrap preguicoso no 1o toque (ARMED desnecessario p/ navegar).
  Highlight = textura de hover presa (linguagem Vanilla de botao; azul
  chapado e de listas). A confirmado (login -> char via pad); B no login
  ok. Char-select/realm/dialogos SEM resposta (fases F3/F4/F5, nao bugs).
  PROVADO in-game: `run=0` x10 sem crash (ponte viva). `IsOnGlueScreen`
  e `GetLoginScreenState` NAO existem no glue (assert falhou). Chunk com
  erro abre dialog de script — asserts removidos (F2a-fix2, sondas
  desligadas);   navegacao usara chunks que nao erram. REGRA Lua: local ANTES do uso
  (referencia futura vira global nil em runtime e abre dialog de script;
  luac50 NAO pega — F4b quebrou assim com setdlg->cur). Gate = byte `isw`
  (falta valor no mundo).
  Licao de crash: primeira sonda em estado Lua semi-construido derrubou
  o jogo (ACCESS_VIOLATION em codigo Lua lendo NULL+0x28) — sonda agora
  exige prontidao (20s de vida + `0xB41DA4==3`).
  Causa raiz do 2o crash (prova por disassembly do WoW.exe): o Lua deste
  cliente e thiscall/fastcall (L em ECX, `ret N`) — __cdecl lia ECX-lixo
  como L e corrompia a stack. GetContext `0x7040D0` confirmado
  (`mov eax,[0xCEEF74]; ret`). 3o crash: GLOBALSINDEX deste cliente e
  -10001 (globals em L+0x40); o -10002 do stock cai em upvalue e le
  ci->func NULL fora de chamada Lua (fault 0x07). Tudo provado no
  disassembly do WoW.exe. Gate tem 2a fonte: byte IsInWorld do
  Interact `*(char*)0xB4B424` (logado como `isw=`).
- **F2 — Login pura (foco + ativação, modelo definitivo):** bootstrap
  `GluePad`, descoberta runtime (`GetChildren()` desde `GlueParent`,
  só `Button`/`EditBox` visíveis+habilitados), primeiro foco no Account,
  `LockHighlight`/caret acompanham D-pad por zonas
  (`CENTRO` ⇄ `CONTAS` ⇄ `LINKS` ⇄ `SISTEMA`). A ativa (`:Click()` /
  foco em editbox, digitação segue no teclado físico), B volta de zona e
  nunca quita. Critério: login completo só no pad (senha no teclado, 1x),
  sem mouse.
- **F3 — Char-select (EM ANDAMENTO):** F3a-descoberta: `GluePad_Screen()`
  (LOGIN = EditBox visivel; senao OTHER|frame) + Boot so age no login
  (Move/Back/Activate travados em `g.screen`, sem :Click stale) + dump
  com prefixo SCR + log `nav scr`. PROVADO F3a in-game: `OTHER|
  CharacterSelect`, N=18 (fileiras `CharSelectCharacterButton1..9` +
  EnterWorld/Create/ChangeRealm/Delete/Back/Addons/RotateL-R/
  SaveCharacter; zero nome pessoal). F3b em codigo: zonas
  PERSONAGENS+ACOES, re-boot por tela a cada intent (sem stale),
  B = Back no char, A no Delete abre dialogo (F4 depois). F3b-fix:
  Screen() era raso (filhos diretos) e lia OTHER|AccountLogin no login
  (edits aninhados) — agora varredura profunda via collect().
  PROVADO in-game: login voltou + char-select perfeito (fileiras azuis,
  ACOES, B=Back). Bonus: criacao cai no modo LOGIN (tem EditBox de nome)
  — navega truncado; modo proprio + UX ficam p/ depois.
- **F4 — Overlay + Steam bypass (EM ANDAMENTO):** F4a-descoberta: Y vira
  dump sob demanda (`GLUEPAD_INT_DUMP`, com edge) p/ fotografar dialogo/
  realm/criacao (so nomes de frame). Gatilho: A no Login abre o modal
  "conectando". PROVADO F4a in-game: `GlueDialogButton1` centralizado,
  tela segue LOGIN; bonus: nomes reais do login p/ o passe de UX. F4b em
  codigo: overlay (dialogo captura D-pad/A/B; A=focado, B=ultimo=Cancel;
  ao fechar, a tela retoma), Boot sincroniza por intent, `nav scr` so ao
  trocar. F4b-fix2: bloco dialogo depois de cur/show/hide (local apos uso
  = global nil = dialog de script). PROVADO in-game: D-pad preso no botao,
  B cancela, A clica, telas retomam.
  global (quando visível, D-pad navega, A confirma, B cancela) + hooks
  `WH_KEYBOARD_LL`/`WH_MOUSE_LL` que engolem só eventos injetados
  (`INJECTED`) enquanto em glue, liberando os carimbados da própria DLL;
  teclado/mouse físicos intactos; mouse do Steam segue como fallback;
  in-game hooks saem (addon opera normal). Critério: mesma F2+F3 com
  Steam Input ligado, sem ação dupla, + 5 min in-game sem input fantasma.
- **F5 — Realm (foco 100% custom):** realm não tem navegação nativa
  (só Enter confirma), então lista `RealmListRealmButton1..18` vira zona
  navegável (D-pad move, A seleciona/confirma via `:Click()`,
  B volta/cancela). Critério: entrar, trocar e confirmar realm só no pad.
- **F6 — Criação de char + homologação:** tela de criação (nome, raça,
  classe, facção, botões) navegável no mesmo motor + boot→mundo repetido
  5x, `screenState` nunca deixa a DLL falar no mundo, sem crash no
  unload. Critério: 5/5 limpo.

## 8. Riscos e limitações aceitas

- Gamepad não digita: usuário/senha, 1x no teclado por sessão (nome persiste; linha salva preenche).
- Quit/Remove/Clear em 1 toque (sem hold) — decisão do dono.
- Realm/diálogos/criação dentro do escopo, por fases (F4–F6): diálogo = overlay global (Enter em diálogo = Cancel no nativo, preservado como B); realm = A confirma pré-selecionado até F5 existir. Incluir depois = mesma DLL + mapeamentos.
- EndScene sob DXVK a validar em F2; alternativa = hook de mensagem da janela.
 - Nomes do glue custom Turtle via descoberta (Gitea Octo bloqueado por DDoS-protection; não dependemos dele).
- **Futuro (fora deste plano): teclado virtual pelo pad** (digitar
  usuário/senha/nome sem teclado físico). Idéia registrada, não entra em
  F1–F6; quando entrar, será fase própria com layout e confirmação
  dedicados.
