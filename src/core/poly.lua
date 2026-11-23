-- core/poly.lua: polinomios p = {c0, c1, c2, ...}  (p[1] = termino independiente).
-- El polinomio cero es {0}. Las funciones no modifican sus argumentos salvo que se diga.
local M = {}

local abs, sqrt = math.abs, math.sqrt

-- Grado efectivo (ignora ceros exactos de cabecera).
function M.grado(p)
  local n = #p
  while n > 1 and p[n] == 0 do n = n - 1 end
  return n - 1
end

-- Quita EN SITIO los coeficientes de mayor grado exactamente nulos (deja al menos uno).
function M.trim(p)
  while #p > 1 and p[#p] == 0 do p[#p] = nil end
  return p
end

function M.eval(p, x)
  local r = 0
  for i = #p, 1, -1 do r = r * x + p[i] end
  return r
end

function M.add(a, b)
  local na, nb = #a, #b
  local n = na > nb and na or nb
  local r = {}
  for i = 1, n do r[i] = (a[i] or 0) + (b[i] or 0) end
  return r
end

function M.sub(a, b)
  local na, nb = #a, #b
  local n = na > nb and na or nb
  local r = {}
  for i = 1, n do r[i] = (a[i] or 0) - (b[i] or 0) end
  return r
end

function M.scale(p, k)
  local r = {}
  for i = 1, #p do r[i] = p[i] * k end
  return r
end

function M.mul(a, b)
  local na, nb = #a, #b
  local r = {}
  for i = 1, na + nb - 1 do r[i] = 0 end
  for i = 1, na do
    local ai = a[i]
    if ai ~= 0 then
      for j = 1, nb do r[i + j - 1] = r[i + j - 1] + ai * b[j] end
    end
  end
  return r
end

-- Integral indefinida con constante c0 (0 por omision).
function M.integ(p, c0)
  local r = { c0 or 0 }
  for i = 1, #p do r[i + 1] = p[i] / i end
  return r
end

function M.deriv(p)
  local n = #p
  if n <= 1 then return { 0 } end
  local r = {}
  for i = 1, n - 1 do r[i] = p[i + 1] * i end
  return r
end

-- q(x) = p(x + a)  (desplazamiento de la variable, division sintetica).
function M.shift(p, a)
  local n = #p
  local r = {}
  for i = 1, n do r[i] = p[i] end
  for i = 1, n - 1 do
    for j = n - 1, i, -1 do r[j] = r[j] + a * r[j + 1] end
  end
  return r
end

-- Ordena un arreglo de numeros (insercion, sin closures).
local function ordenar(t)
  for i = 2, #t do
    local v = t[i]
    local j = i - 1
    while j >= 1 and t[j] > v do t[j + 1] = t[j]; j = j - 1 end
    t[j + 1] = v
  end
end

-- Raiz de p en [lo, hi] con cambio de signo (flo, fhi de signos opuestos):
-- Newton protegido por biseccion.
local function raiz_acotada(p, dp, lo, hi, flo, fhi)
  local x = 0.5 * (lo + hi)
  local escala = abs(lo) > abs(hi) and abs(lo) or abs(hi)
  if escala < 1 then escala = 1 end
  for _ = 1, 100 do
    local f = M.eval(p, x)
    if f == 0 then return x end
    if (f < 0) == (flo < 0) then lo, flo = x, f else hi, fhi = x, f end
    if hi - lo <= 1e-15 * escala then return 0.5 * (lo + hi) end
    local d = M.eval(dp, x)
    local xn
    if d ~= 0 then xn = x - f / d end
    if xn == nil or xn <= lo or xn >= hi then xn = 0.5 * (lo + hi) end
    x = xn
  end
  return x
end

-- Raices reales distintas de p en [a, b], ordenadas.
-- Grado <= 2 analiticas; mayor: puntos criticos (raices de p') + biseccion/Newton.
-- Los coeficientes de cabecera despreciables (relativos a la escala en [a,b]) se descartan.
function M.roots_in(p, a, b)
  local out = {}
  if a > b then a, b = b, a end
  local R = abs(a) > abs(b) and abs(a) or abs(b)
  if R < 1 then R = 1 end
  local n = #p
  local pw = {}
  local s, w = 0, 1
  for i = 1, n do
    pw[i] = w
    s = s + abs(p[i]) * w
    w = w * R
  end
  if s == 0 then return out end
  while n > 1 and abs(p[n]) * pw[n] <= 1e-13 * s do n = n - 1 end
  local tx = 1e-9 * R
  if n <= 1 then return out end
  if n == 2 then
    local x = -p[1] / p[2]
    if x >= a - tx and x <= b + tx then
      if x < a then x = a elseif x > b then x = b end
      out[1] = x
    end
    return out
  end
  if n == 3 then
    local c, bb, aa = p[1], p[2], p[3]
    local disc = bb * bb - 4 * aa * c
    local dd = 1e-12 * (bb * bb + abs(4 * aa * c))
    local r1, r2
    if disc < -dd then
      return out
    elseif disc <= dd then
      r1 = -bb / (2 * aa)
    else
      local sq = sqrt(disc)
      local q = (bb >= 0) and -0.5 * (bb + sq) or -0.5 * (bb - sq)
      r1 = q / aa
      if q ~= 0 then r2 = c / q else r2 = r1 end
      if r2 < r1 then r1, r2 = r2, r1 end
    end
    if r1 >= a - tx and r1 <= b + tx then
      if r1 < a then r1 = a elseif r1 > b then r1 = b end
      out[#out + 1] = r1
    end
    if r2 and r2 >= a - tx and r2 <= b + tx then
      if r2 < a then r2 = a elseif r2 > b then r2 = b end
      if #out == 0 or r2 - out[#out] > tx then out[#out + 1] = r2 end
    end
    return out
  end
  -- grado >= 3
  local q = {}
  for i = 1, n do q[i] = p[i] end
  local dq = M.deriv(q)
  local cp = M.roots_in(dq, a, b)
  local pts = { a }
  for i = 1, #cp do
    if cp[i] > a + tx and cp[i] < b - tx then pts[#pts + 1] = cp[i] end
  end
  pts[#pts + 1] = b
  local vals = {}
  for i = 1, #pts do vals[i] = M.eval(q, pts[i]) end
  local tz = 1e-11 * s
  local cand = {}
  for i = 1, #pts do
    if abs(vals[i]) <= tz then cand[#cand + 1] = pts[i] end
  end
  for i = 1, #pts - 1 do
    local v1, v2 = vals[i], vals[i + 1]
    if abs(v1) > tz and abs(v2) > tz and ((v1 < 0) ~= (v2 < 0)) then
      cand[#cand + 1] = raiz_acotada(q, dq, pts[i], pts[i + 1], v1, v2)
    end
  end
  ordenar(cand)
  for i = 1, #cand do
    if #out == 0 or cand[i] - out[#out] > tx then out[#out + 1] = cand[i] end
  end
  return out
end

local function fmt(v, dec)
  local s = string.format("%." .. dec .. "f", v)
  if string.find(s, ".", 1, true) then
    s = string.gsub(s, "0+$", "")
    s = string.gsub(s, "%.$", "")
  end
  if s == "-0" then s = "0" end
  return s
end

-- Texto legible: tostring({0,10,-5}, "x", 3) --> "-5*x^2+10*x". Coeficientes que se
-- redondean a 0 con 'dec' decimales (3 por omision) se omiten.
function M.tostring(p, var, dec)
  var = var or "x"
  dec = dec or 3
  local out = ""
  for i = #p, 1, -1 do
    local c = p[i]
    local r = fmt(abs(c), dec)
    if r ~= "0" and r ~= "" then
      local k = i - 1
      local t
      if k == 0 then
        t = r
      else
        if r == "1" then t = var else t = r .. "*" .. var end
        if k > 1 then t = t .. "^" .. k end
      end
      if c < 0 then
        out = out .. "-" .. t
      elseif out == "" then
        out = t
      else
        out = out .. "+" .. t
      end
    end
  end
  if out == "" then out = "0" end
  return out
end

-- Coeficiente |a| con 'sig' cifras significativas, sin ceros finales. Fuera de [1e-3, 1e6)
-- usa notacion cientifica: "1.234e-5" (cas=false) o "1.234*10^(-5)" (cas=true, para el CAS,
-- donde "e" se confundiria con el numero de Euler).
local function fmt_sig(a, sig, cas)
  local e10 = math.floor(math.log10(a) + 1e-12)
  if e10 >= -3 and e10 < 6 then
    local d = sig - 1 - e10
    if d < 0 then d = 0 end
    return fmt(a, d)
  end
  local m = a / 10 ^ e10
  local ms = fmt(m, sig - 1)
  if ms == "10" then ms = "1"; e10 = e10 + 1 end
  if cas then return ms .. "*10^(" .. e10 .. ")" end
  return ms .. "e" .. e10
end

-- Texto con 'sig' cifras significativas (4 por omision). 'xref' es la escala de x (p. ej. la
-- longitud de la barra): los terminos que valen menos de 1e-9 del mayor (|c|*xref^k) se omiten.
-- cas = true produce una expresion apta para math.evalStr.
function M.tostring_sig(p, var, sig, cas, xref)
  var = var or "x"
  sig = sig or 4
  xref = xref or 1
  local cmax = 0
  for i = 1, #p do
    local v = abs(p[i]) * xref ^ (i - 1)
    if v > cmax then cmax = v end
  end
  local out = ""
  for i = #p, 1, -1 do
    local c = p[i]
    if c ~= 0 and abs(c) * xref ^ (i - 1) > 1e-9 * cmax then
      local r = fmt_sig(abs(c), sig, cas)
      local k = i - 1
      local t
      if k == 0 then
        t = r
      else
        if r == "1" then t = var else t = r .. "*" .. var end
        if k > 1 then t = t .. "^" .. k end
      end
      if c < 0 then
        out = out .. "-" .. t
      elseif out == "" then
        out = t
      else
        out = out .. "+" .. t
      end
    end
  end
  if out == "" then out = "0" end
  return out
end

return M
