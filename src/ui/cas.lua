-- ui/cas.lua - Presentacion de ecuaciones por tramo: CAS de la calculadora (math.evalStr) con
-- respaldo en el motor propio (core.poly). El solver nunca depende del CAS.
--   CAS.disponible()                       -> bool (existe math.evalStr; no se llama al cargar)
--   CAS.ecuacion(p, a, b, xref)            -> texto, fuente ("CAS" | "propio")
--        p = polinomio en x local; [a, b] = tramo donde es valido (para verificar el CAS).
-- El resultado del CAS solo se acepta si, evaluado numericamente en 2 puntos del tramo,
-- coincide con el polinomio propio; cualquier fallo (o pcall) vuelve al texto propio.
local P = require("core.poly")

local CAS = {}

local abs, max = math.abs, math.max

function CAS.disponible()
  return type(math) == "table" and type(math.evalStr) == "function"
end

-- Texto del CAS -> numero (tolera "ᴇ", el menos tipografico y espacios)
local function a_numero(s)
  if type(s) ~= "string" then return nil end
  s = s:gsub("\225\180\135", "e"):gsub("\226\136\146", "-"):gsub("%s", "")
  return tonumber(s)
end

local function limpiar(s)
  s = s:gsub("\225\180\135", "e"):gsub("\226\136\146", "-")
  return s
end

local function evaluar(expr)
  local ok, r = pcall(math.evalStr, expr)
  if ok then return r end
  return nil
end

-- Coincidencia numerica del texto del CAS con el polinomio en x1 y x2
local function verifica(txt, p, x1, x2, escala)
  local pts = { x1, x2 }
  for i = 1, 2 do
    local x = pts[i]
    local r = a_numero(evaluar("(" .. txt .. ")|x=" .. string.format("%.12g", x)))
    if r == nil then return false end
    local ref = P.eval(p, x)
    if abs(r - ref) > 5e-3 * max(abs(ref), escala) + 1e-12 then return false end
  end
  return true
end

function CAS.ecuacion(p, a, b, xref)
  local propio = P.tostring_sig(p, "x", 4, false, xref)
  if not CAS.disponible() then return propio, "propio" end
  local ex = P.tostring_sig(p, "x", 4, true, xref)
  local s = evaluar("expand(" .. ex .. ")")
  if type(s) ~= "string" or s == "" then return propio, "propio" end
  local x1, x2 = a + 0.3 * (b - a), a + 0.8 * (b - a)
  -- escala de comparacion: suma de |c_k| x^k en el extremo del tramo
  local esc = 0
  for i = 1, #p do esc = esc + abs(p[i]) * max(abs(a), abs(b)) ^ (i - 1) end
  if verifica(s, p, x1, x2, esc) then return limpiar(s), "CAS" end
  return propio, "propio"
end

return CAS
