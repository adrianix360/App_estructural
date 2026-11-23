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
  eq(table.concat(titulos, ","), "Archivo,Herramientas,Vista,Propiedades globales,Ayuda", "menus")
  local n_items = 0
  for _, m in ipairs(mock.toolpalette_menu) do n_items = n_items + #m - 1 end
  check(n_items <= 30 and #mock.toolpalette_menu <= 15, "limites de toolpalette (<=30 items)")
end
check(shown("Modelo vacio"), "pantalla de bienvenida")
check(shown("Barra - Clic en el nodo A"), "barra de estado con instruccion")
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
clic(2, 0); key("1")
check(shown("desde nodo"), "formulario de puntual")
key("down"); typed("25"); key("enter")
local p = modelo().barras[1].cargas[2]
check(p and p.t == "P" and p.p == -25 and p.dir == "GY", "P = -25 GY (abajo)")
near(p.a, 2, "a tomado del clic (snap)")
-- momento y trapezoidal
clic(3, 0); key("4"); key("enter")
eq(modelo().barras[1].cargas[3].t, "M", "momento")
clic(3, 0); key("3")
key("down"); key("down"); key("down"); typed("12"); key("enter")
local tz = modelo().barras[1].cargas[4]
check(tz and tz.t == "w" and tz.w1 == 0 and tz.w2 == -12, "trapezoidal 0 -> -12")
-- error de validacion mantiene el dialogo
clic(3, 0); key("1")
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
clic(3, 0); key("5")
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
key("k"); check(V.snap_i ~= si, "k cicla el snap")
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
  print("   (core.solver presente: ver mensaje de estado)")
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
local nulo = setmetatable({}, { __index = function(_, k)
  if k == "getStringWidth" then return function() return 30 end end
  if k == "getStringHeight" then return function() return 12 end end
  return function() end
end })
env.on.paint(nulo)
gcc("collect")
local m0 = gcc("count")
for i = 1, 100 do env.on.paint(nulo) end
local m1 = gcc("count")
local por_paint = (m1 - m0) / 100
print(string.format("   basura por on.paint (gc nulo, cercha): %.2f KB", por_paint))
check(por_paint < 8, "on.paint genera poca basura: " .. por_paint .. " KB")

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
