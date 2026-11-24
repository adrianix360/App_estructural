-- core/esfuerzos.lua: esfuerzos y deformada por barra como polinomios por tramos.
--
-- E.construir(modelo, res) (lo llama S.resolver) rellena res.barras[e].tramos:
--   tramos[k] = { x0, x1, N, V, M, th, y, u }   (polinomios {c0,c1,..} en x LOCAL de la barra,
--                                                 sin desplazar; y = desplazamiento transversal v)
-- y res.barras[e].verif = { v=, th=, u=, rel= } (diferencias absolutas del extremo j integrado
-- frente a dl, y el mayor error relativo). Convenio de signos: docs/arquitectura.md §3.
local P = require("core.poly")
local Elem = require("core.elemento")

local M = {}
local abs = math.abs

local CAMPO = { N = "N", V = "V", M = "M", th = "th", theta = "th", v = "y", y = "y", u = "u" }

-- Inserta ordenado (insercion) sin closures.
local function ordenar(t, n)
  for i = 2, n do
    local v = t[i]
    local j = i - 1
    while j >= 1 and t[j] > v do t[j + 1] = t[j]; j = j - 1 end
    t[j + 1] = v
  end
end

local function acotar(a, L)
  if a < 0 then return 0 elseif a > L then return L end
  return a
end

-- Integral continua: q' = k*p, q(x0) = v0.
local function integ_cont(p, k, x0, v0)
  local q = P.integ(P.scale(p, k), 0)
  q[1] = v0 - P.eval(q, x0)
  return q
end

local function tramos_barra(b, rb)
  local L, c, s, fl, dl = rb.L, rb.c, rb.s, rb.fl, rb.dl
  local Em, Am, Im = Elem.props(b, L)
  local EI, EA = Em * Im, Em * Am
  local cargas = b.cargas or {}
  local tol = 1e-9 * L
  -- deformaciones termicas impuestas (suman a u' y a v'')
  local eps_T, kap_T = 0, 0
  for k = 1, #cargas do
    if cargas[k].t == "T" then
      local e1, k1 = Elem.termica(cargas[k])
      eps_T, kap_T = eps_T + e1, kap_T + k1
    end
  end

  -- quiebres
  local bp, n = { 0, L }, 2
  for k = 1, #cargas do
    local q = cargas[k]
    n = n + 1
    bp[n] = acotar(q.a or 0, L)
    if q.t == "w" then
      n = n + 1
      bp[n] = acotar(q.b or L, L)
    end
  end
  ordenar(bp, n)
  local xs = { bp[1] }
  for i = 2, n do
    if bp[i] - xs[#xs] > tol then xs[#xs + 1] = bp[i] end
  end
  if L - xs[#xs] <= tol then xs[#xs] = L else xs[#xs + 1] = L end
  xs[1] = 0

  local tr = {}
  local th0, v0, u0 = dl[3], dl[2], dl[1]
  local vsc, thsc, usc = abs(kap_T) * L * L, abs(kap_T) * L, abs(eps_T) * L -- magnitudes tipicas de los campos (para el error relativo)
  for t = 1, #xs - 1 do
    local x0, x1 = xs[t], xs[t + 1]
    local n0, n1, n2 = -fl[1], 0, 0
    local v0c, v1c, v2c = fl[2], 0, 0
    local m0, m1, m2, m3 = -fl[3], fl[2], 0, 0
    for k = 1, #cargas do
      local q = cargas[k]
      local a = acotar(q.a or 0, L)
      if q.t == "P" then
        if a <= x0 + tol then
          local kx, ky = Elem.comp_local(q.dir, c, s)
          local p = q.p or 0
          n0 = n0 - p * kx
          v0c = v0c + p * ky
          m0 = m0 - p * ky * a
          m1 = m1 + p * ky
        end
      elseif q.t == "M" then
        if a <= x0 + tol then m0 = m0 - (q.m or 0) end
      elseif q.t == "w" then
        local bb = acotar(q.b or L, L)
        local l = bb - a
        if l > 1e-12 and x0 > a - tol then
          local kx, ky = Elem.comp_local(q.dir, c, s)
          local w1, w2 = q.w1 or 0, q.w2 or q.w1 or 0
          local qy1, qy2, qx1, qx2 = w1 * ky, w2 * ky, w1 * kx, w2 * kx
          local my = (qy2 - qy1) / l
          local mx = (qx2 - qx1) / l
          if x0 >= bb - tol then
            -- tramo posterior a la carga: resultantes constantes
            local Wy = 0.5 * (qy1 + qy2) * l
            local Wx = 0.5 * (qx1 + qx2) * l
            local b2a2 = bb * bb - a * a
            local b3a3 = bb * bb * bb - a * a * a
            local Sy = qy1 * b2a2 / 2 + my * (b3a3 / 3 - a * b2a2 / 2)
            v0c = v0c + Wy
            m1 = m1 + Wy
            m0 = m0 - Sy
            n0 = n0 - Wx
          else
            -- tramo dentro de [a, b]: q(s) = cq0 + cq1*s
            local cq0, cq1 = qy1 - my * a, my
            local Qa = cq0 * a + cq1 * a * a / 2
            local Sa = cq0 * a * a / 2 + cq1 * a * a * a / 3
            v0c = v0c - Qa
            v1c = v1c + cq0
            v2c = v2c + cq1 / 2
            m0 = m0 + Sa
            m1 = m1 - Qa
            m2 = m2 + cq0 / 2
            m3 = m3 + cq1 / 6
            local dq0, dq1 = qx1 - mx * a, mx
            local Qxa = dq0 * a + dq1 * a * a / 2
            n0 = n0 + Qxa
            n1 = n1 - dq0
            n2 = n2 - dq1 / 2
          end
        end
      end
    end
    local Np = P.trim({ n0, n1, n2 })
    local Vp = P.trim({ v0c, v1c, v2c })
    local Mp = P.trim({ m0, m1, m2, m3 })
    local th = integ_cont(Mp, 1 / EI, x0, th0)
    if kap_T ~= 0 then
      th = P.add(th, { 0, kap_T })
      th[1] = th0 - P.eval(th, x0) + th[1]
    end
    local y = integ_cont(th, 1, x0, v0)
    local u = integ_cont(Np, 1 / EA, x0, u0)
    if eps_T ~= 0 then
      u = P.add(u, { 0, eps_T })
      u[1] = u0 - P.eval(u, x0) + u[1]
    end
    tr[t] = { x0 = x0, x1 = x1, N = Np, V = Vp, M = Mp, th = th, y = y, u = u }
    th0 = P.eval(th, x1)
    v0 = P.eval(y, x1)
    u0 = P.eval(u, x1)
    local xm = 0.5 * (x0 + x1)
    vsc = math.max(vsc, abs(v0), abs(P.eval(y, xm)))
    thsc = math.max(thsc, abs(th0), abs(P.eval(th, xm)))
    usc = math.max(usc, abs(u0), abs(P.eval(u, xm)))
  end

  -- verificacion contra el extremo j
  local ev, eth, eu = abs(v0 - dl[5]), abs(th0 - dl[6]), abs(u0 - dl[4])
  local sv = math.max(vsc, abs(dl[2]), abs(dl[5]), abs(dl[3]) * L, abs(dl[6]) * L)
  local sth = math.max(thsc, abs(dl[3]), abs(dl[6]), abs(dl[5] - dl[2]) / L)
  local su = math.max(usc, abs(dl[1]), abs(dl[4]))
  local rel = math.max(ev / (sv + 1e-30), eth / (sth + 1e-30), eu / (su + 1e-30))
  rb.verif = { v = ev, th = eth, u = eu, rel = rel }
  return tr
end

-- Construye los tramos de todas las barras (res.barras[e] ya con L, c, s, fl, dl).
function M.construir(modelo, res)
  for e = 1, #modelo.barras do
    local rb = res.barras[e]
    rb.tramos = tramos_barra(modelo.barras[e], rb)
  end
end

local function buscar(tr, x)
  local n = #tr
  for k = 1, n - 1 do
    if x < tr[k].x1 then return tr[k] end
  end
  return tr[n]
end

-- N, V, M, theta, v, u en x local (0..L). En un quiebre (carga puntual) devuelve el lado derecho.
function M.eval(res, e, x)
  local rb = res.barras[e]
  local t = buscar(rb.tramos, x)
  return P.eval(t.N, x), P.eval(t.V, x), P.eval(t.M, x),
    P.eval(t.th, x), P.eval(t.y, x), P.eval(t.u, x)
end

-- {x1, val1, x2, val2, ...} del campo "N"|"V"|"M"|"th"|"v"|"u", con ~n puntos en total;
-- en los quiebres con salto aparecen los dos valores (izquierdo y derecho) con el mismo x.
function M.muestras(res, e, campo, n)
  local rb = res.barras[e]
  local key = CAMPO[campo] or campo
  local L = rb.L
  local out, m = {}, 0
  n = n or 50
  local tr = rb.tramos
  for t = 1, #tr do
    local tt = tr[t]
    local p = tt[key]
    local nk = 2
    if P.grado(p) > 1 then
      nk = math.floor(n * (tt.x1 - tt.x0) / L + 0.5)
      if nk < 3 then nk = 3 end
    end
    local dx = (tt.x1 - tt.x0) / (nk - 1)
    for i = 1, nk do
      local x = tt.x0 + dx * (i - 1)
      if i == nk then x = tt.x1 end
      out[m + 1] = x
      out[m + 2] = P.eval(p, x)
      m = m + 2
    end
  end
  return out
end

-- Extremos locales del campo: extremos de la barra, puntos criticos (p' = 0) y picos en
-- quiebres/saltos. Cada elemento {x=, val=, tipo="max"|"min"}. Una meseta se informa una vez
-- (en su primer punto). Un campo constante devuelve un solo punto.
function M.extremos(res, e, campo)
  local rb = res.barras[e]
  local key = CAMPO[campo] or campo
  local tr = rb.tramos
  local px, pv, m = {}, {}, 0
  local vmax = 0
  for t = 1, #tr do
    local tt = tr[t]
    local p = tt[key]
    local tx = 1e-9 * rb.L
    m = m + 1; px[m] = tt.x0; pv[m] = P.eval(p, tt.x0)
    if P.grado(p) >= 2 then
      local cp = P.roots_in(P.deriv(p), tt.x0, tt.x1)
      for i = 1, #cp do
        if cp[i] > tt.x0 + tx and cp[i] < tt.x1 - tx then
          m = m + 1; px[m] = cp[i]; pv[m] = P.eval(p, cp[i])
        end
      end
    end
    m = m + 1; px[m] = tt.x1; pv[m] = P.eval(p, tt.x1)
  end
  for i = 1, m do
    if abs(pv[i]) > vmax then vmax = abs(pv[i]) end
  end
  local tv = 1e-9 * vmax + 1e-14
  local out = {}
  for i = 1, m do
    local v = pv[i]
    if i == 1 or abs(v - pv[i - 1]) > tv then
      local izq, der
      local j = i - 1
      while j >= 1 do
        if abs(pv[j] - v) > tv then izq = pv[j]; break end
        j = j - 1
      end
      j = i + 1
      while j <= m do
        if abs(pv[j] - v) > tv then der = pv[j]; break end
        j = j + 1
      end
      local tipo
      if izq == nil and der == nil then
        tipo = "max"
      elseif (izq == nil or izq < v) and (der == nil or der < v) then
        tipo = "max"
      elseif (izq == nil or izq > v) and (der == nil or der > v) then
        tipo = "min"
      end
      if tipo then out[#out + 1] = { x = px[i], val = v, tipo = tipo } end
    end
  end
  return out
end

-- Abscisas donde el campo vale 0 (V = 0, M = 0 -> inflexion), ordenadas y sin repetir.
-- Incluye cruces por cero en saltos (carga puntual) y ceros en los extremos de la barra.
function M.ceros(res, e, campo)
  local rb = res.barras[e]
  local key = CAMPO[campo] or campo
  local tr = rb.tramos
  local L = rb.L
  local vmax = 0
  for t = 1, #tr do
    local tt = tr[t]
    local p = tt[key]
    local mid = 0.5 * (tt.x0 + tt.x1)
    local a1, a2, a3 = abs(P.eval(p, tt.x0)), abs(P.eval(p, tt.x1)), abs(P.eval(p, mid))
    if a1 > vmax then vmax = a1 end
    if a2 > vmax then vmax = a2 end
    if a3 > vmax then vmax = a3 end
    if P.grado(p) >= 2 then
      local cp = P.roots_in(P.deriv(p), tt.x0, tt.x1)
      for i = 1, #cp do
        local v = abs(P.eval(p, cp[i]))
        if v > vmax then vmax = v end
      end
    end
  end
  local tv = 1e-9 * vmax + 1e-14
  local raw, nr = {}, 0
  for t = 1, #tr do
    local tt = tr[t]
    local p = tt[key]
    local mid = 0.5 * (tt.x0 + tt.x1)
    local plano = abs(P.eval(p, tt.x0)) <= tv and abs(P.eval(p, tt.x1)) <= tv
      and abs(P.eval(p, mid)) <= tv and P.grado(p) <= 1
    if not plano then
      local r = P.roots_in(p, tt.x0, tt.x1)
      for i = 1, #r do nr = nr + 1; raw[nr] = r[i] end
    end
    if t < #tr then
      local vl = P.eval(p, tt.x1)
      local vr = P.eval(tr[t + 1][key], tr[t + 1].x0)
      if (vl > tv and vr < -tv) or (vl < -tv and vr > tv) then
        nr = nr + 1; raw[nr] = tt.x1
      end
    end
  end
  ordenar(raw, nr)
  local out = {}
  local tx = 1e-9 * (L > 1 and L or 1)
  for i = 1, nr do
    if #out == 0 or raw[i] - out[#out] > tx then out[#out + 1] = raw[i] end
  end
  return out
end

-- Lista de tramos { x0, x1, V, M, th, y, N, u } (polinomios en x local de la barra, sin desplazar).
function M.ecuaciones(res, e)
  local tr = res.barras[e].tramos
  local out = {}
  for t = 1, #tr do
    local tt = tr[t]
    out[t] = { x0 = tt.x0, x1 = tt.x1, V = tt.V, M = tt.M, th = tt.th, y = tt.y, N = tt.N, u = tt.u }
  end
  return out
end

-- Posicion deformada (global) del punto x local de la barra: X, Y. 'escala' amplifica los
-- desplazamientos (1 por omision).
function M.global(res, e, x, escala)
  local rb = res.barras[e]
  local _, _, _, _, v, u = M.eval(res, e, x)
  escala = escala or 1
  local ux = rb.c * u - rb.s * v
  local uy = rb.s * u + rb.c * v
  return rb.xi + rb.c * x + escala * ux, rb.yi + rb.s * x + escala * uy
end

return M
