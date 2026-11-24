-- test_resultados.lua - Pantalla de resultados con raton/teclado simulados (tests/mock_nspire.lua).
-- Uso: desde la raiz, tras `python -I tools/build.py --no-tns` (lo hace tools/run_tests.sh).
-- Genera PNG res_*.png en build/png/ (no versionado) si hay python con Pillow.
local mock = dofile("tests/mock_nspire.lua")
local env = mock.load_app("build/app.lua")
local S = require("core.solver")
local P = require("core.poly")
local EE = require("core.esfuerzos")

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
local R = env.require("ui.resultados")
local num = R.num

pcall(os.execute, "mkdir build\\png 2>nul")

local function key(k) mock.key(k) end
local function shown(s) mock.paint(); return (mock.has_text(s)) end
local function px(x) return math.floor(V.ox + x * V.s + 0.5) end
local function py(y) return math.floor(V.oy - y * V.s + 0.5) end
local pngs = {}
local function png(name)
  mock.paint()
  mock.dump_ops("build/png/" .. name .. ".json")
  os.execute('python -I tools/render_png.py build/png/' .. name .. '.json build/png/' .. name .. '.png --scale 2 >nul 2>&1')
  pngs[#pngs + 1] = "build/png/" .. name .. ".png"
end
local function dentro(label)
  mock.paint()
  for _, t in ipairs(mock.screen_text()) do
    local ok = t.x >= 0 and t.x + t.w <= mock.W + 2 and t.y >= 0 and t.y + t.h <= mock.H + 2
    check(ok, label .. ": texto fuera de pantalla '" .. t.text .. "' x=" .. t.x .. " w=" .. t.w .. " y=" .. t.y)
  end
end
-- Textos de la barra de estado (ultimos 16 px): no deben pisarse entre si
local function estado_sin_solape(label)
  mock.paint()
  local tt = {}
  for _, t in ipairs(mock.screen_text()) do
    if t.y >= mock.H - 16 then tt[#tt + 1] = t end
  end
  for i = 1, #tt do
    for j = i + 1, #tt do
      local a, b = tt[i], tt[j]
      local solape = a.x < b.x + b.w and b.x < a.x + a.w
      check(not solape, label .. ": textos de la barra de estado se pisan '" .. a.text .. "' / '" .. b.text .. "'")
    end
  end
end
local function ir(ejemplo)
  if R.modo then H.salir_resultados() end
  H.ejemplo(ejemplo)
  H.encuadrar()
  V.fijar_snap(0.5)
  key("r")
end
local function sin_error(label)
  local ok, err = pcall(mock.paint)
  check(ok, label .. ": paint fallo: " .. tostring(err))
  return ok
end

-- gc nulo con funciones compartidas (para medir basura sin falsearla)
local gcc = env.collectgarbage
local noop, w30, h12 = function() end, function() return 30 end, function() return 12 end
local nulo = setmetatable({}, { __index = function(_, k)
  if k == "getStringWidth" then return w30 end
  if k == "getStringHeight" then return h12 end
  return noop
end })
local function basura_paint()
  env.on.paint(nulo)
  gcc("collect")
  local m0 = gcc("count")
  for _ = 1, 50 do env.on.paint(nulo) end
  return (gcc("count") - m0) / 50
end

-- =================================================================== poly.tostring_sig
print("-- poly.tostring_sig")
eq(P.tostring_sig({ 0, 30, -5 }, "x", 4), "-5*x^2+30*x", "polinomio simple")
eq(P.tostring_sig({ 0, 0, 0 }, "x", 4), "0", "polinomio nulo")
eq(P.tostring_sig({ 1.23456789, 0, 2 }, "x", 4), "2*x^2+1.235", "4 cifras significativas")
eq(P.tostring_sig({ 0, 0, 0, 1.23456e-5 }, "x", 4), "1.235e-5*x^3", "notacion cientifica")
eq(P.tostring_sig({ 0, 0, 0, -1.23456e-5 }, "x", 4, true), "-1.235*10^(-5)*x^3", "modo CAS sin 'e'")
eq(P.tostring_sig({ 0, 1e-14, 3 }, "x", 4, false, 1), "3*x^2", "descarta ruido numerico")
eq(P.tostring_sig({ 0, 1, 1 }, "x", 4), "x^2+x", "coeficiente 1 omitido")
do
  -- el texto se puede evaluar y coincide con el polinomio (4 cifras)
  local p = { 12.3456789, -0.00123456, 1234.56789, -2e-7, 5e5 }
  local f = loadstring("local x = ... ; return " .. P.tostring_sig(p, "x", 4))
  for _, x in ipairs({ 0.3, 1.1, 2.7 }) do
    near(f(x) / P.eval(p, x), 1, "texto evaluable en x=" .. x, 2e-3)
  end
end

-- =================================================================== entrada al modo
print("-- entrada / salida")
H.nuevo()
key("r")
eq(R.modo, nil, "modelo vacio: no entra en resultados")
check(shown("Crea al menos una barra"), "mensaje accionable con modelo vacio")

H.ejemplo("Viga apoyada"); H.set_tool("barra"); H.encuadrar()
key("r")
eq(R.modo, "reac", "r entra en modo resultados (reacciones)")
check(R.activo(), "hay resultados vigentes")
eq(H.tool, "sel", "herramienta sel mientras hay resultados")
eq(#H.botones, 10, "barra de herramientas de resultados (10 botones)")
do
  local ids = {}
  for _, b in ipairs(H.botones) do ids[#ids + 1] = b.id end
  eq(table.concat(ids, ","), "r_reac,r_N,r_V,r_M,r_def,r_tabla,r_ecs,r_mas,r_menos,r_volver", "iconos de resultados")
  for _, b in ipairs(H.botones) do
    check(b.x >= 0 and b.x + b.w <= mock.W and b.y + b.h <= V.rect.y, "boton dentro de la barra: " .. b.id)
  end
end
check(shown("Isostatica"), "clasificacion en la barra de estado: Isostatica")
estado_sin_solape("reac")
key("escape")
eq(R.modo, nil, "ESC vuelve a modelar")
eq(#H.botones, 11, "iconos de modelado de nuevo")
eq(H.tool, "barra", "se restaura la herramienta anterior (Barra)")
check(shown("Isostatica"), "clasificacion visible tambien en modo modelado")

-- teclas de vista y botones
ir("Viga apoyada")
local mapa = { n = "N", v = "V", m = "M", d = "def", t = "tabla", e = "ecs", r = "reac" }
for k, v in pairs(mapa) do
  key(k)
  eq(R.modo, v, "tecla " .. k)
  sin_error("vista " .. v)
  dentro("vista " .. v)
end
key("r"); key("tab")
eq(R.modo, "N", "TAB avanza a la vista siguiente")
for _, b in ipairs(H.botones) do
  if b.vista then
    mock.click(b.x + 3, b.y + 3)
    eq(R.modo, b.vista, "clic en boton " .. b.id)
  end
end
mock.click(H.botones[#H.botones].x + 3, 3)
eq(R.modo, nil, "boton Modelar vuelve")
ir("Viga apoyada"); key("a")
eq(R.modo, nil, "tecla a sale de resultados")
eq(H.tool, "apoyo", "y activa la herramienta Apoyo")
H.set_tool("sel")

-- =================================================================== reacciones
print("-- reacciones")
local function reacciones_ok(nombre, completo)
  ir(nombre)
  key("r")
  local res = S.resolver(ED.m)
  mock.paint()
  local esperadas = {}
  for _, rc in pairs(res.reac) do
    esperadas["Rx=" .. num(rc.rx) .. " kN"] = true
    esperadas["Ry=" .. num(rc.ry) .. " kN"] = true
    esperadas["Mz=" .. num(rc.mz or 0) .. " kN·m"] = true
  end
  local vistas = 0
  for _, t in ipairs(mock.screen_text()) do
    if t.text:match("^R[xy]=.* kN$") or t.text:match("^Mz=.* kN·m$") then
      vistas = vistas + 1
      check(esperadas[t.text], nombre .. ": reaccion mostrada '" .. t.text .. "' no coincide con S.resolver")
    end
  end
  check(vistas >= 1, nombre .. ": se muestran reacciones")
  if completo then
    for txt in pairs(esperadas) do
      if not txt:match("=0 kN") and not txt:match("=0 kN·m") then
        check(mock.has_text(txt), nombre .. ": falta la reaccion '" .. txt .. "'")
      end
    end
  end
  dentro("reacciones " .. nombre)
  return res
end
local r1 = reacciones_ok("Viga apoyada", true)
near(r1.reac[1].ry, 30, "viga apoyada: Ry = wL/2", 1e-9)
check(shown("Ry=30 kN"), "texto 'Ry=30 kN' (formateado)")
reacciones_ok("Voladizo", true)
reacciones_ok("Viga continua", false)
reacciones_ok("Cercha", true)
reacciones_ok("Portal", false)
png("res_reacciones_portal")
reacciones_ok("Viga apoyada", true)
png("res_reacciones_viga")

-- =================================================================== valor al apuntar
print("-- valor al apuntar")
ir("Viga apoyada")
key("m")
local L = 6
mock.paint()
-- altura del diagrama M: ~12% del lado menor del lienzo
do
  local ymax = -1
  for _, op in ipairs(mock.last_ops) do
    if op[1] == "drawLine" and op.color[1] == 20 and op.color[2] == 70 and op.color[3] == 225 then
      ymax = math.max(ymax, op[3], op[5])
    end
  end
  local esperado = 0.12 * math.min(V.rect.w, V.rect.h)
  near(ymax - py(0), esperado, "altura maxima del diagrama M ~12% del lado menor", 2)
  check(ymax > py(0), "M de una viga con carga hacia abajo se dibuja debajo (lado traccionado)")
end
mock.move(px(3), py(0))
check(R.cur ~= nil and R.cur.e == 1, "apuntar a la barra fija el cursor")
near(R.cur.x, 3, "x apuntado", 0.04)
near(R.cur.M, 45, "M(centro) = wL^2/8 = 45", 0.05)
check(shown("M=45 kN·m"), "texto formateado 'M=45 kN·m' en el recuadro")
check(shown("M=45 kN·m | δ="), "y en la barra de estado")
near(R.cur.V, 0, "V(centro) = 0", 0.3)
local dmax = 5 * 10 * L ^ 4 / (384 * 2e8 * 1e-4)
near(math.sqrt(R.cur.ux ^ 2 + R.cur.uy ^ 2), dmax, "flecha central 5wL^4/384EI", 2e-5)
check(shown("δ=8.43"), "flecha en mm en el recuadro")
estado_sin_solape("apuntar")
dentro("apuntar")
png("res_valor_apuntar")
-- teclado: la cruz se mueve con flechas por la barra
mock.move(10, 100)             -- fuera de barras: el cursor del raton se quita
check(R.cur == nil, "al salir de la barra desaparece el valor")
key("left")                    -- primer movimiento: coloca el cursor en L/2
near(R.cur.x, 3, "flecha: parte del centro")
key("right"); key("left")
near(R.cur.x, 3, "ida y vuelta", 1e-9)
near(R.cur.M, 45, "M exacto en x=3", 1e-9)
check(shown("M=45 kN·m"), "valor por teclado")
for _ = 1, 40 do key("right") end
check(R.cur.x <= L + 1e-9 and R.cur.e == 1, "el cursor no sale de la barra (ultima barra)")
key("escape")
check(R.cur == nil and R.modo == "M", "ESC quita el cursor sin salir")
-- clic: valor "al tocar"
mock.click(px(1.5), py(0))
check(R.cur ~= nil and R.cur.src == "clic", "clic fija el punto")
check(H.sel and H.sel.t == "barra" and R.eb == 1, "y selecciona la barra")
-- nodo
mock.move(px(0), py(0))
check(R.cur ~= nil and R.cur.nodo == 1, "apuntar a un nodo muestra sus desplazamientos")
check(shown("Nodo 1"), "recuadro del nodo")
key("escape")

-- continua: V de la barra 2 coincide con E.eval
ir("Viga continua")
key("v")
mock.move(px(7.5), py(0))
check(R.cur and R.cur.e == 2, "continua: barra 2")
do
  local resc = S.resolver(ED.m)
  local _, Vq = EE.eval(resc, 2, R.cur.x)
  near(R.cur.V, Vq, "V apuntado = E.eval", 1e-9)
end

-- =================================================================== diagramas: todos los ejemplos
print("-- diagramas y deformada en todos los ejemplos")
local TECLA = { reac = "r", N = "n", V = "v", M = "m", def = "d", tabla = "t", ecs = "e" }
for _, ej in ipairs(ED.ejemplos) do
  ir(ej)
  for _, v in ipairs({ "reac", "N", "V", "M", "def", "tabla", "ecs" }) do
    key(TECLA[v])
    local ok = sin_error(ej .. " / " .. v)
    if ok then dentro(ej .. " / " .. v) end
    local kb = basura_paint()
    check(kb < 2.5, ej .. " / " .. v .. ": basura por paint " .. string.format("%.2f", kb) .. " KB")
  end
  key("m"); key("z"); key("z"); sin_error(ej .. " zoom"); key("f")
end
ir("Portal"); key("m")
mock.drag(160, 190, 120, 170)
sin_error("pan en resultados")
H.encuadrar()
print(string.format("   basura por paint en resultados (portal, M): %.2f KB", basura_paint()))

-- escala de diagramas
print("-- escala")
ir("Viga apoyada"); key("m")
local k0 = R.kd.M
key("+"); check(R.kd.M > k0, "+ aumenta la escala del diagrama")
key("+"); key("-")
check(R.kd.M > k0, "+,+,- deja mayor que el inicial")
for _ = 1, 20 do key("-") end
check(R.kd.M >= 0.1 - 1e-12, "la escala tiene un minimo")
for _ = 1, 40 do key("+") end
check(R.kd.M <= 100 + 1e-9, "la escala tiene un maximo")
R.kd.M = 1

-- deformada
print("-- deformada")
ir("Viga apoyada"); key("d")
check(shown("Deformada x"), "cabecera con factor de escala")
check(shown("δmax=8.43"), "δmax con valor")
check(shown("B1, x=3 m"), "δmax con posicion")
key("+")
check(R.def_f ~= nil and R.def_f > 0, "+ fija un factor")
local f1 = R.def_f
key("+"); check(R.def_f > f1, "+ aumenta el factor")
local f2 = R.def_f
key("-"); check(R.def_f < f2, "- disminuye")
key("0")
check(R.def_real, "0 activa deformada real")
check(shown("(real)"), "se indica 'real'")
check(shown("x 1 (real)"), "factor real = 1")
key("0")
check(not R.def_real and R.def_f == nil, "0 de nuevo vuelve al factor automatico")
mock.move(px(3), py(0))
check(R.cur ~= nil, "valor al apuntar en deformada")
png("res_deformada_viga")

-- =================================================================== PNG pedidos
print("-- PNG")
ir("Viga continua"); key("m"); mock.move(10, 100); png("res_continua_M")
key("v"); png("res_continua_V")
ir("Cercha"); key("n"); png("res_cercha_N")
ir("Portal"); key("m"); png("res_portal_M")
key("d"); png("res_portal_def")
key("v"); png("res_portal_V")
key("n"); png("res_portal_N")
ir("Viga continua"); key("t"); png("res_tabla")
ir("Portal"); key("t"); key("down"); key("down"); png("res_tabla_portal")
ir("Viga continua"); key("e"); png("res_ecuaciones")
key("l"); check(D.activo() ~= nil and shown("TRACCION"), "leyenda con la tecla l")
png("res_leyenda"); key("escape")
check(D.activo() == nil, "se cierra la leyenda")
ir("Viga continua"); key("?"); check(D.activo() ~= nil, "leyenda con ?"); key("escape")
ir("Voladizo"); key("m"); mock.move(px(2), py(0)); png("res_voladizo_M")

-- =================================================================== tabla
print("-- tabla")
ir("Viga continua"); key("t")
eq(R.modo, "tabla", "tabla")
check(shown("Desplazamientos nodales"), "tabla: desplazamientos")
check(#R.tab_rows > 10, "tabla con filas")
key("down"); key("down"); key("down")
eq(R.scroll, 3, "la tabla se desplaza con las flechas")
key("up"); eq(R.scroll, 2, "arriba")
for _ = 1, 10 do key("right") end
mock.paint()
check(R.scroll <= math.max(0, #R.tab_rows - 15), "el desplazamiento esta acotado")
check(shown("Equilibrio global"), "al final se ve el equilibrio global")
check(shown("equilibrio correcto"), "residuo pequeno marcado correcto")
for _ = 1, 10 do key("left") end
eq(R.scroll, 0, "pagina arriba llega al inicio")
check(shown("Reacciones"), "tabla: seccion de reacciones")
dentro("tabla")
do
  local res = S.resolver(ED.m)
  local fila
  for _, row in ipairs(R.tab_rows) do
    if row.k == "c" and row.c[1] == "1" and row.c[2] == num(res.reac[1].rx) and row.c[3] == num(res.reac[1].ry) then fila = row end
  end
  check(fila ~= nil, "la tabla contiene las reacciones del nodo 1")
  local esf
  for _, row in ipairs(R.tab_rows) do
    if row.k == "c" and row.c[1] == "1 (1-2)" then esf = row end
  end
  local _, _, M0 = EE.eval(res, 1, 0)
  check(esf ~= nil and esf.c[5] == num(M0), "esfuerzo M en i de la barra 1")
end

-- =================================================================== ecuaciones
print("-- ecuaciones")
ir("Viga continua"); key("e")
eq(R.modo, "ecs", "ecuaciones")
eq(R.eb, 1, "barra 1")
check(shown("V(x) ="), "ecuacion de V")
check(shown("M(x) ="), "ecuacion de M")
check(shown("θ(x) ="), "ecuacion de θ")
check(shown("y(x) ="), "ecuacion de y")
check(shown("Barra 1/2"), "indicador de barra")
check(shown("propio (CAS no disponible)"), "sin math.evalStr: motor propio indicado")
key("right")
eq(R.eb, 2, "flecha derecha: barra 2")
check(shown("(nodos 2-3"), "se muestra la barra 2")
key("right"); eq(R.eb, 1, "da la vuelta")
key("left"); eq(R.eb, 2, "izquierda")
for _ = 1, 3 do key("down") end
check(R.scroll >= 0, "scroll")
key("up")
dentro("ecuaciones")
do
  local resc2 = S.resolver(ED.m)
  for e = 1, #resc2.barras do
    local L2 = resc2.barras[e].L
    for _, q in ipairs(EE.ecuaciones(resc2, e)) do
      for _, campo in ipairs({ "V", "M", "th", "y", "N" }) do
        local f = loadstring("local x = ... ; return " .. P.tostring_sig(q[campo], "x", 4, false, L2))
        local xm = 0.5 * (q.x0 + q.x1)
        local a, b = f(xm), P.eval(q[campo], xm)
        local esc = 0
        for i = 1, #q[campo] do esc = esc + math.abs(q[campo][i] * xm ^ (i - 1)) end
        check(math.abs(a - b) <= 2e-3 * esc + 1e-12, "ecuacion " .. campo .. " barra " .. e .. " evaluable y exacta a 4 cifras")
      end
    end
  end
end
-- CAS simulado
mock.set_cas("calc")
R.ecs = nil
check(shown("Motor: CAS"), "CAS que verifica: se usa y se indica")
check(mock.cas_llamadas > 0, "se llamo a math.evalStr")
mock.set_cas("eco"); R.ecs = nil
check(shown("CAS sin verificar"), "CAS que devuelve la misma cadena: no verificable -> propio")
mock.set_cas("nil"); R.ecs = nil
check(shown("CAS sin verificar"), "CAS que devuelve nil -> motor propio")
check(shown("V(x) ="), "y las ecuaciones siguen visibles")
mock.set_cas("error"); R.ecs = nil
check(sin_error("CAS que lanza error"), "CAS que lanza error no rompe")
check(shown("V(x) ="), "ecuaciones con CAS en error")
mock.set_cas("off"); R.ecs = nil
check(shown("CAS no disponible"), "sin CAS vuelve el motor propio")

-- =================================================================== cambio de modelo
print("-- recalculo automatico")
ir("Viga apoyada"); key("m")
mock.move(px(3), py(0))
near(R.cur.M, 45, "antes: M centro", 0.05)
local ver0 = R.ver
ED.hacer(function(m) m.barras[1].cargas[1].w1 = -20; m.barras[1].cargas[1].w2 = -20; return true end)
check(R.ver > ver0, "el cambio de carga re-resuelve")
near(R.cur.M, 90, "despues: M centro duplicado (el punto apuntado se conserva)", 0.1)
check(shown("M=90"), "texto actualizado")
mock.drag(px(6), py(0), px(8), py(0))
check(R.res ~= nil and math.abs(S.resolver(ED.m).reac[1].ry - R.res.reac[1].ry) < 1e-9, "arrastrar un nodo re-resuelve en vivo")
H.deshacer()
-- apoyo quitado -> inestable con mensaje claro
ED.hacer(function(m) m.nodos[1].apoyo = nil; m.nodos[2].apoyo = nil; return true end)
eq(R.res, nil, "sin apoyos no hay resultados")
check(R.err and R.err:find("Falta un apoyo", 1, true), "mensaje en espanol: " .. tostring(R.err))
check(shown("No se puede resolver"), "pantalla de error visible")
check(shown("Falta un apoyo"), "con el texto accionable")
eq(R.modo, "M", "sigue en modo resultados")
png("res_error_sin_apoyos")
H.msg = nil
check(shown("Inestable"), "clasificacion: Inestable en la barra de estado")
estado_sin_solape("inestable")
for _, k in ipairs({ "n", "v", "m", "d", "t", "e", "r", "left", "right", "up", "down", "+", "-", "0", "tab" }) do
  local ok, err = pcall(mock.key, k)
  check(ok, "tecla " .. k .. " con modelo inestable: " .. tostring(err))
  sin_error("inestable " .. k)
end
H.deshacer()
check(R.res ~= nil, "deshacer recupera los resultados")
-- mecanismo
ED.hacer(function(m)
  m.nodos[1].apoyo = { ux = false, uy = true, rz = false }
  m.nodos[2].apoyo = { ux = false, uy = true, rz = false }
  return true
end)
check(R.res == nil and R.err ~= nil, "mecanismo detectado: " .. tostring(R.err))
check(sin_error("mecanismo"), "mecanismo no rompe")
H.deshacer()
-- nodo suelto
ED.hacer(function(m) ED.agregar_nodo(m, 20, 5); return true end)
check(R.res == nil and R.err and R.err:find("nodo 3", 1, true), "nodo suelto: " .. tostring(R.err))
check(R.err:find("conectalo", 1, true), "mensaje accionable")
H.deshacer()
check(R.res ~= nil, "se recupera")
-- clasificacion en la barra de estado para cada ejemplo (modo modelado)
print("-- clasificacion en la barra de estado")
local esperado = { ["Viga apoyada"] = "Isostatica", ["Voladizo"] = "Isostatica", ["Viga continua"] = "Hiperestatica g=1",
  ["Cercha"] = "Isostatica", ["Portal"] = "Hiperestatica g=3" }
for ej, txt in pairs(esperado) do
  if R.modo then H.salir_resultados() end
  H.ejemplo(ej)
  H.msg = nil
  mock.move(150, 100)
  check(shown(txt), ej .. ": '" .. txt .. "' en la barra de estado (modelado)")
  estado_sin_solape("modelado " .. ej)
  dentro("modelado " .. ej)
end
-- mas de 20 nodos: no se re-resuelve solo
print("-- estructuras grandes")
if R.modo then H.salir_resultados() end
H.ejemplo("Viga apoyada")
key("r")
ED.hacer(function(m)
  local ult = 2
  for i = 1, 21 do
    local n = ED.agregar_nodo(m, 6 + i, 0)
    ED.agregar_barra(m, ult, n, ED.PROPS_DEFECTO)
    ult = n
  end
  return true
end)
check(#ED.m.nodos > 20, "modelo grande")
eq(R.res, nil, "mas de 20 nodos: no se resuelve automaticamente")
check(R.err and R.err:find("20 nodos", 1, true), "con aviso: " .. tostring(R.err))
check(sin_error("modelo grande"), "paint con modelo grande")
H.salir_resultados()
H.deshacer()

-- =================================================================== v1.0: unidades en los resultados
print("-- unidades en resultados")
local U = env.require("ui.unidades")
ir("Viga apoyada"); key("m")
mock.move(px(3), py(0))
check(shown("M=45 kN·m"), "kN-m: M=45 kN·m")
H.set_unidades("N-m")
check(shown("M=45000 N·m"), "N-m: el mismo punto muestra M=45000 N·m")
H.msg = nil     -- el aviso "Unidades: ..." tapa la barra de estado hasta la siguiente accion
check(shown("M=45000 N·m | δ="), "N-m: tambien en la barra de estado")
check(shown("max 45000 N·m"), "maximo del diagrama en N·m")
near(R.cur.M, 45, "el valor interno sigue en kN·m", 0.05)
check(shown("δ=0.008437 m"), "flecha en m con el sistema N-m: " .. tostring(R.cur and R.cur.l4))
H.set_unidades("tf-m")
check(shown("M=4.589 tf·m"), "tf-m: M=4.589 tf·m")
H.msg = nil
check(shown("M=4.589 tf·m | δ=8.437 mm"), "tf-m: barra de estado, flecha en mm")
png("pol_apuntar_tfm")
H.set_unidades("kN-m")
check(shown("M=45 kN·m"), "vuelta a kN-m")
-- etiquetas del diagrama
H.set_unidades("N-m")
mock.move(10, 100); mock.paint()
check(shown("45000"), "etiqueta del maximo del diagrama en N·m")
H.set_unidades("kN-m")
-- reacciones
key("r")
check(shown("Ry=30 kN"), "reacciones en kN")
H.set_unidades("N-m"); check(shown("Ry=30000 N") and shown("[N, N·m]"), "reacciones en N")
H.set_unidades("tf-m"); check(shown("Ry=3.059 tf") and shown("[tf, tf·m]"), "reacciones en tf")
H.set_unidades("kN-m")
-- nodo
mock.move(px(0), py(0))
check(shown("Ry=30 kN"), "nodo: reaccion en kN")
H.set_unidades("N-m"); check(shown("Ry=30000 N"), "nodo: reaccion en N")
H.set_unidades("kN-m")
-- tabla
key("t")
check(shown("ux [mm]") and shown("Rx [kN]") and shown("M [kN·m]"), "tabla en kN-m")
H.set_unidades("N-m")
check(shown("ux [m]") and shown("Rx [N]") and shown("M [N·m]") and shown("rz [rad]"), "tabla en N-m")
H.set_unidades("tf-m")
check(shown("Ry [tf]") and shown("M [tf·m]"), "tabla en tf-m")
H.set_unidades("kN-m")
-- ecuaciones: x en m, coeficientes escalados
key("e")
check(shown("M(x) = -5*x^2+30*x"), "ecuaciones kN-m: M = -5x^2+30x")
check(shown("N,V en kN") and shown("M en kN·m") and shown("y en mm"), "encabezado con unidades (kN-m)")
check(not shown("N(x) ="), "N(x) = 0 se omite en la viga")
H.set_unidades("N-m")
check(shown("M(x) = -5000*x^2+30000*x"), "ecuaciones N-m: M = -5000x^2+30000x")
check(shown("V(x) = 30000-10000*x") or shown("V(x) = -10000*x+30000"), "V(x) en N")
check(shown("N,V en N") and shown("M en N·m") and shown("y en m"), "encabezado con unidades (N-m)")
dentro("ecuaciones N-m")
png("pol_ecuaciones_Nm")
-- los valores de las ecuaciones coinciden con E.eval (convertidos)
do
  local rr = S.resolver(ED.m)
  local _, Vx, Mx = EE.eval(rr, 1, 2)
  local q = EE.ecuaciones(rr, 1)[1]
  near(P.eval(q.M, 2), Mx, "ecuacion M(2) = E.eval", 1e-9)
  near(P.eval(P.scale(q.M, 1000), 2), Mx * 1000, "M(2) en N·m", 1e-6)
end
H.set_unidades("tf-m")
check(shown("tf·m") and shown("y en mm"), "ecuaciones en tf-m")
H.set_unidades("kN-m")
-- N(x) aparece cuando hay axial (cercha)
ir("Cercha"); key("e")
check(shown("N(x) ="), "cercha: N(x) distinto de cero se muestra")
-- la tabla se rehace al cambiar de unidades sin salir
ir("Viga apoyada"); key("t")
H.set_unidades("N-m"); check(shown("Rx [N]"), "tabla se rehace al cambiar de unidades")
H.set_unidades("kN-m")
-- leyenda
H.leyenda(); check(shown("Unidades"), "leyenda menciona las unidades"); key("escape")

-- =================================================================== recuadro de valores
print("-- recuadro de valores en la esquina opuesta")
ir("Viga apoyada"); key("m")
local function caja_ok(label, px_, py_)
  mock.move(px_, py_); mock.paint()
  local c = R.caja
  local cx, cy = c.px, c.py
  local inside = cx > c.x - 6 and cx < c.x + c.w + 6 and cy > c.y - 6 and cy < c.y + c.h + 6
  check(not inside, label .. ": el recuadro no tapa el punto apuntado")
  return c
end
do
  local c1 = caja_ok("cursor a la izquierda", px(0.8), py(0))
  check(c1.x + c1.w / 2 > mock.W / 2, "cursor a la izquierda: recuadro en el lado derecho (x=" .. c1.x .. ")")
  local c2 = caja_ok("cursor a la derecha", px(5.2), py(0))
  check(c2.x + c2.w / 2 < mock.W / 2, "cursor a la derecha: recuadro en el lado izquierdo (x=" .. c2.x .. ")")
  dentro("recuadro opuesto")
  -- no cubre las etiquetas ya dibujadas
  mock.move(px(3), py(0)); mock.paint()
  local c3 = R.caja
  for _, t in ipairs(mock.screen_text()) do
    if t.text == "45" and t.size == 7 then
      local solapa = t.x < c3.x + c3.w and t.x + t.w > c3.x and t.y < c3.y + c3.h and t.y + 10 > c3.y
      check(not solapa, "el recuadro no tapa la etiqueta del maximo del diagrama")
    end
  end
end
key("d")
do
  mock.move(px(1), py(0)); mock.paint()
  local c = R.caja
  local sd = R.sel_def
  local solapa = c.x < sd.x + sd.w and c.x + c.w > sd.x and c.y < sd.y + sd.h and c.y + c.h > sd.y
  check(not solapa, "el recuadro no tapa el selector de deformada")
end

-- =================================================================== selector de deformada
print("-- selector de deformada")
ir("Viga apoyada"); key("d")
check(shown("Real") and shown("Ampliada x"), "selector Real / Ampliada visible")
check(not R.def_real, "por omision ampliada")
do
  local sd = R.sel_def
  mock.click(sd.xr + 3, sd.y + 3)
  check(R.def_real, "clic en Real activa la deformada real")
  check(shown("(real)"), "y la cabecera lo dice")
  mock.paint()
  sd = R.sel_def
  mock.click(sd.xa + 3, sd.y + 3)
  check(not R.def_real, "clic en Ampliada vuelve a la ampliada")
  check(shown("Ampliada x"), "con su factor")
end
-- el boton Def, ya activo, alterna
do
  local bdef
  for _, b in ipairs(H.botones) do if b.id == "r_def" then bdef = b end end
  mock.click(bdef.x + 4, bdef.y + 4)
  check(R.def_real, "clic en el boton Def activo alterna a real")
  mock.click(bdef.x + 4, bdef.y + 4)
  check(not R.def_real, "y otra vez a ampliada")
end
H.toggle_def(); check(R.def_real, "H.toggle_def (menu Vista) alterna"); H.toggle_def()
mock.move(10, 100); H.msg = nil
check(shown("0 alterna"), "la barra de estado explica la tecla 0")
dentro("selector de deformada")
png("pol_deformada_selector")
-- el selector no aparece fuera de la vista de deformada
key("m"); check(not shown("Ampliada x"), "sin selector fuera de la deformada")
-- unidades y selector se conservan al guardar
H.set_unidades("tf-m"); R.def_real = true
local sv2 = mock.save()
eq(sv2.cfg.unidades, "tf-m", "cfg.unidades"); eq(sv2.cfg.def_real, true, "cfg.def_real")
H.set_unidades("kN-m"); R.def_real = false
mock.restore(sv2)
eq(U.actual, "tf-m", "restaura unidades"); eq(R.def_real, true, "restaura deformada real")
H.set_unidades("kN-m"); R.def_real = false

-- =================================================================== carga termica en la interfaz
print("-- carga termica: se guarda, dibuja y resuelve")
ir("Viga apoyada")
H.salir_resultados()
ED.agregar_carga_barra(ED.m, 1, { t = "T", du = 0, dg = 30, alfa = 1.2e-5, h = 0.3 })
ED.cambio()
check(shown("ΔT"), "etiqueta ΔT en el lienzo")
key("r")
check(sin_error("resolver con T"), "paint con T y resultados")
H.salir_resultados()

-- =================================================================== robustez
print("-- robustez")
ir("Portal")
for _, k in ipairs({ "n", "v", "m", "d", "t", "e", "r", "left", "right", "up", "down", "+", "-", "0", "tab", "l", "escape", "escape" }) do
  local ok, err = pcall(mock.key, k)
  check(ok, "tecla " .. k .. ": " .. tostring(err))
  if D.activo() then key("escape") end
  sin_error("tecla " .. k)
end
for _, p in ipairs({ { -5, -5 }, { 400, 300 }, { 0, 0 }, { 317, 211 }, { 100, 30 } }) do
  ir("Portal"); key("m")
  local ok, err = pcall(function() mock.move(p[1], p[2]); mock.click(p[1], p[2]) end)
  check(ok, "raton en " .. p[1] .. "," .. p[2] .. ": " .. tostring(err))
  sin_error("raton")
end
ir("Viga continua"); key("m"); V.zoom(1000); sin_error("zoom enorme"); V.zoom(1e-6); sin_error("zoom minimo"); H.encuadrar()
ir("Portal")
local guardado = mock.save()
check(guardado ~= nil, "on.save con resultados activos")
mock.restore(guardado)
sin_error("restore")
H.salir_resultados()

mock.set_cas("off")
check(math.evalStr == nil, "mock limpio")

print(string.format("== test_resultados: %d comprobaciones, %d fallo(s)", checks, fails))
if #pngs > 0 then print("PNG en build/png/: " .. #pngs) end
os.exit(fails == 0 and 0 or 1)
