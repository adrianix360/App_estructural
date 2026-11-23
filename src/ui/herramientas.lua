-- ui/herramientas.lua - Herramientas de modelado, eventos de raton/teclado y dialogos de edicion.
-- Herramientas: sel (Seleccionar/mover), nodo, barra, apoyo, carga. "Resolver" es una accion.
-- Estado publico (lo lee ui.dibujo): H.tool, H.sel, H.barra_a, H.hover, H.msg, H.botones, H.sb_h,
--   H.texto_estado(), H.texto_coord().
-- Toda modificacion del modelo pasa por ED.hacer (deshacer) y termina en un redibujado.
local ED = require("ui.modelo_ed")
local V = require("ui.vista")
local D = require("ui.dialogo")
local Res = require("ui.resultados")

local H = {}

local floor, abs, sqrt, min, max = math.floor, math.abs, math.sqrt, math.min, math.max

H.TB_H = 22
H.sb_h = 16
H.tool = "barra"
H.sel = nil            -- { t = "nodo"|"barra", i = n }
H.barra_a = nil        -- primer nodo de la barra en curso
H.msg = nil            -- { t = texto, err = bool } (se borra con la siguiente accion)
H.ver = 0              -- sube con cada cambio del modelo
H.hover = { px = nil, py = nil, wx = 0, wy = 0, sx = 0, sy = 0, en_lienzo = false, nodo = nil, barra = nil }
H.botones = {}

local WW, HH = 318, 212
local NODO_TOL, BARRA_TOL = 9, 6
local ptr = nil            -- { x0, y0, moved, nodo }
local drag = nil           -- { tipo = "nodo"|"pan", i, lx, ly, sticky, snap }
local ignora_up = false
local forma_cursor = nil

local function redraw()
  if platform and platform.window then platform.window:invalidate() end
end
H.redraw = redraw

local function aviso(t, err)
  H.msg = { t = t, err = err and true or false }
  redraw()
end
H.aviso = aviso

local function fmt(v, d) return ED.fmt(v, d or 2) end

-- ------------------------------------------------------------ inicializacion
local DEF = {
  { id = "sel", herr = "sel", tecla = "S" }, { id = "nodo", herr = "nodo", tecla = "N" },
  { id = "barra", herr = "barra", tecla = "B" }, { id = "apoyo", herr = "apoyo", tecla = "A" },
  { id = "carga", herr = "carga", tecla = "C" }, { id = "resolver", tecla = "R" }, "sep",
  { id = "undo" }, { id = "redo" }, { id = "fit" }, { id = "zmas" }, { id = "zmenos" },
}

local function layout_botones()
  H.botones = {}
  local x = 4
  for i = 1, #DEF do
    local d = DEF[i]
    if d == "sep" then x = x + 10
    else
      H.botones[#H.botones + 1] = { id = d.id, herr = d.herr, tecla = d.tecla, x = x, y = 1, w = 24, h = H.TB_H - 3 }
      x = x + 26
    end
  end
end

function H.resize(w, h)
  WW, HH = w, h
  V.set_rect(0, H.TB_H, w, h - H.TB_H - H.sb_h)
  layout_botones()
  D.size(w, h)
end

function H.init()
  ED.on_cambio = function()
    H.ver = H.ver + 1
    local m = ED.m
    local s = H.sel
    if s then
      if (s.t == "nodo" and not m.nodos[s.i]) or (s.t == "barra" and not m.barras[s.i]) then H.sel = nil end
    end
    if H.barra_a and not m.nodos[H.barra_a] then H.barra_a = nil end
    Res.invalidar()
    if document and document.markChanged then document.markChanged() end
    redraw()
  end
  layout_botones()
end

-- -------------------------------------------------------------- busqueda
local function nodo_en(px, py, tol)
  local m = ED.m
  local best, bd = nil, tol * tol
  for i = 1, #m.nodos do
    local n = m.nodos[i]
    local sx, sy = V.a_pantalla(n.x, n.y)
    local d = (sx - px) ^ 2 + (sy - py) ^ 2
    if d <= bd then best, bd = i, d end
  end
  return best
end

-- barra mas cercana al punto de pantalla; devuelve e, a (m desde el nodo i)
local function barra_en(px, py, tol)
  local m = ED.m
  local best, bd, ba = nil, tol, 0
  for e = 1, #m.barras do
    local b = m.barras[e]
    local a, c = m.nodos[b.ni], m.nodos[b.nj]
    local x1, y1 = V.a_pantalla(a.x, a.y)
    local x2, y2 = V.a_pantalla(c.x, c.y)
    local dx, dy = x2 - x1, y2 - y1
    local l2 = dx * dx + dy * dy
    if l2 > 0 then
      local t = ((px - x1) * dx + (py - y1) * dy) / l2
      if t < 0 then t = 0 elseif t > 1 then t = 1 end
      local qx, qy = x1 + t * dx, y1 + t * dy
      local d = sqrt((px - qx) ^ 2 + (py - qy) ^ 2)
      if d <= bd then
        best, bd = e, d
        ba = t * sqrt((c.x - a.x) ^ 2 + (c.y - a.y) ^ 2)
      end
    end
  end
  return best, ba
end

local function en_lienzo(x, y)
  local R = V.rect
  return x >= R.x and x < R.x + R.w and y >= R.y and y < R.y + R.h
end

local function poner_cursor(forma)
  if forma ~= forma_cursor and cursor and cursor.set then
    forma_cursor = forma
    cursor.set(forma)
  end
end

local function actualizar_hover(x, y)
  local hv = H.hover
  hv.px, hv.py = x, y
  hv.en_lienzo = en_lienzo(x, y)
  if hv.en_lienzo then
    hv.wx, hv.wy = V.snap(V.a_mundo(x, y))
    hv.sx, hv.sy = V.a_pantalla(hv.wx, hv.wy)
    hv.nodo = nodo_en(x, y, NODO_TOL)
    hv.barra = nil
    if not hv.nodo then hv.barra = barra_en(x, y, BARRA_TOL) end
    if drag then poner_cursor("hand closed")
    elseif H.tool == "nodo" or H.tool == "barra" then poner_cursor("crosshair")
    elseif hv.nodo or hv.barra then poner_cursor("pointer")
    else poner_cursor("default") end
  else
    hv.nodo, hv.barra = nil, nil
    poner_cursor("default")
  end
end

-- ------------------------------------------------------- texto de la barra
local est_key = {}
local est_txt = ""

function H.texto_estado()
  local t, s, a, v = H.tool, H.sel, H.barra_a, H.ver
  if est_key.t == t and est_key.s == s and est_key.si == (s and s.i) and est_key.a == a and est_key.v == v
     and est_key.d == (drag ~= nil) then
    return est_txt
  end
  est_key.t, est_key.s, est_key.si, est_key.a, est_key.v, est_key.d = t, s, s and s.i, a, v, (drag ~= nil)
  local m = ED.m
  local r
  if drag then
    r = "Mueve el cursor y haz clic para soltar (ESC cancela)"
  elseif t == "sel" then
    if s and s.t == "nodo" and m.nodos[s.i] then
      r = "Nodo " .. s.i .. ": ENTER edita, DEL borra, M mueve"
    elseif s and s.t == "barra" and m.barras[s.i] then
      local b = m.barras[s.i]
      r = "Barra " .. s.i .. " (" .. b.ni .. "-" .. b.nj .. ", L=" .. fmt(ED.longitud(m, s.i)) .. " m): ENTER edita"
    else
      r = "Seleccionar: clic en nodo/barra, arrastra para mover"
    end
  elseif t == "nodo" then
    r = "Nodo - Clic: crear nodo (ENTER: x,y exactos)"
  elseif t == "barra" then
    if a then r = "Barra - Clic en el nodo B (ESC termina)"
    else r = "Barra - Clic en el nodo A (o en vacio)" end
  elseif t == "apoyo" then
    r = "Apoyo - Clic en un nodo para elegir el tipo"
  else
    r = "Carga - Clic en un nodo o en una barra"
  end
  est_txt = r
  return r
end

local ct = { en = nil, wx = nil, wy = nil, nn = nil, nb = nil, si = nil, s = "" }
function H.texto_coord()
  local hv, m = H.hover, ED.m
  local nn, nb = #m.nodos, #m.barras
  local en = hv.en_lienzo
  local st = V.snap_valor()
  if ct.en == en and ct.wx == hv.wx and ct.wy == hv.wy and ct.nn == nn and ct.nb == nb and ct.si == V.snap_i then
    return ct.s
  end
  ct.en, ct.wx, ct.wy, ct.nn, ct.nb, ct.si = en, hv.wx, hv.wy, nn, nb, V.snap_i
  local sn = (st and st > 0) and ("snap " .. fmt(st)) or "libre"
  if en then
    ct.s = "x=" .. fmt(hv.wx) .. " y=" .. fmt(hv.wy) .. " m | " .. nn .. "N " .. nb .. "B | " .. sn
  else
    ct.s = nn .. "N " .. nb .. "B | " .. sn
  end
  return ct.s
end

-- ---------------------------------------------------------- acciones basicas
function H.set_tool(t)
  H.tool = t
  H.barra_a = nil
  H.msg = nil
  if drag then drag = nil end
  forma_cursor = nil
  if H.hover.px then actualizar_hover(H.hover.px, H.hover.py) end
  redraw()
end

function H.encuadrar()
  V.encuadrar(ED.m)
  redraw()
end

function H.zoom(f)
  local hv = H.hover
  if hv.en_lienzo then V.zoom(f, hv.px, hv.py) else V.zoom(f) end
  if hv.px then actualizar_hover(hv.px, hv.py) end
  redraw()
end

function H.toggle_rejilla()
  V.rejilla = not V.rejilla
  aviso(V.rejilla and "Rejilla visible" or "Rejilla oculta")
end

function H.set_snap(v)
  V.fijar_snap(v)
  if v == 0 then aviso("Snap desactivado (coordenadas libres)")
  else aviso("Snap a " .. fmt(v) .. " m") end
end

function H.ciclar_snap()
  local v = V.ciclar_snap()
  H.set_snap(v)
end

function H.deshacer()
  local ok, msg = ED.deshacer()
  if ok then aviso("Deshecho") else aviso(msg, true) end
end

function H.rehacer()
  local ok, msg = ED.rehacer()
  if ok then aviso("Rehecho") else aviso(msg, true) end
end

local function asegurar_visible(i)
  local n = ED.m.nodos[i]
  if not n then return end
  local R = V.rect
  local sx, sy = V.a_pantalla(n.x, n.y)
  if sx < R.x + 14 or sx > R.x + R.w - 14 or sy < R.y + 14 or sy > R.y + R.h - 14 then
    V.encuadrar(ED.m)
  end
end

-- --------------------------------------------------------------- resolver
function H.resolver()
  local ok, S = pcall(require, "core.solver")
  if not ok or type(S) ~= "table" then
    D.aviso("Solver no disponible", "Resolver")
    return
  end
  local m = ED.m
  if #m.nodos < 2 or #m.barras < 1 then
    aviso("Crea al menos una barra antes de resolver", true)
    return
  end
  local ok2, msg = Res.resolver(S, m)
  if ok2 then aviso(msg or "Resuelto") else aviso(msg or "No se pudo resolver", true) end
end

-- ------------------------------------------------------------- dialogos
local function form(spec) return D.form(spec) end

-- Coordenadas exactas -> accion segun la herramienta
function H.dialogo_coordenadas()
  local hv = H.hover
  form({
    titulo = (H.tool == "barra") and (H.barra_a and "Nodo B: coordenadas (m)" or "Nodo A: coordenadas (m)")
        or "Nodo: coordenadas exactas (m)",
    campos = {
      { id = "x", etq = "x (m)", valor = hv.en_lienzo and hv.wx or 0 },
      { id = "y", etq = "y (m)", valor = hv.en_lienzo and hv.wy or 0 },
    },
    aceptar = function(v)
      if abs(v.x) > ED.MAXCOORD or abs(v.y) > ED.MAXCOORD then return "Coordenada fuera de rango (max 10000 m)" end
      local i = ED.nodo_cerca(ED.m, v.x, v.y, 1e-6)
      H.accion({ nodo = i, wx = v.x, wy = v.y }, true)
      return nil
    end,
  })
end

local function dialogo_nodo(i)
  local n = ED.m.nodos[i]
  if not n then return end
  local c = n.carga or { fx = 0, fy = 0, mz = 0 }
  form({
    titulo = "Nodo " .. i,
    campos = {
      { id = "x", etq = "x (m)", valor = n.x }, { id = "y", etq = "y (m)", valor = n.y },
      { id = "fx", etq = "Fx (kN, + derecha)", valor = c.fx },
      { id = "fy", etq = "Fy (kN, + arriba)", valor = c.fy },
      { id = "mz", etq = "Mz (kN·m, + antih.)", valor = c.mz },
    },
    aceptar = function(v)
      local ok, msg = ED.hacer(function(m)
        local a, b = ED.mover_nodo(m, i, v.x, v.y)
        if not a then return nil, b end
        local c2, d2 = ED.set_carga_nodo(m, i, v.fx, v.fy, v.mz)
        if not c2 then return nil, d2 end
        ED.ajustar_todas(m)
        return true
      end)
      if not ok then return msg end
      aviso("Nodo " .. i .. " actualizado")
      return nil
    end,
  })
end

local function dialogo_barra(e)
  local m = ED.m
  local b = m.barras[e]
  if not b then return end
  local nc = #b.cargas
  form({
    titulo = "Barra " .. e .. " (nodos " .. b.ni .. "-" .. b.nj .. ", L=" .. fmt(ED.longitud(m, e)) .. " m)",
    campos = {
      { id = "E", etq = "E (GPa)", valor = b.E / ED.GPA },
      { id = "A", etq = "A (cm²)", valor = b.A / ED.CM2 },
      { id = "I", etq = "I (cm4)", valor = b.I / ED.CM4 },
      { id = "tipo", etq = "Tipo", tipo = "opcion", opciones = { "Portico", "Cercha" }, valor = (b.tipo == "cercha") and 2 or 1 },
      { id = "ri", etq = "Rotula en nodo i", tipo = "opcion", opciones = { "No", "Si" }, valor = b.rot_i and 2 or 1 },
      { id = "rj", etq = "Rotula en nodo j", tipo = "opcion", opciones = { "No", "Si" }, valor = b.rot_j and 2 or 1 },
      { id = "cg", etq = "Cargas (" .. nc .. ")", tipo = "opcion", opciones = { "Conservar", "Borrar todas" }, valor = 1 },
    },
    aceptar = function(v)
      if v.E <= 0 then return "E debe ser mayor que 0" end
      if v.A <= 0 then return "A debe ser mayor que 0" end
      if v.I <= 0 then return "I debe ser mayor que 0" end
      local ok, msg = ED.hacer(function(mm)
        local bb = mm.barras[e]
        if not bb then return nil, "La barra ya no existe" end
        bb.E, bb.A, bb.I = v.E * ED.GPA, v.A * ED.CM2, v.I * ED.CM4
        bb.tipo = (v.tipo == 2) and "cercha" or "portico"
        bb.rot_i, bb.rot_j = (v.ri == 2), (v.rj == 2)
        if v.cg == 2 then bb.cargas = {} end
        return true
      end)
      if not ok then return msg end
      aviso("Barra " .. e .. " actualizada")
      return nil
    end,
  })
end

function H.props_globales()
  local p = ED.props
  form({
    titulo = "Propiedades globales (barras nuevas)",
    campos = {
      { id = "E", etq = "E (GPa)", valor = p.E / ED.GPA },
      { id = "A", etq = "A (cm²)", valor = p.A / ED.CM2 },
      { id = "I", etq = "I (cm4)", valor = p.I / ED.CM4 },
      { id = "tipo", etq = "Tipo de barra nueva", tipo = "opcion", opciones = { "Portico", "Cercha" }, valor = (p.tipo == "cercha") and 2 or 1 },
      { id = "todas", etq = "Aplicar a", tipo = "opcion", opciones = { "Solo barras nuevas", "Todas las barras" }, valor = 1 },
    },
    aceptar = function(v)
      if v.E <= 0 or v.A <= 0 or v.I <= 0 then return "E, A e I deben ser mayores que 0" end
      p.E, p.A, p.I = v.E * ED.GPA, v.A * ED.CM2, v.I * ED.CM4
      p.tipo = (v.tipo == 2) and "cercha" or "portico"
      if v.todas == 2 and #ED.m.barras > 0 then
        ED.hacer(function(m)
          for e = 1, #m.barras do
            local b = m.barras[e]
            b.E, b.A, b.I = p.E, p.A, p.I
            b.tipo = p.tipo
          end
          return true
        end)
        aviso("Propiedades aplicadas a todas las barras")
      else
        aviso("Propiedades globales actualizadas")
      end
      return nil
    end,
  })
end

-- ---------------------------------------------------------------- apoyos
local NOMBRE_APOYO = { articulado = "articulado", rodilloX = "rodillo X (libre en X)",
                       rodilloY = "rodillo Y (libre en Y)", empotrado = "empotrado" }

local function dialogo_resorte(i)
  local n = ED.m.nodos[i]
  local ap = n.apoyo or {}
  form({
    titulo = "Resorte en nodo " .. i .. " (0 = sin resorte)",
    campos = {
      { id = "kx", etq = "kx (kN/m)", valor = ap.kx or 0, min = 0 },
      { id = "ky", etq = "ky (kN/m)", valor = ap.ky or 0, min = 0 },
      { id = "kr", etq = "kr (kN·m/rad)", valor = ap.kr or 0, min = 0 },
    },
    aceptar = function(v)
      local ok, msg = ED.hacer(function(m) return ED.set_resorte(m, i, v.kx, v.ky, v.kr) end)
      if not ok then return msg end
      aviso("Nodo " .. i .. ": apoyo elastico")
      return nil
    end,
  })
end

local function dialogo_asentamiento(i)
  local n = ED.m.nodos[i]
  if not n.apoyo then aviso("Primero asigna un apoyo a este nodo", true); return end
  local ap = n.apoyo
  form({
    titulo = "Asentamiento nodo " .. i .. " (GDL restringidos)",
    campos = {
      { id = "dx", etq = "dx (mm, + derecha)", valor = (ap.dx or 0) * 1000 },
      { id = "dy", etq = "dy (mm, + arriba)", valor = (ap.dy or 0) * 1000 },
      { id = "dr", etq = "giro (mrad, + antih.)", valor = (ap.drz or 0) * 1000 },
    },
    aceptar = function(v)
      local ok, msg = ED.hacer(function(m) return ED.set_asentamiento(m, i, v.dx / 1000, v.dy / 1000, v.dr / 1000) end)
      if not ok then return msg end
      aviso("Nodo " .. i .. ": asentamiento aplicado")
      return nil
    end,
  })
end

local TIPOS_APOYO = { "articulado", "rodilloX", "rodilloY", "empotrado" }
local SEL_APOYO = { articulado = 1, rodilloX = 2, rodilloY = 3, empotrado = 4, resorte = 5 }

function H.menu_apoyo(i)
  local n = ED.m.nodos[i]
  if not n then return end
  H.sel = { t = "nodo", i = i }
  D.menu({
    titulo = "Apoyo en nodo " .. i,
    items = { "Articulado", "Rodillo X (libre en X)", "Rodillo Y (libre en Y)", "Empotrado",
              "Resorte elastico (k)...", "Asentamiento...", "Quitar apoyo" },
    sel = SEL_APOYO[ED.apoyo_tipo(n.apoyo)] or 1,
    elegir = function(k)
      if k <= 4 then
        local tipo = TIPOS_APOYO[k]
        ED.hacer(function(m) return ED.set_apoyo_tipo(m, i, tipo) end)
        aviso("Nodo " .. i .. ": apoyo " .. NOMBRE_APOYO[tipo])
      elseif k == 5 then dialogo_resorte(i)
      elseif k == 6 then dialogo_asentamiento(i)
      else
        if not ED.m.nodos[i].apoyo then aviso("El nodo " .. i .. " no tiene apoyo", true)
        else
          ED.hacer(function(m) return ED.set_apoyo_tipo(m, i, "libre") end)
          aviso("Nodo " .. i .. ": apoyo quitado")
        end
      end
    end,
  })
end

-- ---------------------------------------------------------------- cargas
local DIR_OPC = { "Abajo (GY-)", "Arriba (GY+)", "Derecha (GX+)", "Izquierda (GX-)",
                  "Perpendicular a la barra", "Axial (a lo largo)" }

local function dir_desde_opcion(k, mag)
  if k == 1 then return "GY", -mag
  elseif k == 2 then return "GY", mag
  elseif k == 3 then return "GX", mag
  elseif k == 4 then return "GX", -mag
  elseif k == 5 then return "L", mag end
  return "LX", mag
end

function H.dialogo_carga_nodo(i)
  local n = ED.m.nodos[i]
  if not n then return end
  H.sel = { t = "nodo", i = i }
  local c = n.carga or { fx = 0, fy = 0, mz = 0 }
  form({
    titulo = "Carga en el nodo " .. i,
    campos = {
      { id = "fx", etq = "Fx (kN, + derecha)", valor = c.fx },
      { id = "fy", etq = "Fy (kN, + arriba)", valor = c.fy },
      { id = "mz", etq = "Mz (kN·m, + antih.)", valor = c.mz },
    },
    aceptar = function(v)
      local ok, msg = ED.hacer(function(m) return ED.set_carga_nodo(m, i, v.fx, v.fy, v.mz) end)
      if not ok then return msg end
      if v.fx == 0 and v.fy == 0 and v.mz == 0 then aviso("Nodo " .. i .. ": sin carga")
      else aviso("Nodo " .. i .. ": carga aplicada") end
      return nil
    end,
  })
end

local function dialogo_carga_barra(e, tipo, a_clic)
  local m = ED.m
  local b = m.barras[e]
  if not b then return end
  local L = ED.longitud(m, e)
  local Ls = fmt(L)
  local pos = a_clic or (L / 2)
  local st = V.snap_valor()
  if st and st > 0 then pos = floor(pos / st + 0.5) * st else pos = floor(pos * 100 + 0.5) / 100 end
  if pos < 0 then pos = 0 elseif pos > L then pos = L end
  local titulo = "Barra " .. e .. " (L=" .. Ls .. " m): "
  local function terminar(c, texto)
    local ok, msg = ED.hacer(function(mm) return ED.agregar_carga_barra(mm, e, c) end)
    if not ok then return msg end
    aviso(texto)
    return nil
  end
  if tipo == "P" then
    form({
      titulo = titulo .. "carga puntual",
      campos = {
        { id = "a", etq = "a (m, desde nodo " .. b.ni .. ")", valor = pos },
        { id = "p", etq = "Valor P (kN)", valor = 10 },
        { id = "d", etq = "Direccion", tipo = "opcion", opciones = DIR_OPC, valor = 1 },
      },
      aceptar = function(v)
        local dir, val = dir_desde_opcion(v.d, v.p)
        return terminar({ t = "P", a = v.a, p = val, dir = dir }, "Carga puntual agregada a la barra " .. e)
      end,
    })
  elseif tipo == "w" then
    form({
      titulo = titulo .. "distribuida",
      campos = {
        { id = "a", etq = "Desde a (m)", valor = 0 },
        { id = "b", etq = "Hasta b (m)", valor = L },
        { id = "w", etq = "Valor w (kN/m)", valor = 10 },
        { id = "d", etq = "Direccion", tipo = "opcion", opciones = DIR_OPC, valor = 1 },
      },
      aceptar = function(v)
        local dir, val = dir_desde_opcion(v.d, v.w)
        return terminar({ t = "w", a = v.a, b = v.b, w1 = val, w2 = val, dir = dir },
          "Carga distribuida agregada a la barra " .. e)
      end,
    })
  elseif tipo == "trap" then
    form({
      titulo = titulo .. "trapezoidal",
      campos = {
        { id = "a", etq = "Desde a (m)", valor = 0 },
        { id = "b", etq = "Hasta b (m)", valor = L },
        { id = "w1", etq = "w1 en a (kN/m)", valor = 0 },
        { id = "w2", etq = "w2 en b (kN/m)", valor = 10 },
        { id = "d", etq = "Direccion", tipo = "opcion", opciones = DIR_OPC, valor = 1 },
      },
      aceptar = function(v)
        local dir, w1 = dir_desde_opcion(v.d, v.w1)
        local _, w2 = dir_desde_opcion(v.d, v.w2)
        return terminar({ t = "w", a = v.a, b = v.b, w1 = w1, w2 = w2, dir = dir },
          "Carga trapezoidal agregada a la barra " .. e)
      end,
    })
  else
    form({
      titulo = titulo .. "momento",
      campos = {
        { id = "a", etq = "a (m, desde nodo " .. b.ni .. ")", valor = pos },
        { id = "m", etq = "M (kN·m, + antih.)", valor = 10 },
      },
      aceptar = function(v)
        return terminar({ t = "M", a = v.a, m = v.m }, "Momento agregado a la barra " .. e)
      end,
    })
  end
end

function H.menu_carga_barra(e, a_clic)
  local b = ED.m.barras[e]
  if not b then return end
  H.sel = { t = "barra", i = e }
  local nc = #b.cargas
  D.menu({
    titulo = "Carga en barra " .. e .. (nc > 0 and (" (" .. nc .. " cargas)") or ""),
    items = { "Puntual", "Distribuida uniforme", "Distribuida trapezoidal/triangular", "Momento puntual",
              "Borrar cargas de esta barra" },
    sel = 2,
    ancho = 270,
    elegir = function(k)
      if k == 1 then dialogo_carga_barra(e, "P", a_clic)
      elseif k == 2 then dialogo_carga_barra(e, "w")
      elseif k == 3 then dialogo_carga_barra(e, "trap")
      elseif k == 4 then dialogo_carga_barra(e, "M", a_clic)
      else
        if #ED.m.barras[e].cargas == 0 then aviso("La barra " .. e .. " no tiene cargas", true)
        else
          ED.hacer(function(m) m.barras[e].cargas = {}; return true end)
          aviso("Cargas de la barra " .. e .. " borradas")
        end
      end
    end,
  })
end

-- ---------------------------------------------------- acciones por herramienta
-- target = { nodo = i | nil, barra = e | nil, a = m, wx, wy }
function H.accion(t, exacto)
  local m = ED.m
  local tool = H.tool
  if tool == "barra" then
    local A = H.barra_a
    if not A then
      if t.nodo then
        H.barra_a = t.nodo
        H.sel = nil
        aviso("Nodo " .. t.nodo .. " es el inicio: haz clic en el nodo B")
      else
        local ok, msg = ED.hacer(function(mm)
          local i, c = ED.agregar_nodo(mm, t.wx, t.wy)
          if not i then return nil, c end
          H.barra_a = i
          return true
        end)
        if not ok then aviso(msg, true) else
          aviso("Nodo A creado: haz clic en el nodo B")
          asegurar_visible(H.barra_a)
        end
      end
      return
    end
    if t.nodo == A then aviso("Selecciona dos nodos distintos", true); return end
    local creada, destino
    local ok, msg = ED.hacer(function(mm)
      local j = t.nodo
      if not j then
        local c
        j, c = ED.agregar_nodo(mm, t.wx, t.wy)
        if not j then return nil, c end
      end
      destino = j
      local e, err = ED.agregar_barra(mm, A, j)
      if not e then return nil, err end
      creada = e
      return true
    end)
    if ok then
      H.sel = nil
      H.barra_a = destino
      aviso("Barra " .. creada .. " creada (" .. #ED.m.nodos .. " nodos). Sigue o ESC")
      asegurar_visible(destino)
    else
      if t.nodo then H.barra_a = t.nodo end
      aviso(msg, true)
    end
    return
  end
  -- demas herramientas
  if tool == "nodo" or (exacto and not t.nodo) then
    if t.nodo then
      H.sel = { t = "nodo", i = t.nodo }
      aviso("Nodo " .. t.nodo .. " seleccionado")
      return
    end
    local idx
    local ok, msg = ED.hacer(function(mm)
      local i, c = ED.agregar_nodo(mm, t.wx, t.wy)
      if not i then return nil, c end
      idx = i
      return true
    end)
    if ok then
      H.sel = { t = "nodo", i = idx }
      aviso("Nodo " .. idx .. " creado en (" .. fmt(t.wx) .. ", " .. fmt(t.wy) .. ")")
      asegurar_visible(idx)
    else
      aviso(msg, true)
    end
    return
  end
  if tool == "sel" then
    if t.nodo then H.sel = { t = "nodo", i = t.nodo }
    elseif t.barra then H.sel = { t = "barra", i = t.barra }
    else H.sel = nil end
    redraw()
    return
  end
  if tool == "apoyo" then
    if t.nodo then H.menu_apoyo(t.nodo)
    else aviso("Haz clic sobre un nodo para asignarle un apoyo", true) end
    return
  end
  if tool == "carga" then
    if t.nodo then H.dialogo_carga_nodo(t.nodo)
    elseif t.barra then H.menu_carga_barra(t.barra, t.a)
    else aviso("Haz clic sobre un nodo o una barra para cargarlos", true) end
    return
  end
end

-- Clic en el lienzo (px,py de pantalla)
local function clic(px, py)
  actualizar_hover(px, py)
  local hv = H.hover
  local t = { nodo = hv.nodo, wx = hv.wx, wy = hv.wy }
  if not t.nodo and H.tool ~= "nodo" then
    local e, a = barra_en(px, py, BARRA_TOL)
    t.barra, t.a = e, a
  end
  H.accion(t, false)
end

-- ------------------------------------------------------------------ arrastre
local function fin_drag(cancelar)
  local d = drag
  drag = nil
  if not d then return end
  if d.tipo == "nodo" and d.snap then
    if cancelar then
      ED.cancelar_snap()
      aviso("Movimiento cancelado")
    else
      local n = ED.m.nodos[d.i]
      local recortadas = ED.ajustar_todas(ED.m)
      ED.cambio()
      if n then
        aviso("Nodo " .. d.i .. " movido a (" .. fmt(n.x) .. ", " .. fmt(n.y) .. ")" ..
          (recortadas > 0 and ". Se ajustaron cargas" or ""))
      end
    end
  end
  redraw()
end

local function drag_mover(px, py)
  local d = drag
  if d.tipo == "pan" then
    V.pan(px - d.lx, py - d.ly)
    d.lx, d.ly = px, py
  else
    local wx, wy = V.snap(V.a_mundo(px, py))
    local n = ED.m.nodos[d.i]
    if n and (n.x ~= wx or n.y ~= wy) then
      if not d.snap then ED.snap(); d.snap = true end
      local ok, msg = ED.mover_nodo(ED.m, d.i, wx, wy)
      if ok then ED.cambio() else aviso(msg, true) end
    end
  end
  redraw()
end

-- ----------------------------------------------------------- eventos raton
local function boton_en(x, y)
  for i = 1, #H.botones do
    local b = H.botones[i]
    if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then return b end
  end
  return nil
end

local function accion_boton(id)
  if id == "resolver" then H.resolver()
  elseif id == "undo" then H.deshacer()
  elseif id == "redo" then H.rehacer()
  elseif id == "fit" then H.encuadrar()
  elseif id == "zmas" then H.zoom(1.4)
  elseif id == "zmenos" then H.zoom(1 / 1.4)
  else H.set_tool(id) end
end

function H.mouseDown(x, y)
  H.msg = nil
  ignora_up = false
  if y < V.rect.y then
    local b = boton_en(x, y)
    ptr = nil
    if b then accion_boton(b.id) end
    redraw()
    return
  end
  if y >= V.rect.y + V.rect.h then return end
  if drag and drag.sticky then
    fin_drag(false)
    ignora_up = true
    return
  end
  ptr = { x0 = x, y0 = y, moved = false, nodo = nil }
  if H.tool == "sel" then ptr.nodo = nodo_en(x, y, NODO_TOL) end
  actualizar_hover(x, y)
  redraw()
end

function H.mouseMove(x, y)
  actualizar_hover(x, y)
  if drag then
    drag_mover(x, y)
    return
  end
  if ptr then
    if not ptr.moved and abs(x - ptr.x0) + abs(y - ptr.y0) > 4 then
      ptr.moved = true
      if ptr.nodo then
        drag = { tipo = "nodo", i = ptr.nodo, lx = ptr.x0, ly = ptr.y0 }
        H.sel = { t = "nodo", i = ptr.nodo }
      else
        drag = { tipo = "pan", lx = ptr.x0, ly = ptr.y0 }
      end
    end
    if drag then drag_mover(x, y) end
  end
  redraw()
end

function H.mouseUp(x, y)
  if ignora_up then ignora_up = false; ptr = nil; return end
  local p = ptr
  ptr = nil
  if drag and not drag.sticky then
    fin_drag(false)
    return
  end
  if p and not p.moved then
    if y >= V.rect.y and y < V.rect.y + V.rect.h then clic(x, y) end
  end
  redraw()
end

-- Mantener clic: arrastre "pegajoso" hasta el siguiente clic
function H.grabDown()
  if drag then return end
  local hv = H.hover
  if not (hv.px and hv.en_lienzo) then return end
  ptr = nil
  local ni = nodo_en(hv.px, hv.py, NODO_TOL)
  if ni then
    drag = { tipo = "nodo", i = ni, lx = hv.px, ly = hv.py, sticky = true }
    H.sel = { t = "nodo", i = ni }
  else
    drag = { tipo = "pan", lx = hv.px, ly = hv.py, sticky = true }
  end
  H.msg = nil
  redraw()
end

-- Tecla M: mueve el nodo seleccionado con el cursor hasta el siguiente clic
function H.mover_seleccion()
  local s = H.sel
  if not (s and s.t == "nodo" and ED.m.nodos[s.i]) then
    aviso("Primero selecciona un nodo (herramienta S)", true)
    return
  end
  local hv = H.hover
  drag = { tipo = "nodo", i = s.i, lx = hv.px or 0, ly = hv.py or 0, sticky = true }
  H.msg = nil
  redraw()
end

-- ------------------------------------------------------------------ teclado
function H.borrar_seleccion()
  local s = H.sel
  if not s then aviso("Nada seleccionado: usa la herramienta S y haz clic", true); return end
  if s.t == "nodo" then
    local i = s.i
    ED.hacer(function(m) return ED.borrar_nodo(m, i) end)
    H.sel = nil
    H.barra_a = nil
    aviso("Nodo " .. i .. " borrado (U deshace)")
  else
    local e = s.i
    ED.hacer(function(m) return ED.borrar_barra(m, e) end)
    H.sel = nil
    aviso("Barra " .. e .. " borrada (U deshace)")
  end
end

function H.editar()
  local tool, s = H.tool, H.sel
  if tool == "nodo" or tool == "barra" then H.dialogo_coordenadas(); return end
  if not s then aviso("Selecciona un nodo o una barra (clic) para editarlo", true); return end
  if tool == "apoyo" and s.t == "nodo" then H.menu_apoyo(s.i); return end
  if tool == "carga" then
    if s.t == "nodo" then H.dialogo_carga_nodo(s.i) else H.menu_carga_barra(s.i, nil) end
    return
  end
  if s.t == "nodo" then dialogo_nodo(s.i) else dialogo_barra(s.i) end
end

local AYUDA = {
  "HERRAMIENTAS (letra o clic en el icono)",
  "S Seleccionar   N Nodo   B Barra",
  "A Apoyo   C Carga   R Resolver",
  "Barra: clic nodo A, clic nodo B...",
  "  (en vacio crea nodos). ESC termina.",
  "ENTER: coordenadas exactas o editar.",
  "DEL borra lo seleccionado.",
  "U deshacer   Y rehacer   E encuadrar",
  "+ / -  zoom    flechas: mover vista",
  "G rejilla   K snap   P propiedades",
  "M mueve el nodo elegido (clic suelta)",
  "Arrastrar el fondo mueve la vista.",
  "Menu (tecla menu): Archivo, Vista...",
  "Signos: x derecha, y arriba, giro +",
  "antihorario. Fy < 0 = hacia abajo.",
  "Unidades: kN, m; E en GPa, A en cm²,",
  "I en cm4. Supuestos: Euler-Bernoulli,",
  "pequenas deformaciones, 2D lineal.",
}

function H.ayuda()
  D.texto("Ayuda - Estructural 2D", AYUDA)
end

function H.charIn(c)
  H.msg = nil
  local k = c:lower()
  if k == "s" then H.set_tool("sel")
  elseif k == "n" then H.set_tool("nodo")
  elseif k == "b" then H.set_tool("barra")
  elseif k == "a" then H.set_tool("apoyo")
  elseif k == "c" then H.set_tool("carga")
  elseif k == "r" then H.resolver()
  elseif k == "u" then H.deshacer()
  elseif k == "y" then H.rehacer()
  elseif k == "e" then H.encuadrar()
  elseif k == "+" or k == "=" then H.zoom(1.4)
  elseif k == "-" or k == "\226\136\146" or k == "_" then H.zoom(1 / 1.4)
  elseif k == "g" then H.toggle_rejilla()
  elseif k == "k" then H.ciclar_snap()
  elseif k == "x" then H.dialogo_coordenadas()
  elseif k == "p" then H.props_globales()
  elseif k == "h" or k == "?" then H.ayuda()
  elseif k == "m" then H.mover_seleccion()
  end
  redraw()
end

function H.arrow(k)
  H.msg = nil
  local s = H.sel
  if H.tool == "sel" and s and s.t == "nodo" and ED.m.nodos[s.i] and not drag then
    local st = V.snap_valor()
    if not st or st == 0 then st = 0.1 end
    local n = ED.m.nodos[s.i]
    local nx, ny = n.x, n.y
    if k == "left" then nx = nx - st elseif k == "right" then nx = nx + st
    elseif k == "up" then ny = ny + st else ny = ny - st end
    nx, ny = V.limpio(nx), V.limpio(ny)
    local i = s.i
    local ok, msg = ED.hacer(function(m)
      local a, b = ED.mover_nodo(m, i, nx, ny)
      if not a then return nil, b end
      ED.ajustar_todas(m)
      return true
    end)
    if not ok then aviso(msg, true) end
  else
    local d = 24
    if k == "left" then V.pan(d, 0) elseif k == "right" then V.pan(-d, 0)
    elseif k == "up" then V.pan(0, d) else V.pan(0, -d) end
    if H.hover.px then actualizar_hover(H.hover.px, H.hover.py) end
  end
  redraw()
end

function H.enter()
  H.msg = nil
  H.editar()
  redraw()
end

function H.esc()
  H.msg = nil
  if drag then fin_drag(true); return end
  if H.barra_a then
    H.barra_a = nil
    aviso("Cadena de barras terminada")
    return
  end
  if H.sel then H.sel = nil; redraw(); return end
  if H.tool ~= "sel" then H.set_tool("sel") end
  redraw()
end

function H.del()
  H.msg = nil
  H.borrar_seleccion()
end

function H.tab()
  -- Tab: siguiente herramienta
  local orden = { "sel", "nodo", "barra", "apoyo", "carga" }
  for i = 1, #orden do
    if orden[i] == H.tool then H.set_tool(orden[i % #orden + 1]); return end
  end
end

-- ----------------------------------------------------- archivo / ejemplos
function H.nuevo()
  ED.reemplazar(ED.nuevo())
  H.sel, H.barra_a = nil, nil
  V.encuadrar(ED.m)
  H.set_tool("barra")
  aviso("Modelo nuevo (U deshace)")
end

function H.ejemplo(nombre)
  local m, msg = ED.ejemplo(nombre)
  if not m then aviso(msg, true); return end
  ED.reemplazar(m)
  H.sel, H.barra_a = nil, nil
  V.encuadrar(ED.m)
  H.set_tool("sel")
  aviso("Ejemplo: " .. nombre .. " (U deshace)")
end

function H.guardar_como()
  form({
    titulo = "Guardar modelo como...",
    campos = { { id = "n", etq = "Nombre", tipo = "texto", valor = ED.nombre_libre() } },
    aceptar = function(v)
      local ok, msg = ED.guardar_como(v.n)
      if not ok then return msg end
      if document and document.markChanged then document.markChanged() end
      aviso("Modelo '" .. v.n .. "' " .. (msg == "reemplazado" and "reemplazado" or "guardado"))
      return nil
    end,
  })
end

function H.abrir()
  local nombres = ED.nombres()
  if #nombres == 0 then aviso("No hay modelos guardados (Archivo > Guardar como)", true); return end
  D.menu({
    titulo = "Abrir modelo",
    items = nombres,
    elegir = function(k)
      local ok, msg = ED.abrir(nombres[k])
      if not ok then aviso(msg, true); return end
      H.sel, H.barra_a = nil, nil
      V.encuadrar(ED.m)
      aviso("Abierto: " .. nombres[k] .. " (U deshace)")
    end,
  })
end

function H.borrar_guardado()
  local nombres = ED.nombres()
  if #nombres == 0 then aviso("No hay modelos guardados", true); return end
  D.menu({
    titulo = "Borrar modelo guardado",
    items = nombres,
    elegir = function(k)
      local nom = nombres[k]
      D.menu({
        titulo = "Borrar '" .. nom .. "'?",
        items = { "No, conservar", "Si, borrar" },
        elegir = function(j)
          if j == 2 then
            ED.borrar_guardado(nom)
            if document and document.markChanged then document.markChanged() end
            aviso("Modelo '" .. nom .. "' borrado")
          end
        end,
      })
    end,
  })
end

return H
