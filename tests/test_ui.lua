-- test_ui.lua - Interfaz de modelado con raton/teclado simulados sobre tests/mock_nspire.lua.
-- Uso: desde la raiz, tras `python -I tools/build.py --no-tns` (lo hace tools/run_tests.sh).
-- Genera PNG de muestra en build/png/ (no versionado) si hay python con Pillow.
local mock = dofile("tests/mock_nspire.lua")
local env = mock.load_app("build/app.lua")

local fails, checks = 0, 0
local function check(cond, msg)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    print("FALLO: " .. tostring(msg))
  end
end
local function eq(a, b, msg)
  check(a == b, (msg or "eq") .. ": esperado " .. tostring(b) .. ", obtenido " .. tostring(a))
end
local function near(a, b, msg, tol)
  check(type(a) == "number" and math.abs(a - b) <= (tol or 1e-9),
    (msg or "near") .. ": esperado " .. tostring(b) .. ", obtenido " .. tostring(a))
end

local ED = env.require("ui.modelo_ed")
local V = env.require("ui.vista")
local D = env.require("ui.dialogo")
local H = env.require("ui.herramientas")

pcall(os.execute, "mkdir build\\png 2>nul")

-- ------------------------------------------------------------------ utilidades
local function key(k) mock.key(k) end
local function typed(s) for c in s:gmatch(".") do mock.key(c) end end
local function shown(s) mock.paint(); return (mock.has_text(s)) end
local function px(x) return math.floor(V.ox + x * V.s + 0.5) end
local function py(y) return math.floor(V.oy - y * V.s + 0.5) end
local function clic(x, y) mock.move(px(x), py(y)); mock.click(px(x), py(y)) end
local function nuevo()
  H.nuevo()
  H.set_tool("barra")
  V.vista_inicial()
  V.auto = false          -- camara fija: las pruebas hacen clic en coordenadas de pantalla calculadas
  V.fijar_snap(0.5)
end
local function dentro(label)
  mock.paint()
  for _, t in ipairs(mock.screen_text()) do
    local ok = t.x >= 0 and t.x + t.w <= mock.W + 2 and t.y >= 0 and t.y + t.h <= mock.H + 2
    check(ok, label .. ": texto fuera de pantalla '" .. t.text .. "' x=" .. t.x .. " w=" .. t.w .. " y=" .. t.y)
  end
end
local function paint_ok(label)
  local ok, err = pcall(mock.paint)
  check(ok, label .. ": paint fallo: " .. tostring(err))
  return ok
end
local pngs = {}
local function png(name)
  mock.paint()
  mock.dump_ops("build/png/" .. name .. ".json")
  local ok = os.execute('python -I tools/render_png.py build/png/' .. name .. '.json build/png/' .. name .. '.png --scale 2 >nul 2>&1')
  pngs[#pngs + 1] = "build/png/" .. name .. ".png"
  return ok
end
local function modelo() return ED.m end

-- ------------------------------------------------------------------ arranque
print("-- arranque")
check(env.platform.apiLevel == "2.4", "apiLevel 2.4")
check(mock.toolpalette_menu ~= nil, "toolpalette registrado")
do
  local titulos = {}
  for _, m in ipairs(mock.toolpalette_menu) do titulos[#titulos + 1] = m[1] end
  eq(table.concat(titulos, ","), "Archivo,Herramientas,Vista,Ajustes,Ayuda", "menus")
  local maxi = 0
  for _, m in ipairs(mock.toolpalette_menu) do maxi = math.max(maxi, #m - 1) end
  check(maxi <= 30 and #mock.toolpalette_menu <= 15, "limites de toolpalette (<=30 items por menu, <=15 menus)")
end
-- v1.1: con el modelo vacio la app pregunta que se va a dibujar; ESC conserva el modo actual
check(D.activo() ~= nil and shown("Qué vas a dibujar"), "arranque vacio: selector de tipo")
eq(ED.props.tipo, "portico", "modo inicial: marco")
key("escape")
check(D.activo() == nil, "ESC cierra el selector de arranque")
eq(ED.props.tipo, "portico", "ESC mantiene el modo actual")
check(shown("Modelo vacio"), "pantalla de bienvenida")
check(shown("Marco: clic nodo A"), "barra de estado con instruccion")
dentro("arranque")
png("01_vacio")

-- ------------------------------------------------------- viga simple en pocos clics
print("-- viga simple")
nuevo()
clic(0, 0)
local m = modelo()
eq(#m.nodos, 1, "primer clic crea nodo A")
check(shown("nodo B"), "estado pide nodo B")
clic(6, 0)
m = modelo()
eq(#m.nodos, 2, "segundo clic crea nodo B")
eq(#m.barras, 1, "y la barra")
near(m.nodos[2].x, 6, "x nodo B"); near(m.nodos[2].y, 0, "y nodo B")
near(ED.longitud(m, 1), 6, "L viga")
eq(m.barras[1].tipo, "portico", "tipo por omision")
near(m.barras[1].E, 2e8, "E por omision 200 GPa", 1)
near(m.barras[1].A, 0.01, "A por omision 100 cm2")
near(m.barras[1].I, 1e-4, "I por omision 10000 cm4", 1e-12)
-- cadena: tercer clic crea otro nodo y otra barra
clic(9, 0)
eq(#modelo().barras, 2, "la cadena continua")
key("escape")
check(H.barra_a == nil, "ESC termina la cadena")
H.deshacer()
eq(#modelo().barras, 1, "deshacer quita la ultima barra")
-- validaciones
H.set_tool("barra")
clic(0, 0); clic(0, 0)
check(shown("Selecciona dos nodos distintos"), "mensaje: nodos distintos")
H.set_tool("barra"); clic(0, 0); clic(6, 0)
check(shown("La barra ya existe"), "mensaje: barra repetida")
eq(#modelo().barras, 1, "no se duplica la barra")
key("escape")

-- apoyos
print("-- apoyos")
key("a")
eq(H.tool, "apoyo", "tecla a = Apoyo")
clic(0, 0)
check(D.activo() ~= nil, "clic en nodo abre el selector de apoyo")
check(shown("Apoyo en nodo 1"), "titulo del selector")
png("02_selector_apoyo")
key("1")
eq(ED.apoyo_tipo(modelo().nodos[1].apoyo), "articulado", "articulado")
clic(6, 0)
key("2")
eq(ED.apoyo_tipo(modelo().nodos[2].apoyo), "rodilloX", "rodillo X")
check(modelo().nodos[2].apoyo.uy and not modelo().nodos[2].apoyo.ux, "rodillo X restringe solo Y")
clic(9 * 0 + 0, 0)  -- otra vez nodo 1: abrir y elegir empotrado (teclas) y volver a articulado
key("down"); key("down"); key("down"); key("enter")
eq(ED.apoyo_tipo(modelo().nodos[1].apoyo), "empotrado", "empotrado con flechas+ENTER")
clic(0, 0); key("1")
-- clic en vacio
clic(3, 2)
check(shown("sobre un nodo"), "apoyo en vacio da aviso")
-- resorte y asentamiento
clic(6, 0); key("5")
check(D.activo() ~= nil, "dialogo de resorte")
typed("0"); key("down"); typed("5000"); key("enter")
check(ED.apoyo_tipo(modelo().nodos[2].apoyo) == "resorte" and modelo().nodos[2].apoyo.ky == 5000, "resorte ky=5000")
clic(6, 0); key("3")
clic(6, 0); key("6")
typed("2"); key("down"); typed("-5"); key("enter")
near(modelo().nodos[2].apoyo.dx, 0.002, "asentamiento dx 2 mm"); near(modelo().nodos[2].apoyo.dy, -0.005, "dy -5 mm")
clic(6, 0); key("7")
eq(modelo().nodos[2].apoyo, nil, "quitar apoyo")
clic(6, 0); key("2")

-- cargas
print("-- cargas")
key("c")
clic(3, 0)
check(D.activo() ~= nil and shown("Carga en barra 1"), "clic en barra abre tipos de carga")
key("2")
check(shown("Valor w"), "formulario de distribuida")
key("enter")
check(D.activo() == nil, "ENTER acepta los valores por omision")
local c = modelo().barras[1].cargas[1]
check(c and c.t == "w" and c.w1 == -10 and c.w2 == -10 and c.dir == "GY", "w = -10 GY")
near(c.a, 0, "a=0"); near(c.b, 6, "b=L")
-- puntual donde se hizo clic
clic(2, 0)
check(shown("Cargas de la barra 1"), "con cargas: aparece la lista de cargas")
key("1"); key("1")               -- Agregar > Puntual
check(shown("desde nodo"), "formulario de puntual")
key("down"); typed("25"); key("enter")
local p = modelo().barras[1].cargas[2]
check(p and p.t == "P" and p.p == -25 and p.dir == "GY", "P = -25 GY (abajo)")
near(p.a, 2, "a tomado del clic (snap)")
-- momento y trapezoidal
clic(3, 0); key("1"); key("4"); key("enter")
eq(modelo().barras[1].cargas[3].t, "M", "momento")
clic(3, 0); key("1"); key("3")
key("down"); key("down"); key("down"); typed("12"); key("enter")
local tz = modelo().barras[1].cargas[4]
check(tz and tz.t == "w" and tz.w1 == 0 and tz.w2 == -12, "trapezoidal 0 -> -12")
-- error de validacion mantiene el dialogo
clic(3, 0); key("1"); key("1")
typed("9"); key("enter")
check(D.activo() ~= nil and shown("posicion"), "posicion fuera de la barra: mensaje y dialogo abierto")
key("escape")
check(D.activo() == nil, "ESC cancela el dialogo")
eq(#modelo().barras[1].cargas, 4, "cancelar no agrega carga")
-- cargas nodales
clic(6, 0)
check(shown("Carga en el nodo 2"), "dialogo carga nodal")
key("down"); typed("-15"); key("down"); typed("4"); key("enter")
check(modelo().nodos[2].carga and modelo().nodos[2].carga.fy == -15 and modelo().nodos[2].carga.mz == 4, "carga nodal")
dentro("viga cargada")
png("03_viga_cargada")
-- borrar cargas
clic(3, 0); key("6")
eq(#modelo().barras[1].cargas, 0, "borrar cargas de la barra")
H.deshacer()
eq(#modelo().barras[1].cargas, 4, "deshacer restaura las cargas")

-- deshacer / rehacer
print("-- deshacer/rehacer")
local n_antes = #modelo().barras[1].cargas
key("u")
eq(#modelo().barras[1].cargas, n_antes, "u deshace el borrado (ya deshecho): sin cambio de n")
H.set_tool("sel")
local nu = ED.n_undo()
check(nu >= 5 and nu <= 30, "pila de deshacer acotada: " .. nu)
for i = 1, 40 do ED.snap() end
local nu2 = ED.n_undo()
eq(nu2, 30, "maximo 30 instantaneas")
ED.reiniciar_historial()
H.set_tool("barra"); clic(0, 3); clic(6, 3); key("escape")
eq(#modelo().barras, 2, "segunda barra")
key("u"); eq(#modelo().barras, 1, "u deshace")
key("y"); eq(#modelo().barras, 2, "y rehace")
key("u"); key("u")
check(shown("Deshecho") or shown("nada"), "mensaje de deshacer")
key("y"); key("y")

-- seleccion, mover, borrar
print("-- seleccionar / mover / borrar")
H.nuevo(); V.vista_inicial()
H.ejemplo("Viga apoyada")
V.vista_inicial()   -- escala 30: nodo 1 en (0,0), nodo 2 en (6,0)
eq(H.tool, "sel", "ejemplo deja la herramienta Seleccionar")
clic(0, 0)
check(H.sel and H.sel.t == "nodo" and H.sel.i == 1, "clic selecciona nodo")
clic(3, 0)
check(H.sel and H.sel.t == "barra" and H.sel.i == 1, "clic selecciona barra")
-- arrastrar nodo 2 a x=5
mock.move(px(6), py(0))
mock.drag(px(6), py(0), px(5), py(0), 4)
near(modelo().nodos[2].x, 5, "arrastre mueve el nodo (snap 0.5)")
near(modelo().barras[1].cargas[1].b, 5, "la carga se recorta a la nueva longitud")
H.deshacer()
near(modelo().nodos[2].x, 6, "deshacer devuelve el nodo")
near(modelo().barras[1].cargas[1].b, 6, "y la carga")
-- arrastre del fondo = pan
local ox0 = V.ox
mock.drag(px(3), py(3), px(3) + 20, py(3) + 10, 3)
near(V.ox, ox0 + 20, "arrastre de fondo desplaza la vista", 1e-6)
V.vista_inicial()
-- grabDown: arrastre pegajoso
mock.move(px(6), py(0))
mock.grab()
mock.move(px(4), py(0))
mock.click(px(4), py(0))      -- suelta
near(modelo().nodos[2].x, 4, "grabDown + mover + clic suelta el nodo")
check(H.hover.px ~= nil, "hover registrado")
H.deshacer()
-- tecla M
clic(6, 0)
key("m")
mock.move(px(5), py(1))
mock.click(px(5), py(1))
near(modelo().nodos[2].x, 5, "M mueve con el cursor (x)"); near(modelo().nodos[2].y, 1, "M mueve con el cursor (y)")
H.deshacer()
-- ESC cancela un movimiento pegajoso
clic(6, 0); key("m"); mock.move(px(8), py(2)); key("escape")
near(modelo().nodos[2].x, 6, "ESC cancela el movimiento")
-- flechas mueven el nodo seleccionado
clic(6, 0); key("left")
near(modelo().nodos[2].x, 5.5, "flecha mueve nodo un paso de snap")
H.deshacer()
-- borrar
clic(6, 0)
mock.key("delete")
eq(#modelo().nodos, 1, "DEL borra el nodo")
eq(#modelo().barras, 0, "y sus barras")
H.deshacer()
eq(#modelo().barras, 1, "deshacer restaura la barra")
eq(modelo().barras[1].ni, 1, "indices correctos tras restaurar")
-- borrar nodo intermedio renumera
H.ejemplo("Viga continua")
V.encuadrar(modelo())
H.sel = { t = "nodo", i = 2 }
mock.key("backspace")
eq(#modelo().nodos, 2, "borra nodo intermedio"); eq(#modelo().barras, 0, "y ambas barras")
H.deshacer()
H.sel = { t = "barra", i = 1 }
mock.key("delete")
eq(#modelo().barras, 1, "borra solo la barra")
eq(modelo().barras[1].ni, 2, "la barra restante conserva nodos 2-3")

-- propiedades por ENTER
print("-- edicion de propiedades")
H.ejemplo("Viga apoyada")
V.vista_inicial()
clic(3, 0)
key("enter")
check(D.activo() ~= nil and shown("E (GPa)"), "ENTER abre propiedades de barra")
check(shown("Rotula en nodo i"), "campos de rotula")
png("04_dialogo_barra")
typed("210"); key("down"); typed("150"); key("down"); typed("8000")
key("down"); key("right")          -- tipo -> Cercha
key("down"); key("right")          -- rotula i
key("enter")
local b1 = modelo().barras[1]
near(b1.E, 210e6, "E 210 GPa -> kN/m2", 1); near(b1.A, 0.015, "A 150 cm2 -> m2"); near(b1.I, 8e-5, "I 8000 cm4 -> m4", 1e-12)
eq(b1.tipo, "cercha", "tipo cercha"); eq(b1.rot_i, true, "rotula i")
-- campo invalido
clic(3, 0); key("enter"); typed("abc")
-- 'abc' no pasa el filtro numerico: queda vacio -> error al aceptar
key("backspace"); key("enter")
check(D.activo() ~= nil, "valor vacio mantiene el dialogo abierto")
check(shown("no es un numero"), "mensaje de numero invalido")
key("escape")
-- nodo
clic(0, 0); key("enter")
check(shown("Nodo 1"), "ENTER sobre nodo abre dialogo de nodo")
typed("1"); key("down"); typed("2"); key("enter")
near(modelo().nodos[1].x, 1, "nodo editado x"); near(modelo().nodos[1].y, 2, "nodo editado y")
H.deshacer()
-- propiedades globales
key("p")
check(shown("Propiedades globales"), "dialogo de propiedades globales")
typed("30"); key("down"); typed("500"); key("down"); typed("40000")
key("down"); key("down"); key("right"); key("enter")
near(ED.props.E, 30e6, "global E=30 GPa", 1)
near(modelo().barras[1].E, 30e6, "aplicada a todas", 1)
ED.props.E, ED.props.A, ED.props.I, ED.props.tipo = 200e6, 0.01, 1e-4, "portico"

-- coordenadas exactas
print("-- coordenadas exactas")
nuevo()
key("n")
mock.move(px(1), py(1))
key("x")
check(shown("coordenadas") and D.activo() ~= nil, "x abre coordenadas")
typed("2.5"); key("down"); typed("-1,25"); key("enter")
eq(#modelo().nodos, 1, "nodo creado por teclado")
near(modelo().nodos[1].x, 2.5, "x exacta"); near(modelo().nodos[1].y, -1.25, "y exacta con coma decimal")
key("enter"); typed("1/4"); key("enter")
near(modelo().nodos[2].x, 0.25, "fraccion 1/4")

-- zoom, pan, rejilla, snap
print("-- vista")
nuevo()
local s0 = V.s
key("+"); check(V.s > s0, "+ acerca")
key("-"); near(V.s, s0, "- aleja", 1e-9)
local oy0 = V.oy
key("up"); check(V.oy ~= oy0, "flechas mueven la vista")
key("down")
H.ejemplo("Cercha"); key("e")
check(V.s > 20 and V.s <= 60, "encuadrar da escala razonable: " .. V.s)
dentro("encuadrar")
local g = V.rejilla
key("g"); check(V.rejilla ~= g, "g alterna rejilla"); key("g")
local si = V.snap_i
key("j"); check(V.snap_i ~= si, "j cicla el snap")
V.fijar_snap(0.5)

-- ejemplos
print("-- ejemplos")
local esperados = { ["Viga apoyada"] = { 2, 1 }, ["Voladizo"] = { 2, 1 }, ["Viga continua"] = { 3, 2 },
                    ["Cercha"] = { 5, 7 }, ["Portal"] = { 4, 3 } }
for _, nom in ipairs(ED.ejemplos) do
  H.ejemplo(nom)
  local mm = modelo()
  eq(#mm.nodos, esperados[nom][1], nom .. ": nodos")
  eq(#mm.barras, esperados[nom][2], nom .. ": barras")
  local norm = ED.normalizar(mm)
  check(norm ~= nil and #norm.nodos == #mm.nodos, nom .. ": modelo valido")
  paint_ok(nom)
  dentro("ejemplo " .. nom)
  png("ej_" .. nom:gsub(" ", "_"):lower())
end
-- menu: cada elemento del menu Archivo>Ejemplo ejecuta
for _, mn in ipairs(mock.toolpalette_menu) do
  for i = 2, #mn do
    local it = mn[i]
    if type(it) == "table" and it[1]:find("^Ejemplo") then
      H.nuevo(); it[2]()
      check(#modelo().nodos >= 2, "menu " .. it[1])
    end
  end
end

-- guardar / abrir / persistencia
print("-- guardar y cargar")
H.ejemplo("Portal")
local antes = ED.copiar(modelo())
H.guardar_como()
check(D.activo() ~= nil and shown("Nombre"), "dialogo guardar como")
typed("MiPortal"); key("enter")
eq(#ED.bib, 1, "modelo guardado en la biblioteca")
H.nuevo()
eq(#modelo().nodos, 0, "nuevo vacia el modelo")
H.abrir()
check(D.activo() ~= nil and shown("MiPortal"), "lista de modelos")
key("enter")
eq(#modelo().nodos, 4, "abrir restaura el modelo")
eq(#modelo().barras[2].cargas, 1, "con sus cargas")
local saved = mock.save()
H.nuevo(); H.ejemplo("Voladizo")
mock.restore(saved)
eq(#modelo().nodos, 4, "on.restore: nodos")
eq(modelo().barras[2].cargas[1].w1, -10, "on.restore: carga")
eq(ED.apoyo_tipo(modelo().nodos[1].apoyo), "empotrado", "on.restore: apoyo")
eq(#ED.bib, 1, "on.restore: biblioteca")
eq(ED.bib[1].nombre, "MiPortal", "on.restore: nombre")
check(not ED.puede_deshacer(), "on.restore: historial limpio")
local ok_json = pcall(mock.save)
check(ok_json, "on.save sin funciones ni ciclos")
-- restore de basura no revienta
local ok_r = pcall(mock.restore, { nodos = "x" })
check(ok_r, "on.restore tolera datos corruptos")
mock.restore(saved)
H.borrar_guardado()
key("1"); key("2")
eq(#ED.bib, 0, "borrar guardado")
-- biblioteca llena
for i = 1, 10 do ED.guardar_como("m" .. i) end
local okb, msgb = ED.guardar_como("otro")
check(not okb and msgb:find("llena"), "biblioteca llena avisa")
ED.bib = {}

-- Resolver
print("-- resolver")
H.ejemplo("Viga apoyada")
key("r")
local hay_solver = pcall(env.require, "core.solver")
if hay_solver then
  check(D.activo() == nil, "con solver no hay aviso modal")
  eq(env.require("ui.resultados").modo, "reac", "con solver entra en modo resultados")
  key("escape")
  eq(env.require("ui.resultados").modo, nil, "ESC vuelve a modelar")
else
  check(D.activo() ~= nil and shown("Solver no disponible"), "sin solver: 'Solver no disponible'")
  key("enter")
  check(D.activo() == nil, "se cierra el aviso")
end

-- toolbar con clics
print("-- barra de herramientas")
for _, b in ipairs(H.botones) do
  if b.herr then
    mock.click(b.x + 5, b.y + 5)
    eq(H.tool, b.herr, "clic en icono " .. b.id)
  end
end
eq(#H.botones, 11, "11 botones")
for _, b in ipairs(H.botones) do
  check(b.x >= 0 and b.x + b.w <= mock.W and b.y + b.h <= V.rect.y, "boton dentro de la barra: " .. b.id)
end

-- ayuda
H.ayuda()
check(shown("HERRAMIENTAS"), "ayuda visible")
key("down"); key("down"); key("escape")
check(D.activo() == nil, "cierra ayuda")

-- menu de la paleta: invoca todos los callbacks sin error
print("-- menu de la paleta")
for _, mn in ipairs(mock.toolpalette_menu) do
  for i = 2, #mn do
    local it = mn[i]
    if type(it) == "table" and type(it[2]) == "function" then
      H.ejemplo("Viga apoyada")
      local ok, err = pcall(it[2])
      check(ok, "menu '" .. mn[1] .. "/" .. it[1] .. "': " .. tostring(err))
      paint_ok("tras menu " .. it[1])
      if D.activo() then key("escape") end
      if D.activo() then key("escape") end
    end
  end
end

-- fuera de pantalla y teclas raras: nada debe lanzar errores
print("-- robustez")
nuevo()
for _, k in ipairs({ "enter", "delete", "backspace", "tab", "up", "left", "escape", "x", "m", "u", "y", "h", "p" }) do
  local ok, err = pcall(mock.key, k)
  check(ok, "tecla " .. k .. " sin modelo: " .. tostring(err))
  if D.activo() then key("escape") end
end
for _, p in ipairs({ { -5, -5 }, { 400, 300 }, { 0, 0 }, { 317, 211 } }) do
  local ok, err = pcall(function() mock.move(p[1], p[2]); mock.click(p[1], p[2]) end)
  check(ok, "clic fuera " .. p[1] .. "," .. p[2] .. ": " .. tostring(err))
end
V.zoom(1000); V.zoom(1e-6)
paint_ok("zoom extremo")
H.ejemplo("Portal"); V.s = 400; V.ox = -3000; V.oy = 5000
paint_ok("estructura fuera del lienzo")
H.encuadrar()

-- rendimiento / memoria del dibujo
print("-- memoria de paint")
H.ejemplo("Cercha"); H.encuadrar()
local gcc = env.collectgarbage
local noop, w30, h12 = function() end, function() return 30 end, function() return 12 end
local nulo = setmetatable({}, { __index = function(_, k)
  if k == "getStringWidth" then return w30 end
  if k == "getStringHeight" then return h12 end
  return noop   -- funciones compartidas: un closure por llamada falsearia la medicion
end })
env.on.paint(nulo)
gcc("collect")
local m0 = gcc("count")
for i = 1, 100 do env.on.paint(nulo) end
local m1 = gcc("count")
local por_paint = (m1 - m0) / 100
print(string.format("   basura por on.paint (gc nulo, cercha): %.2f KB", por_paint))
check(por_paint < 3, "on.paint genera poca basura: " .. por_paint .. " KB")

-- =================================================================== v1.0: pulido de interfaz
local U = env.require("ui.unidades")
local Res = env.require("ui.resultados")
local S = env.require("core.solver")
local EE = env.require("core.esfuerzos")
local function sin_resultados() if Res.modo then H.salir_resultados() end end

-- ------------------------------------------------------------------ dividir barra (UI)
print("-- dividir barra: clics")
sin_resultados()
nuevo()
clic(0, 0); clic(6, 0); key("escape")
do
  local b1 = modelo().barras[1]
  b1.E, b1.A, b1.I, b1.rot_i, b1.rot_j = 123e6, 0.02, 3e-4, true, true
  ED.agregar_carga_barra(modelo(), 1, { t = "P", a = 1, p = -10, dir = "GY" })
  ED.agregar_carga_barra(modelo(), 1, { t = "P", a = 4.5, p = -20, dir = "GY" })
  ED.agregar_carga_barra(modelo(), 1, { t = "w", a = 0, b = 6, w1 = -2, w2 = -8, dir = "GY" })
  ED.agregar_carga_barra(modelo(), 1, { t = "T", du = 20, dg = 10, alfa = 1.2e-5, h = 0.3 })
  ED.agregar_carga_barra(modelo(), 1, { t = "M", a = 3, m = 7 })
end
H.set_tool("nodo")
mock.move(px(3.2), py(0))
check(H.hover.div, "sobre una barra con Nodo se anuncia la division")
shown("x")
ED.reiniciar_historial()
local n_undo0 = ED.n_undo()
clic(3.2, 0)
do
  local mm = modelo()
  eq(#mm.nodos, 3, "dividir: nodo nuevo")
  eq(#mm.barras, 2, "dividir: dos barras")
  near(mm.nodos[3].x, 3, "snap a lo largo de la barra (3.2 -> 3.0)"); near(mm.nodos[3].y, 0, "nodo sobre la barra")
  eq(mm.barras[1].ni, 1, "primera mitad: ni"); eq(mm.barras[1].nj, 3, "primera mitad: nj = nodo nuevo")
  eq(mm.barras[2].ni, 3, "segunda mitad: ni = nodo nuevo"); eq(mm.barras[2].nj, 2, "segunda mitad: nj original")
  eq(mm.barras[1].rot_i, true, "rotula i queda en la primera"); eq(mm.barras[1].rot_j, false, "primera: j rigido")
  eq(mm.barras[2].rot_i, false, "segunda: i rigido"); eq(mm.barras[2].rot_j, true, "rotula j pasa a la segunda")
  near(mm.barras[2].E, 123e6, "E copiado", 1); near(mm.barras[2].A, 0.02, "A copiada"); near(mm.barras[2].I, 3e-4, "I copiada", 1e-12)
  eq(mm.barras[2].tipo, "portico", "tipo copiado")
  eq(H.sel and H.sel.t, "nodo", "queda seleccionado el nodo nuevo")
  -- cargas
  local c1, c2 = mm.barras[1].cargas, mm.barras[2].cargas
  local function cuenta(cs, t) local n = 0 for _, c in ipairs(cs) do if c.t == t then n = n + 1 end end return n end
  eq(cuenta(c1, "P"), 1, "P(a=1) a la primera"); eq(cuenta(c2, "P"), 1, "P(a=4.5) a la segunda")
  for _, c in ipairs(c2) do if c.t == "P" then near(c.a, 1.5, "P desplazada a=4.5-3") end end
  eq(cuenta(c1, "M") + cuenta(c2, "M"), 0, "M(a=3) justo en el corte: ya no queda en ninguna barra ...")
  check(mm.nodos[3].carga ~= nil and math.abs(mm.nodos[3].carga.mz - 7) < 1e-9, "... sino como momento nodal del nodo nuevo")
  eq(cuenta(c1, "T"), 1, "T en la primera"); eq(cuenta(c2, "T"), 1, "T en la segunda")
  for _, c in ipairs(c1) do if c.t == "w" then near(c.a, 0, "w1 a"); near(c.b, 3, "w1 b"); near(c.w1, -2, "w1 w1"); near(c.w2, -5, "w1 w2 interpolado") end end
  for _, c in ipairs(c2) do if c.t == "w" then near(c.a, 0, "w2 a"); near(c.b, 3, "w2 b"); near(c.w1, -5, "w2 w1 interpolado"); near(c.w2, -8, "w2 w2") end end
end
eq(ED.n_undo() - n_undo0, 1, "dividir es UN solo paso de deshacer")
H.deshacer()
eq(#modelo().nodos, 2, "deshacer: sin nodo nuevo"); eq(#modelo().barras, 1, "deshacer: una barra")
eq(#modelo().barras[1].cargas, 5, "deshacer: cargas intactas"); eq(modelo().barras[1].rot_j, true, "deshacer: rotulas")
H.rehacer()
eq(#modelo().barras, 2, "rehacer divide otra vez")
H.deshacer()
-- clic cerca de un nodo: no divide, selecciona el nodo
clic(0.1, 0)
eq(#modelo().nodos, 2, "clic junto a un nodo no divide")
-- un punto interior fuera de la tolerancia del nodo, con snap 0.5
V.fijar_snap(0)
clic(0.4, 0)
eq(#modelo().nodos, 3, "sin snap: divide en el punto del clic")
near(modelo().nodos[3].x, 0.4, "x libre", 0.02)
H.deshacer()
V.fijar_snap(0.5)
-- Barra: un clic en el interior de una barra parte en dos y encadena
H.set_tool("barra")
clic(0, 3)
clic(3, 0)
do
  local mm = modelo()
  eq(#mm.nodos, 4, "Barra: nodo A y nodo de division"); eq(#mm.barras, 3, "Barra: dos mitades y la barra nueva")
  check(ED.barra_existe(mm, 3, 4) or ED.barra_existe(mm, 4, 3), "Barra: une A con el nodo de division")
end
key("escape")
-- no se puede unir A con una barra que ya parte de A
H.set_tool("barra")
clic(0, 0)
clic(1.5, 0)
check(shown("ya parte del nodo A"), "Barra: no divide la barra que sale del nodo A")
key("escape")

-- ---------------------------------------------------- dividir barra: equivalencia numerica
print("-- dividir barra: equivalencia numerica")
local function comparar(m0, e, a, etq, con_T)
  local m1 = ED.copiar(m0)
  local ok, e2 = ED.dividir_barra(m1, e, a)
  check(ok ~= nil, etq .. ": divide (" .. tostring(e2) .. ")")
  local r0, er0 = S.resolver(m0)
  local r1, er1 = S.resolver(m1)
  check(r0 ~= nil, etq .. ": resuelve el original " .. tostring(er0 and er0.msg))
  check(r1 ~= nil, etq .. ": resuelve el dividido " .. tostring(er1 and er1.msg))
  if not (r0 and r1) then return end
  local L = r0.barras[e].L
  local nuevo_e = #m1.barras
  local peor = 0
  for k = 0, 40 do
    local x = L * k / 40
    if math.abs(x - a) > 1e-6 then
      local N0, V0, M0, th0, v0, u0 = EE.eval(r0, e, x)
      local N1, V1, M1, th1, v1, u1
      if x < a then N1, V1, M1, th1, v1, u1 = EE.eval(r1, e, x)
      else N1, V1, M1, th1, v1, u1 = EE.eval(r1, nuevo_e, x - a) end
      local esc = math.max(1, math.abs(M0), math.abs(V0), math.abs(N0))
      peor = math.max(peor, math.abs(M1 - M0) / esc, math.abs(V1 - V0) / esc, math.abs(N1 - N0) / esc,
        math.abs(v1 - v0) / math.max(1e-6, math.abs(v0)), math.abs(u1 - u0) / math.max(1e-9, math.abs(u0)),
        math.abs(th1 - th0) / math.max(1e-6, math.abs(th0)))
    end
  end
  check(peor < 1e-7, etq .. ": M, V, N, theta, v, u iguales antes y despues (peor " .. string.format("%.2e", peor) .. ")")
  -- M y desplazamiento justo en el corte (continuos)
  local _, _, Ma, tha, va = EE.eval(r0, e, a)
  local _, _, Mb, thb, vb = EE.eval(r1, nuevo_e, 0)
  check(math.abs(va - vb) <= 1e-7 * math.max(1e-6, math.abs(va)), etq .. ": flecha en el corte")
  -- reacciones
  for i, rc in pairs(r0.reac) do
    local rc1 = r1.reac[i]
    check(rc1 and math.abs(rc.ry - rc1.ry) <= 1e-7 * math.max(1, math.abs(rc.ry)), etq .. ": reaccion Ry nodo " .. i)
  end
end
do
  local mm = ED.nuevo()
  ED.agregar_nodo(mm, 0, 0); ED.agregar_nodo(mm, 6, 0)
  ED.agregar_barra(mm, 1, 2, ED.PROPS_DEFECTO)
  ED.set_apoyo_tipo(mm, 1, "empotrado"); ED.set_apoyo_tipo(mm, 2, "rodilloX")
  ED.agregar_carga_barra(mm, 1, { t = "w", a = 0, b = 4, w1 = -4, w2 = -10, dir = "GY" })
  ED.agregar_carga_barra(mm, 1, { t = "P", a = 2, p = -15, dir = "GY" })
  ED.agregar_carga_barra(mm, 1, { t = "M", a = 4.5, m = 8 })
  ED.agregar_carga_barra(mm, 1, { t = "P", a = 5, p = 6, dir = "GX" })
  ED.agregar_carga_barra(mm, 1, { t = "w", a = 3, b = 6, w1 = 2, w2 = 2, dir = "L" })
  comparar(mm, 1, 2.5, "hiperestatica, corte en tramo con w trapezoidal")
  comparar(mm, 1, 2, "hiperestatica, corte justo en la P (pasa a nodal)")
  comparar(mm, 1, 4.5, "hiperestatica, corte justo en M (pasa a nodal)")
  comparar(mm, 1, 1.234, "hiperestatica, corte arbitrario")
  -- con carga termica y rotula
  local mt = ED.copiar(mm)
  ED.agregar_carga_barra(mt, 1, { t = "T", du = 15, dg = 12, alfa = 1.2e-5, h = 0.4 })
  mt.barras[1].rot_j = true
  comparar(mt, 1, 3.3, "con carga termica y rotula j")
  -- barra inclinada con cargas globales y locales y P en el corte
  local mi = ED.nuevo()
  ED.agregar_nodo(mi, 0, 0); ED.agregar_nodo(mi, 4, 3); ED.agregar_nodo(mi, 8, 3)
  ED.agregar_barra(mi, 1, 2, ED.PROPS_DEFECTO); ED.agregar_barra(mi, 2, 3, ED.PROPS_DEFECTO)
  ED.set_apoyo_tipo(mi, 1, "empotrado"); ED.set_apoyo_tipo(mi, 3, "articulado")
  ED.agregar_carga_barra(mi, 1, { t = "w", a = 0, b = 5, w1 = -6, w2 = -6, dir = "GY" })
  ED.agregar_carga_barra(mi, 1, { t = "P", a = 2, p = -12, dir = "GY" })
  ED.agregar_carga_barra(mi, 1, { t = "P", a = 2, p = 5, dir = "GX" })
  ED.agregar_carga_barra(mi, 1, { t = "P", a = 2, p = 4, dir = "L" })
  ED.agregar_carga_barra(mi, 1, { t = "P", a = 2, p = 3, dir = "LX" })
  ED.agregar_carga_barra(mi, 1, { t = "w", a = 1, b = 4, w1 = 3, w2 = 9, dir = "L" })
  comparar(mi, 1, 2.2, "inclinada, corte en tramo")
  comparar(mi, 1, 2, "inclinada, corte justo en 4 puntuales (P global x/y, L, LX)")
  -- cercha SIN cargas P/M/w en el vano: ambas mitades siguen siendo cercha; el nodo colineal sin una
  -- tercera barra es un mecanismo hasta conectarlo (el clasificador lo avisa)
  local mc = ED.ejemplo("Cercha")
  local m2 = ED.copiar(mc)
  local ok2 = ED.dividir_barra(m2, 1, 1.5)
  check(ok2 ~= nil, "cercha: divide la barra 1")
  eq(m2.barras[1].tipo, "cercha", "cercha dividida sin cargas: primera mitad cercha")
  eq(m2.barras[#m2.barras].tipo, "cercha", "cercha dividida sin cargas: segunda mitad cercha")
  eq(S.clasificar(m2).tipo, "inestable", "dos cerchas colineales sin tercera barra: inestable")
  eq(S.clasificar(mc).tipo, "isostatica", "la cercha original es isostatica")
  local ec = ED.agregar_barra(m2, ok2, 4, ED.PROPS_DEFECTO)   -- conectar el nodo nuevo al nodo 4
  m2.barras[ec].tipo = "cercha"
  check(S.clasificar(m2).tipo ~= "inestable", "conectado con una tercera barra deja de ser inestable")
  -- cercha CON carga puntual en el vano: portico con extremos articulados (equivalente), mismos desplazamientos
  local mc2 = ED.ejemplo("Cercha")
  ED.agregar_carga_barra(mc2, 1, { t = "P", a = 1, p = -5, dir = "GY" })
  local m2b = ED.copiar(mc2)
  check(ED.dividir_barra(m2b, 1, 1.5) ~= nil, "cercha cargada: divide la barra 1")
  eq(m2b.barras[1].tipo, "portico", "cercha cargada dividida: primera mitad portico")
  check(m2b.barras[1].rot_i and m2b.barras[#m2b.barras].rot_j and not m2b.barras[1].rot_j, "cercha cargada dividida: extremos articulados")
  local rc0, rc1 = S.resolver(mc2), S.resolver(m2b)
  check(rc0 ~= nil and rc1 ~= nil, "cercha cargada dividida se resuelve")
  if rc0 and rc1 then
    local peor = 0
    for i = 1, #mc2.nodos do
      peor = math.max(peor, math.abs(rc0.d[i].ux - rc1.d[i].ux), math.abs(rc0.d[i].uy - rc1.d[i].uy))
    end
    check(peor < 1e-9, "cercha cargada dividida: mismos desplazamientos nodales (" .. peor .. ")")
    local N0 = EE.eval(rc0, 1, 0.5)
    local N1 = EE.eval(rc1, 1, 0.5)
    near(N1, N0, "cercha cargada dividida: mismo axial", 1e-7)
  end
  -- errores
  local m3 = ED.copiar(mm)
  check(ED.dividir_barra(m3, 1, 0) == nil, "no divide en el nodo")
  check(ED.dividir_barra(m3, 1, 6) == nil, "no divide en el otro nodo")
  check(ED.dividir_barra(m3, 9, 1) == nil, "barra inexistente")
  eq(#m3.nodos, 2, "los errores no dejan nodos sueltos")
end

-- ------------------------------------------------------------ lista de cargas / editar / borrar
print("-- lista de cargas")
sin_resultados()
nuevo()
clic(0, 0); clic(6, 0); key("escape")
H.set_tool("carga")
clic(3, 0)
check(shown("Carga en barra 1: nueva"), "sin cargas: directo al tipo")
check(shown("Temperatura"), "el tipo Temperatura existe")
key("escape")
ED.agregar_carga_barra(modelo(), 1, { t = "P", a = 2, p = -10, dir = "GY" })
ED.agregar_carga_barra(modelo(), 1, { t = "w", a = 0, b = 4, w1 = -5, w2 = -8, dir = "GY" })
ED.agregar_carga_barra(modelo(), 1, { t = "M", a = 5, m = -3 })
clic(3, 0)
check(D.activo() ~= nil and shown("Cargas de la barra 1 (3)"), "con cargas: lista")
check(shown("+ Agregar carga"), "opcion Agregar")
check(shown("P 10 kN abajo a=2 m"), "descripcion de la puntual")
check(shown("w 5->8 kN/m 0-4 m abajo"), "descripcion de la trapezoidal")
check(shown("M 3 kN·m horario a=5 m"), "descripcion del momento")
check(shown("Borrar todas las cargas"), "opcion Borrar todas")
png("pol_lista_cargas")
key("escape")
-- tipo Temperatura
clic(3, 0); key("1"); key("5")
check(D.activo() ~= nil and shown("temperatura") and shown("du uniforme") and shown("alfa") and shown("h canto"), "dialogo de temperatura")
check(shown("(°C)") and shown("1e-6/°C") and shown("(cm)"), "unidades en el dialogo de temperatura")
key("enter")    -- du=20 dg=0 -> valido
do
  local c = modelo().barras[1].cargas[4]
  check(c and c.t == "T" and c.du == 20 and c.dg == 0, "T du=20 dg=0")
  near(c.alfa, 1.2e-5, "alfa por omision 12e-6", 1e-12)
end
H.deshacer()
clic(3, 0); key("1"); key("5")
typed("20"); key("down"); typed("10"); key("down"); key("down"); typed("40")
png("pol_dialogo_temperatura")
key("enter")
do
  local c = modelo().barras[1].cargas[4]
  check(c and c.t == "T" and c.du == 20 and c.dg == 10, "T du=20 dg=10")
  near(c.h, 0.4, "h = 40 cm = 0.4 m", 1e-12); near(c.alfa, 1.2e-5, "alfa", 1e-12)
end
check(shown("ΔT"), "etiqueta ΔT junto a la barra")
-- temperatura invalida
clic(3, 0); key("1"); key("5"); typed("0"); key("enter")
check(D.activo() ~= nil and shown("no puede ser cero"), "du=dg=0 se rechaza")
key("escape")
clic(3, 0); key("1"); key("5"); key("down"); typed("5"); key("down"); key("down"); typed("0"); key("enter")
check(D.activo() ~= nil and shown("canto h"), "dg sin canto se rechaza")
key("escape")
eq(#modelo().barras[1].cargas, 4, "los rechazos no agregan cargas")
-- la lista incluye la T
clic(3, 0)
check(shown("T du=20 dg=10 °C"), "descripcion de la temperatura")
key("escape")
-- editar la puntual
ED.reiniciar_historial()
local nundo = ED.n_undo()
clic(3, 0); key("2")
check(shown("P 10 kN abajo") and shown("Editar..."), "submenu de una carga")
key("1")
check(D.activo() ~= nil and shown("editar puntual"), "formulario de edicion")
key("down"); typed("25"); key("down"); key("right")   -- 25 kN, direccion Arriba
key("enter")
do
  local c = modelo().barras[1].cargas[1]
  check(c.t == "P" and c.p == 25 and c.dir == "GY" and c.a == 2, "puntual editada: +25 GY a=2")
  eq(#modelo().barras[1].cargas, 4, "editar no agrega ni quita")
  eq(ED.n_undo() - nundo, 1, "editar = un paso de deshacer")
end
H.deshacer()
near(modelo().barras[1].cargas[1].p, -10, "deshacer restaura la carga")
-- editar la trapezoidal (abre el formulario trapezoidal con sus valores)
clic(3, 0); key("3"); key("1")
check(shown("editar trapezoidal"), "w distinta en extremos: formulario trapezoidal")
check(shown("w1 en a") and shown("w2 en b"), "campos w1/w2")
key("escape")
-- borrar una sola
clic(3, 0); key("4"); key("2")
eq(#modelo().barras[1].cargas, 3, "borrar la momento (3a): quedan 3")
check(D.activo() ~= nil and shown("Cargas de la barra 1 (3)"), "tras borrar se reabre la lista")
check(not shown("M 3 kN·m"), "el momento ya no aparece")
key("escape")
for _, c in ipairs(modelo().barras[1].cargas) do check(c.t ~= "M", "se borro el momento y no otra carga") end
H.deshacer()
eq(#modelo().barras[1].cargas, 4, "deshacer el borrado")
-- Borrar todas desde la lista
clic(3, 0); key("6")
eq(#modelo().barras[1].cargas, 0, "Borrar todas")
H.deshacer()
-- ENTER sobre la barra seleccionada con Carga abre la lista
H.set_tool("carga"); H.sel = { t = "barra", i = 1 }
key("enter")
check(D.activo() ~= nil and shown("Cargas de la barra 1"), "ENTER con la barra seleccionada: lista de cargas")
key("escape")
-- ENTER (herramienta Seleccionar) > campo Cargas > Editar una a una
H.set_tool("sel"); H.sel = { t = "barra", i = 1 }
key("enter")
check(shown("Cargas (4)"), "propiedades de barra con el numero de cargas")
for _ = 1, 6 do key("down") end
key("right"); key("right"); key("enter")
check(D.activo() ~= nil and shown("Cargas de la barra 1"), "propiedades > Editar una a una abre la lista")
key("escape")
-- nodal: sin carga formulario directo; con carga editar/borrar
H.set_tool("carga")
clic(6, 0)
check(shown("Carga en el nodo 2"), "nodo sin carga: formulario")
key("down"); typed("-15"); key("down"); typed("4"); key("enter")
clic(6, 0)
check(D.activo() ~= nil and shown("Fy -15 kN") and shown("Mz 4 kN·m"), "nodo con carga: resumen en el titulo")
check(shown("Editar (Fx, Fy, Mz)") and shown("Borrar la carga del nodo"), "opciones editar y borrar")
key("1")
check(shown("Carga en el nodo 2"), "editar abre el formulario"); key("escape")
clic(6, 0); key("2")
eq(modelo().nodos[2].carga, nil, "borrar la carga nodal")
H.deshacer()
check(modelo().nodos[2].carga ~= nil, "deshacer la carga nodal borrada")
-- la carga termica se guarda y se restaura
do
  local saved2 = mock.save()
  H.nuevo()
  mock.restore(saved2)
  local tc
  for _, c in ipairs(modelo().barras[1].cargas) do if c.t == "T" then tc = c end end
  check(tc ~= nil and tc.du == 20 and tc.dg == 10, "on.save/on.restore conservan la carga T")
end

-- ------------------------------------------------------------------ unidades en los dialogos
print("-- unidades")
sin_resultados()
nuevo()
clic(0, 0); clic(6, 0); key("escape")
eq(U.actual, "kN-m", "unidades por omision")
H.set_unidades("N-m")
H.set_tool("sel"); H.sel = { t = "barra", i = 1 }
key("enter")
check(shown("E (Pa)") and shown("A (m²)") and shown("I (m4)"), "dialogo de barra en N-m")
check(D.activo().campos[1].buf == "2e+11", "E = 200 GPa = 2e11 Pa: " .. tostring(D.activo().campos[1].buf))
key("escape")
H.set_tool("carga"); clic(3, 0)
key("1")                                     -- puntual
check(shown("Valor P (N)"), "puntual: etiqueta en N")
check(D.activo().campos[2].buf == "10000", "valor por omision 10000 N")
key("enter")
near(modelo().barras[1].cargas[1].p, -10, "10000 N se guarda como -10 kN")
check(shown("10000 N"), "etiqueta de la carga en el lienzo: 10000 N")
H.set_unidades("tf-m")
check(shown("1 tf") or shown("1.02 tf"), "etiqueta del lienzo en tf: " .. tostring(select(2, mock.has_text("tf"))))
clic(3, 0)
check(shown("P 1.02 tf abajo a=3 m"), "descripcion en tf")
key("escape")
clic(3, 0); key("1"); key("1")
check(D.activo().campos[2].buf == "1", "valor por omision 1 tf")
key("down"); typed("2"); key("enter")
near(modelo().barras[1].cargas[2].p, -2 * 9.80665, "2 tf se guarda como -19.6133 kN", 1e-9)
H.set_tool("sel"); H.sel = { t = "barra", i = 1 }; key("enter")
check(shown("E (kgf/cm²)"), "E en kgf/cm2")
key("escape")
local sv = mock.save()
eq(sv.cfg.unidades, "tf-m", "on.save guarda cfg.unidades")
check(sv.modelo.barras[1].E > 1e8, "pero el modelo sigue en kN, m (E en kN/m2)")
H.set_unidades("kN-m")
mock.restore(sv)
eq(U.actual, "tf-m", "on.restore recupera las unidades")
-- apoyo elastico y asentamiento
H.set_tool("apoyo"); clic(0, 0); key("5")
check(shown("kx (tf/m)") and shown("kr (tf·m/rad)"), "resorte en tf")
key("escape")
H.set_unidades("N-m")
clic(0, 0); key("5")
check(shown("kx (N/m)") and shown("kr (N·m/rad)"), "resorte en N")
key("escape")
clic(0, 0); key("1"); clic(0, 0); key("6")
check(shown("dx (m, + derecha)") and shown("giro (rad, + antih.)"), "asentamiento en m y rad")
key("escape")
-- menu y teclas
H.set_unidades("kN-m")
key("q")
eq(U.actual, "N-m", "q cicla unidades"); key("q"); eq(U.actual, "tf-m", "q: tf-m"); key("q"); eq(U.actual, "kN-m", "q: vuelta a kN-m")
H.menu_unidades()
check(D.activo() ~= nil and shown("tf, m"), "menu de unidades")
key("3")
eq(U.actual, "tf-m", "el menu elige tf-m")
H.set_unidades("kN-m")

-- conversion consistente
near(U.de_interna("momento", 45), 45, "kN-m: 45"); H.set_unidades("N-m")
near(U.de_interna("momento", 45), 45000, "N-m: 45000"); H.set_unidades("tf-m")
near(U.de_interna("momento", 45), 4.588, "tf-m: 4.588...", 1e-3)
near(U.a_interna("fuerza", U.de_interna("fuerza", 12.5)), 12.5, "ida y vuelta", 1e-12)
check(U.num(U.de_interna("momento", 45)) == "4.589", "4.589 tf·m")
H.set_unidades("kN-m")

-- ------------------------------------------------------------------------- legibilidad
print("-- legibilidad")
-- atajos de la barra de herramientas fuera del icono
sin_resultados(); nuevo(); mock.paint()
for _, b in ipairs(H.botones) do
  if b.tecla then
    local ok, t = mock.has_text(b.tecla)
    local hallado = false
    for _, tt in ipairs(mock.screen_text()) do
      if tt.text == b.tecla and tt.size == 7 and tt.y < V.rect.y and tt.x >= b.x and tt.x < b.x + b.w then
        hallado = true
        check(tt.x >= b.x + 17, "atajo " .. b.tecla .. " no pisa el icono (x=" .. tt.x .. ", boton " .. b.x .. ")")
        check(tt.x + tt.w <= b.x + b.w + 1, "atajo " .. b.tecla .. " cabe en el boton")
      end
    end
    check(hallado, "atajo " .. b.tecla .. " dibujado")
  end
end
-- varias cargas en la misma barra y nodo: ninguna etiqueta de carga se encima con otra
local function etiquetas_carga()
  mock.paint()
  local out = {}
  for _, t in ipairs(mock.screen_text()) do
    local c = t.color
    if c[1] == 225 and c[2] == 100 and c[3] == 0 and t.size == 7 and t.y > 22 and t.y < mock.H - 16 then out[#out + 1] = t end
  end
  return out
end
local function sin_encimarse(label)
  local ts = etiquetas_carga()
  for i = 1, #ts do
    for j = i + 1, #ts do
      local a, b = ts[i], ts[j]
      local solape = a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + 10 and b.y < a.y + 10
      check(not solape, label .. ": etiquetas encimadas '" .. a.text .. "' y '" .. b.text .. "'")
    end
  end
  return #ts
end
sin_resultados(); nuevo()
clic(0, 0); clic(6, 0); key("escape")
V.encuadrar(modelo())
do
  local mm = modelo()
  ED.agregar_carga_barra(mm, 1, { t = "w", a = 0, b = 6, w1 = -10, w2 = -10, dir = "GY" })
  ED.agregar_carga_barra(mm, 1, { t = "P", a = 1.5, p = -30, dir = "GY" })
  ED.agregar_carga_barra(mm, 1, { t = "P", a = 2, p = -25, dir = "GY" })
  ED.agregar_carga_barra(mm, 1, { t = "P", a = 2.5, p = -12.5, dir = "GY" })
  ED.agregar_carga_barra(mm, 1, { t = "M", a = 3, m = 12 })
  ED.agregar_carga_barra(mm, 1, { t = "T", du = 20, dg = 10, alfa = 1.2e-5, h = 0.3 })
  ED.set_carga_nodo(mm, 2, 8, -15, 4)
  ED.set_carga_nodo(mm, 1, -6, -9, -5)
  ED.set_apoyo_tipo(mm, 1, "articulado"); ED.set_apoyo_tipo(mm, 2, "rodilloX")
  mm.barras[1].cargas[#mm.barras[1].cargas + 1] = { t = "w", a = 3, b = 6, w1 = -4, w2 = -12, dir = "GY" }
  ED.cambio()
end
H.set_tool("sel"); H.sel = nil
local nlab = sin_encimarse("viga con varias cargas")
check(nlab >= 8, "se dibujan todas las etiquetas (" .. nlab .. ")")
dentro("viga con varias cargas")
png("pol_cargas_apiladas")
-- la misma viga en N-m (etiquetas mas anchas) tampoco se encima
H.set_unidades("N-m"); sin_encimarse("viga con varias cargas en N-m"); dentro("cargas en N-m")
H.set_unidades("kN-m")
-- division de barra: captura
sin_resultados(); nuevo()
clic(0, 0); clic(6, 0); key("escape")
do
  local mm = modelo()
  ED.set_apoyo_tipo(mm, 1, "articulado"); ED.set_apoyo_tipo(mm, 2, "rodilloX")
  ED.agregar_carga_barra(mm, 1, { t = "w", a = 0, b = 6, w1 = -6, w2 = -10, dir = "GY" })
  ED.agregar_carga_barra(mm, 1, { t = "P", a = 4.5, p = -20, dir = "GY" })
  ED.cambio()
end
V.encuadrar(modelo())
H.set_tool("nodo")
mock.move(px(3), py(0) + 1)
clic(3, 0)
check(shown("divide la barra"), "mensaje de division")
mock.move(px(1.5), py(0))
dentro("division de barra")
png("pol_dividir_barra")
-- reencuadre: un nodo movido que sale de la vista vuelve a verse
sin_resultados(); H.ejemplo("Viga apoyada"); H.encuadrar()
H.set_tool("sel")
clic(6, 0)
key("enter")
typed("60"); key("enter")
do
  local sx, sy = V.a_pantalla(modelo().nodos[2].x, modelo().nodos[2].y)
  check(sx >= V.rect.x and sx <= V.rect.x + V.rect.w and sy >= V.rect.y and sy <= V.rect.y + V.rect.h,
    "el nodo movido a x=60 queda dentro del lienzo (sx=" .. sx .. ")")
end
H.ejemplo("Viga apoyada"); H.encuadrar()
mock.move(px(6), py(0))
mock.drag(px(6), py(0), V.rect.x + V.rect.w - 4, py(0), 4)
do
  local sx = V.a_pantalla(modelo().nodos[2].x, modelo().nodos[2].y)
  check(sx <= V.rect.x + V.rect.w - 14 and sx >= V.rect.x + 14, "tras arrastrar al borde se reencuadra (sx=" .. sx .. ")")
end
H.ejemplo("Viga apoyada"); H.encuadrar()
V.fijar_snap(0.5)
H.sel = { t = "nodo", i = 2 }
for _ = 1, 40 do key("right") end
do
  local sx = V.a_pantalla(modelo().nodos[2].x, modelo().nodos[2].y)
  check(sx <= V.rect.x + V.rect.w - 14, "con flechas el nodo no se sale de la vista (sx=" .. sx .. ")")
end

-- menu reorganizado
print("-- menus")
do
  local titulos = {}
  for _, mn in ipairs(mock.toolpalette_menu) do titulos[#titulos + 1] = mn[1] end
  check(table.concat(titulos, ","):find("Ajustes"), "menu Ajustes")
  local n = 0
  for _, mn in ipairs(mock.toolpalette_menu) do
    n = n + #mn - 1
    check(#mn - 1 <= 30, "menu '" .. mn[1] .. "' con <= 30 items")
  end
  check(#mock.toolpalette_menu <= 15, "toolpalette: " .. #mock.toolpalette_menu .. " menus (<= 15)")
  local hay_unid = false
  for _, mn in ipairs(mock.toolpalette_menu) do
    for i = 2, #mn do if mn[i][1]:find("Unidades") then hay_unid = true end end
  end
  check(hay_unid, "Unidades en el menu")
end

-- =================================================================== v1.1: modo Marco / Cercha
print("-- v1.1: selector Marco | Cercha")
sin_resultados()
-- cercha de la captura del usuario: dibujada con la herramienta Barra y clics
local function dibujar_captura(modo)
  nuevo()
  ED.set_tipo(modo)
  V.auto = true     -- como el usuario: vista automatica (se encuadra al terminar cada cadena)
  clic(0, 0); clic(2, 0); clic(4, 0); key("escape")
  clic(1, 1); clic(2, 1); clic(3, 1); key("escape")
  clic(0, 0); clic(1, 1); key("escape")
  clic(1, 1); clic(2, 0); key("escape")
  clic(2, 0); clic(2, 1); key("escape")
  clic(2, 0); clic(3, 1); key("escape")
  clic(3, 1); clic(4, 0); key("escape")
  local mm = modelo()
  ED.set_apoyo_tipo(mm, 1, "articulado"); ED.set_apoyo_tipo(mm, 2, "rodilloX")
  ED.set_carga_nodo(mm, 3, 0, -10, 0)
  ED.cambio()
end
nuevo(); ED.set_tipo("portico"); H.sel = nil
check(shown("Marco") and shown("Cercha"), "selector: pastillas Marco y Cercha visibles en modelado")
do
  local sl = H.selector
  check(sl.x >= 0 and sl.y >= V.rect.y and sl.x + sl.w <= 120, "selector en la esquina superior izquierda del lienzo")
  mock.paint()
  local hallado = false
  for _, t in ipairs(mock.screen_text()) do
    if t.text == "Cercha" and t.y >= sl.y and t.y < sl.y + sl.h then
      hallado = t.x >= sl.xc and t.x + t.w <= sl.xc + sl.wc and t.y + t.h <= sl.y + sl.h + 2
    end
  end
  check(hallado, "texto Cercha dentro de su pastilla")
  -- clic con el touchpad en la pastilla Cercha / Marco, sin crear nodos
  mock.move(sl.xc + 8, sl.y + 6); mock.click(sl.xc + 8, sl.y + 6)
  eq(ED.props.tipo, "cercha", "clic en la pastilla Cercha fija el modo")
  eq(#modelo().nodos, 0, "el clic en el selector no crea nodos")
  check(shown("Modo Cercha"), "aviso del cambio de modo")
  eq(H.texto_estado(), "Cercha: clic nodo A (K cambia)", "estado de Barra dice Cercha")
  mock.move(sl.xm + 8, sl.y + 6); mock.click(sl.xm + 8, sl.y + 6)
  eq(ED.props.tipo, "portico", "clic en la pastilla Marco fija el modo")
  eq(H.texto_estado(), "Marco: clic nodo A (K cambia)", "estado de Barra dice Marco")
  png("v11_selector_marco")
end
-- teclas: k alterna; b estando ya en Barra alterna
H.set_tool("barra"); ED.set_tipo("portico")
key("k"); eq(ED.props.tipo, "cercha", "k alterna a cercha")
key("k"); eq(ED.props.tipo, "portico", "k alterna a marco")
key("b"); eq(ED.props.tipo, "cercha", "b estando en Barra alterna (b b)")
key("b"); eq(ED.props.tipo, "portico", "b b b vuelve")
H.set_tool("sel"); key("b"); eq(H.tool, "barra", "b desde otra herramienta solo elige Barra")
eq(ED.props.tipo, "portico", "...sin alternar el modo")
-- cada barra nueva nace con el modo
ED.set_tipo("cercha"); clic(0, 0); clic(3, 0); key("escape")
eq(modelo().barras[1].tipo, "cercha", "barra nueva en modo Cercha es cercha")
ED.set_tipo("portico"); clic(3, 0); clic(3, 3); key("escape")
eq(modelo().barras[2].tipo, "portico", "barra nueva en modo Marco es portico")
-- ENTER aplica el modo tambien a la barra seleccionada
H.set_tool("sel"); clic(1.5, 0)
check(H.sel and H.sel.t == "barra" and H.sel.i == 1, "barra 1 seleccionada")
key("k")   -- marco -> cercha, la barra 1 ya es cercha: no hay oferta
check(not shown("ENTER: aplicar"), "sin oferta si la barra ya tiene ese tipo")
key("k")   -- cercha -> marco: la barra 1 (cercha) difiere
check(shown("ENTER: aplicar"), "oferta ENTER: aplicar tambien a la barra seleccionada")
check(D.activo() == nil, "sin dialogo bloqueante")
key("enter")
eq(modelo().barras[1].tipo, "portico", "ENTER aplica el tipo a la barra seleccionada")
H.deshacer(); eq(modelo().barras[1].tipo, "cercha", "U restaura el tipo de la barra")
-- la oferta caduca con cualquier otra accion
key("k"); key("k"); H.sel = { t = "barra", i = 1 }; key("k")
mock.move(5, 100); key("k"); key("k")

print("-- v1.1: cercha de la captura en modo Cercha")
sin_resultados()
dibujar_captura("cercha")
do
  local mm = modelo()
  eq(#mm.nodos, 6, "captura: 6 nodos"); eq(#mm.barras, 9, "captura: 9 barras")
  local todas = true
  for _, b in ipairs(mm.barras) do if b.tipo ~= "cercha" then todas = false end end
  check(todas, "captura: todas las barras son cercha")
  check(D.activo() == nil, "dibujar la cercha no abre dialogos")
  eq(S.clasificar(mm).tipo, "isostatica", "captura en modo Cercha: isostatica")
  H.set_tool("sel"); H.sel = nil
  png("v11_cercha_modelado")
  check(shown("Isostatica"), "barra de estado: Isostatica")
  key("r")
  check(D.activo() == nil, "resolver la cercha no abre dialogos (ya es cercha)")
  check(shown("Isostatica"), "resultados: Isostatica")
  -- encuadre al entrar a resultados: el modelo ocupa >= 60 % del ancho util y queda centrado
  local x0, y0, x1, y1 = V.bbox_pantalla(mm)
  local aw = V.util()
  check((x1 - x0) >= 0.6 * aw, "tras r el modelo ocupa >= 60% del ancho util: " .. (x1 - x0) .. " de " .. aw)
  near((x0 + x1) / 2, V.rect.x + V.rect.w / 2, "modelo centrado en x", 2)
  near((y0 + y1) / 2, V.rect.y + V.rect.h / 2, "modelo centrado en y", 2)
  key("n"); png("v11_cercha_N")
  key("m"); png("v11_cercha_M")
  H.salir_resultados()
end

print("-- v1.1: encuadre automatico y manual")
sin_resultados()
nuevo(); V.auto = true
ED.set_tipo("cercha")
clic(0, 0); clic(4, 0)       -- cadena en curso: la camara no se mueve entre clics
local s_antes, ox_antes = V.s, V.ox
clic(2, 2)
eq(V.s, s_antes, "entre clics de una cadena no cambia la escala"); eq(V.ox, ox_antes, "... ni el origen")
clic(0, 0)
key("escape")
check(V.s ~= s_antes, "al terminar la cadena (ESC) se encuadra con vista automatica")
check(V.auto, "el encuadre deja V.auto = true")
-- zoom manual: V.auto = false y r no reencuadra mientras el modelo se vea
ED.set_apoyo_tipo(modelo(), 1, "articulado"); ED.set_apoyo_tipo(modelo(), 2, "rodilloX")
ED.set_carga_nodo(modelo(), 3, 0, -10, 0); ED.cambio()
H.zoom(1 / 1.4)
check(not V.auto, "zoom manual apaga V.auto")
local s_man = V.s
do
  local x0, y0, x1, y1 = V.bbox_pantalla(modelo())
  check(x0 >= V.rect.x + 4 and x1 <= V.rect.x + V.rect.w - 4 and (x1 - x0) >= 0.4 * V.util(), "el modelo sigue visible y > 40%")
end
key("r")
check(Res.modo ~= nil, "resuelve")
eq(V.s, s_man, "tras zoom manual, r no cambia la escala")
H.salir_resultados()
V.pan(10, 0); check(not V.auto, "pan manual apaga V.auto")
-- modelo diminuto o fuera de vista: r si encuadra aunque la vista sea manual
V.zoom(0.1, V.rect.w / 2, V.rect.h / 2)
key("r")
do
  local a, b, c2, d = V.bbox_pantalla(modelo())
  check((c2 - a) >= 0.6 * V.util(), "modelo diminuto: r encuadra")
end
H.salir_resultados()
V.pan(5000, 0)
key("r")
do
  local a, b, c2, d = V.bbox_pantalla(modelo())
  check(a >= V.rect.x and c2 <= V.rect.x + V.rect.w, "modelo fuera de vista: r lo encuadra")
end
H.salir_resultados()

print("-- v1.1: Archivo > Nuevo pregunta el tipo")
sin_resultados()
ED.set_tipo("portico")
H.nuevo_menu()
check(D.activo() ~= nil and shown("Qué vas a dibujar"), "Nuevo pregunta que vas a dibujar")
check(shown("Viga / Marco") and shown("Cercha"), "opciones Viga / Marco y Cercha")
png("v11_nuevo_pregunta")
key("2")
eq(ED.props.tipo, "cercha", "elegir 2 fija el modo Cercha")
eq(#modelo().nodos, 0, "y el modelo es nuevo")
H.nuevo_menu(); key("escape")
eq(ED.props.tipo, "cercha", "ESC mantiene el modo actual")
check(D.activo() == nil, "ESC cierra el selector")
H.nuevo_menu(); key("1"); eq(ED.props.tipo, "portico", "elegir 1 fija Viga / Marco")
-- el item del menu Archivo > Nuevo abre el selector
do
  local f
  for _, mn in ipairs(mock.toolpalette_menu) do
    if mn[1] == "Archivo" then for i = 2, #mn do if mn[i][1] == "Nuevo" then f = mn[i][2] end end end
  end
  check(f ~= nil, "menu Archivo > Nuevo existe")
  f(); check(D.activo() ~= nil, "el item Nuevo abre el selector de tipo"); key("escape")
end

print("-- v1.1: convertir todo, parece_cercha y sugerencia")
sin_resultados()
dibujar_captura("portico")
do
  local mm = modelo()
  local todas = true
  for _, b in ipairs(mm.barras) do if b.tipo ~= "portico" then todas = false end end
  check(todas, "captura como marco: todas porticos")
  eq(S.clasificar(mm).tipo, "hiperestatica", "captura como marco: hiperestatica")
  check(ED.parece_cercha(mm), "parece_cercha: captura dibujada como marco")
  -- negativos
  local c1 = ED.copiar(mm); ED.agregar_carga_barra(c1, 1, { t = "w", a = 0, b = 2, w1 = -5, w2 = -5, dir = "GY" })
  check(not ED.parece_cercha(c1), "parece_cercha: falso con carga en barra")
  local c2 = ED.copiar(mm); ED.set_carga_nodo(c2, 3, 0, -10, 3)
  check(not ED.parece_cercha(c2), "parece_cercha: falso con momento nodal")
  local c3 = ED.copiar(mm); ED.set_apoyo_tipo(c3, 1, "empotrado")
  check(not ED.parece_cercha(c3), "parece_cercha: falso con empotramiento")
  local c4 = ED.copiar(mm); c4.barras[1].rot_i = true
  check(not ED.parece_cercha(c4), "parece_cercha: falso con rotulas")
  local c5 = ED.copiar(mm); c5.barras[2].tipo = "cercha"
  check(not ED.parece_cercha(c5), "parece_cercha: falso si ya hay barras cercha")
  local c6 = ED.copiar(mm); while #c6.barras > 2 do table.remove(c6.barras) end
  check(not ED.parece_cercha(c6), "parece_cercha: falso con < 3 barras")
  local c7 = ED.ejemplo("Portal")
  check(not ED.parece_cercha(c7), "parece_cercha: falso en el portal")
  local c8 = ED.copiar(mm); ED.set_apoyo_tipo(c8, 2, "libre"); ED.set_apoyo_tipo(c8, 1, "libre")
  check(not ED.parece_cercha(c8), "parece_cercha: falso si la copia convertida seria inestable")
  -- sugerencia al resolver: una sola vez por modelo
  H.set_tool("sel"); H.sel = nil
  key("r")
  check(D.activo() ~= nil and shown("Parece una cercha"), "al resolver aparece la sugerencia")
  check(shown("Convertir") and shown("Mantener marco"), "con los botones Convertir y Mantener marco")
  png("v11_sugerencia_cercha")
  key("2")
  for _, b in ipairs(modelo().barras) do eq(b.tipo, "portico", "Mantener marco no cambia nada") end
  H.salir_resultados(); key("r")
  check(D.activo() == nil, "la sugerencia no se repite para el mismo modelo")
  H.salir_resultados()
  -- convertir desde la sugerencia: un solo paso de deshacer
  H.nuevo(); dibujar_captura("portico")
  key("r")
  check(D.activo() ~= nil, "modelo nuevo: la sugerencia vuelve a aparecer")
  key("1")
  for _, b in ipairs(modelo().barras) do eq(b.tipo, "cercha", "Convertir pasa todas a cercha") end
  eq(Res.clasif_texto(), "Isostatica", "resultado tras convertir: isostatica")
  H.salir_resultados()
  H.deshacer()
  for _, b in ipairs(modelo().barras) do eq(b.tipo, "portico", "un solo U restaura todas las barras") end
  -- Ajustes: convertir todo
  H.convertir_todo("cercha")
  for _, b in ipairs(modelo().barras) do eq(b.tipo, "cercha", "convertir todo a cercha") end
  eq(ED.props.tipo, "cercha", "y el modo de dibujo pasa a Cercha")
  H.convertir_todo("portico")
  for _, b in ipairs(modelo().barras) do eq(b.tipo, "portico", "convertir todo a marco") end
  H.deshacer(); H.deshacer()
  for _, b in ipairs(modelo().barras) do eq(b.tipo, "portico", "dos U vuelven al marco original") end
  local ajustes
  for _, mn in ipairs(mock.toolpalette_menu) do if mn[1] == "Ajustes" then ajustes = mn end end
  local hay_c, hay_m = false, false
  for i = 2, #ajustes do
    if ajustes[i][1] == "Convertir todo a cercha" then hay_c = true end
    if ajustes[i][1] == "Convertir todo a marco" then hay_m = true end
  end
  check(hay_c and hay_m, "menu Ajustes: convertir todo a cercha / marco")
end

print("-- v1.1: textos de estado")
sin_resultados()
do
  local function revisar(label)
    mock.paint()
    local ops = mock.last_ops
    for _, t in ipairs(mock.screen_text(ops)) do
      if t.y >= mock.H - 16 then
        check(t.text:sub(-2) ~= "..", label .. ": texto de estado recortado '" .. t.text .. "'")
        check(t.x >= 0 and t.x + t.w <= mock.W, label .. ": texto de estado fuera de pantalla '" .. t.text .. "'")
      end
    end
  end
  H.nuevo(); V.auto = false
  mock.move(150, 100)
  for _, tool in ipairs({ "sel", "nodo", "barra", "apoyo", "carga" }) do
    H.set_tool(tool); revisar("herramienta " .. tool)
    local est = H.texto_estado()
    check(#est <= 34, "texto de herramienta <= 34 caracteres: '" .. est .. "' (" .. #est .. ")")
  end
  H.set_tool("barra"); clic(0, 0); revisar("barra: nodo B")
  check(#H.texto_estado() <= 34, "estado barra B <= 34: " .. H.texto_estado())
  key("escape")
  dibujar_captura("portico"); H.set_tool("sel"); H.sel = nil
  mock.move(150, 100); revisar("captura marco")
  H.sel = { t = "barra", i = 3 }; revisar("barra seleccionada")
  check(#H.texto_estado() <= 34, "estado barra sel <= 34: " .. H.texto_estado())
  H.sel = { t = "nodo", i = 6 }; revisar("nodo seleccionado")
  check(#H.texto_estado() <= 34, "estado nodo sel <= 34: " .. H.texto_estado())
  -- la clasificacion siempre se ve; las coordenadas se omiten si no caben
  check(shown("Hiperestatica"), "clasificacion visible en el estado")
  H.sel = nil
  for _, ej in ipairs(ED.ejemplos) do
    H.ejemplo(ej); mock.move(150, 100); revisar("ejemplo " .. ej)
    key("r"); if D.activo() then key("escape") end
    for _, v in ipairs({ "r", "n", "v", "m", "d", "t", "e" }) do key(v); revisar("resultados " .. ej .. " " .. v) end
    H.salir_resultados()
  end
  -- mensajes tipicos
  H.nuevo(); V.auto = false; H.set_tool("barra")
  clic(0, 0); clic(3, 0); revisar("mensaje barra creada")
  key("escape"); revisar("mensaje cadena terminada")
  V.vista_inicial(); V.auto = false
  H.set_tool("nodo"); clic(1.5, 0); revisar("mensaje dividir")
  H.deshacer(); revisar("mensaje deshecho")
  H.set_modo("cercha"); revisar("mensaje modo")
  H.set_tool("sel"); clic(1.5, 0); H.set_modo("portico"); revisar("mensaje modo con barra")
  H.convertir_todo("cercha"); revisar("mensaje convertir")
end

print("-- v1.1: Acerca de, autor y version")
sin_resultados()
do
  local ayuda
  for _, mn in ipairs(mock.toolpalette_menu) do if mn[1] == "Ayuda" then ayuda = mn end end
  local f
  for i = 2, #ayuda do if ayuda[i][1] == "Acerca de" then f = ayuda[i][2] end end
  check(f ~= nil, "menu Ayuda > Acerca de")
  f()
  check(D.activo() ~= nil, "Acerca de abre una pantalla")
  check(shown("Estructural v1.1"), "Acerca de: version v1.1")
  check(shown("Autor: Adrián Castro Ramírez"), "Acerca de: autor con acentos")
  check(shown("Euler-Bernoulli"), "Acerca de: supuestos")
  dentro("acerca de")
  png("v11_acerca_de")
  key("escape")
  H.ayuda()
  for _ = 1, 60 do key("down") end
  check(shown("Estructural v1.1 · Adrián Castro Ramírez"), "Guia rapida: autor al pie")
  key("escape")
  H.nuevo()
  mock.paint()
  check(shown("Estructural v1.1 · Adrián Castro Ramírez"), "pantalla de inicio vacia muestra autor y version")
  dentro("inicio vacio")
  png("v11_inicio_vacio")
  local ok, t = mock.has_text("Adrián Castro Ramírez")
  check(ok and t.size == 7, "autor en 7 pt")
  for _, mn in ipairs(mock.toolpalette_menu) do
    check(#mn - 1 <= 30, "menu '" .. mn[1] .. "' <= 30 items (" .. (#mn - 1) .. ")")
  end
end

-- basura por paint con el selector y las cerchas dibujadas (limite igual que antes)
do
  dibujar_captura("cercha"); H.set_tool("sel"); H.sel = nil
  local gcc = env.collectgarbage
  local noop, w30, h12 = function() end, function() return 30 end, function() return 12 end
  local nulo = setmetatable({}, { __index = function(_, k)
    if k == "getStringWidth" then return w30 end
    if k == "getStringHeight" then return h12 end
    return noop
  end })
  env.on.paint(nulo); gcc("collect")
  local m0 = gcc("count")
  for i = 1, 100 do env.on.paint(nulo) end
  local por_paint = (gcc("count") - m0) / 100
  print(string.format("   basura por on.paint (captura cercha, modelado): %.2f KB", por_paint))
  check(por_paint < 3, "on.paint (modelado, cercha con selector) genera poca basura: " .. por_paint .. " KB")
end

-- PNG adicionales: estados representativos
nuevo()
clic(0, 0); clic(6, 0); key("escape")
key("a"); clic(0, 0); key("1"); clic(6, 0); key("2")
key("c"); clic(3, 0); key("2"); key("enter")
H.set_tool("sel"); clic(3, 0)
png("05_flujo_viga")
H.ejemplo("Portal"); png("06_portal_dialogo_carga")
H.set_tool("carga"); clic(0, 4); mock.paint(); png("07_carga_nodal")
key("escape")
H.ayuda(); png("08_ayuda"); key("escape")

print(string.format("== test_ui: %d comprobaciones, %d fallo(s)", checks, fails))
if #pngs > 0 then print("PNG en build/png/: " .. #pngs) end
os.exit(fails == 0 and 0 or 1)
