-- GluePad: navegacao por gamepad no glue (Lua 5.0 estrito).
-- Descoberta runtime (zero nome fixo), foco Vanilla nativo
-- (LockHighlight azul / caret do editbox). Sem textura, sem cursor.
-- Zonas do login (empirico, dump in-game): CENTRO (edits+Login, X~600),
-- CONTAS (Autologin*, X>1000), LINKS (Turtle/Credits/Cinematics),
-- SISTEMA (Exit/Quit). UP/DOWN dentro (com wrap), LEFT/RIGHT troca,
-- A ativa, B volta de zona (nunca quita). X/Y reservados.
-- Regras 5.0: table.getn/sort, sem #, sem gmatch, sem bitwise, sem goto,
-- ASCII puro. NUNCA le texto de EditBox.

GluePad = GluePad or {}
GluePad.ready = GluePad.ready or nil
GluePad.screen = GluePad.screen or nil

local function call1(f, m)
  local g = f[m]
  if type(g) ~= "function" then
    return nil
  end
  local ok, r = pcall(g, f)
  if ok then
    return r
  end
  return nil
end

local function framename(f)
  local g = f.GetName
  if type(g) ~= "function" then
    return nil
  end
  local ok, r = pcall(g, f)
  if ok and type(r) == "string" then
    return string.sub(r, 1, 40)
  end
  return nil
end

-- Largura do UIParent em unidades de UI (zonas relativas, a prova de
-- resolucao/aspecto; fallback 1600 = largura observada nos dumps).
local function uiparentW()
  if type(UIParent) ~= "table" and type(UIParent) ~= "userdata" then
    return 1600
  end
  local g = UIParent.GetWidth
  if type(g) ~= "function" then
    return 1600
  end
  local ok, r = pcall(g, UIParent)
  if ok and type(r) == "number" and r > 0 then
    return r
  end
  return 1600
end

-- F3a: qual tela do glue? (definida depois de collect(): usa a
-- varredura profunda.) LOGIN = tem EditBox visivel (so o login tem).
-- Outra tela = OTHER|<1o frame visivel> (nome estatico, sem texto/dado).
-- F3b-fix: varredura PROFUNDA (os edits moram dentro do AccountLogin,
-- nao como filhos diretos - a versao rasa lia OTHER|AccountLogin e
-- desligava o login). F4-nota: dialogo com editbox precisara ter
-- precedencia aqui (GlueDialog visivel = modo dialogo).

local function zoneOf(t, nm, lf, tp, w)
  if t == "EditBox" then
    return "CENTRO"
  end
  if nm == "AccountLoginLoginButton" then
    return "CENTRO"
  end
  if string.find(nm, "^Autologin") then
    return "CONTAS"
  end
  if string.find(nm, "Turtle") or string.find(nm, "Credits") or string.find(nm, "Cinematics") then
    return "LINKS"
  end
  if string.find(nm, "Exit") or string.find(nm, "Quit") then
    return "SISTEMA"
  end
  -- Corte relativo (era lf>1000 absoluto): mesma particao nos dumps.
  if lf ~= nil then
    local wv = w
    if wv == nil or wv <= 0 then
      wv = 1600
    end
    if lf / wv > 0.62 then
      if tp ~= nil and tp < 440 then
        return "LINKS"
      end
      return "CONTAS"
    end
  end
  return "CENTRO"
end

local function collect()
  local items = {}
  local n = 0
  local cap = 300
  local w = uiparentW()
  local function rec(c)
    if n >= cap then
      return
    end
    local vs = call1(c, "IsVisible")
    if vs ~= 1 then
      return
    end
    local t = call1(c, "GetObjectType")
    if t ~= "Button" and t ~= "EditBox" and t ~= "CheckButton" then
      return
    end
    local nm = nil
    local g = c.GetName
    if type(g) == "function" then
      local ok, r = pcall(g, c)
      if ok and type(r) == "string" then
        nm = r
      end
    end
    if nm == nil then
      nm = "?"
    end
    local en = call1(c, "IsEnabled")
    if t == "Button" or t == "CheckButton" then
      if en ~= 1 then
        return
      end
    end
    local tp = call1(c, "GetTop")
    local lf = call1(c, "GetLeft")
    if type(tp) ~= "number" then
      tp = 0
    end
    if type(lf) ~= "number" then
      lf = 0
    end
    n = n + 1
    items[n] = { ref = c, t = t, nm = nm, tp = tp, lf = lf, zn = zoneOf(t, nm, lf, tp, w) }
  end
  local function walk(f, depth)
    if n >= cap or depth > 6 then
      return
    end
    if type(f.GetChildren) ~= "function" then
      return
    end
    local ok, kids = pcall(function() local t = { f:GetChildren() }; return t end)
    if not ok or type(kids) ~= "table" then
      return
    end
    local i = 1
    while kids[i] ~= nil do
      local c = kids[i]
      if type(c) == "table" or type(c) == "userdata" then
        rec(c)
        walk(c, depth + 1)
      end
      i = i + 1
    end
  end
  if GlueParent ~= nil then
    walk(GlueParent, 0)
  end
  return items, n
end

function GluePad_Screen()
  if GlueParent == nil then
    return "NONE"
  end
  -- Profundo: algum EditBox visivel em qualquer nivel? (so o login tem).
  local items, n = collect()
  local i = 1
  -- F6b: criacao primeiro (tem EditBox de nome, mas e tela propria).
  -- Ancorado ^ : CharSelectCreateCharacterButton (char-select) nao casa.
  -- F7-addons: janela de addons tambem tem EditBox (ScriptMemory, so
  -- display) - modo proprio antes do LOGIN, mesma tecnica.
  while i <= n do
    local nm = items[i].nm
    if string.find(nm, "^CharacterCreate") or string.find(nm, "^CharCreate") then
      return "CREATE"
    end
    if string.find(nm, "^AddonList") or string.find(nm, "^AddonCharacter") then
      return "ADDONS"
    end
    i = i + 1
  end
  i = 1
  while i <= n do
    if items[i].t == "EditBox" then
      return "LOGIN"
    end
    i = i + 1
  end
  -- Raso p/ nomear a outra tela: 1o filho direto visivel (frame estatico).
  if type(GlueParent.GetChildren) ~= "function" then
    return "OTHER|?"
  end
  local ok, kids = pcall(function() local t = { GlueParent:GetChildren() }; return t end)
  if not ok or type(kids) ~= "table" then
    return "OTHER|?"
  end
  local top = nil
  i = 1
  while kids[i] ~= nil do
    local c = kids[i]
    if type(c) == "table" or type(c) == "userdata" then
      if call1(c, "IsVisible") == 1 then
        top = framename(c)
        if top ~= nil then
          break
        end
      end
    end
    i = i + 1
  end
  if top == nil then
    top = "?"
  end
  return "OTHER|" .. top
end

local ZORDER = { "CENTRO", "CONTAS", "LINKS", "SISTEMA" }
-- F3b: zonas do char-select (empirico, dump F3a). Lista = fileiras
-- CharSelectCharacterButton1..9; ACOES = EnterWorld/Create/ChangeRealm/
-- Delete/Back/Addons/SaveCharacter. Rotate pula fora (spinner de modelo).
local CZORDER = { "PERSONAGENS", "ACOES" }
-- F5b: zonas do realm (empirico, dump F5a). Fileiras RealmListRealmButton*
-- (3 visiveis; texto do realm nunca lido); OKCANCEL = Ok/Cancel/Close.
-- Sort-headers pulam fora (ordenacao, fora do fluxo).
local RZORDER = { "REALMS", "OKCANCEL" }

local function rzone(nm)
  if string.find(nm, "^RealmListRealmButton") then
    return "REALMS"
  end
  if string.find(nm, "RealmListOkButton") or
     string.find(nm, "RealmListCancelButton") or
     string.find(nm, "RealmListCloseButton") then
    return "OKCANCEL"
  end
  return nil
end
-- F6b: zonas da criacao (empirico, dump F6a). RACA 1..10, CLASSE 1..6,
-- GENERO, CUSTOM (setas 1..5 + Randomize), NOME (edit + dado), CONFIRMA
-- (Okay cria de verdade; Back cancela). Scroll/Rotate/faction pulam fora.
-- F6b-fix (UX): a tela e UM fluxo vertical (raca->genero->classe->custom
-- ->nome->okay); quebrar por categoria obrigava LEFT/RIGHT e invertia a
-- ordem visual. Uma zona CRIACAO ordenada por altura desce naturalmente.
-- F6c (pedido do dono): 3 zonas por TERCOS relativos (ESQUERDA/MEIO/
-- DIREITA); Randomize = excecao nomeada p/ o MEIO (mora a esquerda).
local KZORDER = { "ESQUERDA", "MEIO", "DIREITA" }
local function kzone(t, nm, lf, w)
  if string.find(nm, "RandomizeButton") then
    return "MEIO"
  end
  local incl = string.find(nm, "^CharacterCreateRaceButton") or
     string.find(nm, "^CharacterCreateClassButton") or
     string.find(nm, "^CharacterCreateGenderButton") or
     string.find(nm, "^CharacterCustomizationButtonFrame") or
     string.find(nm, "RandomName") or
     string.find(nm, "OkayButton") or
     string.find(nm, "BackButton") or
     t == "EditBox"
  if not incl then
    return nil
  end
  local wv = w
  if wv == nil or wv <= 0 then
    wv = 1600
  end
  local rel = 0
  if lf ~= nil then
    rel = lf / wv
  end
  if rel >= 0.66 then
    return "DIREITA"
  end
  if rel >= 0.33 then
    return "MEIO"
  end
  return "ESQUERDA"
end
-- F7-addons (pedido do dono: B sai da lista). ENTRADAS = checks
-- EntryNEnabled (dono pediu: navegar SO pelos checkboxes; A alterna).
-- Botoes de fileira SAEM (co-localizados = foco incerto). RODAPE =
-- Ok/Cancel/EnableAll/DisableAll. CROMO = Close/ForceLoad/DropDown
-- (alcancavel por seta; sem wrap p/ ninguem, F8).
-- Scroll e ScriptMemory pulam fora. Limite: scroll alem dos visiveis.
local AZORDER = { "ENTRADAS", "RODAPE", "CROMO" }
local function azone(t, nm)
  if t == "CheckButton" and string.find(nm, "^AddonListEntry%d+Enabled$") then
    return "ENTRADAS"
  end
  if string.find(nm, "AddonListOkButton") or
     string.find(nm, "AddonListCancelButton") or
     string.find(nm, "AddonListEnableAllButton") or
     string.find(nm, "AddonListDisableAllButton") then
    return "RODAPE"
  end
  if string.find(nm, "AddonListCloseButton") or
     string.find(nm, "AddonListForceLoad") or
     string.find(nm, "^AddonCharacterDropDown") then
    return "CROMO"
  end
  return nil
end
-- F10-wizard (tela de sugestao de realm, foto via Y: 5 checks + Cancel,
-- sem Okay - avanca sozinho ao escolher). B = Cancel.
local WZORDER = { "OPCOES", "SAIDA" }

local function wzone(nm)
  if string.find(nm, "^RealmWizard") and not string.find(nm, "Cancel") then
    return "OPCOES"
  end
  if string.find(nm, "RealmWizardCancel") then
    return "SAIDA"
  end
  return nil
end

-- F7-scroll: acha os botoes de scroll nativos entre os coletados
-- (refs guardadas; nada de nome fixo alem do padrao ScrollUp/Down).
local function findscroll(g, items, n)
  g.scrollUp = nil
  g.scrollDown = nil
  local i = 1
  while i <= n do
    local nm = items[i].nm
    if string.find(nm, "ScrollUp") then
      g.scrollUp = items[i].ref
    elseif string.find(nm, "ScrollDown") then
      g.scrollDown = items[i].ref
    end
    i = i + 1
  end
end

-- F9b: rola EXATAMENTE 1 fileira pela barra (SetValue + altura medida).
-- :Click() nativo pula ~11 (provado nos prints). Retorna true se rolou.
local function scrollStep(g, dir)
  local bar = g.scrollBar
  local h = g.rowH
  if bar == nil or type(h) ~= "number" or h <= 0 then
    return false
  end
  local gf = bar.GetValue
  if type(gf) ~= "function" then
    return false
  end
  local ok, cur = pcall(gf, bar)
  if not ok or type(cur) ~= "number" then
    return false
  end
  local gm = bar.GetMinMaxValues
  if type(gm) ~= "function" then
    return false
  end
  local ok2, mn, mx = pcall(gm, bar)
  if not ok2 or type(mn) ~= "number" or type(mx) ~= "number" then
    return false
  end
  local new = cur + h
  if dir == "UP" then
    new = cur - h
  end
  if new < mn then
    new = mn
  end
  if new > mx then
    new = mx
  end
  if new == cur then
    return false
  end
  local gs = bar.SetValue
  if type(gs) ~= "function" then
    return false
  end
  local ok3 = pcall(gs, bar, new)
  if not ok3 then
    return false
  end
  return true
end
local function czone(nm)
  if string.find(nm, "^CharSelectCharacterButton") then
    return "PERSONAGENS"
  end
  if string.find(nm, "EnterWorld") or string.find(nm, "CreateCharacter") or
     string.find(nm, "ChangeRealm") or string.find(nm, "Delete") or
     string.find(nm, "BackButton") or string.find(nm, "Addons") or
     string.find(nm, "SaveCharacter") then
    return "ACOES"
  end
  return nil
end

-- F11-anel: indicador de foco (pedido do dono). 4 bordas solidas ouro
-- (SetTexture RGBA, sem arquivo), reposicionadas no show(). Se o glue
-- nao tiver CreateFrame, vira no-op (LockHighlight segue). Mouse off.
-- F11-dup (pos-mortem do magenta duplo): defs roda 2x por processo
-- (BootNav + DoProbes-ARMED) - local morre no 2o load e duplica o frame.
-- Cache no GLOBAL sobrevive a reloads no mesmo estado.
local function ringparent()
  if type(UIParent) == "table" or type(UIParent) == "userdata" then
    return UIParent
  end
  if type(GlueParent) == "table" or type(GlueParent) == "userdata" then
    return GlueParent
  end
  return nil
end

local function ringshape()
  local g = GluePad
  if g._ring ~= nil then
    return g._ring
  end
  local par = ringparent()
  if par == nil then
    g.ringstage = "noparent"
    return nil
  end
  local ok, f = pcall(CreateFrame, "Frame", nil, par)
  if not ok then
    g.ringstage = "createfail"
    return nil
  end
  if f == nil then
    g.ringstage = "nilframe"
    return nil
  end
  g.ringstage = "okframe"
  pcall(function()
    f:SetFrameStrata("TOOLTIP")
    f:EnableMouse(false)
    f:Hide()
  end)
  local edges = {}
  local i = 1
  while i <= 4 do
    local ot, t = pcall(function()
      local tx = f:CreateTexture(nil, "OVERLAY")
      -- Ouro final (magenta era so diagnostico).
      tx:SetTexture(1, 0.82, 0, 0.9)
      tx:Hide()
      return tx
    end)
    if ot and t ~= nil then
      edges[i] = t
    end
    i = i + 1
  end
  g._ring = { f = f, e = edges }
  if table.getn(edges) < 4 then
    g.ringstage = "edges=" .. tostring(table.getn(edges))
  else
    g.ringstage = "ok"
  end
  return g._ring
end

local function ringshow(ref)
  local r = ringshape()
  if r == nil or r.f == nil then
    return
  end
  if table.getn(r.e) < 4 then
    return
  end
  local gw = call1(ref, "GetWidth")
  local gh = call1(ref, "GetHeight")
  if type(gw) ~= "number" or type(gh) ~= "number" then
    return
  end
  if gw <= 0 or gh <= 0 then
    return
  end
  local e = r.e
  local ok = pcall(function()
    e[1]:ClearAllPoints()
    e[1]:SetPoint("BOTTOMLEFT", ref, "TOPLEFT", -2, 0)
    e[1]:SetPoint("BOTTOMRIGHT", ref, "TOPRIGHT", 2, 0)
    e[1]:SetHeight(2)
    e[2]:ClearAllPoints()
    e[2]:SetPoint("TOPLEFT", ref, "BOTTOMLEFT", -2, 0)
    e[2]:SetPoint("TOPRIGHT", ref, "BOTTOMRIGHT", 2, 0)
    e[2]:SetHeight(2)
    e[3]:ClearAllPoints()
    e[3]:SetPoint("TOPRIGHT", ref, "TOPLEFT", 0, 2)
    e[3]:SetPoint("BOTTOMRIGHT", ref, "BOTTOMLEFT", 0, -2)
    e[3]:SetWidth(2)
    e[4]:ClearAllPoints()
    e[4]:SetPoint("TOPLEFT", ref, "TOPRIGHT", 0, 2)
    e[4]:SetPoint("BOTTOMLEFT", ref, "BOTTOMRIGHT", 0, -2)
    e[4]:SetWidth(2)
  end)
  if ok then
    pcall(function()
      local i = 1
      while i <= 4 do
        e[i]:Show()
        i = i + 1
      end
      r.f:Show()
    end)
  end
end

local function ringhide()
  local r = GluePad._ring
  if r == nil then
    return
  end
  pcall(function()
    local i = 1
    while i <= 4 do
      if r.e[i] ~= nil then
        r.e[i]:Hide()
      end
      i = i + 1
    end
    if r.f ~= nil then
      r.f:Hide()
    end
  end)
end

-- (RingDiag mora depois de cur(); ver abaixo.)
local function show(it)
  if it == nil then
    -- F11-fantasma2: sem foco = sem anel.
    ringhide()
    return
  end
  local f = it.ref
  if it.t == "EditBox" then
    if f.SetFocus then
      f:SetFocus()
    end
  else
    if f.LockHighlight then
      f:LockHighlight()
    end
  end
  -- F11-anel: contorno acompanha o foco (vale p/ dialogo tambem).
  -- F11-noring: lista de chars tem selecao nativa (anel = ruido).
  if it.noring == nil then
    ringshow(f)
  end
end

local function hide(it)
  -- F11-fantasma2: esconde o anel ANTES de qualquer saida.
  ringhide()
  if it == nil then
    return
  end
  local f = it.ref
  if it.t == "EditBox" then
    if f.ClearFocus then
      f:ClearFocus()
    end
  else
    if f.UnlockHighlight then
      f:UnlockHighlight()
    end
  end
end

-- (Camada dialogo F4b mora depois de cur(): usa hide/show/cur.)

local function cur()
  local g = GluePad
  if g.zones == nil then
    return nil
  end
  if g.order == nil then
    return nil
  end
  local z = g.zones[g.order[g.zi]]
  if z == nil then
    return nil
  end
  return z[g.ii]
end

-- F11-diag: relata o estagio do anel (DEPOIS de cur: usa cur como upvalue).
function GluePad_RingDiag()
  if type(CreateFrame) ~= "function" then
    return "nocreate"
  end
  local r = ringshape()
  local st = GluePad.ringstage
  if st == nil then
    st = "?"
  end
  if r == nil then
    return st
  end
  local n = table.getn(r.e)
  local it = cur()
  if it == nil then
    return st .. " edges=" .. tostring(n) .. " nofocus"
  end
  local gw = call1(it.ref, "GetWidth")
  local gh = call1(it.ref, "GetHeight")
  return st .. " edges=" .. tostring(n) .. " w=" .. tostring(gw) ..
         " h=" .. tostring(gh)
end

-- F4b: camada dialogo overlay. Botoes ^GlueDialogButton (provado: so o
-- Button1 visivel por vez no conectando/senha; cabem 1..3). Enquanto o
-- dialogo vive, ele captura D-pad/A/B; ao fechar, a tela retoma o foco.
-- A = clica o focado; B = clica o ULTIMO (convencao Cancel/Nao).
-- (Aqui depois de cur/show/hide: usa os 3 como upvalue, sem global nil.)
local function finddlg(items, n)
  local d = {}
  local m = 0
  local i = 1
  while i <= n do
    local it = items[i]
    if it.t == "Button" and string.find(it.nm, "^GlueDialogButton") then
      m = m + 1
      d[m] = it
    end
    i = i + 1
  end
  if m == 0 then
    return nil
  end
  if m > 1 then
    table.sort(d, function(a, b) return a.tp > b.tp end)
  end
  return d
end

local function showdlg(g)
  local d = g.dlg
  if d == nil then
    return
  end
  local it = d[g.dlgii]
  if it ~= nil then
    show(it)
  end
end

local function hidedlg(g)
  local d = g.dlg
  if d == nil then
    return
  end
  local it = d[g.dlgii]
  if it ~= nil then
    hide(it)
  end
end

-- Sincroniza a camada dialogo; retorna true se o dialogo esta no ar.
local function setdlg(g, dlg)
  if dlg ~= nil then
    if g.dlg == nil then
      hide(cur())
      g.dlg = dlg
      g.dlgii = 1
    else
      hidedlg(g)
      g.dlg = dlg
      if g.dlgii > table.getn(dlg) then
        g.dlgii = 1
      end
    end
    showdlg(g)
    return true
  end
  if g.dlg ~= nil then
    g.dlg = nil
    show(cur())
  end
  return false
end

-- F13a: teclado virtual (painel mudo navegavel, sem digitar).
-- Teclas sao Frames (nao Button/EditBox/CheckButton): collect()/Sniff()/
-- Dump()/Screen() nem as veem - exclusao por construcao, sem filtro por
-- nome. Nomes GluePadKB* (nossos, permitido) so p/ diagnostico via foc=.
-- Foco mora no campo (caret, SetFocus mantido); o anel ouro anda nas
-- teclas. A/B nao digitam na F13a (mudo); B fecha o painel.
-- Layout aprovado: 3 fileiras de letras + fileira [esp][del][ABC/123][OK].
-- Modo 123 existe como dado (a troca vem na F13b com INT_X).
local KB_ROWS_ABC = { "QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM" }
local KB_ROWS_123 = { "1234567890", "-/:;()$&@", ",?!'#%*" }
local KB_FUNCS = { "esp", "del", "ABC/123", "OK" }
local KB_KW = 44
local KB_KH = 36
local KB_GAP = 6
local KB_PAD = 12
-- Larguras da fileira de funcao (esp larga, resto estreito).
local KB_FW1 = 180
local KB_FW2 = 80
local KB_FW3 = 110
local KB_FW4 = 80

local function kbrows(mode)
  if mode == "123" then
    return KB_ROWS_123
  end
  return KB_ROWS_ABC
end

local function kbclose(g)
  if g.kb ~= nil and g.kb.panel ~= nil then
    pcall(function() g.kb.panel:Hide() end)
  end
  g.kb = nil
end

local function kbcursor(g)
  if g.kb == nil or g.kb.keys == nil then
    return
  end
  local row = g.kb.keys[g.kb.r]
  if row == nil then
    return
  end
  local key = row[g.kb.c]
  if key ~= nil then
    ringshow(key)
  end
end

-- F13a-fix (letras invisiveis): checa se a fonte vale. So vale a
-- FontString cujo GetText ecoa o rotulo E cuja GetStringWidth > 0
-- (largura do texto rasterizado; 0 = sem fonte). Sem GetStringWidth
-- no cliente, vale o eco do texto.
local function kbcheck(key, fs, label)
  local ok = pcall(function()
    fs:ClearAllPoints()
    fs:SetAllPoints(key)
    fs:SetText(label)
    fs:SetTextColor(0.9, 0.85, 0.7)
  end)
  if not ok then
    return false
  end
  local back = nil
  pcall(function() back = fs:GetText() end)
  if back ~= label then
    return false
  end
  local sw = call1(fs, "GetStringWidth")
  if type(sw) == "number" then
    return sw > 0
  end
  return true
end

-- Cascata de fonte (1o passo que passa no kbcheck vence):
-- 1=GameFontNormal, 2=GameFontNormalSmall, 3=FRIZQT 14, 4=FRIZQT 12.
-- Retorna passo + FontString vencedora (p/ re-rotular no toggle F13b).
local function kbsetlabel(key, label)
  local okf, fs = pcall(function()
    return key:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  end)
  if okf and fs ~= nil and kbcheck(key, fs, label) then
    return 1, fs
  end
  local ok2, fs2 = pcall(function()
    return key:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  end)
  if ok2 and fs2 ~= nil and kbcheck(key, fs2, label) then
    return 2, fs2
  end
  local ok3, fs3 = pcall(function()
    return key:CreateFontString(nil, "OVERLAY")
  end)
  if ok3 and fs3 ~= nil then
    local sz = 14
    while sz >= 12 do
      local step = 3
      if sz < 14 then
        step = 4
      end
      local px = sz
      local okf2 = pcall(function()
        fs3:SetFont("Fonts\\FRIZQT__.TTF", px)
      end)
      if okf2 and kbcheck(key, fs3, label) then
        return step, fs3
      end
      sz = sz - 2
    end
  end
  return 0, nil
end

-- F13b-pos (painel cobria o campo de cima na senha): ancora no EditBox
-- mais alto da tela (login: acima do Account, nenhum campo coberto).
-- Usa o collect (so visiveis); maior tp = mais alto na tela.
local function kbanchor(panel, field)
  local tgt = field
  local items, n = collect()
  local best = nil
  local besttp = nil
  local i = 1
  while i <= n do
    local it = items[i]
    if it.t == "EditBox" then
      if besttp == nil or it.tp > besttp then
        besttp = it.tp
        best = it.ref
      end
    end
    i = i + 1
  end
  if best ~= nil then
    tgt = best
  end
  pcall(function()
    panel:ClearAllPoints()
    panel:SetPoint("BOTTOM", tgt, "TOP", 0, 12)
    panel:Show()
  end)
end

-- Constroi o painel UMA vez (cache global: defs roda 2x por processo,
-- licao do magenta duplo - local morre, global sobrevive).
local function kbbuild(g, field)
  kbclose(g)
  local par = ringparent()
  if par == nil then
    return false
  end
  local rows = kbrows("ABC")
  local n1 = string.len(rows[1])
  local w = n1 * KB_KW + (n1 - 1) * KB_GAP + 2 * KB_PAD
  local h = 4 * KB_KH + 3 * KB_GAP + 2 * KB_PAD
  local ok, p = pcall(CreateFrame, "Frame", "GluePadKB_Panel", par)
  if not ok or p == nil then
    return false
  end
  local panel = p
  pcall(function()
    panel:SetWidth(w)
    panel:SetHeight(h)
    panel:EnableMouse(false)
    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(0, 0, 0, 0.85)
    bg:ClearAllPoints()
    bg:SetAllPoints(panel)
    panel:SetFrameStrata("TOOLTIP")
    kbanchor(panel, field)
  end)
  local keys = {}
  local lab = {}
  local r = 1
  while r <= 4 do
    keys[r] = {}
    lab[r] = {}
    local n = 0
    if r <= 3 then
      n = string.len(rows[r])
    else
      n = 4
    end
    local roww = 0
    if r <= 3 then
      roww = n * KB_KW + (n - 1) * KB_GAP
    else
      roww = KB_FW1 + KB_FW2 + KB_FW3 + KB_FW4 + 3 * KB_GAP
    end
    local x = (w - roww) / 2
    local y = KB_PAD + (r - 1) * (KB_KH + KB_GAP)
    local c = 1
    while c <= n do
      local kw = KB_KW
      local label = nil
      if r <= 3 then
        label = string.sub(rows[r], c, c)
      else
        label = KB_FUNCS[c]
        if c == 1 then
          kw = KB_FW1
        elseif c == 2 then
          kw = KB_FW2
        elseif c == 3 then
          kw = KB_FW3
        else
          kw = KB_FW4
        end
      end
      local knm = "GluePadKB_" .. tostring(r) .. "_" .. tostring(c)
      local okk, key = pcall(CreateFrame, "Frame", knm, panel)
      if okk and key ~= nil then
        local fs = nil
        pcall(function()
          key:SetWidth(kw)
          key:SetHeight(KB_KH)
          key:EnableMouse(false)
          local t = key:CreateTexture(nil, "BACKGROUND")
          t:SetTexture(0.12, 0.12, 0.12, 0.9)
          t:ClearAllPoints()
          t:SetAllPoints(key)
          key:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -y)
          local st, fw = kbsetlabel(key, label)
          if st > 0 and GluePad._kbfont == nil then
            GluePad._kbfont = st
          end
          fs = fw
          key:Show()
        end)
        keys[r][c] = key
        lab[r][c] = fs
      end
      x = x + kw + KB_GAP
      c = c + 1
    end
    r = r + 1
  end
  g.kb = { mode = "ABC", r = 1, c = 1, keys = keys, lab = lab, panel = panel }
  kbcursor(g)
  return true
end

-- Abre o painel (reaproveita o cache; re-ancora no campo atual).
local function kbopen(g, field)
  if g.kb ~= nil then
    return
  end
  local cx = GluePad._kbcache
  if cx ~= nil and cx.panel ~= nil and cx.keys ~= nil and cx.lab ~= nil then
    kbanchor(cx.panel, field)
    g.kb = { mode = "ABC", r = 1, c = 1, keys = cx.keys, lab = cx.lab, panel = cx.panel }
    kbcursor(g)
    return
  end
  if kbbuild(g, field) then
    GluePad._kbcache = { keys = g.kb.keys, lab = g.kb.lab, panel = g.kb.panel }
  end
end

-- Anda no grid (clamp, sem wrap - regra F8). Vertical casa por centro-x
-- (fileiras tem larguras diferentes); sem geometria, espelha o indice.
local function kbmove(g, dir)
  if g.kb == nil or g.kb.keys == nil then
    return
  end
  local r = g.kb.r
  local c = g.kb.c
  -- F13b-wrap (pedido do dono): SO no teclado as bordas pulam p/ o
  -- lado oposto (Q<->P etc.). Nas telas segue sem wrap (regra F8).
  if dir == "LEFT" then
    if c > 1 then
      g.kb.c = c - 1
    else
      g.kb.c = table.getn(g.kb.keys[r])
    end
  elseif dir == "RIGHT" then
    local m = table.getn(g.kb.keys[r])
    if c < m then
      g.kb.c = c + 1
    else
      g.kb.c = 1
    end
  elseif dir == "UP" or dir == "DOWN" then
    local nr = r - 1
    if dir == "DOWN" then
      nr = r + 1
    end
    if nr < 1 then
      nr = 4
    end
    if nr > 4 then
      nr = 1
    end
    if g.kb.keys[nr] ~= nil then
      local m = table.getn(g.kb.keys[nr])
      if m >= 1 then
        local best = c
        if best > m then
          best = m
        end
        local curk = g.kb.keys[r][c]
        local cx = nil
        if curk ~= nil then
          local lx = call1(curk, "GetLeft")
          local lw = call1(curk, "GetWidth")
          if type(lx) == "number" and type(lw) == "number" then
            cx = lx + lw / 2
          end
        end
        if cx ~= nil then
          local i = 1
          local bestd = nil
          while i <= m do
            local k = g.kb.keys[nr][i]
            if k ~= nil then
              local lx = call1(k, "GetLeft")
              local lw = call1(k, "GetWidth")
              if type(lx) == "number" and type(lw) == "number" then
                local d = lx + lw / 2 - cx
                if d < 0 then
                  d = -d
                end
                if bestd == nil or d < bestd then
                  bestd = d
                  best = i
                end
              end
            end
            i = i + 1
          end
        end
        g.kb.r = nr
        g.kb.c = best
      end
    end
  end
  kbcursor(g)
end

-- F13b: alterna ABC/123 no painel (X). Re-rotula com as fileiras do
-- modo novo (mesmos comprimentos por construcao); cursor preservado.
function GluePad_KbToggle()
  local g = GluePad
  if g.kb == nil or g.kb.lab == nil then
    return
  end
  local nm = "123"
  if g.kb.mode == "123" then
    nm = "ABC"
  end
  local rows = kbrows(nm)
  local r = 1
  while r <= 3 do
    local row = rows[r]
    local c = 1
    while c <= string.len(row) do
      local t = nil
      if g.kb.lab[r] ~= nil then
        t = g.kb.lab[r][c]
      end
      if t ~= nil then
        local lb = string.sub(row, c, c)
        pcall(function() t:SetText(lb) end)
      end
      c = c + 1
    end
    r = r + 1
  end
  g.kb.mode = nm
  kbcursor(g)
end

-- F13b: painel aberto? (X/Y do pad viram backspace/espaco; Y volta a
-- ser dump com o painel fechado). Escreve 1/nil no Mbox p/ o C ler.
function GluePad_IsKb()
  if GluePad.kb ~= nil then
    GluePad_Mbox = 1
  else
    GluePad_Mbox = nil
  end
end

-- F13b: A no painel. Retorna VK (numero) p/ a DLL enviar carimbado,
-- -1 = tratado aqui (OK fecha, ABC/123 alterna, resto no-op),
-- nil = sem painel (a DLL segue o Activate normal).
-- Nunca le texto do campo; rotulo e DADO nosso.
function GluePad_KbPress()
  local g = GluePad
  if g.kb == nil then
    return nil
  end
  local r = g.kb.r
  local c = g.kb.c
  if r == 4 then
    local f = KB_FUNCS[c]
    if f == "esp" then
      return 32
    end
    if f == "del" then
      return 8
    end
    if f == "ABC/123" then
      GluePad_KbToggle()
      return -1
    end
    if f == "OK" then
      kbclose(g)
      show(cur())
      return -1
    end
    return -1
  end
  local row = kbrows(g.kb.mode)[r]
  if row == nil or c > string.len(row) then
    return -1
  end
  local b = string.byte(string.sub(row, c, c))
  -- Letras (0x41-0x5A) e digitos (0x30-0x39) = wVk direto, sem shift
  -- (minusculas; shift vem na F13d). Simbolos: no-op na F13b.
  if (b >= 65 and b <= 90) or (b >= 48 and b <= 57) then
    return b
  end
  return -1
end

-- F7-diag: nome do foco atual (so nomes de frame; p/ calibrar o espacial).
function GluePad_FocusName()
  local g = GluePad
  if g.dlg ~= nil then
    local it = g.dlg[g.dlgii]
    if it ~= nil and it.nm ~= nil then
      return it.nm
    end
    return "dlg?"
  end
  -- F13b: cursor posicional (nunca o rotulo: nao vaza a digitacao).
  if g.kb ~= nil then
    return "KB:" .. tostring(g.kb.r) .. "," .. tostring(g.kb.c)
  end
  local it = cur()
  if it ~= nil and it.nm ~= nil then
    return it.nm
  end
  return "?"
end

function GluePad_Boot()
  local g = GluePad
  -- F3b: reconstroi ao trocar de tela (login <-> char); mesma tela = re-mostra.
  local scr = GluePad_Screen()
  if g.ready and g.screen == scr then
    -- Mesma tela: so sincroniza a camada dialogo (abriu/fechou sozinha)
    -- e recaptura o scroll (Up aparece ao sair do topo).
    local items, n = collect()
    local hadkb = (g.kb ~= nil)
    setdlg(g, finddlg(items, n))
    findscroll(g, items, n)
    g.sniff = GluePad_Sniff()
    if g.dlg == nil then
      if hadkb then
        -- F13a: painel segue aberto; so re-ancora o anel na tecla.
        kbcursor(g)
      else
        show(cur())
      end
    elseif hadkb then
      -- F13a: dialogo vence; fecha o painel junto.
      kbclose(g)
    end
    return
  end
  g.screen = scr
  g.mode = nil
  g.ready = nil
  g.order = nil
  g.zones = nil
  g.scrollUp = nil
  g.scrollDown = nil
  g.scrollBar = nil
  g.rowH = nil
  -- F13a: troca de tela fecha o painel (cache segue p/ reabrir).
  kbclose(g)
  -- F11-fantasma: o anel e global (nao some c/ a tela) - esconde no rebuild.
  ringhide()
  local items, n = collect()
  local zones = nil
  local zn = nil
  local order = nil
  if scr == "LOGIN" then
    g.mode = "login"
    order = ZORDER
    zones = { CENTRO = {}, CONTAS = {}, LINKS = {}, SISTEMA = {} }
    zn = { CENTRO = 0, CONTAS = 0, LINKS = 0, SISTEMA = 0 }
    local i = 1
    while i <= n do
      local it = items[i]
      local z = it.zn
      if zones[z] ~= nil then
        zn[z] = zn[z] + 1
        zones[z][zn[z]] = it
      end
      i = i + 1
    end
  elseif scr == "OTHER|CharacterSelect" then
    g.mode = "char"
    order = CZORDER
    zones = { PERSONAGENS = {}, ACOES = {} }
    zn = { PERSONAGENS = 0, ACOES = 0 }
    local i = 1
    while i <= n do
      local it = items[i]
      local z = czone(it.nm)
      if z ~= nil and zones[z] ~= nil then
        -- F11-noring: fileira tem selecao nativa azul (anel = ruido).
        if z == "PERSONAGENS" then
          it.noring = true
        end
        zn[z] = zn[z] + 1
        zones[z][zn[z]] = it
      end
      i = i + 1
    end
  elseif scr == "OTHER|RealmList" then
    g.mode = "realm"
    order = RZORDER
    zones = { REALMS = {}, OKCANCEL = {} }
    zn = { REALMS = 0, OKCANCEL = 0 }
    local i = 1
    while i <= n do
      local it = items[i]
      local z = rzone(it.nm)
      if z ~= nil and zones[z] ~= nil then
        zn[z] = zn[z] + 1
        zones[z][zn[z]] = it
      end
      i = i + 1
    end
  elseif scr == "OTHER|RealmWizard" then
    g.mode = "wizard"
    order = WZORDER
    zones = { OPCOES = {}, SAIDA = {} }
    zn = { OPCOES = 0, SAIDA = 0 }
    local i = 1
    while i <= n do
      local it = items[i]
      local z = wzone(it.nm)
      if z ~= nil and zones[z] ~= nil then
        zn[z] = zn[z] + 1
        zones[z][zn[z]] = it
      end
      i = i + 1
    end
  elseif scr == "CREATE" then
    g.mode = "create"
    order = KZORDER
    zones = { ESQUERDA = {}, MEIO = {}, DIREITA = {} }
    zn = { ESQUERDA = 0, MEIO = 0, DIREITA = 0 }
    local bw = uiparentW()
    local i = 1
    while i <= n do
      local it = items[i]
      local z = kzone(it.t, it.nm, it.lf, bw)
      if z ~= nil and zones[z] ~= nil then
        zn[z] = zn[z] + 1
        zones[z][zn[z]] = it
      end
      i = i + 1
    end
  elseif scr == "ADDONS" then
    g.mode = "addons"
    order = AZORDER
    zones = { ENTRADAS = {}, RODAPE = {}, CROMO = {} }
    zn = { ENTRADAS = 0, RODAPE = 0, CROMO = 0 }
    local i = 1
    while i <= n do
      local it = items[i]
      local z = azone(it.t, it.nm)
      if z ~= nil and zones[z] ~= nil then
        zn[z] = zn[z] + 1
        zones[z][zn[z]] = it
      end
      i = i + 1
    end
  else
    -- Tela desconhecida: descoberta, sem agir (e sem anel fantasma).
    ringhide()
    return
  end
  local k = 1
  while k <= table.getn(order) do
    local z = zones[order[k]]
    if table.getn(z) > 1 then
      table.sort(z, function(a, b) return a.tp > b.tp end)
    end
    k = k + 1
  end
  g.order = order
  g.zones = zones
  g.zi = 1
  g.ii = 1
  g.hist = {}
  g.ready = true
  -- Botoes primeiro (a barra resolve a partir deles).
  findscroll(g, items, n)
  -- F9b: resolve barra (pai do botao) + altura da fileira (pos-sort).
  if g.mode == "addons" then
    local ez = g.zones["ENTRADAS"]
    if ez ~= nil and table.getn(ez) >= 2 then
      local h = ez[1].tp - ez[2].tp
      if h > 0 then
        g.rowH = h
      end
    end
    local sb = g.scrollDown
    if sb == nil then
      sb = g.scrollUp
    end
    g.scrollBar = nil
    if sb ~= nil then
      local par = call1(sb, "GetParent")
      if (type(par) == "table" or type(par) == "userdata") and
         type(par.SetValue) == "function" and
         type(par.GetValue) == "function" then
        g.scrollBar = par
      end
    end
  end
  -- F4b: dialogo por cima (se nasceu junto da tela); senao, foco da tela.
  if not setdlg(g, finddlg(items, n)) then
    show(cur())
  end
  g.sniff = GluePad_Sniff()
end

-- F7-scroll: releitura forcada (pos-scroll: o conjunto visivel mudou).
-- Preserva o historico se a tela continua a mesma.
function GluePad_Rebuild()
  local g = GluePad
  local s = g.screen
  local h = g.hist
  g.ready = nil
  GluePad_Boot()
  if g.screen == s and h ~= nil then
    g.hist = h
  end
end

-- F11-B (some o fantasma na troca): pos-clique que pode trocar de tela,
-- some o anel e DESARMA sem mostrar (o proximo toque constroi na tela
-- que estiver valendo). Vale p/ A e B, toda tela.
function GluePad_Disarm()
  local g = GluePad
  ringhide()
  -- F13a: desarma fecha o painel junto (vale p/ dialogo de erro no meio
  -- da digitacao).
  kbclose(g)
  g.ready = nil
  g.zones = nil
  g.order = nil
  g.mode = nil
  g.screen = nil
  g.dlg = nil
  g.hist = {}
  g.sniff = nil
end

-- F12-sync: assinatura leve (visivel+tipo+nome, sem posicao) p/ farejar
-- mudanca a 4Hz. collect() completo so quando muda (via Sync).
function GluePad_Sniff()
  if GlueParent == nil then
    return "?"
  end
  local parts = {}
  local m = 0
  local cap = 300
  local function rec(c)
    if m >= cap then
      return
    end
    local vs = call1(c, "IsVisible")
    if vs ~= 1 then
      return
    end
    local t = call1(c, "GetObjectType")
    if t ~= "Button" and t ~= "EditBox" and t ~= "CheckButton" then
      return
    end
    local nm = framename(c)
    if nm == nil then
      nm = "?"
    end
    m = m + 1
    parts[m] = t .. "|" .. nm .. ";"
  end
  local function walk(f, depth)
    if m >= cap or depth > 6 then
      return
    end
    if type(f.GetChildren) ~= "function" then
      return
    end
    local ok, kids = pcall(function() local t = { f:GetChildren() }; return t end)
    if not ok or type(kids) ~= "table" then
      return
    end
    local i = 1
    while kids[i] ~= nil do
      local c = kids[i]
      if type(c) == "table" or type(c) == "userdata" then
        rec(c)
        walk(c, depth + 1)
      end
      i = i + 1
    end
  end
  walk(GlueParent, 0)
  return table.concat(parts)
end

-- F12-sync (vigia 250ms, hide-only, sem log): reage a troca SEM clique
-- (dialogo que fecha sozinho, auth com delay). Nunca move foco; mostrar
-- so no dialogo que ABRIU sozinho (foco nativo existe). Silencio total.
function GluePad_Sync()
  local g = GluePad
  if not g.ready then
    return
  end
  local sig = GluePad_Sniff()
  if sig == g.sniff then
    return
  end
  g.sniff = sig
  local scr = GluePad_Screen()
  if scr ~= g.screen then
    GluePad_Disarm()
    return
  end
  local items, n = collect()
  local dlg = finddlg(items, n)
  -- F13a: dialogo que abre com o painel aberto fecha o painel.
  if dlg ~= nil and g.kb ~= nil then
    kbclose(g)
  end
  if dlg ~= nil then
    if g.dlg == nil then
      g.dlg = dlg
      g.dlgii = 1
    else
      g.dlg = dlg
      if g.dlgii > table.getn(dlg) then
        g.dlgii = 1
      end
    end
    showdlg(g)
  else
    if g.dlg ~= nil then
      g.dlg = nil
      ringhide()
    end
  end
  findscroll(g, items, n)
end

-- F6c: LEFT/RIGHT espacial (pedido do dono: ir p/ o lado certo, nao
-- ciclar a esmo). F6d: UP/DOWN tambem (fim da prisao de zona: do painel
-- Autologin, DOWN desce p/ os links). Vizinho real na direcao. F8 (dono):
-- SEM wrap - no fim, fica parado (vale p/ toda tela). F9: vertical pesa
-- o eixo 4x (fileira mais proxima ganha do alinhado longe: ForceLoad
-- caia no Okay a 422 abaixo em vez da lista a 30). B/hist preservados.
local function spatial(g, dir)
  local c = cur()
  if c == nil then
    return nil
  end
  local bestscore = nil
  local bestzi = nil
  local bestii = nil
  local zi = 1
  while zi <= table.getn(g.order) do
    local z = g.zones[g.order[zi]]
    local ii = 1
    while ii <= table.getn(z) do
      local it = z[ii]
      local dx = it.lf - c.lf
      local dy = c.tp - it.tp
      local prim = nil
      local sec = nil
      if dir == "RIGHT" and dx > 4 then
        prim = dx
        sec = dy
      elseif dir == "LEFT" and dx < -4 then
        prim = -dx
        sec = dy
      elseif dir == "DOWN" and dy > 4 then
        prim = dy
        sec = dx
      elseif dir == "UP" and dy < -4 then
        prim = -dy
        sec = dx
      end
      if prim ~= nil then
        if sec < 0 then
          sec = -sec
        end
        -- F9: vertical pesa o eixo 4x; horizontal segue 2x (validado).
        local score = prim + 2 * sec
        if dir == "UP" or dir == "DOWN" then
          score = prim * 4 + sec
        end
        if bestscore == nil or score < bestscore then
          bestscore = score
          bestzi = zi
          bestii = ii
        end
      end
      ii = ii + 1
    end
    zi = zi + 1
  end
  if bestscore ~= nil then
    return { zi = bestzi, ii = bestii }
  end
  -- F8: sem vizinho na direcao = fica parado (sem wrap em toda tela).
  return nil
end

function GluePad_Move(dir)
  local g = GluePad
  if not g.ready or g.zones == nil then
    return
  end
  -- Seguranca: sem modo (tela desconhecida/stale), nunca age.
  if g.mode == nil then
    return
  end
  -- F4b: dialogo no ar captura tudo (so UP/DOWN andam; resto ignora).
  -- F8: sem wrap - nos extremos, fica parado.
  if g.dlg ~= nil then
    if dir == "UP" or dir == "DOWN" then
      hidedlg(g)
      local m = table.getn(g.dlg)
      if dir == "UP" then
        g.dlgii = g.dlgii - 1
        if g.dlgii < 1 then
          g.dlgii = 1
        end
      else
        g.dlgii = g.dlgii + 1
        if g.dlgii > m then
          g.dlgii = m
        end
      end
      showdlg(g)
    end
    return
  end
  -- F13a: painel aberto captura o D-pad (anda no grid, nunca nas zonas).
  if g.kb ~= nil then
    kbmove(g, dir)
    return
  end
  local z = g.zones[g.order[g.zi]]
  if z == nil or table.getn(z) == 0 then
    return
  end
  -- F7-scroll: na borda da lista de addons, rola 1 passo nativo em vez de
  -- cair no rodape; fim de curso (botao ausente/desabilitado) = espacial.
  -- F9-sticky: o foco gruda no MESMO addon (sobe/desce 1pos na releitura),
  -- ritmo rola-pisa (sem pular fileira, sem disparada no hold).
  -- F9b: passo EXATO via barra (click nativo pula ~11, provado no print);
  -- click legado so como fallback sem barra.
  if g.mode == "addons" and (dir == "UP" or dir == "DOWN") and
     g.order[g.zi] == "ENTRADAS" then
    local m = table.getn(z)
    local edge = (dir == "DOWN" and g.ii >= m) or (dir == "UP" and g.ii <= 1)
    if edge and m > 0 then
      local btn = g.scrollDown
      if dir == "UP" then
        btn = g.scrollUp
      end
      local okBtn = (btn ~= nil and call1(btn, "IsEnabled") == 1)
      if okBtn or g.scrollBar ~= nil then
        local keep = g.ii
        hide(cur())
        local moved = scrollStep(g, dir)
        if not moved and okBtn and g.scrollBar == nil then
          if btn.Click then
            btn:Click()
          end
          moved = true
        end
        if moved then
          GluePad_Rebuild()
          local oi = 1
          while oi <= table.getn(g.order) do
            if g.order[oi] == "ENTRADAS" then
              g.zi = oi
            end
            oi = oi + 1
          end
          local nz = g.zones["ENTRADAS"]
          if nz ~= nil and table.getn(nz) > 0 then
            local nm = table.getn(nz)
            if dir == "DOWN" then
              g.ii = keep - 1
              if g.ii < 1 then
                g.ii = 1
              end
            else
              g.ii = keep + 1
            end
            if g.ii > nm then
              g.ii = nm
            end
            show(cur())
          end
          return
        end
        show(cur())
      end
    end
  end
  -- F6d: toda direcao e espacial (entre zonas inclusive); B guarda a zona.
  local tgt = spatial(g, dir)
  if tgt == nil then
    return
  end
  if tgt.zi == g.zi and tgt.ii == g.ii then
    return
  end
  hide(cur())
  if tgt.zi ~= g.zi then
    local h = g.hist
    h[table.getn(h) + 1] = g.zi
  end
  g.zi = tgt.zi
  g.ii = tgt.ii
  show(cur())
end

function GluePad_Back()
  local g = GluePad
  if not g.ready or g.zones == nil then
    return
  end
  if g.mode == nil then
    return
  end
  -- F4b: dialogo no ar = B clica o ULTIMO (convencao Cancel/Nao).
  if g.dlg ~= nil then
    local d = g.dlg
    local it = d[table.getn(d)]
    if it ~= nil then
      local f = it.ref
      if f.Click then
        f:Click()
      end
    end
    GluePad_Disarm()
    return
  end
  -- F13a: B com o painel aberto fecha o painel e volta o anel ao campo.
  if g.kb ~= nil then
    kbclose(g)
    show(cur())
    return
  end
  -- F10-wizard: B = Cancel (sai da sugestao).
  if g.mode == "wizard" then
    local oi = 1
    while oi <= table.getn(g.order) do
      local wz = g.zones[g.order[oi]]
      if wz ~= nil then
        local i = 1
        while i <= table.getn(wz) do
          if string.find(wz[i].nm, "Cancel") then
            local f = wz[i].ref
            if f.Click then
              f:Click()
            end
            GluePad_Disarm()
            return
          end
          i = i + 1
        end
      end
      oi = oi + 1
    end
    return
  end
  -- F7-addons: B = Cancel (sai sem salvar; Ok confirma via A).
  if g.mode == "addons" then
    local oi = 1
    while oi <= table.getn(g.order) do
      local az = g.zones[g.order[oi]]
      if az ~= nil then
        local i = 1
        while i <= table.getn(az) do
          if string.find(az[i].nm, "Cancel") then
            local f = az[i].ref
            if f.Click then
              f:Click()
            end
            GluePad_Disarm()
            return
          end
          i = i + 1
        end
      end
      oi = oi + 1
    end
    return
  end
  -- F6b: B na criacao = Back (cancela, volta ao char-select; varre as
  -- zonas, robusto a reparticao).
  if g.mode == "create" then
    local oi = 1
    while oi <= table.getn(g.order) do
      local kz = g.zones[g.order[oi]]
      if kz ~= nil then
        local i = 1
        while i <= table.getn(kz) do
          if string.find(kz[i].nm, "Back") then
            local f = kz[i].ref
            if f.Click then
              f:Click()
            end
            GluePad_Disarm()
            return
          end
          i = i + 1
        end
      end
      oi = oi + 1
    end
    return
  end
  -- F5b: B no realm = Cancel (volta ao char-select).
  if g.mode == "realm" then
    local oz = g.zones["OKCANCEL"]
    if oz ~= nil then
      local i = 1
      while i <= table.getn(oz) do
          if string.find(oz[i].nm, "Cancel") then
            local f = oz[i].ref
            if f.Click then
              f:Click()
            end
            GluePad_Disarm()
            return
          end
        i = i + 1
      end
    end
    return
  end
  -- F3b: B no char-select = voltar ao login (botao Back).
  if g.mode == "char" then
    local az = g.zones["ACOES"]
    if az ~= nil then
      local i = 1
      while i <= table.getn(az) do
          if string.find(az[i].nm, "Back") then
            local f = az[i].ref
            if f.Click then
              f:Click()
            end
            GluePad_Disarm()
            return
          end
        i = i + 1
      end
    end
    return
  end
  local h = g.hist
  if table.getn(h) == 0 then
    return
  end
  hide(cur())
  g.zi = h[table.getn(h)]
  h[table.getn(h)] = nil
  g.ii = 1
  show(cur())
end

function GluePad_Activate()
  local g = GluePad
  if not g.ready or g.zones == nil then
    return
  end
  -- Nunca :Click() sem modo (ex.: Login escondido no char-select).
  if g.mode == nil then
    return
  end
  -- F4b: dialogo no ar = A clica o focado.
  if g.dlg ~= nil then
    local it = g.dlg[g.dlgii]
    if it ~= nil then
      local f = it.ref
      if f.Click then
        f:Click()
      end
    end
    -- F11-B: o click pode abrir/fechar dialogo (refs mudam).
    GluePad_Disarm()
    return
  end
  -- F13a: painel aberto = A mudo (ainda nao digita; F13b liga o envio).
  if g.kb ~= nil then
    return
  end
  local it = cur()
  if it == nil then
    return
  end
  local f = it.ref
  if it.t == "EditBox" then
    if f.SetFocus then
      f:SetFocus()
    end
    -- F13a: A no campo abre o painel mudo (caret fica no campo).
    kbopen(g, f)
  else
    if f.Click then
      f:Click()
    end
    -- F11-B: o click pode reembaralhar/trocar a tela - desarma em vez de
    -- rezonar velho (proximo toque constroi do zero, sem fantasma).
    GluePad_Disarm()
  end
end

function GluePad_Dump()
  local items, n = collect()
  local out = {}
  local m = 0
  local i = 1
  while i <= n do
    local it = items[i]
    m = m + 1
    out[m] = it.t .. "|" .. it.nm .. "|1|1|" .. tostring(it.tp) .. "|" .. tostring(it.lf) .. ";"
    i = i + 1
  end
  -- F13b: estado posicional (modo + fileira,coluna + passo da fonte;
  -- nunca rotulo: nao vaza a digitacao).
  local kbstr = "-"
  if GluePad.kb ~= nil then
    local ff = 0
    if GluePad._kbfont ~= nil then
      ff = GluePad._kbfont
    end
    kbstr = GluePad.kb.mode .. " " .. tostring(GluePad.kb.r) .. "," ..
            tostring(GluePad.kb.c) .. " f" .. tostring(ff)
  end
  return "SCR=" .. GluePad_Screen() .. " N=" .. tostring(n) .. " KB=" .. kbstr .. " " .. table.concat(out, "")
end
