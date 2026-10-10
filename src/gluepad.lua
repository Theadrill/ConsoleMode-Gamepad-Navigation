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

local ZORDER = { "CENTRO", "CONTAS", "LINKS", "SISTEMA" }

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

local function cur()
  local g = GluePad
  if g.zones == nil then
    return nil
  end
  local z = g.zones[ZORDER[g.zi]]
  if z == nil then
    return nil
  end
  return z[g.ii]
end

function GluePad_Boot()
  local g = GluePad
  if g.ready then
    show(cur())
    return
  end
  local items, n = collect()
  local zones = { CENTRO = {}, CONTAS = {}, LINKS = {}, SISTEMA = {} }
  local zn = { CENTRO = 0, CONTAS = 0, LINKS = 0, SISTEMA = 0 }
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
  local k = 1
  while k <= table.getn(ZORDER) do
    local z = zones[ZORDER[k]]
    if table.getn(z) > 1 then
      table.sort(z, function(a, b) return a.tp > b.tp end)
    end
    k = k + 1
  end
  g.zones = zones
  g.zi = 1
  g.ii = 1
  g.hist = {}
  g.ready = true
  show(cur())
end

function GluePad_Move(dir)
  local g = GluePad
  if not g.ready or g.zones == nil then
    return
  end
  local z = g.zones[ZORDER[g.zi]]
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
      if g.zi > table.getn(ZORDER) then
        g.zi = 1
      end
    else
      g.zi = g.zi - 1
      if g.zi < 1 then
        g.zi = table.getn(ZORDER)
      end
    end
    local nz = g.zones[ZORDER[g.zi]]
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
  return "N=" .. tostring(n) .. " " .. table.concat(out, "")
end
