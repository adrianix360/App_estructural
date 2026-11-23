-- ui/resultados.lua - Modo resultados: reacciones, diagramas N/V/M, deformada, valor al apuntar,
-- tabla, ecuaciones y leyenda. Se activa con "Resolver" (tecla r) y se re-resuelve solo tras
-- cada cambio del modelo (estructuras <= 20 nodos).
--
-- Contrato con la UI de modelado (herramientas.lua / dibujo.lua):
--   R.resolver(S, modelo) -> ok, msg    resuelve y ENTRA en modo resultados (si no lo estaba)
--   R.invalidar()          tras cualquier cambio del modelo: descarta caches y re-resuelve si hay modo
--   R.limpiar()            borra los resultados y vuelve a modo modelado
--   R.activo() -> bool     hay resultados vigentes en modo resultados
--   R.pintar(gc, V, m, PR) dibuja sobre el lienzo (PR = primitivas de ui.dibujo)
--   R.estado() -> texto    texto de la barra de estado (valor al apuntar o ayuda de la vista)
--   R.mouse(x, y) -> texto valor al apuntar sobre una barra/nodo (o nil); fija R.cur
--   R.modo = nil | "reac" | "N" | "V" | "M" | "def" | "tabla" | "ecs"
--   R.clasif_texto() -> texto corto de clasificacion (tambien en modo modelado)
-- Cache: las muestras de cada campo se guardan por resultado en COORDENADAS DE BARRA (x local,
-- valor); la camara solo interviene al pintar (sin crear tablas), asi paneo/zoom no recalculan.
local ED = require("ui.modelo_ed")
local V0 = require("ui.vista")
local D = require("ui.dialogo")
local E = require("core.esfuerzos")
local CAS = require("ui.cas")

local R = {}

local floor, abs, sqrt, min, max, log10 = math.floor, math.abs, math.sqrt, math.min, math.max, math.log10
local format = string.format

R.res = nil
R.err = nil
R.modo = nil
R.cur = nil
R.S = nil
R.kd = { N = 1, V = 1, M = 1 }     -- multiplicador de escala de cada diagrama
R.def_f = nil                       -- factor de deformada fijado por el usuario (nil = automatico)
R.def_real = false                  -- deformada real (factor 1)
R.eb = 1                            -- barra activa (ecuaciones y cursor por teclado)
R.scroll = 0
R.ultimo = "reac"
R.ver = 0                           -- sube con cada resolucion
R.on_modo = nil                     -- callback(antes, ahora) (lo fija herramientas.lua)
R.barra_sel = nil                   -- funcion() -> indice de barra seleccionada o nil
R.MAX_NODOS = 20

local cache = {}
local cl_ok, cl_val, cl_txt = false, nil, ""

local VISTAS = { "reac", "N", "V", "M", "def", "tabla", "ecs" }
local NOMBRE = { reac = "Reacciones", N = "Axial N", V = "Cortante V", M = "Momento M",
                 def = "Deformada", tabla = "Tabla", ecs = "Ecuaciones" }
local UNID = { N = "kN", V = "kN", M = "kN·m" }
local COL = {
  N = { 140, 50, 190 }, V = { 215, 30, 30 }, M = { 20, 70, 225 },
  def = { 0, 150, 60 }, reac = { 205, 0, 165 },
}
local TINTE = { N = { 214, 184, 232 }, V = { 244, 176, 176 }, M = { 172, 194, 248 } }

-- ------------------------------------------------------------------ numeros
-- Cifras significativas sin notacion cientifica; |v| < 1e-6 se muestra 0.
local function num(v, sig)
  if v ~= v then return "nan" end
  local a = abs(v)
  if a < 1e-6 then return "0" end
  sig = sig or 4
  local d = sig - 1 - floor(log10(a) + 1e-12)
  if d < 0 then d = 0 elseif d > 8 then d = 8 end
  local s = format("%." .. d .. "f", v)
  if s:find(".", 1, true) then
    s = s:gsub("0+$", "")
    s = s:gsub("%.$", "")
  end
  if s == "-0" then s = "0" end
  return s
end
R.num = num

local function exp_txt(v)
  if abs(v) < 1e-300 then return "0" end
  return format("%.1e", v)
end

-- escalon "agradable" 1-2-5 mas cercano / siguiente / anterior
local function nice(v)
  if v <= 0 then return 1 end
  local e = floor(log10(v))
  local m = v / 10 ^ e
  local n
  if m < 1.5 then n = 1 elseif m < 3.5 then n = 2 elseif m < 7.5 then n = 5 else n = 10 end
  return n * 10 ^ e
end
local function nice_up(v)
  local e = floor(log10(v) + 1e-9)
  local m = v / 10 ^ e
  local n
  if m < 1.5 then n = 2 elseif m < 3.5 then n = 5 else n = 10 end
  return n * 10 ^ e
end
local function nice_down(v)
  local e = floor(log10(v) + 1e-9)
  local m = v / 10 ^ e
  local n
  if m > 6 then n = 5 elseif m > 3 then n = 2 elseif m > 1.5 then n = 1 else n = 0.5 end
  return n * 10 ^ e
end

-- ----------------------------------------------------------- clasificacion
local function solver()
  if R.S then return R.S end
  local ok, S = pcall(require, "core.solver")
  if ok and type(S) == "table" then R.S = S end
  return R.S
end

function R.clasif()
  if cl_ok then return cl_val end
  cl_ok = true
  cl_val, cl_txt = nil, ""
  local m = ED.m
  if #m.nodos == 0 or #m.barras == 0 then
    R.cl_ver = (R.cl_ver or 0) + 1
    return nil
  end
  if #m.nodos > R.MAX_NODOS then
    cl_txt = "Mas de " .. R.MAX_NODOS .. " nodos"
    R.cl_ver = (R.cl_ver or 0) + 1
    return nil
  end
  local S = solver()
  if S then
    local ok, cl = pcall(S.clasificar, m)
    if ok and type(cl) == "table" then
      cl_val = cl
      if cl.tipo == "isostatica" then cl_txt = "Isostatica"
      elseif cl.tipo == "hiperestatica" then cl_txt = "Hiperestatica g=" .. (cl.grado or 0)
      else
        local msg = cl.msg or "estructura inestable"
        if msg:sub(1, 9) == "Inestable" then cl_txt = msg else cl_txt = "Inestable: " .. msg end
      end
    end
  end
  R.cl_ver = (R.cl_ver or 0) + 1
  return cl_val
end
R.cl_ver = 0

function R.clasif_texto()
  R.clasif()
  return cl_txt
end

-- ---------------------------------------------------------------- errores
local function traducir(err)
  if type(err) ~= "table" then return tostring(err or "No se pudo resolver") end
  local c, msg = err.cod, err.msg or "No se pudo resolver"
  if c == "SIN_NODOS" then return "No hay nodos: crea una barra con la herramienta Barra (B)" end
  if c == "SIN_APOYOS" then return "Falta un apoyo: la estructura es inestable. Usa Apoyo (A) sobre un nodo" end
  if c == "LONG_CERO" then return msg .. ": mueve o borra uno de sus nodos" end
  if c == "NODO_SUELTO" then return msg .. ": conectalo con una barra o borralo" end
  if c == "MECANISMO" then return msg .. ". Agrega apoyos o barras" end
  if c == "SINGULAR" then return msg .. ". Revisa apoyos y rotulas" end
  if c == "DATO" then return msg .. ". Corrigelo con ENTER sobre la barra" end
  return msg
end

-- -------------------------------------------------------------------- modo
local function limpiar_caches()
  cache = {}
  R.cur = nil
  R.tab_rows = nil
  R.ecs = nil
end

local function set_modo(m)
  local antes = R.modo
  if m ~= antes then
    R.scroll = 0
    R.cur = nil
  end
  R.modo = m
  if m then R.ultimo = m end
  if R.on_modo and antes ~= m and (antes == nil or m == nil) then R.on_modo(antes, m) end
end

local function mensaje_ok(res)
  local cl = R.clasif_texto()
  local t = "Resuelto"
  if cl ~= "" then t = t .. ": " .. cl end
  local eq = res.equilibrio
  if eq and eq.rel and eq.rel > 1e-6 then
    t = t .. " (aviso: residuo de equilibrio " .. exp_txt(eq.rel) .. ")"
  end
  return t
end

local punto_barra, punto_nodo

local function resolver_interno(S, modelo)
  R.S = S or R.S
  local s = R.S or solver()
  if not s then
    limpiar_caches()
    R.res, R.err = nil, "Solver no disponible"
    return false, R.err
  end
  local c = R.cur
  local cb, cx, cn, cs
  if c then cb, cx, cn, cs = c.e, c.x, c.nodo, c.src end
  local ok, res, err = pcall(s.resolver, modelo)
  limpiar_caches()
  R.ver = R.ver + 1
  if not ok then
    R.res, R.err = nil, "Error interno al resolver: " .. tostring(res)
    return false, R.err
  end
  if not res then
    R.res, R.err = nil, traducir(err)
    return false, R.err
  end
  R.res, R.err = res, nil
  if R.eb > #modelo.barras then R.eb = max(1, #modelo.barras) end
  -- conserva el punto apuntado si sigue existiendo
  if cb and res.barras[cb] then punto_barra(cb, cx, cs)
  elseif cn and res.d[cn] then punto_nodo(cn, cs) end
  return true, mensaje_ok(res)
end

-- Resuelve y entra en modo resultados. En caso de error y sin modo previo, NO entra.
function R.resolver(S, modelo)
  local ok, msg = resolver_interno(S, modelo)
  if ok then
    if not R.modo then
      set_modo(R.ultimo or "reac")
      if R.barra_sel then
        local e = R.barra_sel()
        if e and modelo.barras[e] then R.eb = e end
      end
    end
  end
  return ok, msg
end

function R.invalidar()
  cl_ok = false
  R.tab_rows, R.ecs = nil, nil
  if R.modo then
    local m = ED.m
    if #m.nodos > R.MAX_NODOS then
      limpiar_caches()
      R.res, R.err = nil, "Mas de " .. R.MAX_NODOS .. " nodos: pulsa R para recalcular"
    elseif #m.nodos == 0 or #m.barras == 0 then
      limpiar_caches()
      R.res, R.err = nil, "No hay barras: crea una con la herramienta Barra (B)"
    else
      resolver_interno(R.S, m)
    end
  else
    cache = {}
    R.res = nil
    R.cur = nil
  end
end

function R.limpiar()
  R.res, R.err = nil, nil
  limpiar_caches()
  set_modo(nil)
end

function R.activo()
  return R.modo ~= nil and R.res ~= nil
end

function R.pantalla_completa()
  return R.modo == "tabla" or R.modo == "ecs"
end

function R.set_vista(v)
  if not R.modo then return end
  if v == "ecs" and R.barra_sel then
    local e = R.barra_sel()
    if e and ED.m.barras[e] then R.eb = e end
  end
  if v ~= R.modo then
    R.scroll = 0
    R.cur = nil
    R.modo = v
    R.ultimo = v
    R.ecs = nil
  end
end

function R.siguiente(dir)
  local k = 1
  for i = 1, #VISTAS do if VISTAS[i] == R.modo then k = i end end
  k = (k - 1 + (dir or 1)) % #VISTAS + 1
  R.set_vista(VISTAS[k])
end

-- --------------------------------------------------------------- geometria
local function barra_cerca(px, py, tol)
  local res = R.res
  if not res then return nil end
  local S = V0.s
  local best, bd, bx = nil, tol, 0
  for e = 1, #res.barras do
    local rb = res.barras[e]
    local x1, y1 = V0.a_pantalla(rb.xi, rb.yi)
    local dx, dy = rb.c * S * rb.L, -rb.s * S * rb.L
    local l2 = dx * dx + dy * dy
    if l2 > 0 then
      local t = ((px - x1) * dx + (py - y1) * dy) / l2
      if t < 0 then t = 0 elseif t > 1 then t = 1 end
      local qx, qy = x1 + t * dx, y1 + t * dy
      local d = sqrt((px - qx) ^ 2 + (py - qy) ^ 2)
      if d <= bd then best, bd, bx = e, d, t * rb.L end
    end
  end
  return best, bx
end

local function nodo_cerca(px, py, tol)
  local m = ED.m
  local best, bd = nil, tol * tol
  for i = 1, #m.nodos do
    local sx, sy = V0.a_pantalla(m.nodos[i].x, m.nodos[i].y)
    local d = (sx - px) ^ 2 + (sy - py) ^ 2
    if d <= bd then best, bd = i, d end
  end
  return best
end

-- ------------------------------------------------------------ valor puntual
function punto_barra(e, x, src)
  local res = R.res
  local rb = res and res.barras[e]
  if not rb then return nil end
  if x < 0 then x = 0 elseif x > rb.L then x = rb.L end
  local N, Vv, M, th, v, u = E.eval(res, e, x)
  local ux = rb.c * u - rb.s * v
  local uy = rb.s * u + rb.c * v
  local d = sqrt(ux * ux + uy * uy)
  local c = R.cur
  if not c then c = {}; R.cur = c end
  c.e, c.nodo, c.x, c.src = e, nil, x, src
  c.N, c.V, c.M, c.th, c.v, c.u, c.ux, c.uy = N, Vv, M, th, v, u, ux, uy
  local sN, sV, sM = num(N), num(Vv), num(M)
  local sd = num(d * 1000)
  c.l1 = "Barra " .. e .. "  x=" .. num(x, 3) .. " m"
  c.l2 = "N=" .. sN .. "  V=" .. sV .. " kN"
  c.l3 = "M=" .. sM .. " kN·m"
  c.l4 = "δ=" .. sd .. " mm (" .. num(ux * 1000) .. "; " .. num(uy * 1000) .. ")"
  c.l5 = nil
  c.txt = "B" .. e .. " x=" .. num(x, 3) .. " m | N=" .. sN .. " V=" .. sV .. " kN M=" .. sM
    .. " kN·m | δ=" .. sd .. " mm"
  R.eb = e
  return c.txt
end

function punto_nodo(i, src)
  local res = R.res
  local d = res and res.d[i]
  if not d then return nil end
  local c = R.cur
  if not c then c = {}; R.cur = c end
  c.e, c.x, c.nodo, c.src = nil, nil, i, src
  c.l1 = "Nodo " .. i
  c.l2 = "ux=" .. num(d.ux * 1000) .. "  uy=" .. num(d.uy * 1000) .. " mm"
  c.l3 = d.rz and ("rz=" .. num(d.rz * 1000) .. " mrad") or "rz: nudo articulado"
  local rc = res.reac[i]
  if rc then
    c.l4 = "Rx=" .. num(rc.rx) .. " Ry=" .. num(rc.ry) .. " kN"
    c.l5 = (rc.mz and abs(rc.mz) > 1e-6) and ("Mz=" .. num(rc.mz) .. " kN·m") or nil
  else
    c.l4, c.l5 = nil, nil
  end
  c.txt = "Nodo " .. i .. " | ux=" .. num(d.ux * 1000) .. " uy=" .. num(d.uy * 1000) .. " mm"
    .. (d.rz and (" rz=" .. num(d.rz * 1000) .. " mrad") or "")
    .. (rc and (" | Rx=" .. num(rc.rx) .. " Ry=" .. num(rc.ry) .. " kN") or "")
  return c.txt
end

-- Valor al apuntar (sin clic): R.cur sigue al raton sobre barras y nodos
function R.mouse(x, y)
  if not (R.modo and R.res) then return nil end
  if R.pantalla_completa() then return nil end
  local R0 = V0.rect
  if not (x >= R0.x and x < R0.x + R0.w and y >= R0.y and y < R0.y + R0.h) then
    if R.cur and R.cur.src == "mouse" then R.cur = nil end
    return nil
  end
  local i = nodo_cerca(x, y, 7)
  if i then return punto_nodo(i, "mouse") end
  local e, bx = barra_cerca(x, y, 8)
  if e then return punto_barra(e, bx, "mouse") end
  if R.cur and R.cur.src == "mouse" then R.cur = nil end
  return nil
end

-- Clic (valor "al tocar"): el punto queda fijo hasta moverse a otra barra o ESC
function R.clic(x, y)
  if not (R.modo and R.res) or R.pantalla_completa() then return end
  local i = nodo_cerca(x, y, 7)
  if i then punto_nodo(i, "clic"); return end
  local e, bx = barra_cerca(x, y, 8)
  if e then punto_barra(e, bx, "clic") end
end

-- Flechas en vistas con lienzo: izquierda/derecha avanzan por la barra, arriba/abajo cambian de barra
local function mover_cursor(k)
  local res = R.res
  local nb = #res.barras
  local c = R.cur
  if not (c and c.e) then
    local e = R.eb
    if R.barra_sel then
      local s = R.barra_sel()
      if s and res.barras[s] then e = s end
    end
    if not res.barras[e] then e = 1 end
    punto_barra(e, res.barras[e].L / 2, "tecla")
    return
  end
  local e, x = c.e, c.x
  local L = res.barras[e].L
  if k == "left" or k == "right" then
    x = x + ((k == "right") and 1 or -1) * L / 20
    if x < -1e-9 then
      if e > 1 then e = e - 1; x = res.barras[e].L else x = 0 end
    elseif x > L + 1e-9 then
      if e < nb then e = e + 1; x = 0 else x = L end
    end
  else
    local f = x / L
    e = e + ((k == "down") and 1 or -1)
    if e < 1 then e = nb elseif e > nb then e = 1 end
    x = f * res.barras[e].L
  end
  punto_barra(e, x, "tecla")
end

-- ------------------------------------------------------------ cache: diagramas
local function cache_diag(campo)
  local c = cache[campo]
  if c then return c end
  local res = R.res
  c = { campo = campo, bars = {}, maxabs = 0 }
  local nb = #res.barras
  for e = 1, nb do
    local mu = E.muestras(res, e, campo, 41)
    local n = #mu / 2
    local b = { n = n, xs = {}, vs = {}, lab = {}, ceros = {} }
    for i = 1, n do
      local v = mu[2 * i]
      b.xs[i], b.vs[i] = mu[2 * i - 1], v
      if abs(v) > c.maxabs then c.maxabs = abs(v) end
    end
    -- el maximo exacto (puntos criticos) puede quedar entre muestras
    b.ex = E.extremos(res, e, campo)
    for i = 1, #b.ex do
      if abs(b.ex[i].val) > c.maxabs then c.maxabs = abs(b.ex[i].val) end
    end
    c.bars[e] = b
  end
  local tiny = 1e-6 * c.maxabs
  if c.maxabs > 1e-9 then
    for e = 1, nb do
      local b = c.bars[e]
      local L = res.barras[e].L
      local vmin, vmax = 1e300, -1e300
      for i = 1, b.n do
        if b.vs[i] < vmin then vmin = b.vs[i] end
        if b.vs[i] > vmax then vmax = b.vs[i] end
      end
      if vmax - vmin <= 1e-9 * c.maxabs then
        -- campo constante (p. ej. N en una cercha): una sola etiqueta en el centro
        if abs(vmax) > tiny then
          b.lab[1] = { x = L / 2, val = vmax, txt = num(vmax) }
        end
      else
        local ex = b.ex
        for i = 1, #ex do
          if abs(ex[i].val) > tiny then
            b.lab[#b.lab + 1] = { x = ex[i].x, val = ex[i].val, txt = num(ex[i].val) }
          end
        end
      end
      if campo == "V" or campo == "M" then
        local z = E.ceros(res, e, campo)
        for i = 1, #z do
          if z[i] > 1e-6 * L and z[i] < L * (1 - 1e-6) then b.ceros[#b.ceros + 1] = z[i] end
        end
      end
    end
    local R0 = V0.rect
    c.kpx = 0.12 * min(R0.w, R0.h) / c.maxabs
  else
    c.kpx = 0
  end
  cache[campo] = c
  return c
end

-- ------------------------------------------------------------ cache: deformada
local function cache_def()
  local c = cache.def
  if c then return c end
  local res = R.res
  local nb = #res.barras
  c = { bars = {}, dmax = 0, dmax_e = 1, dmax_x = 0 }
  for e = 1, nb do
    local rb = res.barras[e]
    local n = 40
    local b = { n = n + 1, xs = {}, us = {}, vs = {} }
    for i = 0, n do
      local x = rb.L * i / n
      local _, _, _, _, v, u = E.eval(res, e, x)
      b.xs[i + 1], b.us[i + 1], b.vs[i + 1] = x, u, v
      local ux, uy = rb.c * u - rb.s * v, rb.s * u + rb.c * v
      local d = sqrt(ux * ux + uy * uy)
      if d > c.dmax then c.dmax, c.dmax_e, c.dmax_x = d, e, x end
    end
    -- puntos criticos exactos de la flecha transversal
    local ex = E.extremos(res, e, "v")
    for i = 1, #ex do
      local _, _, _, _, v, u = E.eval(res, e, ex[i].x)
      local ux, uy = rb.c * u - rb.s * v, rb.s * u + rb.c * v
      local d = sqrt(ux * ux + uy * uy)
      if d > c.dmax + 1e-15 then c.dmax, c.dmax_e, c.dmax_x = d, e, ex[i].x end
    end
    c.bars[e] = b
  end
  -- factor automatico: desplazamiento maximo ~12% del lado menor del lienzo con la camara actual
  local R0 = V0.rect
  if c.dmax > 1e-12 then
    c.f_auto = nice(0.12 * min(R0.w, R0.h) / (c.dmax * V0.s))
  else
    c.f_auto = 1
  end
  cache.def = c
  return c
end

local function factor_def()
  if R.def_real then return 1 end
  if R.def_f then return R.def_f end
  return cache_def().f_auto
end

-- ---------------------------------------------------------- cache: reacciones
local function cache_reac()
  local c = cache.reac
  if c then return c end
  local res, m = R.res, ED.m
  c = { items = {} }
  local mx = 0
  for i = 1, #m.nodos do
    local rc = res.reac[i]
    if rc then
      if abs(rc.rx) > mx then mx = abs(rc.rx) end
      if abs(rc.ry) > mx then mx = abs(rc.ry) end
      if rc.mz and abs(rc.mz) > mx then mx = abs(rc.mz) end
    end
  end
  local tol = 1e-6 * max(mx, 1e-9) + 1e-9
  for i = 1, #m.nodos do
    local rc = res.reac[i]
    if rc then
      local it = { i = i, vx = 0, vy = 0 }
      if abs(rc.rx) > tol then it.rx = rc.rx; it.trx = "Rx=" .. num(rc.rx) .. " kN" end
      if abs(rc.ry) > tol then it.ry = rc.ry; it.try = "Ry=" .. num(rc.ry) .. " kN" end
      if rc.mz and abs(rc.mz) > tol then it.mz = rc.mz; it.tmz = "Mz=" .. num(rc.mz) .. " kN·m" end
      -- direccion media (mundo) hacia las barras vecinas, para desplazar las flechas al lado libre
      for e = 1, #m.barras do
        local b = m.barras[e]
        local j
        if b.ni == i then j = b.nj elseif b.nj == i then j = b.ni end
        if j then
          local dx, dy = m.nodos[j].x - m.nodos[i].x, m.nodos[j].y - m.nodos[i].y
          local l = sqrt(dx * dx + dy * dy)
          if l > 0 then it.vx = it.vx + dx / l; it.vy = it.vy + dy / l end
        end
      end
      if it.rx or it.ry or it.mz then c.items[#c.items + 1] = it end
    end
  end
  cache.reac = c
  return c
end

-- --------------------------------------------------------------- primitivas
local PRm = nil          -- primitivas de dibujo (se reciben en R.pintar)
local LB, nlb = {}, 0    -- rectangulos de etiquetas ya colocadas (anti-solape)

local function libre(x0, y0, x1, y1)
  for i = 1, nlb, 4 do
    if x0 < LB[i + 2] and x1 > LB[i] and y0 < LB[i + 3] and y1 > LB[i + 1] then return false end
  end
  return true
end

-- Etiqueta de 7 pt junto a (cx,cy), preferentemente desplazada en la direccion (ux,uy); si choca con
-- otra ya colocada prueba el lado opuesto, los laterales y distancias mayores. Fondo blanco.
local ORDEN_ALT = { 0, 2, 3, 1 }   -- principal, laterales, opuesto
local LT, LX, LY = {}, {}, {}      -- textos y anclas ya colocados (evita duplicados en nodos compartidos)
local nlt = 0
local function etiqueta(gc, s, cx, cy, ux, uy, col)
  local PR = PRm
  PR.fuente(gc, "r", 7)
  local w = gc:getStringWidth(s)
  local R0 = V0.rect
  for i = 1, nlt do
    if LT[i] == s and abs(LX[i] - cx) < 6 and abs(LY[i] - cy) < 6 then return true end
  end
  for intento = 0, 7 do
    local k = ORDEN_ALT[intento % 4 + 1]
    local dx, dy
    if k == 0 then dx, dy = ux, uy elseif k == 1 then dx, dy = -ux, -uy
    elseif k == 2 then dx, dy = -uy, ux else dx, dy = uy, -ux end
    local off = (abs(dx) * (w / 2 + 4) + abs(dy) * 8) * (intento < 4 and 1 or 1.8)
    local bx = floor(cx + dx * off - w / 2 + 0.5)
    local by = floor(cy + dy * off - 5 + 0.5)
    if bx < R0.x + 2 then bx = R0.x + 2 elseif bx + w > R0.x + R0.w - 2 then bx = R0.x + R0.w - 2 - w end
    if by < R0.y + 1 then by = R0.y + 1 elseif by + 10 > R0.y + R0.h - 1 then by = R0.y + R0.h - 11 end
    if libre(bx - 1, by, bx + w + 1, by + 10) then
      LB[nlb + 1], LB[nlb + 2], LB[nlb + 3], LB[nlb + 4] = bx - 1, by, bx + w + 1, by + 10
      nlb = nlb + 4
      nlt = nlt + 1
      LT[nlt], LX[nlt], LY[nlt] = s, cx, cy
      PR.setc(gc, PR.C.fondo)
      gc:fillRect(bx - 1, by, w + 2, 10)
      PR.setc(gc, col)
      gc:drawString(s, bx, by, "top")
      return true
    end
  end
  return false
end

local function momento_arco(gc, cx, cy, rad, antihorario)
  local PR = PRm
  local r = PR.r
  gc:drawArc(r(cx - rad), r(cy - rad), r(2 * rad), r(2 * rad), 30, 270)
  local ang, tx, ty, dx, dy
  if antihorario then
    ang = (30 + 270) * math.pi / 180
    tx, ty = cx + rad * math.cos(ang), cy - rad * math.sin(ang)
    dx, dy = -math.sin(ang), -math.cos(ang)
  else
    ang = 30 * math.pi / 180
    tx, ty = cx + rad * math.cos(ang), cy - rad * math.sin(ang)
    dx, dy = math.sin(ang), math.cos(ang)
  end
  PR.punta(gc, tx, ty, dx, dy, 6)
end

-- ---------------------------------------------------------- pintado: reacciones
-- Las flechas salen del nodo en el sentido de la reaccion, desplazadas al lado libre de barras.
local function pintar_reac(gc)
  local PR = PRm
  local c = cache_reac()
  local m = ED.m
  local col = COL.reac
  for k = 1, #c.items do
    local it = c.items[k]
    local nd = m.nodos[it.i]
    local px, py = V0.a_pantalla(nd.x, nd.y)
    local svx, svy = it.vx, -it.vy
    PR.setc(gc, col); PR.pen(gc, "medium")
    if it.rx then
      local dx = it.rx > 0 and 1 or -1
      local ly = (svy > 0) and -7 or ((svy < 0) and 7 or -7)
      local tx, ty = px + dx * 6, py + ly
      local ex = tx + dx * 26
      PR.ln(gc, tx, ty, ex, ty)
      PR.punta(gc, ex, ty, dx, 0, 7)
    end
    if it.ry then
      local dy = it.ry > 0 and -1 or 1
      local lx = (svx > 0) and -7 or ((svx < 0) and 7 or -7)
      local tx, ty = px + lx, py + dy * 6
      local ey = ty + dy * 26
      PR.ln(gc, tx, ty, tx, ey)
      PR.punta(gc, tx, ey, 0, dy, 7)
    end
    if it.mz then
      PR.pen(gc, "thin")
      momento_arco(gc, px, py, 15, it.mz > 0)
    end
    PR.pen(gc, "thin")
  end
  for k = 1, #c.items do
    local it = c.items[k]
    local nd = m.nodos[it.i]
    local px, py = V0.a_pantalla(nd.x, nd.y)
    local svx, svy = it.vx, -it.vy
    if it.rx then
      local dx = it.rx > 0 and 1 or -1
      local ly = (svy > 0) and -7 or ((svy < 0) and 7 or -7)
      etiqueta(gc, it.trx, px + dx * 32, py + ly, dx, 0, col)
    end
    if it.ry then
      local dy = it.ry > 0 and -1 or 1
      local lx = (svx > 0) and -7 or ((svx < 0) and 7 or -7)
      if abs(svy) > 0.5 then
        -- barras verticales en el nodo: la etiqueta va al costado de la flecha, no sobre la barra
        etiqueta(gc, it.try, px + lx, py + dy * 19, (lx < 0) and -1 or 1, 0, col)
      else
        etiqueta(gc, it.try, px + lx, py + dy * 32, 0, dy, col)
      end
    end
    if it.mz then
      local sx = (svx > 0.3) and -1 or 1
      etiqueta(gc, it.tmz, px + sx * 22, py + 4, sx, 0, col)
    end
  end
end

-- ----------------------------------------------------------- pintado: diagramas
local function pintar_diag(gc, campo)
  local PR = PRm
  local res = R.res
  local c = cache_diag(campo)
  if c.kpx == 0 then return end
  local k = c.kpx * R.kd[campo]
  if campo == "M" then k = -k end           -- M del lado traccionado
  local S = V0.s
  local col, tin = COL[campo], TINTE[campo]
  local nb = #res.barras
  for e = 1, nb do
    local rb, b = res.barras[e], c.bars[e]
    local sx0, sy0 = V0.a_pantalla(rb.xi, rb.yi)
    local dx, dy = rb.c * S, -rb.s * S
    local nx, ny = -rb.s, -rb.c
    -- rayado ligero (perpendicular a la barra)
    PR.setc(gc, tin); PR.pen(gc, "thin")
    for i = 1, b.n - 1 do
      local xa, xb = b.xs[i], b.xs[i + 1]
      if xb - xa > 1e-12 then
        local va, vb = b.vs[i] * k, b.vs[i + 1] * k
        local q = floor((xb - xa) * S / 5)
        if q > 10 then q = 10 end
        for j = 0, q do
          local t = j / (q + 1)
          local x = xa + (xb - xa) * t
          local off = va + (vb - va) * t
          if abs(off) >= 1 then
            local bx, by = sx0 + dx * x, sy0 + dy * x
            PR.ln(gc, bx, by, bx + nx * off, by + ny * off)
          end
        end
      end
    end
    -- contorno
    PR.setc(gc, col); PR.pen(gc, "medium")
    local px, py
    for i = 1, b.n do
      local x = b.xs[i]
      local off = b.vs[i] * k
      local qx, qy = sx0 + dx * x + nx * off, sy0 + dy * x + ny * off
      if i == 1 then PR.ln(gc, sx0 + dx * x, sy0 + dy * x, qx, qy)
      else PR.ln(gc, px, py, qx, qy) end
      px, py = qx, qy
      if i == b.n then PR.ln(gc, qx, qy, sx0 + dx * x, sy0 + dy * x) end
    end
    PR.pen(gc, "thin")
    -- ceros (V = 0, M = 0) sobre la barra
    for i = 1, #b.ceros do
      local bx, by = sx0 + dx * b.ceros[i], sy0 + dy * b.ceros[i]
      PR.setc(gc, PR.C.fondo); PR.disco(gc, bx, by, 3)
      PR.setc(gc, col); PR.anillo(gc, bx, by, 3)
      PR.disco(gc, bx, by, 1)
    end
  end
  -- etiquetas de valores
  for e = 1, nb do
    local rb, b = res.barras[e], c.bars[e]
    local sx0, sy0 = V0.a_pantalla(rb.xi, rb.yi)
    local dx, dy = rb.c * S, -rb.s * S
    local nx, ny = -rb.s, -rb.c
    for i = 1, #b.lab do
      local lb = b.lab[i]
      local cur = R.cur
      if not (cur and cur.e == e and abs(cur.x - lb.x) * S < 14) then
        local off = lb.val * k
        local qx, qy = sx0 + dx * lb.x + nx * off, sy0 + dy * lb.x + ny * off
        local sg = (off >= 0) and 1 or -1
        PR.setc(gc, col); PR.disco(gc, qx, qy, 2)
        etiqueta(gc, lb.txt, qx, qy, nx * sg, ny * sg, col)
      end
    end
  end
end

-- ------------------------------------------------------------ pintado: deformada
local function pintar_def(gc)
  local PR = PRm
  local res = R.res
  local c = cache_def()
  local f = factor_def()
  local S = V0.s
  local ox, oy = V0.ox, V0.oy
  PR.setc(gc, COL.def); PR.pen(gc, "medium")
  for e = 1, #res.barras do
    local rb, b = res.barras[e], c.bars[e]
    local cc, ss = rb.c, rb.s
    local px, py
    for i = 1, b.n do
      local x, u, v = b.xs[i], b.us[i], b.vs[i]
      local X = rb.xi + cc * x + f * (cc * u - ss * v)
      local Y = rb.yi + ss * x + f * (ss * u + cc * v)
      local qx, qy = ox + X * S, oy - Y * S
      if i > 1 then PR.ln(gc, px, py, qx, qy) end
      px, py = qx, qy
    end
  end
  PR.pen(gc, "thin")
  local m = ED.m
  for i = 1, #m.nodos do
    local d = res.d[i]
    local nd = m.nodos[i]
    if d then
      PR.disco(gc, ox + (nd.x + f * d.ux) * S, oy - (nd.y + f * d.uy) * S, 2)
    end
  end
  -- punto de desplazamiento maximo
  if c.dmax > 1e-12 then
    local rb = res.barras[c.dmax_e]
    local _, _, _, _, v, u = E.eval(res, c.dmax_e, c.dmax_x)
    local X = rb.xi + rb.c * c.dmax_x + f * (rb.c * u - rb.s * v)
    local Y = rb.yi + rb.s * c.dmax_x + f * (rb.s * u + rb.c * v)
    local qx, qy = ox + X * S, oy - Y * S
    PR.setc(gc, PR.C.fondo); PR.disco(gc, qx, qy, 4)
    PR.setc(gc, COL.def); PR.anillo(gc, qx, qy, 4); PR.disco(gc, qx, qy, 1)
  end
end

-- ------------------------------------------------------------ cursor y recuadro
local function pintar_cursor(gc)
  local c = R.cur
  if not c then return end
  local PR = PRm
  local res = R.res
  local modo = R.modo
  local qxm
  if c.e then
    local rb = res.barras[c.e]
    if not rb then return end
    local S = V0.s
    local sx0, sy0 = V0.a_pantalla(rb.xi, rb.yi)
    local bx, by = sx0 + rb.c * S * c.x, sy0 - rb.s * S * c.x
    qxm = bx
    local col = COL[modo] or COL.M
    if modo == "N" or modo == "V" or modo == "M" then
      local cd = cache_diag(modo)
      local val = c[modo] or 0
      local off = val * cd.kpx * R.kd[modo] * ((modo == "M") and -1 or 1)
      local qx, qy = bx - rb.s * off, by - rb.c * off
      PR.setc(gc, col); PR.pen(gc, "thin", "dotted")
      PR.ln(gc, bx, by, qx, qy)
      PR.pen(gc, "thin", "smooth")
      PR.setc(gc, PR.C.fondo); PR.disco(gc, qx, qy, 5)
      PR.setc(gc, col); PR.disco(gc, qx, qy, 3); PR.anillo(gc, qx, qy, 5)
      PR.anillo(gc, bx, by, 3)
    elseif modo == "def" then
      local f = factor_def()
      local X = rb.xi + rb.c * c.x + f * c.ux
      local Y = rb.yi + rb.s * c.x + f * c.uy
      local qx, qy = V0.ox + X * S, V0.oy - Y * S
      PR.setc(gc, col)
      PR.ln(gc, bx, by, qx, qy)
      PR.setc(gc, PR.C.fondo); PR.disco(gc, qx, qy, 5)
      PR.setc(gc, col); PR.disco(gc, qx, qy, 3); PR.anillo(gc, qx, qy, 5)
    else
      PR.setc(gc, PR.C.info); PR.anillo(gc, bx, by, 5); PR.disco(gc, bx, by, 2)
    end
  elseif c.nodo then
    local nd = ED.m.nodos[c.nodo]
    if nd then
      local qx, qy = V0.a_pantalla(nd.x, nd.y)
      qxm = qx
      PR.setc(gc, PR.C.info); PR.anillo(gc, qx, qy, 8)
    end
  end
  -- recuadro con los valores (derecha; a la izquierda si el cursor esta cerca de ese lado)
  local n = c.l5 and 5 or (c.l4 and 4 or 3)
  PR.fuente(gc, "r", 7)
  local w = gc:getStringWidth(c.l1)
  local t2, t3, t4, t5 = c.l2, c.l3, c.l4, c.l5
  local a = gc:getStringWidth(t2); if a > w then w = a end
  a = gc:getStringWidth(t3); if a > w then w = a end
  if t4 then a = gc:getStringWidth(t4); if a > w then w = a end end
  if t5 then a = gc:getStringWidth(t5); if a > w then w = a end end
  w = w + 8
  local R0 = V0.rect
  local bx = R0.x + R0.w - w - 3
  local by = R0.y + 2
  if qxm and qxm > bx - 10 then bx = R0.x + 3; by = R0.y + 24 end
  local h = n * 10 + 4
  PR.setc(gc, PR.C.fondo); gc:fillRect(bx, by, w, h)
  PR.setc(gc, PR.C.tb_borde); gc:drawRect(bx, by, w, h)
  PR.setc(gc, PR.C.texto)
  gc:drawString(c.l1, bx + 4, by + 2, "top")
  gc:drawString(t2, bx + 4, by + 12, "top")
  gc:drawString(t3, bx + 4, by + 22, "top")
  if t4 then gc:drawString(t4, bx + 4, by + 32, "top") end
  if t5 then gc:drawString(t5, bx + 4, by + 42, "top") end
end

-- ---------------------------------------------------------- cabecera de la vista
local hk_modo, hk_kd, hk_f, hk_real, hk_ver
local hdr1, hdr2 = "", ""
local function cabecera(gc)
  local PR = PRm
  local modo = R.modo
  local R0 = V0.rect
  local kd = R.kd[modo]
  if hk_modo ~= modo or hk_kd ~= kd or hk_f ~= R.def_f or hk_real ~= R.def_real or hk_ver ~= R.ver then
    hk_modo, hk_kd, hk_f, hk_real, hk_ver = modo, kd, R.def_f, R.def_real, R.ver
    if modo == "N" or modo == "V" or modo == "M" then
      local c = cache_diag(modo)
      hdr1 = NOMBRE[modo] .. " [" .. UNID[modo] .. "]"
      if c.kpx == 0 then hdr2 = modo .. " = 0 en toda la estructura"
      else hdr2 = "max " .. num(c.maxabs) .. " | escala x" .. num(kd, 3) .. " (+/-)" end
    elseif modo == "def" then
      local c = cache_def()
      hdr1 = "Deformada x " .. num(factor_def(), 3) .. (R.def_real and " (real)" or "")
      if c.dmax > 1e-12 then
        hdr2 = "δmax=" .. num(c.dmax * 1000) .. " mm (B" .. c.dmax_e .. ", x=" .. num(c.dmax_x, 3) .. " m)"
      else
        hdr2 = "sin desplazamientos"
      end
    else
      hdr1 = "Reacciones [kN, kN·m]"
      hdr2 = "flecha = sentido de la reaccion"
    end
  end
  PR.txt(gc, hdr1, R0.x + 4, R0.y + 1, 9, "l", "b")
  PR.setc(gc, PR.C.etiq)
  PR.txt(gc, hdr2, R0.x + 4, R0.y + 13, 7, "l")
end

-- ------------------------------------------------------------ pantalla de error
local function pintar_error(gc)
  local PR = PRm
  local R0 = V0.rect
  local w = min(R0.w - 20, 270)
  local lineas = D.ajustar(R.err or "No se pudo resolver", w - 16)
  local h = 22 + #lineas * 12 + 16
  local x = R0.x + floor((R0.w - w) / 2)
  local y = R0.y + 4        -- arriba: no tapa la estructura
  PR.setc(gc, PR.C.fondo); gc:fillRect(x, y, w, h)
  PR.setc(gc, PR.C.err); PR.pen(gc, "medium"); gc:drawRect(x, y, w, h); PR.pen(gc, "thin")
  PR.txt(gc, "No se puede resolver", x + 8, y + 4, 9, "l", "b")
  PR.setc(gc, PR.C.texto)
  for i = 1, #lineas do PR.txt(gc, lineas[i], x + 8, y + 20 + (i - 1) * 12, 9, "l") end
  PR.setc(gc, PR.C.etiq)
  PR.txt(gc, "Se recalcula solo al corregir. ESC: volver a modelar", x + 8, y + h - 12, 7, "l")
end

-- ------------------------------------------------------------------- tabla
local function construir_tabla()
  local res, m = R.res, ED.m
  R.clasif()
  local rows = {}
  local function t(s, bold) rows[#rows + 1] = { k = "t", s = s, b = bold } end
  local function fila(xs, cells, head, izq) rows[#rows + 1] = { k = "c", xs = xs, c = cells, h = head, izq = izq or 1 } end
  t("Clasificacion: " .. (cl_txt ~= "" and cl_txt or "-"), true)
  local XN = { 6, 96, 170, 250 }
  t("Desplazamientos nodales", true)
  fila(XN, { "Nodo", "ux [mm]", "uy [mm]", "rz [mrad]" }, true)
  for i = 1, #m.nodos do
    local d = res.d[i]
    if d then
      fila(XN, { tostring(i), num(d.ux * 1000), num(d.uy * 1000), d.rz and num(d.rz * 1000) or "-" })
    end
  end
  t("Reacciones", true)
  fila(XN, { "Nodo", "Rx [kN]", "Ry [kN]", "Mz [kN·m]" }, true)
  local hay = false
  for i = 1, #m.nodos do
    local rc = res.reac[i]
    if rc then
      hay = true
      fila(XN, { tostring(i), num(rc.rx), num(rc.ry), rc.mz and num(rc.mz) or "0" })
    end
  end
  if not hay then t("(sin apoyos)") end
  local XB = { 6, 62, 160, 226, 300 }
  t("Esfuerzos en extremos de barra (convencion de la leyenda)", true)
  fila(XB, { "Barra", "Extremo", "N [kN]", "V [kN]", "M [kN·m]" }, true, 2)
  for e = 1, #res.barras do
    local rb = res.barras[e]
    local N0, V0v, M0 = E.eval(res, e, 0)
    local N1, V1, M1 = E.eval(res, e, rb.L)
    fila(XB, { tostring(e) .. " (" .. rb.ni .. "-" .. rb.nj .. ")", "i  x=0", num(N0), num(V0v), num(M0) }, false, 2)
    fila(XB, { "L=" .. num(rb.L, 3) .. " m", "j  x=L", num(N1), num(V1), num(M1) }, false, 2)
  end
  local eq = res.equilibrio
  t("Equilibrio global (cargas + reacciones)", true)
  if eq then
    t("SFx=" .. exp_txt(eq.fx) .. "  SFy=" .. exp_txt(eq.fy) .. "  SM=" .. exp_txt(eq.m))
    t("Residuo relativo: " .. exp_txt(eq.rel or 0) .. ((eq.rel or 0) < 1e-9 and "  (equilibrio correcto)" or "  (REVISAR)"))
  end
  R.tab_rows = rows
  return rows
end

local function pintar_tabla(gc)
  local PR = PRm
  local R0 = V0.rect
  PR.setc(gc, PR.C.fondo); gc:fillRect(R0.x, R0.y, R0.w, R0.h)
  local rows = R.tab_rows or construir_tabla()
  local y0 = R0.y + 16
  local vis = floor((R0.h - 16) / 10)
  local n = #rows
  local maxs = max(0, n - vis)
  if R.scroll > maxs then R.scroll = maxs end
  if R.scroll < 0 then R.scroll = 0 end
  PR.setc(gc, PR.C.texto)
  PR.txt(gc, "Tabla de resultados", R0.x + 4, R0.y + 1, 9, "l", "b")
  PR.setc(gc, PR.C.etiq)
  PR.txt(gc, (R.scroll + 1) .. "-" .. min(n, R.scroll + vis) .. " / " .. n, R0.x + R0.w - 4, R0.y + 3, 7, "r")
  PR.setc(gc, PR.C.tb_borde); gc:drawLine(R0.x, R0.y + 14, R0.x + R0.w - 1, R0.y + 14)
  for k = 1, vis do
    local row = rows[R.scroll + k]
    if not row then break end
    local y = y0 + (k - 1) * 10
    if row.k == "t" then
      PR.setc(gc, row.b and PR.C.info or PR.C.texto)
      PR.txt(gc, row.s, R0.x + 4, y, 7, "l", row.b and "b" or "r")
    else
      if row.h then
        PR.setc(gc, PR.C.sb); gc:fillRect(R0.x, y, R0.w, 10)
      end
      PR.setc(gc, PR.C.texto)
      local xs, c = row.xs, row.c
      local st = row.h and "b" or "r"
      for i = 1, #c do
        if i <= row.izq then PR.txt(gc, c[i], xs[i], y, 7, "l", st)
        else PR.txt(gc, c[i], xs[i], y, 7, "r", st) end
      end
    end
  end
  PR.setc(gc, PR.C.gris)
  if R.scroll > 0 then PR.txt(gc, "^", R0.x + R0.w - 8, R0.y + 15, 7, "c") end
  if R.scroll < maxs then PR.txt(gc, "v", R0.x + R0.w - 8, R0.y + R0.h - 10, 7, "c") end
end

-- ------------------------------------------------------------ ecuaciones
local CAMPOS_ECS = {
  { "V", "V(x)" }, { "M", "M(x)" }, { "th", "θ(x)" }, { "y", "y(x)" }, { "N", "N(x)" },
}

local function construir_ecs()
  local res = R.res
  local e = R.eb
  if e < 1 then e = 1 elseif e > #res.barras then e = #res.barras end
  R.eb = e
  local rb = res.barras[e]
  local eqs = E.ecuaciones(res, e)
  local lines = {}
  local ncas, ntot = 0, 0
  local function add(s, tipo) lines[#lines + 1] = { s = s, t = tipo or "r" } end
  add("Barra " .. e .. "  (nodos " .. rb.ni .. "-" .. rb.nj .. ", L=" .. num(rb.L, 4) .. " m)", "h")
  for k = 1, #eqs do
    local q = eqs[k]
    add("Tramo " .. k .. ":  " .. num(q.x0, 4) .. " <= x <= " .. num(q.x1, 4) .. " m", "s")
    for j = 1, #CAMPOS_ECS do
      local key, nom = CAMPOS_ECS[j][1], CAMPOS_ECS[j][2]
      local txt, src = CAS.ecuacion(q[key], q.x0, q.x1, rb.L)
      ntot = ntot + 1
      if src == "CAS" then ncas = ncas + 1 end
      add(nom .. " = " .. txt, "r")
    end
  end
  local fuente
  if CAS.disponible() then
    if ncas == ntot then fuente = "CAS"
    elseif ncas == 0 then fuente = "propio (CAS sin verificar)"
    else fuente = "CAS " .. ncas .. "/" .. ntot .. ", resto propio" end
  else
    fuente = "propio (CAS no disponible)"
  end
  R.ecs = { e = e, lines = lines, fuente = fuente, vl = nil }
  return R.ecs
end

-- Parte una ecuacion larga en lineas visuales cortando en los signos +/- entre terminos
local function envolver(gc, s, maxw, out, tipo, sangria)
  if gc:getStringWidth(s) <= maxw then out[#out + 1] = { s = s, t = tipo }; return end
  local toks, ini = {}, 1
  for j = 2, #s do
    local ch = s:sub(j, j)
    if ch == "+" or ch == "-" then
      local prev = s:sub(j - 1, j - 1)
      if prev ~= "e" and prev ~= "(" and prev ~= "=" and prev ~= " " then
        toks[#toks + 1] = s:sub(ini, j - 1)
        ini = j
      end
    end
  end
  toks[#toks + 1] = s:sub(ini)
  local linea, nuevo = "", true
  for i = 1, #toks do
    local cand = linea .. toks[i]
    if not nuevo and gc:getStringWidth(cand) > maxw then
      out[#out + 1] = { s = linea, t = tipo }
      linea = sangria .. toks[i]
    else
      linea = cand
      nuevo = false
    end
  end
  if linea ~= "" then out[#out + 1] = { s = linea, t = tipo } end
end

local function pintar_ecs(gc)
  local PR = PRm
  local R0 = V0.rect
  PR.setc(gc, PR.C.fondo); gc:fillRect(R0.x, R0.y, R0.w, R0.h)
  local ecs = R.ecs
  if not ecs or ecs.e ~= R.eb then ecs = construir_ecs() end
  PR.fuente(gc, "r", 9)
  if not ecs.vl then
    local vl = {}
    for i = 1, #ecs.lines do
      local l = ecs.lines[i]
      if l.t == "r" then envolver(gc, l.s, R0.w - 20, vl, "r", "   ")
      else vl[#vl + 1] = { s = l.s, t = l.t } end
    end
    ecs.vl = vl
  end
  local vl = ecs.vl
  local top = R0.y + 27
  local vis = floor((R0.y + R0.h - top) / 12)
  local n = #vl
  local maxs = max(0, n - vis)
  if R.scroll > maxs then R.scroll = maxs end
  if R.scroll < 0 then R.scroll = 0 end
  PR.setc(gc, PR.C.texto)
  PR.txt(gc, "Ecuaciones por tramo", R0.x + 4, R0.y + 1, 9, "l", "b")
  PR.setc(gc, PR.C.etiq)
  PR.txt(gc, "Barra " .. R.eb .. "/" .. #R.res.barras .. "  (< > cambia)", R0.x + R0.w - 4, R0.y + 3, 7, "r")
  PR.txt(gc, "x desde el nodo i; kN, m, rad. Motor: " .. ecs.fuente, R0.x + 4, R0.y + 15, 7, "l")
  PR.setc(gc, PR.C.tb_borde); gc:drawLine(R0.x, R0.y + 25, R0.x + R0.w - 1, R0.y + 25)
  for k = 1, vis do
    local l = vl[R.scroll + k]
    if not l then break end
    local y = top + (k - 1) * 12
    if l.t == "h" then
      PR.setc(gc, PR.C.info); PR.txt(gc, l.s, R0.x + 4, y, 9, "l", "b")
    elseif l.t == "s" then
      PR.setc(gc, PR.C.sel); PR.txt(gc, l.s, R0.x + 4, y, 9, "l", "b")
    else
      PR.setc(gc, PR.C.texto); PR.txt(gc, l.s, R0.x + 8, y, 9, "l", "r")
    end
  end
  PR.setc(gc, PR.C.gris)
  if R.scroll > 0 then PR.txt(gc, "^", R0.x + R0.w - 8, R0.y + 27, 7, "c") end
  if R.scroll < maxs then PR.txt(gc, "v", R0.x + R0.w - 8, R0.y + R0.h - 10, 7, "c") end
end

-- ---------------------------------------------------------------- pintar
function R.pintar(gc, V, m, PR)
  if not R.modo then return end
  PRm = PR
  nlb, nlt = 0, 0
  if not R.res then pintar_error(gc); return end
  local modo = R.modo
  if modo == "reac" then
    pintar_reac(gc)
  elseif modo == "N" or modo == "V" or modo == "M" then
    pintar_diag(gc, modo)
  elseif modo == "def" then
    pintar_def(gc)
  elseif modo == "tabla" then
    pintar_tabla(gc)
    return
  elseif modo == "ecs" then
    pintar_ecs(gc)
    return
  end
  PR.setc(gc, COL[modo] or PR.C.texto)
  cabecera(gc)
  pintar_cursor(gc)
end

-- ------------------------------------------------------------ estado / teclas
local ek_modo, ek_kd, ek_f, ek_real, ek_scroll, ek_eb, ek_ver
local est_txt = ""
function R.estado()
  if not R.modo then return nil end
  if not R.res then return R.err or "Sin resultados" end
  local c = R.cur
  if c and c.txt then return c.txt end
  local modo = R.modo
  local kd = R.kd[modo]
  if ek_modo == modo and ek_kd == kd and ek_f == R.def_f and ek_real == R.def_real
     and ek_scroll == R.scroll and ek_eb == R.eb and ek_ver == R.ver then
    return est_txt
  end
  ek_modo, ek_kd, ek_f, ek_real, ek_scroll, ek_eb, ek_ver = modo, kd, R.def_f, R.def_real, R.scroll, R.eb, R.ver
  local t
  if modo == "reac" then
    t = "Reacciones [kN, kN·m] | apunta a barra o nodo"
  elseif modo == "N" or modo == "V" or modo == "M" then
    t = modo .. " [" .. UNID[modo] .. "] esc x" .. num(kd, 3) .. " (+/-) | apunta o usa flechas"
  elseif modo == "def" then
    t = "Deformada x " .. num(factor_def(), 3) .. (R.def_real and " (real)" or "") .. " | +/- factor, 0 real"
  elseif modo == "tabla" then
    t = "Tabla | flechas desplazan (izq/der: pagina)"
  else
    t = "Ecs barra " .. R.eb .. " | < > cambia barra, ^ v desplaza"
  end
  est_txt = t
  return t
end

function R.leyenda()
  local fuente = {
    "Unidades: kN, m, rad (desplaz. en mm).",
    "Ejes: x derecha, y arriba, giro + antihorario. Ejes locales: x de nodo i a j, y local = x girado 90 grados antihorario.",
    "N: + = TRACCION, - = compresion. Se dibuja hacia +y local.",
    "V: suma de fuerzas transversales a la izquierda de la seccion (+ hacia +y local). V = dM/dx.",
    "M: + comprime la fibra +y local (viga horizontal: traccion abajo). El diagrama M se dibuja del lado TRACCIONADO.",
    "Deformada: ampliada por el factor 'x N' (0 = real, escala 1).",
    "Reacciones (magenta): flecha en el sentido de la fuerza que ejerce el apoyo; Mz + antihorario.",
    "Circulos sobre la barra: puntos de V=0 o M=0.",
    "TECLAS: r Reac, n N, v V, m M, d Deformada, t Tabla, e Ecuaciones, TAB siguiente vista.",
    "+/- escala del diagrama o factor de la deformada; 0 = deformada real.",
    "Flechas: izq/der mueven el cursor por la barra, arriba/abajo cambian de barra. f encuadrar, z/x zoom. ESC quita el cursor y luego vuelve a modelar.",
  }
  local l = {}
  for i = 1, #fuente do
    local w = D.ajustar(fuente[i], 270)
    for j = 1, #w do l[#l + 1] = w[j] end
  end
  D.texto("Leyenda de signos", l)
end

function R.tecla(c)
  if not R.modo then return false end
  local k = c:lower()
  local v
  if k == "r" then v = "reac" elseif k == "n" then v = "N" elseif k == "v" then v = "V"
  elseif k == "m" then v = "M" elseif k == "d" then v = "def" elseif k == "t" then v = "tabla"
  elseif k == "e" then v = "ecs" end
  if v then
    if not R.res and (k == "r" or #ED.m.nodos <= R.MAX_NODOS) then resolver_interno(R.S, ED.m) end
    R.set_vista(v)
    return true
  end
  if k == "?" or k == "l" then R.leyenda(); return true end
  local modo = R.modo
  if k == "+" or k == "=" or k == "-" or k == "_" or k == "\226\136\146" then
    local mas = (k == "+" or k == "=")
    if modo == "N" or modo == "V" or modo == "M" then
      local f = R.kd[modo]
      R.kd[modo] = mas and min(nice_up(f), 100) or max(nice_down(f), 0.1)
      return true
    elseif modo == "def" and R.res then
      R.def_real = false
      local f = factor_def()
      R.def_f = mas and min(nice_up(f), 1e6) or max(nice_down(f), 1)
      return true
    end
    return false
  end
  if k == "0" and modo == "def" then
    R.def_real = not R.def_real
    if not R.def_real then R.def_f = nil end
    return true
  end
  return false
end

function R.arrow(k)
  if not R.modo then return false end
  if not R.res then return true end
  local modo = R.modo
  if modo == "tabla" then
    local vis = floor((V0.rect.h - 16) / 10)
    if k == "up" then R.scroll = R.scroll - 1 elseif k == "down" then R.scroll = R.scroll + 1
    elseif k == "left" then R.scroll = R.scroll - vis else R.scroll = R.scroll + vis end
  elseif modo == "ecs" then
    if k == "up" then R.scroll = R.scroll - 1 elseif k == "down" then R.scroll = R.scroll + 1
    else
      local nb = #R.res.barras
      R.eb = R.eb + ((k == "right") and 1 or -1)
      if R.eb < 1 then R.eb = nb elseif R.eb > nb then R.eb = 1 end
      R.scroll = 0
      R.ecs = nil
    end
  else
    mover_cursor(k)
  end
  if R.scroll < 0 then R.scroll = 0 end
  return true
end

-- ESC: true si consumio la tecla (quito el cursor)
function R.esc()
  if R.cur then R.cur = nil; return true end
  return false
end

return R
