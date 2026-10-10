-- GluePad F2b-1: inventario de frames do glue (somente leitura).
-- Lua 5.0 estrito: table.getn, sem #, sem gmatch, sem bitwise,
-- sem goto, sem //, sem table.unpack. ASCII puro.
-- NUNCA loga texto de EditBox (pode ser senha) - so nomes de frames.

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

local function rec(c, out, st)
  if st.n >= st.cap then
    return
  end
  -- So o visivel (1.12: IsVisible devolve 1 ou nil). Escondido nao
  -- entra: some com o ruido (realm/addons escondidos no login) e o
  -- inventario vira o conjunto acionavel da tela atual.
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
  local tp = call1(c, "GetTop")
  local lf = call1(c, "GetLeft")
  st.n = st.n + 1
  out[st.n] = t .. "|" .. nm .. "|" .. tostring(vs) .. "|" .. tostring(en) .. "|" .. tostring(tp) .. "|" .. tostring(lf) .. ";"
end

local function walk(f, depth, out, st)
  if st.n >= st.cap or depth > 6 then
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
      rec(c, out, st)
      walk(c, depth + 1, out, st)
    end
    i = i + 1
  end
end

local out = {}
local st = { n = 0, cap = 300 }
if GlueParent ~= nil then
  walk(GlueParent, 0, out, st)
end
GluePad_Mbox = "N=" .. tostring(st.n) .. " " .. table.concat(out, "")
