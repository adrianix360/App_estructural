-- tests/test_solver.lua: pruebas analiticas del nucleo numerico (core.*).
-- Ejecutar desde la raiz:  LUA_PATH="./?.lua;./tests/?.lua;./src/?.lua" lua tests/test_solver.lua
-- Termina con os.exit(1) si algo falla.
local S = require("core.solver")
local E = require("core.esfuerzos")
local P = require("core.poly")
local LA = require("core.linalg")

local E0, A0, I0 = 2e8, 0.01, 1e-4
local EI = E0 * I0
local sqrt, abs = math.sqrt, math.abs

local total, fallos = 0, 0
local peor = 0
local function chk(nombre, v, e, tol, esc)
  tol = tol or 1e-6
  total = total + 1
  local den = math.max(abs(e), esc or 0, 1e-12)
  local err = abs(v - e) / den
  if err > peor then peor = err end
  if err <= tol and v == v then
    print(string.format("  ok   %-52s %.9g (err %.1e)", nombre, v, err))
  else
    fallos = fallos + 1
    print(string.format("  FALLA %-51s obtenido %.9g esperado %.9g (err %.2e > %.0e)",
      nombre, v, e, err, tol))
  end
end
local function cierto(nombre, cond, detalle)
  total = total + 1
  if cond then
    print("  ok   " .. nombre)
  else
    fallos = fallos + 1
    print("  FALLA " .. nombre .. (detalle and (" (" .. tostring(detalle) .. ")") or ""))
  end
end
local function grupo(t) print("\n== " .. t) end

-- constructores de modelos
local PIN = { ux = true, uy = true }
local ROD = { uy = true }
local EMP = { ux = true, uy = true, rz = true }
local function nuevo() return { ver = 1, nodos = {}, barras = {} } end
local function nodo(m, x, y, ap, ca)
  m.nodos[#m.nodos + 1] = { x = x, y = y, apoyo = ap, carga = ca }
  return #m.nodos
end
local function barra(m, ni, nj, o)
  local b = { ni = ni, nj = nj, tipo = "portico", E = E0, A = A0, I = I0, cargas = {} }
  if o then for k, v in pairs(o) do b[k] = v end end
  m.barras[#m.barras + 1] = b
  return b
end
local function wunif(b, w, a, c) -- w>0 hacia abajo
  b.cargas[#b.cargas + 1] = { t = "w", a = a or 0, b = c, w1 = -w, w2 = -w, dir = "GY" }
end

-- Resuelve y comprueba equilibrio global (< 1e-8 relativo) y consistencia de v(L), th(L), u(L).
local function resolver(m, nombre)
  local res, err = S.resolver(m)
  if not res then
    fallos = fallos + 1
    total = total + 1
    print("  FALLA " .. nombre .. ": error de resolver " .. tostring(err and err.cod)
      .. " " .. tostring(err and err.msg))
    return nil
  end
  local rel = res.equilibrio.rel
  total = total + 1
  if rel < 1e-8 then
    print(string.format("  ok   equilibrio global [%s] (rel %.1e)", nombre, rel))
  else
    fallos = fallos + 1
    print(string.format("  FALLA equilibrio global [%s] rel %.2e fx=%g fy=%g m=%g", nombre, rel,
      res.equilibrio.fx, res.equilibrio.fy, res.equilibrio.m))
  end
  local vmax = 0
  for e = 1, #res.barras do
    if res.barras[e].verif.rel > vmax then vmax = res.barras[e].verif.rel end
  end
  total = total + 1
  if vmax < 1e-8 then
    print(string.format("  ok   consistencia v(L),th(L),u(L) [%s] (rel %.1e)", nombre, vmax))
  else
    fallos = fallos + 1
    print(string.format("  FALLA consistencia v(L),th(L),u(L) [%s] rel %.2e", nombre, vmax))
  end
  return res
end

----------------------------------------------------------------------------------------------
grupo("Utilidades: poly y linalg")
do
  chk("poly.eval", P.eval({ 1, 2, 3 }, 2), 17)
  chk("poly.integ", P.eval(P.integ({ 0, 2 }, 5), 3), 14)
  chk("poly.deriv", P.eval(P.deriv({ 1, 2, 3 }), 2), 14)
  chk("poly.mul", P.eval(P.mul({ 1, 1 }, { -1, 1 }), 3), 8)
  chk("poly.shift p(x+2), p=x^2", P.eval(P.shift({ 0, 0, 1 }, 2), 1), 9)
  local r = P.roots_in({ -6, 11, -6, 1 }, 0, 4)
  cierto("roots_in cubica (x-1)(x-2)(x-3): 3 raices", #r == 3)
  if #r == 3 then
    chk("  raiz 1", r[1], 1, 1e-10); chk("  raiz 2", r[2], 2, 1e-10); chk("  raiz 3", r[3], 3, 1e-10)
  end
  r = P.roots_in({ -3, 7, -5, 1 }, 0, 4) -- (x-1)^2 (x-3)
  cierto("roots_in raiz doble: {1,3}", #r == 2 and abs(r[1] - 1) < 1e-6 and abs(r[2] - 3) < 1e-9)
  r = P.roots_in({ 3, -4, 1 }, 2, 5)
  cierto("roots_in cuadratica en [2,5]: {3}", #r == 1 and abs(r[1] - 3) < 1e-12)
  r = P.roots_in({ 24, -50, 35, -10, 1 }, 0, 5) -- (x-1)(x-2)(x-3)(x-4)
  cierto("roots_in cuartica: 4 raices", #r == 4 and abs(r[4] - 4) < 1e-9)
  cierto("poly.tostring", P.tostring({ 0, 10, -5 }, "x", 3) == "-5*x^2+10*x", P.tostring({ 0, 10, -5 }, "x", 3))
  cierto("poly.tostring 2", P.tostring({ 1.5, -1, 0, 1 }, "x", 2) == "x^3-x+1.5", P.tostring({ 1.5, -1, 0, 1 }, "x", 2))
  cierto("poly.tostring cero", P.tostring({ 0 }, "x", 2) == "0")
  local x, info = LA.solve({ { 2, 1 }, { 1, 3 } }, { 3, 5 })
  chk("linalg.solve x1", x[1], 0.8); chk("linalg.solve x2", x[2], 1.4)
  x, info = LA.solve({ { 1, 1 }, { 2, 2 } }, { 1, 2 })
  cierto("linalg.solve singular -> nil + indice", x == nil and info == 2, info)
  chk("linalg.rank 3x3 de rango 2", LA.rank({ { 1, 2, 3 }, { 4, 5, 6 }, { 7, 8, 9 } }), 2)
  chk("linalg.rank identidad 3", LA.rank({ { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }), 3)
end

----------------------------------------------------------------------------------------------
grupo("1. Simplemente apoyada con w uniforme")
do
  local L, w = 6, 10
  local m = nuevo()
  nodo(m, 0, 0, PIN); nodo(m, L, 0, ROD)
  wunif(barra(m, 1, 2), w, 0, L)
  local res = resolver(m, "caso 1")
  chk("R_i = wL/2", res.reac[1].ry, w * L / 2)
  chk("R_j = wL/2", res.reac[2].ry, w * L / 2)
  chk("Rx_i = 0", res.reac[1].rx, 0, 1e-9, w * L)
  local ex = E.extremos(res, 1, "M")
  local mx
  for i = 1, #ex do if ex[i].tipo == "max" and (not mx or ex[i].val > mx.val) then mx = ex[i] end end
  chk("Mmax = wL^2/8", mx.val, w * L * L / 8)
  chk("x(Mmax) = L/2", mx.x, L / 2)
  local _, _, M, _, v = E.eval(res, 1, L / 2)
  chk("M(L/2)", M, w * L * L / 8)
  chk("ymax = -5wL^4/(384EI)", v, -5 * w * L ^ 4 / (384 * EI))
  local ev = E.extremos(res, 1, "v")
  local vm = 0
  for i = 1, #ev do if ev[i].val < vm then vm = ev[i].val end end
  chk("extremos v: minimo = -5wL^4/(384EI)", vm, -5 * w * L ^ 4 / (384 * EI))
  chk("clasificacion: isostatica", S.clasificar(m).grado, 0)
  cierto("clasificacion: tipo", S.clasificar(m).tipo == "isostatica")
  local eq = E.ecuaciones(res, 1)
  cierto("ecuacion M(x) legible", P.tostring(eq[1].M, "x", 3) == "-5*x^2+30*x", P.tostring(eq[1].M, "x", 3))
  chk("theta(0) = -wL^3/(24EI)", res.barras[1].dl[3], -w * L ^ 3 / (24 * EI))
end

----------------------------------------------------------------------------------------------
grupo("2. Simplemente apoyada con P al centro (dos formas)")
do
  local L, Pp = 6, 20
  -- a) nodo intermedio con carga nodal
  local m = nuevo()
  nodo(m, 0, 0, PIN); nodo(m, L / 2, 0, nil, { fy = -Pp }); nodo(m, L, 0, ROD)
  barra(m, 1, 2); barra(m, 2, 3)
  local res = resolver(m, "caso 2a")
  chk("2a: R_i = P/2", res.reac[1].ry, Pp / 2)
  local _, _, M, _, v = E.eval(res, 1, L / 2)
  chk("2a: Mmax = PL/4", M, Pp * L / 4)
  chk("2a: ymax = -PL^3/(48EI)", res.d[2].uy, -Pp * L ^ 3 / (48 * EI))
  chk("2a: v(L/2) por tramos", v, -Pp * L ^ 3 / (48 * EI))
  -- b) carga puntual dentro de la barra
  m = nuevo()
  nodo(m, 0, 0, PIN); nodo(m, L, 0, ROD)
  local b = barra(m, 1, 2)
  b.cargas[1] = { t = "P", a = L / 2, p = -Pp, dir = "GY" }
  res = resolver(m, "caso 2b")
  chk("2b: R_j = P/2", res.reac[2].ry, Pp / 2)
  _, _, M, _, v = E.eval(res, 1, L / 2)
  chk("2b: Mmax = PL/4", M, Pp * L / 4)
  chk("2b: ymax = -PL^3/(48EI)", v, -Pp * L ^ 3 / (48 * EI))
  local ex = E.extremos(res, 1, "M")
  local mx = -1e99
  for i = 1, #ex do if ex[i].val > mx then mx = ex[i].val end end
  chk("2b: extremos M max", mx, Pp * L / 4)
  local z = E.ceros(res, 1, "V")
  cierto("2b: V = 0 en el salto (L/2)", #z == 1 and abs(z[1] - L / 2) < 1e-9, #z)
  local mu = E.muestras(res, 1, "V", 20)
  local izq, der
  for i = 1, #mu, 2 do
    if abs(mu[i] - L / 2) < 1e-9 then
      if not izq then izq = mu[i + 1] else der = mu[i + 1] end
    end
  end
  cierto("2b: muestras V con salto +P/2 / -P/2", izq and der and abs(izq - Pp / 2) < 1e-9 and abs(der + Pp / 2) < 1e-9)
  chk("2b: primer x de muestras = 0", mu[1], 0, 1e-12, 1)
  chk("2b: ultimo x de muestras = L", mu[#mu - 1], L)
end

----------------------------------------------------------------------------------------------
grupo("3. Voladizo con P en el extremo")
do
  local L, Pp = 4, 15
  local m = nuevo()
  nodo(m, 0, 0, EMP); nodo(m, L, 0, nil, { fy = -Pp })
  barra(m, 1, 2)
  local res = resolver(m, "caso 3")
  local _, _, M0 = E.eval(res, 1, 0)
  chk("M interno en el empotramiento = -PL", M0, -Pp * L)
  chk("reaccion Ry = P", res.reac[1].ry, Pp)
  chk("reaccion Mz = +PL (antihorario)", res.reac[1].mz, Pp * L)
  chk("flecha en la punta = -PL^3/(3EI)", res.d[2].uy, -Pp * L ^ 3 / (3 * EI))
  chk("giro en la punta = -PL^2/(2EI)", res.d[2].rz, -Pp * L ^ 2 / (2 * EI))
  chk("cortante V = +P (= dM/dx)", select(2, E.eval(res, 1, L / 2)), Pp)
  local X, Y = E.global(res, 1, L, 1)
  chk("E.global X punta", X, L); chk("E.global Y punta", Y, -Pp * L ^ 3 / (3 * EI))
  X, Y = E.global(res, 1, L, 100)
  chk("E.global Y punta (x100)", Y, -100 * Pp * L ^ 3 / (3 * EI))
  chk("clasificacion: isostatica", S.clasificar(m).grado, 0)
end

----------------------------------------------------------------------------------------------
grupo("4. Empotrada-apoyada con w")
do
  local L, w = 5, 8
  local m = nuevo()
  nodo(m, 0, 0, EMP); nodo(m, L, 0, ROD)
  wunif(barra(m, 1, 2), w, 0, L)
  local res = resolver(m, "caso 4")
  chk("R_apoyo = 3wL/8", res.reac[2].ry, 3 * w * L / 8)
  chk("R_emp = 5wL/8", res.reac[1].ry, 5 * w * L / 8)
  chk("M_emp reaccion = wL^2/8", res.reac[1].mz, w * L * L / 8)
  local _, _, M0 = E.eval(res, 1, 0)
  chk("M interno emp = -wL^2/8", M0, -w * L * L / 8)
  local cl = S.clasificar(m)
  chk("clasificacion: grado 1", cl.grado, 1)
  cierto("clasificacion: msg", cl.msg == "Hiperestatica de grado 1", cl.msg)
end

----------------------------------------------------------------------------------------------
grupo("5. Continua de 2 tramos iguales con w")
local m5, res5
do
  local L, w = 5, 8
  local m = nuevo()
  nodo(m, 0, 0, PIN); nodo(m, L, 0, ROD); nodo(m, 2 * L, 0, ROD)
  wunif(barra(m, 1, 2), w, 0, L)
  wunif(barra(m, 2, 3), w, 0, L)
  local res = resolver(m, "caso 5")
  m5, res5 = m, res
  chk("R_central = 5wL/4", res.reac[2].ry, 5 * w * L / 4)
  chk("R_extremo = 3wL/8", res.reac[1].ry, 3 * w * L / 8)
  chk("clasificacion: grado 1", S.clasificar(m).grado, 1)
  chk("giro del apoyo central = 0 (simetria)", res.d[2].rz, 0, 1e-9, 1e-3)
  -- extremos y ceros (del tramo 1)
  local z = E.ceros(res, 1, "M")
  cierto("ceros de M: 2 (x=0 y 3L/4)", #z == 2, #z)
  if #z == 2 then
    chk("  inflexion x = 3L/4", z[2], 3 * L / 4)
    chk("  cero en x = 0", z[1], 0, 1e-9, 1)
  end
  z = E.ceros(res, 1, "V")
  cierto("ceros de V: 1 (x=3L/8)", #z == 1 and abs(z[1] - 3 * L / 8) < 1e-9)
  local ex = E.extremos(res, 1, "M")
  local mx, mn = -1e99, 1e99
  for i = 1, #ex do
    if ex[i].val > mx then mx = ex[i].val end
    if ex[i].val < mn then mn = ex[i].val end
  end
  chk("extremos M max = 9wL^2/128", mx, 9 * w * L * L / 128)
  chk("extremos M min = -wL^2/8", mn, -w * L * L / 8)
end

----------------------------------------------------------------------------------------------
grupo("6. Cercha triangular (metodo de los nudos)")
do
  local P0 = 12
  local m = nuevo()
  nodo(m, 0, 0, PIN); nodo(m, 4, 0, ROD); nodo(m, 2, 3, nil, { fy = -P0 })
  barra(m, 1, 2, { tipo = "cercha", I = 0 })
  barra(m, 1, 3, { tipo = "cercha", I = 0 })
  barra(m, 2, 3, { tipo = "cercha", I = 0 })
  local res = resolver(m, "caso 6")
  local R = P0 / 2
  -- nudo 1: Ry = N13*sen; N13 = -R/sen (compresion), N12 = +R*dx/dy (traccion)
  local N12 = E.eval(res, 1, 1)
  local N13 = E.eval(res, 2, 1)
  local N23 = E.eval(res, 3, 1)
  chk("N base (traccion) = R*2/3 = 4", N12, R * 2 / 3)
  chk("N diagonal izq (compresion) = -R*sqrt(13)/3", N13, -R * sqrt(13) / 3)
  chk("N diagonal der (compresion) = -R*sqrt(13)/3", N23, -R * sqrt(13) / 3)
  chk("reaccion Ry en A = P/2", res.reac[1].ry, R)
  chk("reaccion Ry en B = P/2", res.reac[2].ry, R)
  chk("reaccion Rx en A = 0", res.reac[1].rx, 0, 1e-9, P0)
  local cl = S.clasificar(m)
  cierto("clasificacion: isostatica", cl.tipo == "isostatica" and cl.grado == 0, cl.msg)
  cierto("giros de nudo eliminados (rz = nil)", res.d[1].rz == nil and res.d[3].rz == nil)
  local mm = E.extremos(res, 2, "M")
  local mxm = 0
  for i = 1, #mm do if abs(mm[i].val) > mxm then mxm = abs(mm[i].val) end end
  chk("momento flector en barras de cercha = 0", mxm, 0, 1e-9, P0)
  -- cercha hiperestatica: cuadrado con ambas diagonales
  m = nuevo()
  nodo(m, 0, 0, PIN); nodo(m, 3, 0, ROD); nodo(m, 3, 3, nil, { fx = 10 }); nodo(m, 0, 3)
  barra(m, 1, 2, { tipo = "cercha" }); barra(m, 2, 3, { tipo = "cercha" })
  barra(m, 3, 4, { tipo = "cercha" }); barra(m, 4, 1, { tipo = "cercha" })
  barra(m, 1, 3, { tipo = "cercha" }); barra(m, 2, 4, { tipo = "cercha" })
  cl = S.clasificar(m)
  cierto("cuadrado con 2 diagonales: hiperestatica grado 1", cl.tipo == "hiperestatica" and cl.grado == 1, cl.msg)
  res = resolver(m, "cercha hiperestatica")
  chk("  Rx total = -10", res.reac[1].rx + res.reac[2].rx, -10)
end

----------------------------------------------------------------------------------------------
grupo("7. Marco portal con carga lateral (pendiente-deflexion)")
do
  -- Fuente: metodo de pendiente-deflexion (Kassimali, cap. 15; Hibbeler cap. 11). Columnas de
  -- altura h empotradas en la base, viga de luz L, mismo EI, axial rigido (A grande), carga H
  -- en el nudo superior izquierdo. Momentos de extremo POSITIVOS HORARIOS:
  --   M_ij = (2EI/l)(2 th_i + th_j - 3 psi)       psi = delta/l (horario +)
  -- Simetria: th2 = th3 = th (desplazamiento lateral comun, viga sin acortamiento).
  --   Nudo 2: a(2 th - 3 psi) + b(3 th) = 0 -> th = 3 a psi/(2a + 3b),  a = 2EI/h, b = 2EI/L
  --   Cortante de piso (cada columna toma H/2): H = -2 a (3 th - 6 psi)/h
  --   => psi = H h^2 (2 + 3k) / (12 EI (1 + 6k)),  k = h/L ; delta = psi*h
  -- Momentos (horario+): base a(th - 3 psi), cabeza a(2 th - 3 psi), viga 3 b th.
  -- En fl el momento de extremo es ANTIHORARIO+, es decir el opuesto.
  local h, L, H = 4, 6, 30
  local Ab = 1e3
  local m = nuevo()
  nodo(m, 0, 0, EMP); nodo(m, 0, h, nil, { fx = H }); nodo(m, L, h); nodo(m, L, 0, EMP)
  barra(m, 1, 2, { A = Ab }); barra(m, 2, 3, { A = Ab }); barra(m, 4, 3, { A = Ab })
  local res = resolver(m, "portal")
  local k = h / L
  local psi = H * h * h * (2 + 3 * k) / (12 * EI * (1 + 6 * k))
  local a, b = 2 * EI / h, 2 * EI / L
  local th = 3 * psi / (2 + 3 * k)
  chk("desplazamiento lateral delta", res.d[2].ux, psi * h, 1e-5)
  chk("desplazamiento lateral nudo 3", res.d[3].ux, psi * h, 1e-5)
  chk("giro nudo 2", res.d[2].rz, -th, 1e-5)
  local f1, f2, f3 = res.barras[1].fl, res.barras[2].fl, res.barras[3].fl
  chk("momento base izq (fl, antihorario+)", f1[3], -a * (th - 3 * psi), 1e-5)
  chk("momento cabeza col izq", f1[6], -a * (2 * th - 3 * psi), 1e-5)
  chk("momento viga extremo 2", f2[3], -3 * b * th, 1e-5)
  chk("momento viga extremo 3", f2[6], -3 * b * th, 1e-5)
  chk("momento base der", f3[3], -a * (th - 3 * psi), 1e-5)
  chk("momento cabeza col der", f3[6], -a * (2 * th - 3 * psi), 1e-5)
  chk("reaccion horizontal base izq = -H/2", res.reac[1].rx, -H / 2, 1e-6)
  chk("reaccion horizontal base der = -H/2", res.reac[4].rx, -H / 2, 1e-6)
  chk("sumatoria Fx = 0 (reacciones + H)", res.reac[1].rx + res.reac[4].rx + H, 0, 1e-9, H)
  chk("sumatoria Fy = 0", res.reac[1].ry + res.reac[4].ry, 0, 1e-9, H)
  -- Suma de momentos respecto al origen: reacciones + carga H en (0,h)
  local sm = res.reac[1].mz + res.reac[4].mz + (L * res.reac[4].ry - 0 * res.reac[4].rx)
    - 0 * res.reac[1].rx + (0 * 0 - h * H)
  chk("sumatoria M = 0 (origen)", sm, 0, 1e-9, H * h)
  local cl = S.clasificar(m)
  cierto("clasificacion: hiperestatica grado 3", cl.tipo == "hiperestatica" and cl.grado == 3, cl.msg)
  -- con A normal tambien equilibrio
  m.barras[1].A, m.barras[2].A, m.barras[3].A = A0, A0, A0
  resolver(m, "portal A normal")
end

----------------------------------------------------------------------------------------------
grupo("Clasificacion, rotulas y mecanismos")
do
  local L, w = 4, 6
  -- Gerber: empotrada - rotula - apoyo
  local m = nuevo()
  nodo(m, 0, 0, EMP); nodo(m, L, 0); nodo(m, 2 * L, 0, ROD)
  barra(m, 1, 2, { rot_j = true })
  wunif(barra(m, 2, 3), w, 0, L)
  local cl = S.clasificar(m)
  cierto("Gerber (rotula interna): isostatica", cl.tipo == "isostatica" and cl.grado == 0, cl.msg)
  local res = resolver(m, "Gerber")
  chk("Gerber: R apoyo = wL/2", res.reac[3].ry, w * L / 2)
  chk("Gerber: Ry empotramiento = wL/2", res.reac[1].ry, w * L / 2)
  chk("Gerber: Mz empotramiento = wL/2*L", res.reac[1].mz, w * L / 2 * L)
  local _, _, Mh = E.eval(res, 1, L)
  chk("Gerber: M en la rotula = 0", Mh, 0, 1e-9, w * L * L)
  chk("Gerber: giro extremo j barra 1 = -P L^2/(2EI)", res.barras[1].dl[6], -(w * L / 2) * L * L / (2 * EI))
  -- giro = giro de cuerda (la rotula baja con la punta del voladizo) + giro de viga apoyada
  chk("Gerber: giro extremo i barra 2", res.barras[2].dl[3], (w * L / 2) * L ^ 2 / (3 * EI) - w * L ^ 3 / (24 * EI))
  cierto("Gerber: giro de nudo en la rotula definido (rz)", res.d[2].rz ~= nil)

  -- mecanismo: dos rodillos
  m = nuevo()
  nodo(m, 0, 0, ROD); nodo(m, L, 0, ROD)
  barra(m, 1, 2)
  cl = S.clasificar(m)
  cierto("2 rodillos: inestable", cl.tipo == "inestable", cl.msg)
  local r, err = S.resolver(m)
  cierto("2 rodillos: resolver -> MECANISMO", r == nil and err and err.cod == "MECANISMO", err and err.cod)
  print("     msg: " .. tostring(err and err.msg))

  -- tres rotulas alineadas
  m = nuevo()
  nodo(m, 0, 0, PIN); nodo(m, L, 0); nodo(m, 2 * L, 0, PIN)
  barra(m, 1, 2, { rot_j = true }); barra(m, 2, 3, { rot_i = true })
  cl = S.clasificar(m)
  cierto("3 rotulas en linea: inestable", cl.tipo == "inestable", cl.msg)
  r, err = S.resolver(m)
  cierto("3 rotulas en linea: MECANISMO", r == nil and err and err.cod == "MECANISMO", err and err.cod)
  print("     msg: " .. tostring(err and err.msg))
  -- cadena de cercha colineal
  m = nuevo()
  nodo(m, 0, 0, PIN); nodo(m, L, 0); nodo(m, 2 * L, 0, PIN)
  barra(m, 1, 2, { tipo = "cercha" }); barra(m, 2, 3, { tipo = "cercha" })
  r, err = S.resolver(m)
  cierto("cercha colineal: MECANISMO", r == nil and err and err.cod == "MECANISMO", err and err.cod)
  -- mecanismo de un lazo articulado: cuadrilatero articulado
  m = nuevo()
  nodo(m, 0, 0, PIN); nodo(m, 3, 0, PIN); nodo(m, 3, 3); nodo(m, 0, 3)
  barra(m, 1, 2, { tipo = "cercha" }); barra(m, 2, 3, { tipo = "cercha" })
  barra(m, 3, 4, { tipo = "cercha" }); barra(m, 4, 1, { tipo = "cercha" })
  cl = S.clasificar(m)
  cierto("cuadrilatero articulado: inestable (falta 1)", cl.tipo == "inestable" and cl.n_ec - cl.rango == 1, cl.msg)

  -- momento en nudo totalmente articulado
  m = nuevo()
  nodo(m, 0, 0, PIN); nodo(m, L, 0, nil, { mz = 5 }); nodo(m, 2 * L, 0, PIN)
  barra(m, 1, 2, { rot_j = true }); barra(m, 2, 3, { rot_i = true })
  r, err = S.resolver(m)
  cierto("momento en nudo articulado: MECANISMO nodo 2", r == nil and err and err.cod == "MECANISMO" and err.nodo == 2,
    err and err.msg)

  -- errores de validacion
  r, err = S.resolver({ nodos = {}, barras = {} })
  cierto("SIN_NODOS", err and err.cod == "SIN_NODOS", err and err.cod)
  m = nuevo()
  nodo(m, 0, 0, PIN); nodo(m, 1, 0, ROD); nodo(m, 5, 5)
  barra(m, 1, 2)
  r, err = S.resolver(m)
  cierto("NODO_SUELTO (nodo 3)", err and err.cod == "NODO_SUELTO" and err.nodo == 3, err and err.msg)
  m = nuevo()
  nodo(m, 0, 0, PIN); nodo(m, 4, 0, ROD); nodo(m, 4, 0)
  barra(m, 1, 2); barra(m, 2, 3)
  r, err = S.resolver(m)
  cierto("LONG_CERO", err and err.cod == "LONG_CERO" and err.msg == "La barra 2 tiene longitud cero", err and err.msg)
  m = nuevo()
  nodo(m, 0, 0); nodo(m, 4, 0)
  barra(m, 1, 2)
  r, err = S.resolver(m)
  cierto("SIN_APOYOS", err and err.cod == "SIN_APOYOS" and err.msg == "Falta un apoyo: la estructura es inestable",
    err and err.msg)
  m = nuevo()
  nodo(m, 0, 0, EMP); nodo(m, 4, 0)
  barra(m, 1, 2, { E = -1 })
  r, err = S.resolver(m)
  cierto("DATO (E invalido)", err and err.cod == "DATO", err and err.cod)
  m = nuevo()
  nodo(m, 0, 0, EMP); nodo(m, 4, 0)
  local bb = barra(m, 1, 2)
  bb.cargas[1] = { t = "P", a = 9, p = -1 }
  r, err = S.resolver(m)
  cierto("DATO (carga fuera de la barra)", err and err.cod == "DATO", err and err.cod)
end

----------------------------------------------------------------------------------------------
grupo("Resorte, asentamiento, trapezoidal, inclinada, momento, axial")
do
  -- voladizo con resorte vertical en la punta
  local L, Pp, kv = 4, 10, 500
  local m = nuevo()
  nodo(m, 0, 0, EMP); nodo(m, L, 0, { ky = kv }, { fy = -Pp })
  barra(m, 1, 2)
  local res = resolver(m, "resorte")
  local d = Pp / (kv + 3 * EI / L ^ 3)
  chk("resorte: flecha = P/(k + 3EI/L^3)", res.d[2].uy, -d)
  chk("resorte: reaccion = k*d", res.reac[2].ry, kv * d)
  chk("resorte: clasificacion hiperestatica 1", S.clasificar(m).grado, 1)
  -- resorte rotacional
  m = nuevo()
  nodo(m, 0, 0, PIN); nodo(m, L, 0, { uy = true, kr = 1e4 })
  barra(m, 1, 2, { cargas = { { t = "M", a = 0, m = 10 } } })
  res = resolver(m, "resorte rotacional")
  cierto("resorte rotacional: reaccion mz = -kr*rz", abs(res.reac[2].mz + 1e4 * res.d[2].rz) < 1e-9)

  -- asentamiento en viga empotrada-empotrada
  local Lv, dlt = 5, 0.01
  m = nuevo()
  nodo(m, 0, 0, EMP); nodo(m, Lv, 0, { ux = true, uy = true, rz = true, dy = -dlt })
  barra(m, 1, 2)
  res = resolver(m, "asentamiento")
  local _, _, M0 = E.eval(res, 1, 0)
  local _, _, ML = E.eval(res, 1, Lv)
  chk("asentamiento: M(0) = -6EId/L^2", M0, -6 * EI * dlt / Lv ^ 2)
  chk("asentamiento: M(L) = +6EId/L^2", ML, 6 * EI * dlt / Lv ^ 2)
  chk("asentamiento: reaccion Ry_i = 12EId/L^3", res.reac[1].ry, 12 * EI * dlt / Lv ^ 3)
  chk("asentamiento: desplazamiento prescrito", res.d[2].uy, -dlt)

  -- trapezoidal sobre empotrada-empotrada
  local Lt = 6
  m = nuevo()
  nodo(m, 0, 0, EMP); nodo(m, Lt, 0, EMP)
  local bt = barra(m, 1, 2)
  bt.cargas[1] = { t = "w", a = 0, b = Lt, w1 = -4, w2 = -10, dir = "GY" }
  res = resolver(m, "trapezoidal")
  chk("trapecio: M_i = (3q1+2q2)L^2/60", res.barras[1].fl[3], (3 * 4 + 2 * 10) * Lt ^ 2 / 60)
  chk("trapecio: M_j = -(2q1+3q2)L^2/60", res.barras[1].fl[6], -(2 * 4 + 3 * 10) * Lt ^ 2 / 60)
  chk("trapecio: Fy_i = L(7q1+3q2)/20", res.barras[1].fl[2], Lt * (7 * 4 + 3 * 10) / 20)
  chk("trapecio: Fy_j = L(3q1+7q2)/20", res.barras[1].fl[5], Lt * (3 * 4 + 7 * 10) / 20)

  -- carga parcial: viga apoyada con w en a..b
  m = nuevo()
  nodo(m, 0, 0, PIN); nodo(m, 8, 0, ROD)
  local bp = barra(m, 1, 2)
  bp.cargas[1] = { t = "w", a = 2, b = 6, w1 = -5, w2 = -5, dir = "GY" }
  res = resolver(m, "carga parcial")
  chk("parcial: R_i = W/2 (simetrica)", res.reac[1].ry, 10)
  local _, _, Mc = E.eval(res, 1, 4)
  chk("parcial: M(4) = 10*4 - 5*2^2/2", Mc, 30)
  local _, _, Mfuera = E.eval(res, 1, 1)
  chk("parcial: M(1) = 10", Mfuera, 10)

  -- barra inclinada con carga GY
  m = nuevo()
  nodo(m, 0, 0, PIN); nodo(m, 3, 4, ROD)
  local bi = barra(m, 1, 2)
  bi.cargas[1] = { t = "w", a = 0, b = 5, w1 = -10, w2 = -10, dir = "GY" }
  res = resolver(m, "inclinada")
  chk("inclinada: Ry_i = W/2 = 25", res.reac[1].ry, 25)
  chk("inclinada: Ry_j = 25", res.reac[2].ry, 25)
  chk("inclinada: Rx_i = 0", res.reac[1].rx, 0, 1e-9, 50)
  local ex = E.extremos(res, 1, "M")
  local mx = -1e99
  for i = 1, #ex do if ex[i].val > mx then mx = ex[i].val end end
  chk("inclinada: Mmax = w*cos*L^2/8", mx, 10 * 0.6 * 25 / 8)
  -- inclinada con carga perpendicular a la barra (dir L) y axial local (LX)
  m = nuevo()
  nodo(m, 0, 0, PIN); nodo(m, 3, 4, ROD)
  bi = barra(m, 1, 2)
  bi.cargas[1] = { t = "w", a = 0, b = 5, w1 = 7, w2 = 7, dir = "L" }
  res = resolver(m, "inclinada L")
  local _, _, Ml = E.eval(res, 1, 2.5)
  chk("inclinada dir L (+y local): M(L/2) = -wL^2/8", Ml, -7 * 25 / 8)

  -- momento puntual en viga apoyada
  local Lm, M0m, am = 6, 12, 2
  m = nuevo()
  nodo(m, 0, 0, PIN); nodo(m, Lm, 0, ROD)
  barra(m, 1, 2, { cargas = { { t = "M", a = am, m = M0m } } })
  res = resolver(m, "momento puntual")
  chk("momento: Ry_i = M0/L", res.reac[1].ry, M0m / Lm)
  chk("momento: Ry_j = -M0/L", res.reac[2].ry, -M0m / Lm)
  local _, _, Ma = E.eval(res, 1, am - 1e-7)
  local _, _, Md = E.eval(res, 1, am)
  chk("momento: M(a-) = M0/L*a", Ma, M0m / Lm * am, 1e-6)
  chk("momento: M(a+) = M0/L*a - M0", Md, M0m / Lm * am - M0m)

  -- carga axial distribuida (LX) en barra empotrada
  local La, wa = 4, 5
  m = nuevo()
  nodo(m, 0, 0, EMP); nodo(m, La, 0)
  barra(m, 1, 2, { cargas = { { t = "w", a = 0, b = La, w1 = wa, w2 = wa, dir = "LX" } } })
  res = resolver(m, "axial LX")
  chk("axial: N(0) = wL (traccion)", (E.eval(res, 1, 0)), wa * La)
  chk("axial: N(L) = 0", (E.eval(res, 1, La - 1e-12)), 0, 1e-9, wa * La)
  chk("axial: u(L) = wL^2/(2EA)", res.d[2].ux, wa * La * La / (2 * E0 * A0))
  chk("axial: reaccion Rx = -wL", res.reac[1].rx, -wa * La)

  -- carga GX sobre barra vertical
  m = nuevo()
  nodo(m, 0, 0, EMP); nodo(m, 0, 4)
  barra(m, 1, 2, { cargas = { { t = "w", a = 0, b = 4, w1 = 3, w2 = 3, dir = "GX" } } })
  res = resolver(m, "voladizo vertical GX")
  chk("voladizo vertical: Rx = -wL", res.reac[1].rx, -12)
  chk("voladizo vertical: flecha = wL^4/(8EI)", res.d[2].ux, 3 * 4 ^ 4 / (8 * EI))
end

----------------------------------------------------------------------------------------------
grupo("Marco con rotula y tramos (equilibrio)")
do
  -- portico a dos aguas con rotula en la cumbrera y carga mixta
  local m = nuevo()
  nodo(m, 0, 0, PIN); nodo(m, 0, 4); nodo(m, 4, 6, nil, { fy = -5 }); nodo(m, 8, 4); nodo(m, 8, 0, PIN)
  barra(m, 1, 2); barra(m, 2, 3, { rot_j = true }); barra(m, 3, 4, { rot_i = true }); barra(m, 4, 5)
  m.barras[2].cargas[1] = { t = "w", a = 0, b = m.barras[2].cargas and 4.4721359549995796, w1 = -3, w2 = -3, dir = "GY" }
  m.barras[1].cargas[1] = { t = "P", a = 2, p = 8, dir = "GX" }
  local res = resolver(m, "marco a dos aguas")
  local cl = S.clasificar(m)
  cierto("marco 3 articulaciones: isostatico", cl.tipo == "isostatica", cl.msg)
  local _, _, Mr = E.eval(res, 2, 4.4721359549995796)
  chk("momento en la rotula = 0", Mr, 0, 1e-8, 20)
end

print(string.format("\n== Resumen: %d comprobaciones, %d fallo(s). Peor error relativo en chk: %.2e",
  total, fallos, peor))
if fallos > 0 then os.exit(1) end
os.exit(0)
