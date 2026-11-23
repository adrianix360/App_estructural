platform.apiLevel = '2.4'

-- main.lua - Punto de entrada de Estructural 2D (TI-Nspire CX II CAS).
-- Solo cablea los eventos on.* hacia ui.herramientas / ui.dialogo, dibuja con ui.dibujo y
-- guarda/restaura el documento. La logica vive en src/ui/*.lua.
local ED = require("ui.modelo_ed")
local V = require("ui.vista")
local D = require("ui.dialogo")
local P = require("ui.dibujo")
local H = require("ui.herramientas")

H.init()

local function redraw()
  if platform and platform.window then platform.window:invalidate() end
end

local function tamano()
  local w, h = 318, 212
  local ok, a, b = pcall(function() return platform.window:width(), platform.window:height() end)
  if ok and type(a) == "number" and type(b) == "number" and a > 50 and b > 50 then w, h = a, b end
  return w, h
end

local function aplicar_tamano(w, h)
  P.size(w, h)
  H.resize(w, h)
end

local function registrar_menu()
  if not (toolpalette and toolpalette.register) then return end
  local ej = {}
  for i = 1, #ED.ejemplos do
    local nom = ED.ejemplos[i]
    ej[#ej + 1] = { "Ejemplo: " .. nom, function() H.ejemplo(nom) end }
  end
  local archivo = { "Archivo", { "Nuevo", H.nuevo } }
  for i = 1, #ej do archivo[#archivo + 1] = ej[i] end
  archivo[#archivo + 1] = { "Guardar como...", H.guardar_como }
  archivo[#archivo + 1] = { "Abrir...", H.abrir }
  archivo[#archivo + 1] = { "Borrar guardado...", H.borrar_guardado }
  archivo[#archivo + 1] = { "Deshacer (U)", H.deshacer }
  archivo[#archivo + 1] = { "Rehacer (Y)", H.rehacer }
  toolpalette.register({
    archivo,
    { "Herramientas",
      { "Seleccionar / mover (S)", function() H.set_tool("sel") end },
      { "Nodo (N)", function() H.set_tool("nodo") end },
      { "Barra (B)", function() H.set_tool("barra") end },
      { "Apoyo (A)", function() H.set_tool("apoyo") end },
      { "Carga (C)", function() H.set_tool("carga") end },
      { "Resolver (R)", H.resolver },
      { "Coordenadas exactas (X)", H.dialogo_coordenadas } },
    { "Vista",
      { "Encuadrar (E)", H.encuadrar },
      { "Acercar (+)", function() H.zoom(1.4) end },
      { "Alejar (-)", function() H.zoom(1 / 1.4) end },
      { "Rejilla (G)", H.toggle_rejilla },
      { "Snap 0.1 m", function() H.set_snap(0.1) end },
      { "Snap 0.25 m", function() H.set_snap(0.25) end },
      { "Snap 0.5 m", function() H.set_snap(0.5) end },
      { "Snap 1 m", function() H.set_snap(1) end },
      { "Sin snap", function() H.set_snap(0) end } },
    { "Propiedades globales",
      { "E, A, I y tipo de barra (P)", H.props_globales } },
    { "Ayuda",
      { "Guia rapida (H)", H.ayuda },
      { "Leyenda de signos (L)", H.leyenda } },
  })
end

function on.construction()
  local w, h = tamano()
  aplicar_tamano(w, h)
  V.encuadrar(ED.m)
  registrar_menu()
  redraw()
end

function on.resize(w, h)
  aplicar_tamano(w, h)
  if #ED.m.nodos == 0 then V.vista_inicial() end
  redraw()
end

function on.paint(gc)
  P.pintar(gc, H)
  D.pintar(gc)
end

-- ------------------------------------------------------------------ raton
function on.mouseDown(x, y)
  if D.mouseDown(x, y) then return end
  H.mouseDown(x, y)
end

function on.mouseUp(x, y)
  if D.activo() then return end
  H.mouseUp(x, y)
end

function on.mouseMove(x, y)
  if D.mouseMove(x, y) then return end
  H.mouseMove(x, y)
end

function on.grabDown(x, y)
  if D.activo() then return end
  H.grabDown()
end

-- ----------------------------------------------------------------- teclado
function on.charIn(c)
  if D.charIn(c) then return end
  H.charIn(c)
end

function on.arrowKey(k)
  if D.arrow(k) then return end
  H.arrow(k)
end

function on.enterKey()
  if D.enter() then return end
  H.enter()
end

function on.escapeKey()
  if D.esc() then return end
  H.esc()
end

function on.backspaceKey()
  if D.backspace() then return end
  H.del()
end

function on.deleteKey()
  if D.backspace() then return end
  H.del()
end

function on.tabKey()
  if D.tab() then return end
  H.tab()
end

-- ------------------------------------------------------------- persistencia
function on.save()
  local t = ED.exportar()
  t.cfg = { rejilla = V.rejilla, snap_i = V.snap_i, tool = H.tool, s = V.s, ox = V.ox, oy = V.oy }
  return t
end

function on.restore(t)
  if type(t) ~= "table" then return end
  ED.importar(t)
  H.sel, H.barra_a = nil, nil
  local c = t.cfg
  if type(c) == "table" then
    if type(c.rejilla) == "boolean" then V.rejilla = c.rejilla end
    if type(c.snap_i) == "number" and V.pasos[c.snap_i] then V.snap_i = c.snap_i end
    if c.tool == "sel" or c.tool == "nodo" or c.tool == "barra" or c.tool == "apoyo" or c.tool == "carga" then
      H.tool = c.tool
    end
    if type(c.s) == "number" and type(c.ox) == "number" and type(c.oy) == "number" and c.s >= V.S_MIN and c.s <= V.S_MAX then
      V.s, V.ox, V.oy = c.s, c.ox, c.oy
    else
      V.encuadrar(ED.m)
    end
  else
    V.encuadrar(ED.m)
  end
  redraw()
end
