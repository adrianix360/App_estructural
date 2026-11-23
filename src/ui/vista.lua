-- ui/vista.lua - Camara del lienzo (zoom/pan), rejilla y snap.
-- Pantalla: x a la derecha, y hacia abajo. Mundo: x a la derecha, y hacia arriba (m).
-- API: V.a_pantalla(x,y) -> px,py   V.a_mundo(px,py) -> x,y   V.snap(x,y) -> x,y
--      V.zoom(f,px,py)  V.pan(dx,dy)  V.encuadrar(modelo)  V.set_rect(x,y,w,h)
--      V.paso_rejilla()  V.paso_etiqueta()  V.snap_valor()  V.ciclar_snap()
local V = {}

local floor, ceil, abs, min, max = math.floor, math.ceil, math.abs, math.min, math.max

V.rect = { x = 0, y = 22, w = 318, h = 164 }   -- area del lienzo en la ventana
V.s = 30                                       -- px por metro
V.ox, V.oy = 40, 150                           -- posicion en pantalla del origen del mundo
V.rejilla = true
V.pasos = { 0.1, 0.25, 0.5, 1, 0 }             -- 0 = libre (sin snap)
V.snap_i = 3
V.S_MIN, V.S_MAX = 4, 400

local NICE = { 0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10, 20, 50, 100, 200, 500, 1000 }

function V.set_rect(x, y, w, h)
  V.rect.x, V.rect.y, V.rect.w, V.rect.h = x, y, w, h
end

function V.vista_inicial()
  local R = V.rect
  V.s = 30
  V.ox = R.x + 30
  V.oy = R.y + R.h - 30
end

function V.a_pantalla(x, y)
  return V.ox + x * V.s, V.oy - y * V.s
end

function V.a_mundo(px, py)
  return (px - V.ox) / V.s, (V.oy - py) / V.s
end

local function limpio(v)
  v = floor(v * 1e6 + 0.5) / 1e6
  return v + 0   -- evita -0
end
V.limpio = limpio

function V.snap_valor()
  return V.pasos[V.snap_i]
end

function V.ciclar_snap()
  V.snap_i = V.snap_i % #V.pasos + 1
  return V.pasos[V.snap_i]
end

function V.fijar_snap(v)
  for i = 1, #V.pasos do
    if V.pasos[i] == v then V.snap_i = i; return true end
  end
  return false
end

function V.snap(x, y)
  local st = V.pasos[V.snap_i]
  if st and st > 0 then
    return limpio(floor(x / st + 0.5) * st), limpio(floor(y / st + 0.5) * st)
  end
  return limpio(x * 100 / 100), limpio(y)
end

function V.zoom(f, px, py)
  local R = V.rect
  px = px or (R.x + R.w / 2)
  py = py or (R.y + R.h / 2)
  local ns = max(V.S_MIN, min(V.S_MAX, V.s * f))
  local k = ns / V.s
  V.ox = px - (px - V.ox) * k
  V.oy = py - (py - V.oy) * k
  V.s = ns
end

function V.pan(dx, dy)
  V.ox = V.ox + dx
  V.oy = V.oy + dy
end

-- Ajusta la camara para ver todo el modelo (con margen para apoyos y cargas)
function V.encuadrar(m)
  local R = V.rect
  local n = m and #m.nodos or 0
  if n == 0 then V.vista_inicial(); return end
  local x0, y0, x1, y1 = 1e30, 1e30, -1e30, -1e30
  for i = 1, n do
    local nd = m.nodos[i]
    if nd.x < x0 then x0 = nd.x end
    if nd.x > x1 then x1 = nd.x end
    if nd.y < y0 then y0 = nd.y end
    if nd.y > y1 then y1 = nd.y end
  end
  local dx, dy = x1 - x0, y1 - y0
  local aw, ah = R.w - 72, R.h - 92
  local s = 60
  if dx > 1e-9 then s = min(s, aw / dx) end
  if dy > 1e-9 then s = min(s, ah / dy) end
  if dx <= 1e-9 and dy <= 1e-9 then s = 30 end
  s = max(V.S_MIN, min(V.S_MAX, s))
  V.s = s
  V.ox = R.x + R.w / 2 - (x0 + x1) / 2 * s
  V.oy = R.y + R.h / 2 + (y0 + y1) / 2 * s
end

-- Paso de rejilla visible: el menor "redondo" que quede a >= 16 px
function V.paso_rejilla()
  for i = 1, #NICE do
    if NICE[i] * V.s >= 16 then return NICE[i] end
  end
  return NICE[#NICE]
end

-- Paso de las etiquetas numericas de los ejes (>= 44 px)
function V.paso_etiqueta()
  for i = 1, #NICE do
    if NICE[i] * V.s >= 44 then return NICE[i] end
  end
  return NICE[#NICE]
end

-- Rango visible del mundo: x0, y0 (abajo), x1, y1 (arriba)
function V.rango_mundo()
  local R = V.rect
  local x0, y1 = V.a_mundo(R.x, R.y)
  local x1, y0 = V.a_mundo(R.x + R.w, R.y + R.h)
  return x0, y0, x1, y1
end

return V
