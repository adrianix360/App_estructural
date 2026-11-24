-- ui/herramientas.lua - Herramientas de modelado, eventos de raton/teclado y dialogos de edicion.
-- Herramientas: sel (Seleccionar/mover), nodo, barra, apoyo, carga. "Resolver" es una accion.
-- Estado publico (lo lee ui.dibujo): H.tool, H.sel, H.barra_a, H.hover, H.msg, H.botones, H.sb_h,
--   H.texto_estado(), H.texto_coord().
--   H.selector (pastillas Marco | Cercha), H.set_modo(tipo), H.alternar_modo().
-- Toda modificacion del modelo pasa por ED.hacer (deshacer) y termina en un redibujado.
local ED = require("ui.modelo_ed")
local V = require("ui.vista")
local D = require("ui.dialogo")
local Res = require("ui.resultados")
local U = require("ui.unidades")

local H = {}

local floor, abs, sqrt, min, max = math.floor, math.abs, math.sqrt, math.min, math.max

H.TB_H = 22
H.sb_h = 16
H.tool = "barra"
H.sel = nil            -- { t = "nodo"|"barra", i = n }
H.barra_a = nil        -- primer nodo de la barra en curso
H.msg = nil            -- { t = texto, err = bool } (se borra con la siguiente accion)
H.ver = 0              -- sube con cada cambio del modelo
H.hover = { px = nil, py = nil, wx = 0, wy = 0, sx = 0, sy = 0, en_lienzo = false, nodo = nil, barra = nil,
                div = false, dx = 0, dy = 0 }
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

-- Barra de herramientas del modo resultados (botones con texto; vista = sub-vista que activan)
local DEFR = {
  { id = "r_reac", vista = "reac", txt = "Reac", w = 30 }, { id = "r_N", vista = "N", txt = "N", w = 20 },
  { id = "r_V", vista = "V", txt = "V", w = 20 }, { id = "r_M", vista = "M", txt = "M", w = 20 },
  { id = "r_def", vista = "def", txt = "Def", w = 26 }, { id = "r_tabla", vista = "tabla", txt = "Tabla", w = 32 },
  { id = "r_ecs", vista = "ecs", txt = "Ecs", w = 26 }, "sep",
  { id = "r_mas", txt = "+", w = 20 }, { id = "r_menos", txt = "-", w = 20 }, "sep",
  { id = "r_volver", txt = "Modelar", w = 44 },
}

local function layout_botones()
  H.botones = {}
  local x = 4
  if Res.modo then
    for i = 1, #DEFR do
      local d = DEFR[i]
      if d == "sep" then x = x + 8
      else
        H.botones[#H.botones + 1] = { id = d.id, vista = d.vista, txt = d.txt, x = x, y = 1, w = d.w, h = H.TB_H - 3 }
        x = x + d.w + 2
      end
    end
    return
  end
  for i = 1, #DEF do
    local d = DEF[i]
    if d == "sep" then x = x + 10
    else
      H.botones[#H.botones + 1] = { id = d.id, herr = d.herr, tecla = d.tecla, x = x, y = 1, w = 25, h = H.TB_H - 3 }
      x = x + 27
    end
  end
end

-- Selector Marco | Cercha: esquina superior izquierda del lienzo (geometria fija, sin medir texto)
H.selector = { x = 3, y = H.TB_H + 2, w = 98, h = 15, xm = 3, wm = 44, xc = 47, wc = 54 }
local function layout_selector()
  local sl = H.selector
  sl.y = V.rect.y + 2
end
local function en_selector(x, y)
  local sl = H.selector
  return x >= sl.x and x < sl.x + sl.w and y >= sl.y and y < sl.y + sl.h
end

function H.resize(w, h)
  WW, HH = w, h
  V.set_rect(0, H.TB_H, w, h - H.TB_H - H.sb_h)
  layout_botones()
  layout_selector()
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
  Res.barra_sel = function()
    local s = H.sel
    if s and s.t == "barra" and ED.m.barras[s.i] then return s.i end
    return nil
  end
  Res.on_modo = function(antes, ahora)
    if antes == nil and ahora ~= nil then
      H.tool_prev = H.tool
      H.tool = "sel"
      H.barra_a = nil
      H.cadena_sucia = false
    elseif antes ~= nil and ahora == nil then
      if H.tool_prev then H.tool = H.tool_prev end
      H.tool_prev = nil
    end
    forma_cursor = nil
    layout_botones()
    H.msg = nil
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

-- Punto de division de la barra e para un clic a `a` m del nodo i: con snap activo se ajusta a un
-- multiplo del paso a lo largo de la barra. Devuelve a2 | nil si queda pegado a un nodo.
local MINSEG = 1e-3
local function punto_div(e, a)
  local m = ED.m
  if not m.barras[e] then return nil end
  local L = ED.longitud(m, e)
  local st = V.snap_valor()
  local a2 = a
  if st and st > 0 then
    local q = floor(a / st + 0.5) * st
    if q >= MINSEG and q <= L - MINSEG then a2 = q end
  end
  if a2 < MINSEG or a2 > L - MINSEG then return nil end
  return a2
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
    hv.div = false
    local ba
    if not hv.nodo then hv.barra, ba = barra_en(x, y, BARRA_TOL) end
    if hv.barra and not drag and (H.tool == "nodo" or H.tool == "barra") then
      local a2 = punto_div(hv.barra, ba)
      if a2 then
        local b = ED.m.barras[hv.barra]
        local na, nb = ED.m.nodos[b.ni], ED.m.nodos[b.nj]
        local f = a2 / ED.longitud(ED.m, hv.barra)
        hv.dx, hv.dy = V.a_pantalla(na.x + (nb.x - na.x) * f, na.y + (nb.y - na.y) * f)
        hv.div = true
      end
    end
    if drag then poner_cursor("hand closed")
    elseif H.tool == "nodo" or H.tool == "barra" then poner_cursor("crosshair")
    elseif hv.nodo or hv.barra then poner_cursor("pointer")
    else poner_cursor("default") end
  else
    hv.nodo, hv.barra, hv.div = nil, nil, false
    poner_cursor("default")
  end
end

-- ------------------------------------------------------- texto de la barra
local est_key = {}
local est_txt = ""

local function nombre_modo()
  return (ED.props.tipo == "cercha") and "Cercha" or "Marco"
end
H.nombre_modo = nombre_modo

function H.texto_estado()
  if Res.modo then return Res.estado() or "" end
  local t, s, a, v, tp = H.tool, H.sel, H.barra_a, H.ver, ED.props.tipo
  if est_key.t == t and est_key.s == s and est_key.si == (s and s.i) and est_key.a == a and est_key.v == v
     and est_key.d == (drag ~= nil) and est_key.tp == tp then
    return est_txt
  end
  est_key.t, est_key.s, est_key.si, est_key.a, est_key.v, est_key.d, est_key.tp =
    t, s, s and s.i, a, v, (drag ~= nil), tp
  local m = ED.m
  local r
  if drag then
    r = "Clic para soltar (ESC cancela)"
  elseif t == "sel" then
    if s and s.t == "nodo" and m.nodos[s.i] then
      r = "Nodo " .. s.i .. ": ENTER edita, DEL borra"
    elseif s and s.t == "barra" and m.barras[s.i] then
      local b = m.barras[s.i]
      r = "Barra " .. s.i .. " (" .. b.ni .. "-" .. b.nj .. ") L=" .. fmt(ED.longitud(m, s.i)) .. " m"
      if #r <= 22 then r = r .. ": ENTER edita" end
    else
      r = "Seleccionar: clic o arrastra"
    end
  elseif t == "nodo" then
    r = "Nodo: clic crea, ENTER: x,y"
  elseif t == "barra" then
    if a then r = nombre_modo() .. ": clic nodo B (ESC termina)"
    else r = nombre_modo() .. ": clic nodo A (K cambia)" end
  elseif t == "apoyo" then
    r = "Apoyo: clic en un nodo"
  else
    r = "Carga: clic en nodo o barra"
  end
  est_txt = r
  return r
end

-- Parte derecha de la barra de estado: coordenadas del cursor y clasificacion (o recuento y snap)
local ct = { en = nil, wx = nil, wy = nil, nn = nil, nb = nil, si = nil, cv = nil, coord = "", cls = "" }
function H.texto_coord_partes()
  local hv, m = H.hover, ED.m
  Res.clasif()
  local cls = Res.clasif_texto()
  if Res.modo then
    if Res.cur then return "", "" end
    return "", cls
  end
  local nn, nb = #m.nodos, #m.barras
  local en = hv.en_lienzo
  if ct.en == en and ct.wx == hv.wx and ct.wy == hv.wy and ct.nn == nn and ct.nb == nb and ct.si == V.snap_i
     and ct.cv == Res.cl_ver then
    return ct.coord, ct.cls
  end
  ct.en, ct.wx, ct.wy, ct.nn, ct.nb, ct.si, ct.cv = en, hv.wx, hv.wy, nn, nb, V.snap_i, Res.cl_ver
  local coord = en and ("x=" .. fmt(hv.wx) .. " y=" .. fmt(hv.wy)) or ""
  if cls == "" then
    local st = V.snap_valor()
    local sn = (st and st > 0) and ("snap " .. fmt(st)) or "libre"
    cls = nn .. "N " .. nb .. "B | " .. sn
  end
  ct.coord, ct.cls = coord, cls
  return coord, cls
end

function H.texto_coord()
  local c, k = H.texto_coord_partes()
  if c ~= "" and k ~= "" then return c .. " | " .. k end
  return (c ~= "") and c or k
end

-- ---------------------------------------------------------- acciones basicas
-- Fin de la cadena de barras (ESC o cambio de herramienta): con vista automatica se encuadra el modelo
function H.fin_cadena()
  H.barra_a = nil
  if H.cadena_sucia then
    H.cadena_sucia = false
    if V.auto and #ED.m.nodos > 0 and not Res.modo then V.encuadrar(ED.m) end
  end
end

function H.set_tool(t)
  if Res.modo then H.salir_resultados() end
  if H.tool == "barra" and t ~= "barra" then H.fin_cadena() end
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
  Res.camara_cambio()
  redraw()
end

function H.zoom(f)
  local hv = H.hover
  if hv.en_lienzo then V.zoom(f, hv.px, hv.py) else V.zoom(f) end
  if hv.px then actualizar_hover(hv.px, hv.py) end
  redraw()
end

-- ------------------------------------------------- modo Marco / Cercha (v1.1)
-- El modo es ED.props.tipo: cada barra nueva nace con ese tipo.
H.pend = nil       -- { e, tipo, msg }: ENTER aplica el nuevo tipo a la barra que estaba seleccionada

function H.set_modo(tipo)
  tipo = (tipo == "cercha") and "cercha" or "portico"
  local cambio = ED.props.tipo ~= tipo
  ED.set_tipo(tipo)
  if cambio and document and document.markChanged then document.markChanged() end
  local nom = nombre_modo()
  local s = H.sel
  H.pend = nil
  if cambio and not Res.modo and s and s.t == "barra" and ED.m.barras[s.i] and ED.m.barras[s.i].tipo ~= tipo then
    aviso("Modo " .. nom .. ". ENTER: aplicar también a la barra " .. s.i)
    H.pend = { e = s.i, tipo = tipo, msg = H.msg }
  else
    aviso("Modo " .. nom .. ": las barras nuevas serán " .. (tipo == "cercha" and "cercha" or "de marco"))
  end
  redraw()
end

function H.alternar_modo()
  H.set_modo(ED.props.tipo == "cercha" and "portico" or "cercha")
end

-- Aplica el tipo a todas las barras (un solo paso de deshacer)
function H.convertir_todo(tipo)
  tipo = (tipo == "cercha") and "cercha" or "portico"
  local nom = (tipo == "cercha") and "cercha" or "marco"
  if #ED.m.barras == 0 then aviso("No hay barras que convertir", true); return end
  local n = 0
  local ok = ED.hacer(function(m)
    n = ED.convertir_todo(m, tipo)
    if n == 0 then return nil, "Todas las barras ya son " .. nom end
    return true
  end)
  ED.set_tipo(tipo)
  if ok then aviso(n .. ((n == 1) and " barra convertida a " or " barras convertidas a ") .. nom .. " (U deshace)")
  else aviso("Todas las barras ya son " .. nom) end
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

-- Menu Ajustes: snap, unidades y deformada
function H.menu_snap()
  local pasos = { 0.1, 0.25, 0.5, 1, 0 }
  local items = { "0.1 m", "0.25 m", "0.5 m", "1 m", "Sin snap (libre)" }
  D.menu({
    titulo = "Snap de la rejilla",
    items = items,
    sel = V.snap_i,
    ancho = 200,
    elegir = function(k) H.set_snap(pasos[k]) end,
  })
end

function H.set_unidades(nombre)
  if not U.set(nombre) then return end
  Res.unidades_cambiaron()
  if document and document.markChanged then document.markChanged() end
  aviso("Unidades: " .. nombre .. " (fuerza " .. U.etiqueta("fuerza") .. ", E en " .. U.etiqueta("E") .. ")")
end

function H.menu_unidades()
  D.menu({
    titulo = "Unidades de presentacion",
    items = { U.nombres[1], U.nombres[2], U.nombres[3] },
    sel = U.indice(),
    ancho = 230,
    elegir = function(k) H.set_unidades(U.sistemas[k]) end,
  })
end

function H.ciclar_unidades()
  H.set_unidades(U.sistemas[U.indice() % #U.sistemas + 1])
end

-- Deformada real <-> ampliada (con resultados abre la vista de deformada)
function H.toggle_def()
  if Res.modo then
    if Res.modo ~= "def" then Res.set_vista("def") else Res.toggle_def() end
    aviso(Res.def_real and "Deformada real" or "Deformada ampliada")
  else
    Res.toggle_def()
    aviso(Res.def_real and "Deformada: real (al resolver)" or "Deformada: ampliada (al resolver)")
  end
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
  -- con una cadena de barras en curso nunca se mueve la vista entre clics (se encuadra al terminar)
  if H.tool == "barra" and H.barra_a then return end
  local R = V.rect
  local sx, sy = V.a_pantalla(n.x, n.y)
  if sx < R.x + 14 or sx > R.x + R.w - 14 or sy < R.y + 14 or sy > R.y + R.h - 14 then
    V.encuadrar(ED.m)
  end
end

-- --------------------------------------------------------------- resolver
-- Sugerencia (una sola vez por modelo): marco dibujado con cargas solo en nudos que funciona como cercha
local function sugerir_cercha()
  local m = ED.m
  if H.sug_hecho or not ED.parece_cercha(m) then return end
  H.sug_hecho = true
  D.menu({
    titulo = "Cercha detectada",
    msg = "Parece una cercha (cargas solo en nudos). ¿Convertir las " .. #m.barras .. " barras a cercha?",
    items = { "Convertir a cercha", "Mantener marco" },
    ancho = 270,
    elegir = function(k)
      if k == 1 then H.convertir_todo("cercha") end
    end,
  })
end

function H.resolver()
  if Res.modo then Res.tecla("r"); redraw(); return end
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
  if ok2 then
    -- al mostrar resultados: encuadre si la vista es automatica, hay nodos fuera o el modelo se ve diminuto
    if V.conviene_encuadrar(m) then V.encuadrar(m); Res.camara_cambio() end
    aviso(msg or "Resuelto")
    sugerir_cercha()
  else
    aviso(msg or "No se pudo resolver", true)
  end
end

-- Vuelve al modo modelado (y a la herramienta que habia)
function H.salir_resultados()
  if not Res.modo then return end
  Res.limpiar()
  redraw()
end

function H.leyenda()
  Res.leyenda()
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

-- Etiquetas de campos con las unidades del sistema vigente: ef("Fx", "fuerza", ", + derecha")
local function ef(nombre, cant, extra)
  return nombre .. " (" .. U.etiqueta(cant) .. (extra or "") .. ")"
end
local function vi(cant, v) return U.de_interna(cant, v) end   -- interna -> pantalla
local function ai(cant, v) return U.a_interna(cant, v) end    -- pantalla -> interna

local function dialogo_nodo(i)
  local n = ED.m.nodos[i]
  if not n then return end
  local c = n.carga or { fx = 0, fy = 0, mz = 0 }
  form({
    titulo = "Nodo " .. i,
    campos = {
      { id = "x", etq = "x (m)", valor = n.x }, { id = "y", etq = "y (m)", valor = n.y },
      { id = "fx", etq = ef("Fx", "fuerza", ", + derecha"), valor = vi("fuerza", c.fx) },
      { id = "fy", etq = ef("Fy", "fuerza", ", + arriba"), valor = vi("fuerza", c.fy) },
      { id = "mz", etq = ef("Mz", "momento", ", + antih."), valor = vi("momento", c.mz) },
    },
    aceptar = function(v)
      local ok, msg = ED.hacer(function(m)
        local a, b = ED.mover_nodo(m, i, v.x, v.y)
        if not a then return nil, b end
        local c2, d2 = ED.set_carga_nodo(m, i, ai("fuerza", v.fx), ai("fuerza", v.fy), ai("momento", v.mz))
        if not c2 then return nil, d2 end
        ED.ajustar_todas(m)
        return true
      end)
      if not ok then return msg end
      asegurar_visible(i)
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
      { id = "E", etq = ef("E", "E"), valor = vi("E", b.E) },
      { id = "A", etq = ef("A", "A"), valor = vi("A", b.A) },
      { id = "I", etq = ef("I", "I"), valor = vi("I", b.I) },
      { id = "tipo", etq = "Tipo", tipo = "opcion", opciones = { "Portico", "Cercha" }, valor = (b.tipo == "cercha") and 2 or 1 },
      { id = "ri", etq = "Rotula en nodo i", tipo = "opcion", opciones = { "No", "Si" }, valor = b.rot_i and 2 or 1 },
      { id = "rj", etq = "Rotula en nodo j", tipo = "opcion", opciones = { "No", "Si" }, valor = b.rot_j and 2 or 1 },
      { id = "cg", etq = "Cargas (" .. nc .. ")", tipo = "opcion",
        opciones = { "Conservar", "Borrar todas", "Editar una a una" }, valor = 1 },
    },
    aceptar = function(v)
      if v.E <= 0 then return "E debe ser mayor que 0" end
      if v.A <= 0 then return "A debe ser mayor que 0" end
      if v.I <= 0 then return "I debe ser mayor que 0" end
      local ok, msg = ED.hacer(function(mm)
        local bb = mm.barras[e]
        if not bb then return nil, "La barra ya no existe" end
        bb.E, bb.A, bb.I = ai("E", v.E), ai("A", v.A), ai("I", v.I)
        bb.tipo = (v.tipo == 2) and "cercha" or "portico"
        bb.rot_i, bb.rot_j = (v.ri == 2), (v.rj == 2)
        if v.cg == 2 then bb.cargas = {} end
        return true
      end)
      if not ok then return msg end
      aviso("Barra " .. e .. " actualizada")
      if v.cg == 3 then H.menu_carga_barra(e, nil) end
      return nil
    end,
  })
end

function H.props_globales()
  local p = ED.props
  form({
    titulo = "Propiedades globales (barras nuevas)",
    campos = {
      { id = "E", etq = ef("E", "E"), valor = vi("E", p.E) },
      { id = "A", etq = ef("A", "A"), valor = vi("A", p.A) },
      { id = "I", etq = ef("I", "I"), valor = vi("I", p.I) },
      { id = "tipo", etq = "Tipo de barra nueva", tipo = "opcion", opciones = { "Portico", "Cercha" }, valor = (p.tipo == "cercha") and 2 or 1 },
      { id = "todas", etq = "Aplicar a", tipo = "opcion", opciones = { "Solo barras nuevas", "Todas las barras" }, valor = 1 },
    },
    aceptar = function(v)
      if v.E <= 0 or v.A <= 0 or v.I <= 0 then return "E, A e I deben ser mayores que 0" end
      p.E, p.A, p.I = ai("E", v.E), ai("A", v.A), ai("I", v.I)
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
      { id = "kx", etq = ef("kx", "rig"), valor = vi("rig", ap.kx or 0), min = 0 },
      { id = "ky", etq = ef("ky", "rig"), valor = vi("rig", ap.ky or 0), min = 0 },
      { id = "kr", etq = ef("kr", "rigrot"), valor = vi("rigrot", ap.kr or 0), min = 0 },
    },
    aceptar = function(v)
      local ok, msg = ED.hacer(function(m)
        return ED.set_resorte(m, i, ai("rig", v.kx), ai("rig", v.ky), ai("rigrot", v.kr))
      end)
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
      { id = "dx", etq = ef("dx", "desp", ", + derecha"), valor = vi("desp", ap.dx or 0) },
      { id = "dy", etq = ef("dy", "desp", ", + arriba"), valor = vi("desp", ap.dy or 0) },
      { id = "dr", etq = ef("giro", "giro", ", + antih."), valor = vi("giro", ap.drz or 0) },
    },
    aceptar = function(v)
      local ok, msg = ED.hacer(function(m)
        return ED.set_asentamiento(m, i, ai("desp", v.dx), ai("desp", v.dy), ai("giro", v.dr))
      end)
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
local DIR_SIG = { -1, 1, 1, -1, 1, 1 }       -- signo de la carga interna respecto de la magnitud tecleada
local DIR_DIR = { "GY", "GY", "GX", "GX", "L", "LX" }
local DIR_TXT = { "abajo", "arriba", "der.", "izq.", "perp.", "axial" }

local function dir_desde_opcion(k, mag)
  return DIR_DIR[k], DIR_SIG[k] * mag
end

-- (indice de opcion, magnitud) a partir de una carga existente (v = p, w1 o w2 con signo)
local function opcion_de(dir, v)
  if dir == "GY" then return (v < 0) and 1 or 2, abs(v) end
  if dir == "GX" then return (v > 0) and 3 or 4, abs(v) end
  if dir == "L" then return 5, v end
  return 6, v
end

-- Descripcion corta de una carga de barra (lista de cargas), en las unidades vigentes
local function nf(cant, v, sig) return U.num(U.de_interna(cant, v), sig or 4) end
function H.describir_carga(c)
  if c.t == "P" then
    local k, mag = opcion_de(c.dir, c.p)
    return "P " .. nf("fuerza", mag) .. " " .. U.etiqueta("fuerza") .. " " .. DIR_TXT[k] .. " a=" .. nf("long", c.a) .. " m"
  elseif c.t == "M" then
    return "M " .. nf("momento", abs(c.m)) .. " " .. U.etiqueta("momento") .. (c.m > 0 and " antih." or " horario")
      .. " a=" .. nf("long", c.a) .. " m"
  elseif c.t == "w" then
    local ref = (c.w1 ~= 0) and c.w1 or c.w2
    local k = opcion_de(c.dir, ref)
    local sg = DIR_SIG[k]
    local v1, v2 = sg * c.w1, sg * c.w2
    local val
    if c.w1 == c.w2 then val = nf("dist", v1) else val = nf("dist", v1) .. "->" .. nf("dist", v2) end
    return "w " .. val .. " " .. U.etiqueta("dist") .. " " .. nf("long", c.a) .. "-" .. nf("long", c.b) .. " m " .. DIR_TXT[k]
  elseif c.t == "T" then
    return "T du=" .. nf("temp", c.du) .. " dg=" .. nf("temp", c.dg) .. " " .. U.etiqueta("temp")
  end
  return "?"
end

local function describir_nodal(c)
  local p = {}
  if c.fx ~= 0 then p[#p + 1] = "Fx " .. nf("fuerza", c.fx) end
  if c.fy ~= 0 then p[#p + 1] = "Fy " .. nf("fuerza", c.fy) end
  local t = table.concat(p, ", ")
  if t ~= "" then t = t .. " " .. U.etiqueta("fuerza") end
  if c.mz ~= 0 then t = t .. ((t ~= "") and ", " or "") .. "Mz " .. nf("momento", c.mz) .. " " .. U.etiqueta("momento") end
  return t
end

local function form_carga_nodo(i)
  local n = ED.m.nodos[i]
  if not n then return end
  H.sel = { t = "nodo", i = i }
  local c = n.carga or { fx = 0, fy = 0, mz = 0 }
  form({
    titulo = "Carga en el nodo " .. i,
    campos = {
      { id = "fx", etq = ef("Fx", "fuerza", ", + derecha"), valor = vi("fuerza", c.fx) },
      { id = "fy", etq = ef("Fy", "fuerza", ", + arriba"), valor = vi("fuerza", c.fy) },
      { id = "mz", etq = ef("Mz", "momento", ", + antih."), valor = vi("momento", c.mz) },
    },
    aceptar = function(v)
      local ok, msg = ED.hacer(function(m)
        return ED.set_carga_nodo(m, i, ai("fuerza", v.fx), ai("fuerza", v.fy), ai("momento", v.mz))
      end)
      if not ok then return msg end
      if v.fx == 0 and v.fy == 0 and v.mz == 0 then aviso("Nodo " .. i .. ": sin carga")
      else aviso("Nodo " .. i .. ": carga aplicada") end
      return nil
    end,
  })
end

-- Sin carga: formulario directo. Con carga: Editar / Borrar
function H.dialogo_carga_nodo(i)
  local n = ED.m.nodos[i]
  if not n then return end
  H.sel = { t = "nodo", i = i }
  if not n.carga then form_carga_nodo(i); return end
  D.menu({
    titulo = "Nodo " .. i .. ": " .. describir_nodal(n.carga),
    items = { "Editar (Fx, Fy, Mz)...", "Borrar la carga del nodo" },
    ancho = 290,
    elegir = function(k)
      if k == 1 then form_carga_nodo(i)
      else
        ED.hacer(function(m) return ED.set_carga_nodo(m, i, 0, 0, 0) end)
        aviso("Nodo " .. i .. ": carga borrada (U deshace)")
      end
    end,
  })
end

-- o = { a = posicion sugerida (clic), k = indice de la carga que se edita, c = esa carga }
local function dialogo_carga_barra(e, tipo, o)
  o = o or {}
  local m = ED.m
  local b = m.barras[e]
  if not b then return end
  local L = ED.longitud(m, e)
  local Ls = fmt(L)
  local c0 = o.c
  local pos = o.a or (L / 2)
  local st = V.snap_valor()
  if not c0 then
    if st and st > 0 then pos = floor(pos / st + 0.5) * st else pos = floor(pos * 100 + 0.5) / 100 end
  end
  if pos < 0 then pos = 0 elseif pos > L then pos = L end
  local editar = o.k ~= nil
  local titulo = "Barra " .. e .. " (L=" .. Ls .. " m): "
  local function terminar(c, texto)
    local ok, msg = ED.hacer(function(mm)
      if editar then return ED.reemplazar_carga_barra(mm, e, o.k, c) end
      return ED.agregar_carga_barra(mm, e, c)
    end)
    if not ok then return msg end
    aviso(editar and ("Carga " .. o.k .. " de la barra " .. e .. " modificada") or texto)
    return nil
  end
  local mag0 = U.defecto("fuerza")
  if tipo == "P" then
    local opt, mag = 1, mag0
    if c0 then opt, mag = opcion_de(c0.dir, c0.p); mag = vi("fuerza", mag) end
    form({
      titulo = titulo .. (editar and "editar puntual" or "carga puntual"),
      campos = {
        { id = "a", etq = "a (m, desde nodo " .. b.ni .. ")", valor = c0 and c0.a or pos },
        { id = "p", etq = ef("Valor P", "fuerza"), valor = mag },
        { id = "d", etq = "Direccion", tipo = "opcion", opciones = DIR_OPC, valor = opt },
      },
      aceptar = function(v)
        local dir, val = dir_desde_opcion(v.d, ai("fuerza", v.p))
        return terminar({ t = "P", a = v.a, p = val, dir = dir }, "Carga puntual agregada a la barra " .. e)
      end,
    })
  elseif tipo == "w" then
    local opt, mag = 1, mag0
    if c0 then opt, mag = opcion_de(c0.dir, (c0.w1 ~= 0) and c0.w1 or c0.w2); mag = vi("dist", mag) end
    form({
      titulo = titulo .. (editar and "editar distribuida" or "distribuida"),
      campos = {
        { id = "a", etq = "Desde a (m)", valor = c0 and c0.a or 0 },
        { id = "b", etq = "Hasta b (m)", valor = c0 and c0.b or L },
        { id = "w", etq = ef("Valor w", "dist"), valor = mag },
        { id = "d", etq = "Direccion", tipo = "opcion", opciones = DIR_OPC, valor = opt },
      },
      aceptar = function(v)
        local dir, val = dir_desde_opcion(v.d, ai("dist", v.w))
        return terminar({ t = "w", a = v.a, b = v.b, w1 = val, w2 = val, dir = dir },
          "Carga distribuida agregada a la barra " .. e)
      end,
    })
  elseif tipo == "trap" then
    local opt, m1, m2 = 1, 0, mag0
    if c0 then
      opt = opcion_de(c0.dir, (c0.w1 ~= 0) and c0.w1 or c0.w2)
      m1, m2 = vi("dist", DIR_SIG[opt] * c0.w1), vi("dist", DIR_SIG[opt] * c0.w2)
    end
    form({
      titulo = titulo .. (editar and "editar trapezoidal" or "trapezoidal"),
      campos = {
        { id = "a", etq = "Desde a (m)", valor = c0 and c0.a or 0 },
        { id = "b", etq = "Hasta b (m)", valor = c0 and c0.b or L },
        { id = "w1", etq = ef("w1 en a", "dist"), valor = m1 },
        { id = "w2", etq = ef("w2 en b", "dist"), valor = m2 },
        { id = "d", etq = "Direccion", tipo = "opcion", opciones = DIR_OPC, valor = opt },
      },
      aceptar = function(v)
        local dir, w1 = dir_desde_opcion(v.d, ai("dist", v.w1))
        local _, w2 = dir_desde_opcion(v.d, ai("dist", v.w2))
        return terminar({ t = "w", a = v.a, b = v.b, w1 = w1, w2 = w2, dir = dir },
          "Carga trapezoidal agregada a la barra " .. e)
      end,
    })
  elseif tipo == "T" then
    form({
      titulo = titulo .. (editar and "editar temperatura" or "temperatura"),
      campos = {
        { id = "du", etq = ef("du uniforme", "temp"), valor = c0 and vi("temp", c0.du) or 20 },
        { id = "dg", etq = ef("dg inf-sup", "temp"), valor = c0 and vi("temp", c0.dg) or 0 },
        { id = "al", etq = ef("alfa", "alfa"), valor = vi("alfa", c0 and c0.alfa or 1.2e-5) },
        { id = "h", etq = ef("h canto", "canto"), valor = vi("canto", c0 and c0.h or 0.3) },
      },
      aceptar = function(v)
        if v.al <= 0 then return "alfa debe ser mayor que 0" end
        if v.dg ~= 0 and v.h <= 0 then return "Con gradiente (dg) el canto h debe ser mayor que 0" end
        local c = { t = "T", du = ai("temp", v.du), dg = ai("temp", v.dg), alfa = ai("alfa", v.al) }
        if v.h > 0 then c.h = ai("canto", v.h) end
        return terminar(c, "Carga termica agregada a la barra " .. e)
      end,
    })
  else
    form({
      titulo = titulo .. (editar and "editar momento" or "momento"),
      campos = {
        { id = "a", etq = "a (m, desde nodo " .. b.ni .. ")", valor = c0 and c0.a or pos },
        { id = "m", etq = ef("M", "momento", ", + antih."), valor = c0 and vi("momento", c0.m) or mag0 },
      },
      aceptar = function(v)
        return terminar({ t = "M", a = v.a, m = ai("momento", v.m) }, "Momento agregado a la barra " .. e)
      end,
    })
  end
end

local function editar_carga(e, k)
  local c = ED.m.barras[e] and ED.m.barras[e].cargas[k]
  if not c then return end
  local tipo = c.t
  if tipo == "w" and c.w1 ~= c.w2 then tipo = "trap" end
  dialogo_carga_barra(e, tipo, { k = k, c = c })
end

-- Elegir el tipo de carga nueva
local function menu_tipos(e, a_clic)
  local b = ED.m.barras[e]
  if not b then return end
  D.menu({
    titulo = "Carga en barra " .. e .. ": nueva",
    items = { "Puntual", "Distribuida uniforme", "Distribuida trapezoidal/triangular", "Momento puntual",
              "Temperatura (du, dg)" },
    sel = 2,
    ancho = 270,
    elegir = function(k)
      if k == 1 then dialogo_carga_barra(e, "P", { a = a_clic })
      elseif k == 2 then dialogo_carga_barra(e, "w")
      elseif k == 3 then dialogo_carga_barra(e, "trap")
      elseif k == 4 then dialogo_carga_barra(e, "M", { a = a_clic })
      else dialogo_carga_barra(e, "T") end
    end,
  })
end

-- Una carga: Editar / Borrar / Volver a la lista
local function menu_una_carga(e, k)
  local c = ED.m.barras[e] and ED.m.barras[e].cargas[k]
  if not c then return end
  D.menu({
    titulo = H.describir_carga(c),
    items = { "Editar...", "Borrar esta carga", "Volver a la lista" },
    ancho = 290,
    elegir = function(j)
      if j == 1 then editar_carga(e, k)
      elseif j == 2 then
        ED.hacer(function(m) return ED.borrar_carga_barra(m, e, k) end)
        aviso("Carga " .. k .. " de la barra " .. e .. " borrada (U deshace)")
        if #ED.m.barras[e].cargas > 0 then H.menu_carga_barra(e) end
      else H.menu_carga_barra(e) end
    end,
  })
end

-- Sin cargas: elige el tipo. Con cargas: lista (Agregar, cada carga -> Editar/Borrar, Borrar todas)
function H.menu_carga_barra(e, a_clic)
  local b = ED.m.barras[e]
  if not b then return end
  H.sel = { t = "barra", i = e }
  local nc = #b.cargas
  if nc == 0 then menu_tipos(e, a_clic); return end
  local items = { "+ Agregar carga..." }
  for k = 1, nc do items[#items + 1] = H.describir_carga(b.cargas[k]) end
  items[#items + 1] = "Borrar todas las cargas"
  D.menu({
    titulo = "Cargas de la barra " .. e .. " (" .. nc .. ")",
    items = items,
    sel = 1,
    ancho = 296,
    elegir = function(k)
      if k == 1 then menu_tipos(e, a_clic)
      elseif k == #items then
        ED.hacer(function(m) m.barras[e].cargas = {}; return true end)
        aviso("Cargas de la barra " .. e .. " borradas (U deshace)")
      else menu_una_carga(e, k - 1) end
    end,
  })
end

-- ---------------------------------------------------- acciones por herramienta
-- target = { nodo = i | nil, barra = e | nil, a = m, wx, wy }
-- Divide la barra t.barra en el punto del clic y devuelve el indice del nodo nuevo (o nil)
local function dividir_en_clic(t)
  local a2 = punto_div(t.barra, t.a or 0)
  if not a2 then aviso("Demasiado cerca de un nodo: haz clic en el nodo", true); return nil end
  local e, idx, e2, tipo0 = t.barra, nil, nil, ED.m.barras[t.barra].tipo
  local ok, msg = ED.hacer(function(mm)
    local i, e2n = ED.dividir_barra(mm, e, a2)
    if not i then return nil, e2n end
    idx, e2 = i, e2n
    return true
  end)
  if not ok then aviso(msg, true); return nil end
  H.sel = { t = "nodo", i = idx }
  local nuevo_tipo = ED.m.barras[e] and ED.m.barras[e].tipo
  aviso("Nodo " .. idx .. " divide la barra " .. e .. " en " .. fmt(a2) .. " m"
    .. ((tipo0 == "cercha" and nuevo_tipo ~= "cercha") and " (articuladas)" or "") .. ". U deshace")
  return idx
end

function H.accion(t, exacto)
  local m = ED.m
  local tool = H.tool
  -- clic en el interior de una barra con Nodo o Barra: nodo nuevo que la divide
  if (tool == "nodo" or tool == "barra") and not t.nodo and t.barra and not exacto then
    local b = m.barras[t.barra]
    if tool == "barra" and H.barra_a and b and (b.ni == H.barra_a or b.nj == H.barra_a) then
      aviso("Esa barra ya parte del nodo A: haz clic en otro lugar", true)
      return
    end
    local idx = dividir_en_clic(t)
    if not idx then return end
    asegurar_visible(idx)
    if tool == "nodo" then return end
    t = { nodo = idx, wx = ED.m.nodos[idx].x, wy = ED.m.nodos[idx].y }
    m = ED.m
  end
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
      H.cadena_sucia = true
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
  if Res.modo and Res.clic_selector(px, py) then redraw(); return end
  local t = { nodo = hv.nodo, wx = hv.wx, wy = hv.wy }
  if not t.nodo then
    local e, a = barra_en(px, py, BARRA_TOL)
    t.barra, t.a = e, a
  end
  H.accion(t, false)
  if Res.modo then Res.clic(px, py) end
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
        asegurar_visible(d.i)
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
  if id == "r_volver" then H.salir_resultados()
  elseif id == "r_mas" then if not Res.tecla("+") then H.zoom(1.4) end
  elseif id == "r_menos" then if not Res.tecla("-") then H.zoom(1 / 1.4) end
  elseif id == "r_def" and Res.modo == "def" then Res.toggle_def()
  elseif id:sub(1, 2) == "r_" then Res.set_vista(id:sub(3))
  elseif id == "resolver" then H.resolver()
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
  if not Res.modo and en_selector(x, y) then
    -- pastillas Marco | Cercha: un toque fija el modo
    ptr = nil
    ignora_up = true
    local sl = H.selector
    H.set_modo((x >= sl.xc) and "cercha" or "portico")
    return
  end
  ptr = { x0 = x, y0 = y, moved = false, nodo = nil }
  if H.tool == "sel" then ptr.nodo = nodo_en(x, y, NODO_TOL) end
  actualizar_hover(x, y)
  redraw()
end

function H.mouseMove(x, y)
  actualizar_hover(x, y)
  if Res.modo and not drag and not ptr then Res.mouse(x, y) end
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
  "MARCO | CERCHA: pastillas arriba a la",
  "  izquierda del lienzo (clic), o tecla K,",
  "  o B estando en Barra. Cada barra nueva",
  "  nace con ese tipo. Archivo > Nuevo lo",
  "  pregunta. Ajustes: convertir todo.",
  "HERRAMIENTAS (letra o clic en el icono)",
  "S Seleccionar   N Nodo   B Barra",
  "A Apoyo   C Carga   R Resolver",
  "Barra: clic nodo A, clic nodo B...",
  "  (en vacio crea nodos). ESC termina.",
  "DIVIDIR: con Nodo o Barra, un clic en",
  "  el interior de una barra crea un nodo",
  "  y la parte en dos (U deshace).",
  "ENTER: coordenadas exactas o editar.",
  "DEL borra lo seleccionado.",
  "CARGAS (tecla C, o ENTER con C activa):",
  "  clic en la barra = lista de cargas:",
  "  Agregar, Editar o Borrar una a una.",
  "  Tipos: puntual, w, trapezoidal,",
  "  momento y Temperatura (du, dg).",
  "  Clic en un nodo: editar/borrar su carga.",
  "U deshacer   Y rehacer   E encuadrar",
  "+ / -  zoom    flechas: mover vista",
  "G rejilla   J snap   P propiedades",
  "Q cambia unidades (kN-m, N-m, tf-m);",
  "  tambien menu Ajustes > Unidades.",
  "M mueve el nodo elegido (clic suelta)",
  "Arrastrar el fondo mueve la vista.",
  "RESULTADOS: R N V M D T E; 0 o el",
  "  selector Real / Ampliada (Def).",
  "Menu (tecla menu): Archivo, Ajustes...",
  "Signos: x derecha, y arriba, giro +",
  "antihorario. Fy < 0 = hacia abajo.",
  "El modelo siempre se guarda en kN, m.",
  "Supuestos: Euler-Bernoulli,",
  "pequeñas deformaciones, 2D lineal.",
  "Estructural v1.1 · Adrián Castro Ramírez",
}

local ACERCA = {
  "Estructural v1.1",
  "Autor: Adrián Castro Ramírez",
  "Análisis estructural 2D de vigas, marcos y cerchas por el método de rigidez directa, con diagramas N, V, M y deformada.",
  "Supuestos: elementos Euler-Bernoulli, pequeñas deformaciones, material lineal elástico, análisis 2D estático (sin P-Δ ni cortante).",
}

function H.acerca()
  local l = {}
  for i = 1, #ACERCA do
    local w = D.ajustar(ACERCA[i], 270)
    for k = 1, #w do l[#l + 1] = w[k] end
    if i == 2 then l[#l + 1] = "" end
  end
  D.texto("Acerca de", l)
end

function H.ayuda()
  D.texto("Ayuda - Estructural 2D", AYUDA)
end

function H.charIn(c)
  H.msg = nil
  local k = c:lower()
  local en_res = Res.modo ~= nil
  if Res.modo then
    -- teclas del modo resultados; s/a/c/b vuelven a modelar con esa herramienta
    if k == "s" or k == "a" or k == "c" or k == "b" then
      H.salir_resultados()
    elseif Res.tecla(c) then
      redraw()
      return
    elseif k == "f" then H.encuadrar(); return
    elseif k == "z" then H.zoom(1.4); return
    elseif k == "x" then H.zoom(1 / 1.4); return
    elseif k == "p" then
      H.props_globales()
      return
    end
  end
  if k == "s" then H.set_tool("sel")
  elseif k == "n" then H.set_tool("nodo")
  elseif k == "b" then
    -- b estando ya en Barra alterna Marco / Cercha
    if H.tool == "barra" and not en_res then H.alternar_modo() else H.set_tool("barra") end
  elseif k == "a" then H.set_tool("apoyo")
  elseif k == "c" then H.set_tool("carga")
  elseif k == "r" then H.resolver()
  elseif k == "u" then H.deshacer()
  elseif k == "y" then H.rehacer()
  elseif k == "e" then H.encuadrar()
  elseif k == "+" or k == "=" then H.zoom(1.4)
  elseif k == "-" or k == "\226\136\146" or k == "_" then H.zoom(1 / 1.4)
  elseif k == "g" then H.toggle_rejilla()
  elseif k == "k" then H.alternar_modo()
  elseif k == "j" then H.ciclar_snap()
  elseif k == "x" then H.dialogo_coordenadas()
  elseif k == "p" then H.props_globales()
  elseif k == "q" then H.ciclar_unidades()
  elseif k == "h" then H.ayuda()
  elseif k == "l" or k == "?" then H.leyenda()
  elseif k == "m" then H.mover_seleccion()
  end
  redraw()
end

function H.arrow(k)
  H.msg = nil
  if Res.modo and not drag and Res.arrow(k) then redraw(); return end
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
    if not ok then aviso(msg, true) else asegurar_visible(i) end
  else
    local d = 24
    if k == "left" then V.pan(d, 0) elseif k == "right" then V.pan(-d, 0)
    elseif k == "up" then V.pan(0, d) else V.pan(0, -d) end
    if H.hover.px then actualizar_hover(H.hover.px, H.hover.py) end
  end
  redraw()
end

function H.enter()
  local p = H.pend
  if p and H.msg == p.msg and not Res.modo and ED.m.barras[p.e] then
    H.pend = nil
    local e, tipo = p.e, p.tipo
    ED.hacer(function(m)
      local b = m.barras[e]
      b.tipo, b.rot_i, b.rot_j = tipo, false, false
      return true
    end)
    aviso("Barra " .. e .. ": ahora " .. (tipo == "cercha" and "cercha" or "marco") .. " (U deshace)")
    return
  end
  H.pend = nil
  H.msg = nil
  H.editar()
  redraw()
end

function H.esc()
  H.msg = nil
  if drag then fin_drag(true); return end
  if Res.modo then
    if not Res.esc() then H.salir_resultados() end
    redraw()
    return
  end
  if H.barra_a then
    H.fin_cadena()
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
  if Res.modo then Res.siguiente(1); redraw(); return end
  -- Tab: siguiente herramienta
  local orden = { "sel", "nodo", "barra", "apoyo", "carga" }
  for i = 1, #orden do
    if orden[i] == H.tool then H.set_tool(orden[i % #orden + 1]); return end
  end
end

-- ----------------------------------------------------- archivo / ejemplos
-- Modelo nuevo inmediato; tipo (opcional) fija el modo de dibujo
function H.nuevo(tipo)
  if Res.modo then H.salir_resultados() end
  if tipo then ED.set_tipo(tipo) end
  ED.reemplazar(ED.nuevo())
  H.sel, H.barra_a, H.cadena_sucia, H.pend = nil, nil, false, nil
  H.sug_hecho = false
  V.encuadrar(ED.m)
  H.set_tool("barra")
  aviso("Modelo nuevo: " .. nombre_modo() .. " (U deshace)")
end

-- Archivo > Nuevo: pregunta que se va a dibujar (ESC conserva el modo actual)
local function menu_tipo(titulo, elegir, cancelar)
  return D.menu({
    titulo = titulo,
    items = { "Viga / Marco", "Cercha" },
    sel = (ED.props.tipo == "cercha") and 2 or 1,
    ancho = 220,
    elegir = elegir,
    cancelar = cancelar,
  })
end

function H.nuevo_menu()
  if Res.modo then H.salir_resultados() end
  menu_tipo("¿Qué vas a dibujar?",
    function(k) H.nuevo(k == 2 and "cercha" or "portico") end,
    function() H.nuevo() end)
end

-- Al arrancar con el modelo vacio: elegir el modo (ESC conserva el actual)
H.dialogo_inicio = nil
function H.preguntar_inicio()
  H.dialogo_inicio = menu_tipo("¿Qué vas a dibujar?",
    function(k) H.set_modo(k == 2 and "cercha" or "portico") end, nil)
  return H.dialogo_inicio
end

function H.ejemplo(nombre)
  local m, msg = ED.ejemplo(nombre)
  if not m then aviso(msg, true); return end
  ED.reemplazar(m)
  H.sel, H.barra_a, H.cadena_sucia, H.pend = nil, nil, false, nil
  H.sug_hecho = false
  V.encuadrar(ED.m)
  Res.camara_cambio()
  if not Res.modo then H.set_tool("sel") end
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
      H.sel, H.barra_a, H.cadena_sucia, H.pend = nil, nil, false, nil
      H.sug_hecho = false
      V.encuadrar(ED.m)
      Res.camara_cambio()
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
