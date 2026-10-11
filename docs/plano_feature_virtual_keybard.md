# F13 — Teclado virtual: plano em fases testáveis

> Origem: levantamento aprovado em conversa (navegar telas só no pad,
> digitar usuário/senha/nome sem teclado físico). Visual aprovado: B
> (flat escuro + anel ouro), painel ancorado acima do campo focado.

## 0. Regras do projeto (valem todas, sem exceção)

1. **Push:** nunca sem pedido explícito; quando pedir, uma vez só.
2. **Binário:** sempre i686 (`Machine=0x014C`); **Lua:** sempre 5.0 estrito
   (`C:\Tools\lua50\luac50.exe -p`, exit 0) + **ASCII puro** em
   `src/gluepad.lua` (o build quebra senão); sem `#`, bitwise, `goto`,
   `//`, `require`, `table.unpack`, `gmatch`.
3. **Segurança:** UI-level sempre — navegar telas pré-jogo e `SendInput`
   carimbado próprio. Nada de unlock/bot/gameplay/Warden-adjacent.
   **Privacidade:** nunca ler texto de EditBox; nunca logar sequência
   digitada (carimbadas passam em silêncio — verificar com `grep` em
   toda fase que digita).
4. **Thread:** Lua só na main thread (hook posta, WndProc executa).
5. **Ordem Lua:** `local` antes do uso (auditar inventário de funções
   com `grep` após mover bloco — regra nascida no apagão do Boot).
6. **Deploy:** `build.bat` (luac50 + embed + PE + auto-install); jogo
   fechado para instalar (kill pode negar com acesso negado — o usuário
   fecha); `dlls.txt` (LF puro) com `mods/GluePad.dll`; log a IA zera,
   o usuário joga, a IA lê (`%TEMP%\gluepad_f1.log`).
7. **Nomes:** zero nome fixo do jogo; prefixo próprio `GluePadKB*`
   (nosso, permitido). Foco mora no campo (caret); teclas do grid nunca
   recebem foco (só o anel anda).

## Arquivos de referência (ler antes de codar cada fase)

- `AI_CONTEXTO_MOD_GLUEPAD.md` — regras-mãe, endereços provados, mapa
  Steam Input (`7/8/9/0` D-pad, Espaço=A, `3`=B, `1`=X, `2`=Y).
- `docs/plano_gluepad_dll.md` — fases F0–F12 e débitos.
- `src/gluepad.lua` — `collect`/`zoneOf`, `Boot`/`Rebuild`/`Disarm`/
  `Sync`/`Sniff`, `Move` espacial, `Activate`/`Back`, `show`+anel,
  `foc=`/`Dump`/`RingDiag`.
- `src/keycap.c` / `src/keycap.h` — edge A/B/X/Y, isenção
  `GLUEPAD_EXTRAINFO`, `INT_*` (X = backspace com kb, toggle sem kb;
  Y = espaço com kb, dump sem kb).
- `src/glue.c` / `src/glue.h` — intents, hold-repeat, `WM_SYNC`,
  `Glue_CallL` + `foc=`, `GluePad_SendKeyStamped` (em uso na F13b),
  `Glue_IsKbOpen`/`Glue_LogKbFoc`.
- `src/dllmain.c` — poll thread (slots 1s/2s/250ms).
- `embed_lua.py`, `build.bat` — pipeline (luac50 + PE `014C` + install).

## F13a — Painel mudo navegável (sem digitar) ✅ VALIDADA 2026-10-11

**Escopo:** grid QWERTY+123 (`[esp][del][ABC/123][OK]`), modo `kb`, abre
com A no campo, B fecha; teclas excluídas das zonas (`^GluePadKB` pula
fora nos classificadores); A/B não digitam ainda.
**Ritual:** boot → A no usuário → foto (`Y`) → grade completa no anel,
B fecha, regressão login/char (dump sem `GluePadKB` nas zonas).
**Critério:** visual aprovado + navegação total + zero regressão.
**Resultado:** validada in-game. Ajustes entraram no caminho: teclas
viraram `Frame` (exclusão por construção, `collect` nem as vê);
cascata de fonte com prova (`GameFontNormal` não existe no glue,
venceu fonte direta); painel ancora no EditBox mais alto + strata
`TOOLTIP` (não cobre nenhum campo); wrap SÓ no teclado (telas sem
wrap, regra F8 intacta).

## F13b — Digitação visível (username) ✅ VALIDADA 2026-10-11

**Escopo:** novo `GLUEPAD_INT_X` (com edge; com kb = backspace, sem
kb = toggle); no modo-kb, A **envia** (`SendInput` carimbado) em vez
de `:Click()`; Y = espaco com kb, dump com kb fechado (convencao
Steam: X apaga, Y espaca); DEL=backspace;
OK fecha; campo nunca perde foco (regra de 1 linha: nenhuma tecla do
grid é clicável via `:Click()` nosso).
**Ritual:** digitar o usuário só no pad → `grep` no log provando zero
sequência vazada → B fecha.
**Critério:** nome correto no campo + log limpo.
**Resultado:** validada in-game (usuário só no pad; `grep` 0/0).
`foc=`/`Dump` viraram posicionais (`KB:r,c`, nunca rótulo/VK);
`KbPress` via Mbox (número=VK, `-1`=interno, `nil`=Activate);
corrigido crash `Glue_CallL("?", NULL)` no caminho AKB.

## F13c — Senha (dado sensível) ✅ VALIDADA 2026-10-11

**Escopo:** idem F13b no campo password (máscara nativa); B fecha sem
salvar rastro; diálogo de erro com teclado aberto fecha junto
(`Disarm`).
**Ritual:** login completo só no pad → valida entrada no char →
`grep` de vazamento de novo.
**Critério:** boot→char só no pad, senha em nenhum log.
**Resultado:** validada in-game (login completo só no pad).
`kbclose` limpa o Mbox (fecha sem rastro).

## F13d — Nome de char (shift + validação do jogo) ✅ VALIDADA 2026-10-11

**Escopo:** shift **momentâneo** no LB (segura LB + A = maiúscula,
solta = normal; vários A's seguidos todos maiúsculos); RB = toggle
ABC/123; indicador visual: letras `+KB_BUMP`px com shift armado
(GetFont/SetFont com pcall, sem crash se a API não existir); respeitar
`maxLetters`/regras do Turtle (o campo valida — observar, não
contornar); sem criar char ainda (só nome válido/inválido).
**Ritual:** criação → digita nome → jogo aceita/recusa como no teclado.
**Critério:** paridade total com teclado físico.
**Resultado:** validada in-game (limite de caracteres respeitado, LB/RB
tudo OK; `grep` de vazamento 0/0, só `KB:r,c[S]` posicional).
LB físico quebrado do dono virou botões traseiros = TAB (`0x09`);
RB = Left Control (`0xA2`) — captura Deck 2026-10-11 (ver seção Deck).

## F13e — Endurecimento + regressão geral ⏳ PARCIAL (falta wizard)

**Escopo:** hold não repete A (já é edge — provar); sync/dialog/addons
convivem com painel aberto; `Disarm` cobre teclado; homologação das
telas antigas com o código novo instalado.
**Critério:** 5/5 sem regressão + F13a–d revalidados por cima.
**Resultado parcial 2026-10-11:** hold não repete (A/LB/RB/X/Y, provado
segurando); login por clique de mouse com painel aberto fecha correto;
diálogo de erro com painel aberto revalidado (fecha junto); addons OK
com o código novo; todas as telas homologadas **menos wizard**.

## Riscos registrados

1. Roubo de foco (mitigação: grid nunca clicável, só anel).
2. Diálogo no meio da digitação (mitigação: fecha junto no `Disarm`).
3. Acentos/case (validar na criação, campo visível e seguro).
4. Hold segurando A não pode repetir digitação (edge puro por construção).

## Steam Deck — RESOLVIDO 2026-10-11

- LB físico quebrado → botões traseiros mapeados p/ TAB. Captura no
  glue: `vk=0x09` down/up (2 amostras, `screen=0x00`).
- RB = Left Control no perfil Steam. Captura no glue: `vk=0xA2`
  down/up (2 amostras, `screen=0x00`, assumido e confirmado no teste).
- Mapeamento F13d (pedido do dono): LB = shift momentâneo, RB = toggle
  ABC/123 (X segue backspace, Y segue espaço com kb aberto).
- `KB_BUMP` final em aberto (10px é prova; candidato ~3px — decisão do
  dono pendente).
