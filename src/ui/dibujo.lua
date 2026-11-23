-- ui/dibujo.lua - Todo el dibujo con gc: lienzo (rejilla, ejes), estructura, apoyos, rotulas,
-- cargas, barra de herramientas (iconos) y barra de estado.
-- Sin asignaciones por cuadro salvo cadenas cortas (cache de numeros); coordenadas siempre enteras.
-- API: P.size(w,h)  P.pintar(gc, H)  H = estado de ui.herramientas (tool, sel, barra_a, hover, botones...)
local V = require("ui.vista")
local ED = require("ui.modelo_ed")
local Res = require("ui.resultados")

local P = {}

local floor, abs, sqrt, sin, cos, atan2, min, max, pi =
  math.floor, math.abs, math.sqrt, math.sin, math.cos, math.atan2, math.min, math.max, math.pi

local WW, HH = 318, 212
local XMIN, YMIN, XMAX, YMAX = 0, 0, 317, 211
function P.size(w, h)
  WW, HH = w, h
  XMAX, YMAX = w - 1, h - 1
end

-- ------------------------------------------------------------------ colores
local C = {
  fondo = { 255, 255, 255 }, rej = { 234, 234, 238 }, eje = { 140, 140, 152 }, etiq = { 120, 120, 132 },
  barra = { 30, 30, 42 }, sel = { 0, 105, 230 }, hover = { 90, 150, 235 },
  apoyo = { 55, 55, 68 }, apoyo_f = { 222, 226, 232 }, carga = { 225, 100, 0 },
  nodo = { 20, 20, 32 }, rotula = { 255, 255, 255 }, guia = { 0, 105, 230 },
  tb = { 226, 229, 236 }, tb_borde = { 150, 155, 170 }, tb_act = { 190, 218, 255 }, tb_act_b = { 0, 90, 200 },
  sb = { 236, 238, 244 }, texto = { 25, 25, 35 }, err = { 190, 0, 0 }, info = { 0, 80, 160 },
  gris = { 150, 150, 160 }, verde = { 0, 140, 50 },
}
P.C = C

local function setc(gc, c) gc:setColorRGB(c[1], c[2], c[3]) end
local function pen(gc, g, estilo) gc:setPen(g or "thin", estilo or "smooth") end

local function r(v)
  v = floor(v + 0.5)
  if v > 30000 then return 30000 elseif v < -30000 then return -30000 end
  return v
end

-- ------------------------------------------------------- primitivas seguras
-- Recorte de segmento (Liang-Barsky) a la ventana: devuelve ok, x1, y1, x2, y2
local function clip(x1, y1, x2, y2)
  local dx, dy = x2 - x1, y2 - y1
  local t0, t1 = 0, 1
  local p, q
  for i = 1, 4 do
    if i == 1 then p, q = -dx, x1 - XMIN
    elseif i == 2 then p, q = dx, XMAX - x1
    elseif i == 3 then p, q = -dy, y1 - YMIN
    else p, q = dy, YMAX - y1 end
    if p == 0 then
      if q < 0 then return false end
    else
      local t = q / p
      if p < 0 then
        if t > t1 then return false elseif t > t0 then t0 = t end
      else
        if t < t0 then return false elseif t < t1 then t1 = t end
      end
    end
  end
  return true, x1 + t0 * dx, y1 + t0 * dy, x1 + t1 * dx, y1 + t1 * dy
end

local function ln(gc, x1, y1, x2, y2)
  local ok, a, b, c, d = clip(x1, y1, x2, y2)
  if ok then gc:drawLine(r(a), r(b), r(c), r(d)) end
end

local function frect(gc, x, y, w, h)
  w, h = r(w), r(h)
  if w > 0 and h > 0 then gc:fillRect(r(x), r(y), w, h) end
end
local function rect(gc, x, y, w, h)
  w, h = r(w), r(h)
  if w > 0 and h > 0 then gc:drawRect(r(x), r(y), w, h) end
end
local function disco(gc, x, y, rad)
  gc:fillArc(r(x - rad), r(y - rad), r(2 * rad), r(2 * rad), 0, 360)
end
local function anillo(gc, x, y, rad)
  gc:drawArc(r(x - rad), r(y - rad), r(2 * rad), r(2 * rad), 0, 360)
end

local TRI = { 0, 0, 0, 0, 0, 0 }
local function triangulo(gc, x1, y1, x2, y2, x3, y3)
  TRI[1], TRI[2], TRI[3], TRI[4], TRI[5], TRI[6] = r(x1), r(y1), r(x2), r(y2), r(x3), r(y3)
  gc:fillPolygon(TRI)
end

local TRI8 = { 0, 0, 0, 0, 0, 0, 0, 0 }
local function triangulo_borde(gc, x1, y1, x2, y2, x3, y3)
  TRI8[1], TRI8[2], TRI8[3], TRI8[4] = r(x1), r(y1), r(x2), r(y2)
  TRI8[5], TRI8[6], TRI8[7], TRI8[8] = r(x3), r(y3), r(x1), r(y1)
  gc:drawPolyLine(TRI8)
end

-- punta de flecha en (tx,ty) mirando hacia (dx,dy) unitario
local function punta(gc, tx, ty, dx, dy, tam)
  local bx, by = tx - dx * tam, ty - dy * tam
  local nx, ny = -dy * tam * 0.45, dx * tam * 0.45
  triangulo(gc, tx, ty, bx + nx, by + ny, bx - nx, by - ny)
end

local function flecha(gc, x1, y1, x2, y2)
  ln(gc, x1, y1, x2, y2)
  local dx, dy = x2 - x1, y2 - y1
  local l = sqrt(dx * dx + dy * dy)
  if l < 2 then return end
  punta(gc, x2, y2, dx / l, dy / l, min(6, l * 0.7))
end

local fcur_s, fcur_z
local function fuente(gc, estilo, tam)
  if fcur_s ~= estilo or fcur_z ~= tam then
    gc:setFont("sansserif", estilo, tam)
    fcur_s, fcur_z = estilo, tam
  end
end

-- texto (alineacion "l", "c", "r" respecto de x). Devuelve el ancho
local function txt(gc, s, x, y, tam, al, estilo)
  fuente(gc, estilo or "r", tam or 9)
  local w = gc:getStringWidth(s)
  if al == "c" then x = x - floor(w / 2) elseif al == "r" then x = x - w end
  gc:drawString(s, r(x), r(y), "top")
  return w
end

-- cache de numeros formateados
local fcache, fcount = {}, 0
local function fmtc(v)
  local s = fcache[v]
  if not s then
    s = ED.fmt(v, 2)
    if fcount > 300 then fcache, fcount = {}, 0 end
    fcache[v] = s; fcount = fcount + 1
  end
  return s
end

-- ------------------------------------------------------------ rejilla y ejes
local function rejilla(gc)
  local R = V.rect
  local x0, y0, x1, y1 = V.rango_mundo()
  if V.rejilla then
    local st = V.paso_rejilla()
    setc(gc, C.rej); pen(gc, "thin")
    local k0, k1 = math.ceil(x0 / st), floor(x1 / st)
    for k = k0, k1 do
      local px = V.ox + k * st * V.s
      gc:drawLine(r(px), R.y, r(px), R.y + R.h - 1)
    end
    k0, k1 = math.ceil(y0 / st), floor(y1 / st)
    for k = k0, k1 do
      local py = V.oy - k * st * V.s
      gc:drawLine(R.x, r(py), R.x + R.w - 1, r(py))
    end
  end
  -- ejes
  setc(gc, C.eje); pen(gc, "medium")
  if V.oy >= R.y and V.oy < R.y + R.h then gc:drawLine(R.x, r(V.oy), R.x + R.w - 1, r(V.oy)) end
  if V.ox >= R.x and V.ox < R.x + R.w then gc:drawLine(r(V.ox), R.y, r(V.ox), R.y + R.h - 1) end
  pen(gc, "thin")
  -- etiquetas numericas en los bordes del lienzo
  local le = V.paso_etiqueta()
  setc(gc, C.etiq)
  local k0, k1 = math.ceil(x0 / le), floor(x1 / le)
  for k = k0, k1 do
    local px = V.ox + k * le * V.s
    if px > R.x + 8 and px < R.x + R.w - 14 then
      gc:drawLine(r(px), R.y + R.h - 4, r(px), R.y + R.h - 1)
      txt(gc, fmtc(k * le), px, R.y + R.h - 13, 7, "c")
    end
  end
  k0, k1 = math.ceil(y0 / le), floor(y1 / le)
  for k = k0, k1 do
    local py = V.oy - k * le * V.s
    if py > R.y + 6 and py < R.y + R.h - 14 then
      gc:drawLine(R.x, r(py), R.x + 3, r(py))
      txt(gc, fmtc(k * le), R.x + 5, py - 4, 7, "l")
    end
  end
  txt(gc, "m", R.x + R.w - 3, R.y + R.h - 13, 7, "r")
end

-- ------------------------------------------------------------------ apoyos
local function sp(px, py, nx, ny, u, v)
  return px + nx * u - ny * v, py + ny * u + nx * v
end

local function suelo(gc, px, py, nx, ny, u, mitad)
  local ax, ay = sp(px, py, nx, ny, u, -mitad)
  local bx, by = sp(px, py, nx, ny, u, mitad)
  setc(gc, C.apoyo); pen(gc, "medium"); ln(gc, ax, ay, bx, by)
  pen(gc, "thin"); setc(gc, C.gris)
  local v = -mitad + 4
  while v <= mitad do
    local cx, cy = sp(px, py, nx, ny, u, v)
    local dx, dy = sp(px, py, nx, ny, u + 4, v - 4)
    ln(gc, cx, cy, dx, dy)
    v = v + 4
  end
end

local function sentido(sx, sy, modo)
  -- (nx,ny): hacia donde se dibuja el apoyo (fuera de la estructura), en pantalla (y hacia abajo)
  if modo == "v" then
    if sy > 0.5 then return 0, -1 end
    return 0, 1
  elseif modo == "h" then
    if abs(sx) > 0.3 then return (sx > 0) and -1 or 1, 0 end
    return -1, 0
  end
  if sx * sx + sy * sy < 0.09 then return 0, 1 end
  if abs(sx) >= abs(sy) then return (sx > 0) and -1 or 1, 0 end
  return 0, (sy > 0) and -1 or 1
end

local NX, NY = {}, {}

local function vecinos(m, i, px, py)
  local sx, sy = 0, 0
  for e = 1, #m.barras do
    local b = m.barras[e]
    local j
    if b.ni == i then j = b.nj elseif b.nj == i then j = b.ni end
    if j then
      local dx, dy = NX[j] - px, NY[j] - py
      local l = sqrt(dx * dx + dy * dy)
      if l > 0 then sx = sx + dx / l; sy = sy + dy / l end
    end
  end
  return sx, sy
end

local function apoyo(gc, m, i, ap)
  local px, py = NX[i], NY[i]
  local sx, sy = vecinos(m, i, px, py)
  local tipo = ED.apoyo_tipo(ap)
  setc(gc, C.apoyo); pen(gc, "thin")
  if tipo == "empotrado" then
    local nx, ny = sentido(sx, sy)
    local ax, ay = sp(px, py, nx, ny, 0, -12)
    local bx, by = sp(px, py, nx, ny, 0, 12)
    pen(gc, "thick"); ln(gc, ax, ay, bx, by); pen(gc, "thin")
    setc(gc, C.gris)
    local v = -8
    while v <= 12 do
      local cx, cy = sp(px, py, nx, ny, 0, v)
      local dx, dy = sp(px, py, nx, ny, 6, v - 6)
      ln(gc, cx, cy, dx, dy)
      v = v + 6
    end
  elseif tipo == "articulado" then
    local nx, ny = sentido(sx, sy, "v")
    local x1, y1 = sp(px, py, nx, ny, 11, -7)
    local x2, y2 = sp(px, py, nx, ny, 11, 7)
    setc(gc, C.apoyo_f); triangulo(gc, px, py, x1, y1, x2, y2)
    setc(gc, C.apoyo); triangulo_borde(gc, px, py, x1, y1, x2, y2)
    suelo(gc, px, py, nx, ny, 11, 10)
  elseif tipo == "rodilloX" or tipo == "rodilloY" then
    local nx, ny
    if tipo == "rodilloX" then nx, ny = sentido(sx, sy, "v") else nx, ny = sentido(sx, sy, "h") end
    local x1, y1 = sp(px, py, nx, ny, 8, -6)
    local x2, y2 = sp(px, py, nx, ny, 8, 6)
    setc(gc, C.apoyo_f); triangulo(gc, px, py, x1, y1, x2, y2)
    setc(gc, C.apoyo); triangulo_borde(gc, px, py, x1, y1, x2, y2)
    local cx, cy = sp(px, py, nx, ny, 11, -3.5)
    anillo(gc, cx, cy, 2.5)
    cx, cy = sp(px, py, nx, ny, 11, 3.5)
    anillo(gc, cx, cy, 2.5)
    suelo(gc, px, py, nx, ny, 14, 10)
  else
    -- resortes (y cualquier combinacion rara): zigzag por direccion con rigidez
    local function zig(nx, ny)
      local ux, uy = px, py
      local pts = { { 5, 0 }, { 7, 5 }, { 11, -5 }, { 15, 5 }, { 19, -5 }, { 21, 0 }, { 26, 0 } }
      setc(gc, C.apoyo); pen(gc, "thin")
      for k = 1, #pts do
        local qx, qy = sp(px, py, nx, ny, pts[k][1], pts[k][2])
        ln(gc, ux, uy, qx, qy)
        ux, uy = qx, qy
      end
      suelo(gc, px, py, nx, ny, 26, 8)
    end
    if (ap.ky or 0) > 0 then local nx, ny = sentido(sx, sy, "v"); zig(nx, ny) end
    if (ap.kx or 0) > 0 then local nx, ny = sentido(sx, sy, "h"); zig(nx, ny) end
    if (ap.kr or 0) > 0 then
      setc(gc, C.apoyo)
      gc:drawArc(r(px - 9), r(py - 9), 18, 18, 0, 270)
      txt(gc, "k", px + 10, py - 14, 7, "l", "b")
    end
    if tipo == "otro" then
      -- restricciones sueltas junto a resortes: marcas simples
      if ap.ux then ln(gc, px - 8, py - 6, px - 8, py + 6) end
      if ap.uy then ln(gc, px - 6, py + 8, px + 6, py + 8) end
    end
  end
  if (ap.dx or 0) ~= 0 or (ap.dy or 0) ~= 0 or (ap.drz or 0) ~= 0 then
    txt(gc, "d", px + 7, py + 3, 9, "l", "b")
  end
end

-- ------------------------------------------------------------------- cargas
-- direccion de la fuerza en el MUNDO (unitario) segun dir, signo y angulo de barra
local function dir_mundo(dir, sg, cb, sb)
  if dir == "GX" then return sg, 0 end
  if dir == "L" then return -sb * sg, cb * sg end
  if dir == "LX" then return cb * sg, sb * sg end
  return 0, sg                       -- GY
end

local function etiqueta_carga(gc, s, tx, ty, dx, dy)
  -- texto 7 pt centrado, desplazado del extremo de la flecha en el sentido contrario a la fuerza
  fuente(gc, "r", 7)
  local w = gc:getStringWidth(s)
  local off = abs(dx) * (w / 2 + 3) + abs(dy) * 8
  local cx, cy = tx - dx * off, ty - dy * off
  gc:drawString(s, r(cx - w / 2), r(cy - 5), "top")
end

local function momento(gc, cx, cy, rad, antihorario, s)
  gc:drawArc(r(cx - rad), r(cy - rad), r(2 * rad), r(2 * rad), 30, 270)
  -- punta en el extremo hacia el que gira
  local ang, tx, ty, dx, dy
  if antihorario then
    ang = (30 + 270) * pi / 180
    tx, ty = cx + rad * cos(ang), cy - rad * sin(ang)
    dx, dy = -sin(ang), -cos(ang)
  else
    ang = 30 * pi / 180
    tx, ty = cx + rad * cos(ang), cy - rad * sin(ang)
    dx, dy = sin(ang), cos(ang)
  end
  punta(gc, tx, ty, dx, dy, 6)
  if s then txt(gc, s, cx - rad - 2, cy - 4, 7, "r") end
end

local function carga_nodal(gc, i, c)
  local px, py = NX[i], NY[i]
  if c.fx and c.fx ~= 0 then
    local sg = c.fx > 0 and 1 or -1
    flecha(gc, px - sg * 30, py, px - sg * 5, py)
    etiqueta_carga(gc, fmtc(c.fx), px - sg * 30, py, sg, 0)
  end
  if c.fy and c.fy ~= 0 then
    local sg = c.fy > 0 and 1 or -1       -- +: hacia arriba
    flecha(gc, px, py + sg * 30, px, py + sg * 5)
    etiqueta_carga(gc, fmtc(c.fy), px, py + sg * 30, 0, -sg)
  end
  if c.mz and c.mz ~= 0 then
    momento(gc, px, py, 13, c.mz > 0, fmtc(c.mz))
  end
end

local function cargas_barra(gc, m, e)
  local b = m.barras[e]
  if #b.cargas == 0 then return end
  local x1, y1, x2, y2 = NX[b.ni], NY[b.ni], NX[b.nj], NY[b.nj]
  local na, nb = m.nodos[b.ni], m.nodos[b.nj]
  local L = sqrt((nb.x - na.x) ^ 2 + (nb.y - na.y) ^ 2)
  if L < 1e-9 then return end
  local cb, sb = (nb.x - na.x) / L, (nb.y - na.y) / L
  for k = 1, #b.cargas do
    local c = b.cargas[k]
    if c.t == "P" then
      local f = min(1, max(0, c.a / L))
      local bx, by = x1 + (x2 - x1) * f, y1 + (y2 - y1) * f
      local dx, dy = dir_mundo(c.dir, c.p >= 0 and 1 or -1, cb, sb)
      local sdx, sdy = dx, -dy
      flecha(gc, bx - sdx * 28, by - sdy * 28, bx, by)
      etiqueta_carga(gc, fmtc(c.p), bx - sdx * 28, by - sdy * 28, sdx, sdy)
    elseif c.t == "M" then
      local f = min(1, max(0, c.a / L))
      momento(gc, x1 + (x2 - x1) * f, y1 + (y2 - y1) * f, 11, c.m > 0, fmtc(c.m))
    elseif c.t == "w" then
      local a, bb = min(c.a, L), min(c.b, L)
      local wmax = max(abs(c.w1), abs(c.w2))
      if wmax > 0 and bb > a then
        local lpx = (bb - a) / L * sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
        local n = max(2, min(12, floor(lpx / 15) + 1))
        local px0, py0
        local tx1, ty1, sdx1, sdy1, w1v
        local ptx, pty, psx, psy
        for q = 0, n - 1 do
          local t = q / (n - 1)
          local s = a + (bb - a) * t
          local w = c.w1 + (c.w2 - c.w1) * t
          local f = s / L
          local bx, by = x1 + (x2 - x1) * f, y1 + (y2 - y1) * f
          local len = abs(w) / wmax * 24
          local dx, dy = dir_mundo(c.dir, w >= 0 and 1 or -1, cb, sb)
          local sdx, sdy = dx, -dy
          local tx, ty = bx - sdx * len, by - sdy * len
          if len >= 4 then flecha(gc, tx, ty, bx, by) end
          if ptx then ln(gc, ptx, pty, tx, ty) end
          if q == 0 then tx1, ty1, sdx1, sdy1 = tx, ty, sdx, sdy end
          ptx, pty, psx, psy = tx, ty, sdx, sdy
        end
        if c.w1 == c.w2 then
          local mx, my = (tx1 + ptx) / 2, (ty1 + pty) / 2
          etiqueta_carga(gc, fmtc(c.w1), mx, my, sdx1, sdy1)
        else
          if c.w1 ~= 0 then etiqueta_carga(gc, fmtc(c.w1), tx1, ty1, sdx1, sdy1) end
          if c.w2 ~= 0 then etiqueta_carga(gc, fmtc(c.w2), ptx, pty, psx, psy) end
        end
      end
    end
  end
end

-- ------------------------------------------------------------------ modelo
local function modelo(gc, H)
  local m = ED.m
  local nn, nb = #m.nodos, #m.barras
  for i = 1, nn do
    local n = m.nodos[i]
    NX[i], NY[i] = V.a_pantalla(n.x, n.y)
  end
  local sel = H.sel
  -- barras
  for e = 1, nb do
    local b = m.barras[e]
    local x1, y1, x2, y2 = NX[b.ni], NY[b.ni], NX[b.nj], NY[b.nj]
    setc(gc, C.barra)
    pen(gc, b.tipo == "cercha" and "thin" or "medium")
    ln(gc, x1, y1, x2, y2)
    if b.tipo == "cercha" then ln(gc, x1, y1 + 1, x2, y2 + 1) end
  end
  -- cargas (debajo de los apoyos)
  setc(gc, C.carga); pen(gc, "thin")
  for e = 1, nb do cargas_barra(gc, m, e) end
  setc(gc, C.carga)
  for i = 1, nn do
    local c = m.nodos[i].carga
    if c then carga_nodal(gc, i, c) end
  end
  -- apoyos
  for i = 1, nn do
    local ap = m.nodos[i].apoyo
    if ap then apoyo(gc, m, i, ap) end
  end
  -- rotulas (circulo hueco cerca del extremo)
  pen(gc, "thin")
  for e = 1, nb do
    local b = m.barras[e]
    if b.tipo ~= "cercha" and (b.rot_i or b.rot_j) then
      local x1, y1, x2, y2 = NX[b.ni], NY[b.ni], NX[b.nj], NY[b.nj]
      local dx, dy = x2 - x1, y2 - y1
      local l = sqrt(dx * dx + dy * dy)
      if l > 20 then
        local ux, uy = dx / l, dy / l
        if b.rot_i then
          setc(gc, C.rotula); disco(gc, x1 + ux * 8, y1 + uy * 8, 3.5)
          setc(gc, C.barra); anillo(gc, x1 + ux * 8, y1 + uy * 8, 3.5)
        end
        if b.rot_j then
          setc(gc, C.rotula); disco(gc, x2 - ux * 8, y2 - uy * 8, 3.5)
          setc(gc, C.barra); anillo(gc, x2 - ux * 8, y2 - uy * 8, 3.5)
        end
      end
    end
  end
  -- seleccion y resaltado
  if sel and sel.t == "barra" and m.barras[sel.i] then
    local b = m.barras[sel.i]
    setc(gc, C.sel); pen(gc, "thick")
    ln(gc, NX[b.ni], NY[b.ni], NX[b.nj], NY[b.nj])
    pen(gc, "thin")
  end
  local hv = H.hover
  if hv and hv.nodo and m.nodos[hv.nodo] and not (sel and sel.t == "nodo" and sel.i == hv.nodo) then
    setc(gc, C.hover); anillo(gc, NX[hv.nodo], NY[hv.nodo], 7)
  elseif hv and hv.barra and m.barras[hv.barra] and H.tool ~= "nodo" and not (sel and sel.t == "barra" and sel.i == hv.barra) then
    local b = m.barras[hv.barra]
    setc(gc, C.hover); pen(gc, "medium")
    ln(gc, NX[b.ni], NY[b.ni], NX[b.nj], NY[b.nj])
    pen(gc, "thin")
  end
  -- nodos
  for i = 1, nn do
    setc(gc, C.nodo); disco(gc, NX[i], NY[i], 3)
  end
  if sel and sel.t == "nodo" and m.nodos[sel.i] then
    setc(gc, C.sel); disco(gc, NX[sel.i], NY[sel.i], 4); anillo(gc, NX[sel.i], NY[sel.i], 7)
    anillo(gc, NX[sel.i], NY[sel.i], 8)
  end
  if H.barra_a and m.nodos[H.barra_a] then
    setc(gc, C.guia); anillo(gc, NX[H.barra_a], NY[H.barra_a], 7)
  end
  -- numeros de nodo: en la diagonal mas libre de barras, apoyos y cargas
  setc(gc, C.etiq)
  for i = 1, nn do
    local px, py = NX[i], NY[i]
    local nd = m.nodos[i]
    local mejor, mx, my = 2, 1, -1
    for q = 1, 4 do
      local cx, cy = (q % 2 == 1) and 0.7071 or -0.7071, (q <= 2) and -0.7071 or 0.7071
      local peor = -1
      for e = 1, nb do
        local b = m.barras[e]
        local j
        if b.ni == i then j = b.nj elseif b.nj == i then j = b.ni end
        if j then
          local dx, dy = NX[j] - px, NY[j] - py
          local l = sqrt(dx * dx + dy * dy)
          if l > 0 then
            local d = (dx * cx + dy * cy) / l
            if d > peor then peor = d end
          end
        end
      end
      if nd.apoyo and cy > 0 and peor < 0.6 then peor = 0.6 end
      if nd.carga then
        if nd.carga.fy and nd.carga.fy ~= 0 and cy * (nd.carga.fy < 0 and -1 or 1) < 0 and peor < 0.7 then peor = 0.7 end
      end
      if peor < mejor then mejor, mx, my = peor, cx, cy end
    end
    local ox = (mx > 0) and 4 or -4
    local oy = (my < 0) and -12 or 2
    txt(gc, tostring(i), px + ox, py + oy, 7, (mx > 0) and "l" or "r")
  end
end

local function guia_cursor(gc, H)
  local hv = H.hover
  if not (hv and hv.px and hv.en_lienzo) then return end
  local m = ED.m
  if H.tool == "barra" and H.barra_a and m.nodos[H.barra_a] then
    setc(gc, C.guia); pen(gc, "thin", "dotted")
    ln(gc, NX[H.barra_a], NY[H.barra_a], hv.sx, hv.sy)
    pen(gc, "thin", "smooth")
  end
  if H.tool == "nodo" or H.tool == "barra" then
    setc(gc, C.guia)
    local x, y = r(hv.sx), r(hv.sy)
    gc:drawLine(x - 6, y, x - 2, y); gc:drawLine(x + 2, y, x + 6, y)
    gc:drawLine(x, y - 6, x, y - 2); gc:drawLine(x, y + 2, x, y + 6)
  end
end

-- ---------------------------------------------------------- barra de herramientas
local function icono(gc, id, cx, cy, gris)
  local function k(c) if gris then setc(gc, C.gris) else setc(gc, c) end end
  pen(gc, "thin")
  if id == "sel" then
    k(C.nodo)
    gc:fillPolygon({ r(cx - 4), r(cy - 7), r(cx - 4), r(cy + 5), r(cx - 1), r(cy + 2), r(cx + 2), r(cy + 8),
                     r(cx + 4), r(cy + 7), r(cx + 1), r(cy + 1), r(cx + 5), r(cy + 1) })
  elseif id == "nodo" then
    k(C.nodo); disco(gc, cx, cy, 4)
    k(C.sel); gc:drawLine(r(cx + 5), r(cy - 6), r(cx + 5), r(cy - 2)); gc:drawLine(r(cx + 3), r(cy - 4), r(cx + 7), r(cy - 4))
  elseif id == "barra" then
    k(C.nodo); pen(gc, "medium"); gc:drawLine(r(cx - 7), r(cy + 4), r(cx + 7), r(cy - 4)); pen(gc, "thin")
    disco(gc, cx - 7, cy + 4, 2.5); disco(gc, cx + 7, cy - 4, 2.5)
  elseif id == "apoyo" then
    k(C.apoyo)
    triangulo_borde(gc, cx, cy - 6, cx - 6, cy + 4, cx + 6, cy + 4)
    gc:drawLine(r(cx - 8), r(cy + 6), r(cx + 8), r(cy + 6))
  elseif id == "carga" then
    k(C.carga); pen(gc, "medium")
    gc:drawLine(r(cx), r(cy - 8), r(cx), r(cy + 3)); pen(gc, "thin")
    triangulo(gc, cx, cy + 8, cx - 4, cy + 2, cx + 4, cy + 2)
  elseif id == "resolver" then
    k(C.verde); triangulo(gc, cx - 4, cy - 7, cx - 4, cy + 7, cx + 7, cy)
  elseif id == "undo" or id == "redo" then
    k(C.info)
    gc:drawArc(r(cx - 6), r(cy - 6), 12, 12, 0, 180)
    gc:drawArc(r(cx - 5), r(cy - 5), 10, 10, 0, 180)
    if id == "undo" then triangulo(gc, cx - 9, cy, cx - 2, cy, cx - 5.5, cy + 5)
    else triangulo(gc, cx + 2, cy, cx + 9, cy, cx + 5.5, cy + 5) end
  elseif id == "fit" then
    k(C.info)
    gc:drawLine(r(cx - 7), r(cy - 3), r(cx - 7), r(cy - 7)); gc:drawLine(r(cx - 7), r(cy - 7), r(cx - 3), r(cy - 7))
    gc:drawLine(r(cx + 7), r(cy - 3), r(cx + 7), r(cy - 7)); gc:drawLine(r(cx + 7), r(cy - 7), r(cx + 3), r(cy - 7))
    gc:drawLine(r(cx - 7), r(cy + 3), r(cx - 7), r(cy + 7)); gc:drawLine(r(cx - 7), r(cy + 7), r(cx - 3), r(cy + 7))
    gc:drawLine(r(cx + 7), r(cy + 3), r(cx + 7), r(cy + 7)); gc:drawLine(r(cx + 7), r(cy + 7), r(cx + 3), r(cy + 7))
    disco(gc, cx, cy, 2)
  elseif id == "zmas" or id == "zmenos" then
    k(C.info)
    anillo(gc, cx - 1, cy - 1, 5.5)
    gc:drawLine(r(cx + 3), r(cy + 3), r(cx + 8), r(cy + 8))
    gc:drawLine(r(cx - 4), r(cy - 1), r(cx + 2), r(cy - 1))
    if id == "zmas" then gc:drawLine(r(cx - 1), r(cy - 4), r(cx - 1), r(cy + 2)) end
  end
end

local function barra_herramientas(gc, H)
  local bh = V.rect.y
  setc(gc, C.tb); gc:fillRect(0, 0, WW, bh)
  setc(gc, C.tb_borde); pen(gc, "thin"); gc:drawLine(0, bh - 1, WW - 1, bh - 1)
  for i = 1, #H.botones do
    local b = H.botones[i]
    local activo = b.herr and H.tool == b.herr
    local gris = (b.id == "undo" and not ED.puede_deshacer()) or (b.id == "redo" and not ED.puede_rehacer())
    if activo then
      setc(gc, C.tb_act); gc:fillRect(b.x, b.y, b.w, b.h)
      setc(gc, C.tb_act_b); pen(gc, "medium"); gc:drawRect(b.x, b.y, b.w, b.h); pen(gc, "thin")
    else
      setc(gc, C.fondo); gc:fillRect(b.x, b.y, b.w, b.h)
      setc(gc, C.tb_borde); gc:drawRect(b.x, b.y, b.w, b.h)
    end
    icono(gc, b.id, b.x + 10, b.y + b.h / 2, gris)
    if b.tecla then
      setc(gc, activo and C.tb_act_b or C.etiq)
      txt(gc, b.tecla, b.x + b.w - 3, b.y + b.h - 10, 7, "r", activo and "b" or "r")
    end
  end
end

local function barra_estado(gc, H)
  local sy = HH - H.sb_h
  setc(gc, C.sb); gc:fillRect(0, sy, WW, H.sb_h)
  setc(gc, C.tb_borde); gc:drawLine(0, sy, WW - 1, sy)
  local msg = H.msg
  local der = H.texto_coord()
  fuente(gc, "r", 7)
  local wd = (not msg and der) and gc:getStringWidth(der) or 0
  local izq, tam = nil, 9
  if msg then izq = msg.t; setc(gc, msg.err and C.err or C.info)
  else izq = H.texto_estado(); setc(gc, C.texto) end
  fuente(gc, "r", 9)
  local maxw = WW - 8 - (wd > 0 and wd + 6 or 0)
  if gc:getStringWidth(izq) > maxw then
    tam = 7
    fuente(gc, "r", 7)
  end
  gc:drawString(izq, 4, sy + (tam == 9 and 1 or 3), "top")
  if wd > 0 then
    setc(gc, C.etiq)
    fuente(gc, "r", 7)
    gc:drawString(der, WW - 4 - wd, sy + 3, "top")
  end
end

-- --------------------------------------------------------------------- todo
function P.pintar(gc, H)
  fcur_s, fcur_z = nil, nil
  setc(gc, C.fondo); gc:fillRect(0, 0, WW, HH)
  rejilla(gc)
  modelo(gc, H)
  Res.pintar(gc, V, ED.m)
  guia_cursor(gc, H)
  if #ED.m.nodos == 0 then
    local R = V.rect
    setc(gc, C.etiq)
    txt(gc, "Modelo vacio", R.x + R.w / 2, R.y + R.h / 2 - 24, 12, "c", "b")
    txt(gc, "Herramienta Barra: haz clic en dos puntos", R.x + R.w / 2, R.y + R.h / 2 - 6, 9, "c")
    txt(gc, "Menu > Archivo > Ejemplos para empezar", R.x + R.w / 2, R.y + R.h / 2 + 8, 9, "c")
  end
  barra_herramientas(gc, H)
  barra_estado(gc, H)
end

return P
