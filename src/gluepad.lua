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

-- F3a: qual tela do glue? (definida depois de collect(): usa a
-- varredura profunda.) LOGIN = tem EditBox visivel (so o login tem).
-- Outra tela = OTHER|<1o frame visivel> (nome estatico, sem texto/dado).
-- F3b-fix: varredura PROFUNDA (os edits moram dentro do AccountLogin,
-- nao como filhos diretos - a versao rasa lia OTHER|AccountLogin e
-- desligava o login). F4-nota: dialogo com editbox precisara ter
-- precedencia aqui (GlueDialog visivel = modo dialogo).

local function zoneOf(t, nm, lf, tp)
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
  if lf ~= nil and lf > 1000 then
    if tp ~= nil and tp < 440 then
      return "LINKS"
    end
    return "CONTAS"
  end
  return "CENTRO"
end

local function collect()
  local items = {}
  local n = 0
  local cap = 300
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
    items[n] = { ref = c, t = t, nm = nm, tp = tp, lf = lf, zn = zoneOf(t, nm, lf, tp) }
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

local function show(it)
  if it == nil then
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
end

local function hide(it)
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

function GluePad_Boot()
  local g = GluePad
  -- F3b: reconstroi ao trocar de tela (login <-> char); mesma tela = re-mostra.
  local scr = GluePad_Screen()
  if g.ready and g.screen == scr then
    -- Mesma tela: so sincroniza a camada dialogo (abriu/fechou sozinha).
    local items, n = collect()
    setdlg(g, finddlg(items, n))
    if g.dlg == nil then
      show(cur())
    end
    return
  end
  g.screen = scr
  g.mode = nil
  g.ready = nil
  g.order = nil
  g.zones = nil
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
        zn[z] = zn[z] + 1
        zones[z][zn[z]] = it
      end
      i = i + 1
    end
  else
    -- Tela desconhecida (realm/criacao/dialogo): descoberta, sem agir.
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
  -- F4b: dialogo por cima (se nasceu junto da tela); senao, foco da tela.
  if not setdlg(g, finddlg(items, n)) then
    show(cur())
  end
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
  if g.dlg ~= nil then
    if dir == "UP" or dir == "DOWN" then
      hidedlg(g)
      local m = table.getn(g.dlg)
      if dir == "UP" then
        g.dlgii = g.dlgii - 1
        if g.dlgii < 1 then
          g.dlgii = m
        end
      else
        g.dlgii = g.dlgii + 1
        if g.dlgii > m then
          g.dlgii = 1
        end
      end
      showdlg(g)
    end
    return
  end
  local z = g.zones[g.order[g.zi]]
  if z == nil or table.getn(z) == 0 then
    return
  end
  if dir == "UP" or dir == "DOWN" then
    hide(cur())
    local m = table.getn(z)
    if dir == "UP" then
      g.ii = g.ii - 1
      if g.ii < 1 then
        g.ii = m
      end
    else
      g.ii = g.ii + 1
      if g.ii > m then
        g.ii = 1
      end
    end
    show(cur())
  elseif dir == "LEFT" or dir == "RIGHT" then
    hide(cur())
    local h = g.hist
    h[table.getn(h) + 1] = g.zi
    if dir == "RIGHT" then
      g.zi = g.zi + 1
      if g.zi > table.getn(g.order) then
        g.zi = 1
      end
    else
      g.zi = g.zi - 1
      if g.zi < 1 then
        g.zi = table.getn(g.order)
      end
    end
    local nz = g.zones[g.order[g.zi]]
    if nz == nil or table.getn(nz) == 0 then
      g.zi = h[table.getn(h)]
      h[table.getn(h)] = nil
    else
      g.ii = 1
    end
    show(cur())
  end
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
  else
    if f.Click then
      f:Click()
    end
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
  return "SCR=" .. GluePad_Screen() .. " N=" .. tostring(n) .. " " .. table.concat(out, "")
end
