-- ui/modelo_ed.lua - Edicion del modelo estructural (formato de docs/arquitectura.md §4).
-- Operaciones puras sobre un modelo `m` + estado de la sesion: ED.m (modelo actual),
-- pila de deshacer/rehacer (instantaneas, max 30), propiedades globales y biblioteca.
-- Unidades internas: kN, m (E en kN/m2, A en m2, I en m4). Ver ED.GPA, ED.CM2, ED.CM4.
-- Las funciones que pueden fallar devuelven nil, "mensaje en espanol".
local ED = {}

local floor, abs, sqrt = math.floor, math.abs, math.sqrt

local TOL = 1e-6
ED.MAXCOORD = 10000
ED.MAX_UNDO = 30
ED.MAX_BIB = 10

-- Factores de conversion de la UI a unidades internas
ED.GPA = 1e6      -- 1 GPa = 1e6 kN/m2
ED.CM2 = 1e-4     -- 1 cm2 = 1e-4 m2
ED.CM4 = 1e-8     -- 1 cm4 = 1e-8 m4

ED.PROPS_DEFECTO = { E = 200 * 1e6, A = 100 * 1e-4, I = 10000 * 1e-8, tipo = "portico" }
ED.props = { E = ED.PROPS_DEFECTO.E, A = ED.PROPS_DEFECTO.A, I = ED.PROPS_DEFECTO.I, tipo = "portico" }

ED.on_cambio = nil     -- callback tras cualquier cambio del modelo (lo fija la UI)

-- ------------------------------------------------------------ utilidades
function ED.copiar(v)
  if type(v) ~= "table" then return v end
  local c = {}
  for k, x in pairs(v) do c[k] = ED.copiar(x) end
  return c
end

-- Numero corto: hasta `dec` decimales sin ceros finales ("2.5", "10", "-0.25")
function ED.fmt(v, dec)
  local s = string.format("%." .. (dec or 2) .. "f", v)
  if s:find(".", 1, true) then
    s = s:gsub("0+$", "")
    s = s:gsub("%.$", "")
  end
  if s == "-0" then s = "0" end
  return s
end

function ED.nuevo()
  return { ver = 1, nodos = {}, barras = {} }
end

function ED.resumen(m)
  return #m.nodos, #m.barras
end

local function num(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

-- ------------------------------------------------------------------ nodos
function ED.nodo_cerca(m, x, y, tol)
  tol = tol or TOL
  local best, bd = nil, tol * tol
  for i = 1, #m.nodos do
    local n = m.nodos[i]
    local d = (n.x - x) ^ 2 + (n.y - y) ^ 2
    if d <= bd then best, bd = i, d end
  end
  return best
end

-- Devuelve indice, creado. Si ya hay un nodo en (x,y) devuelve ese (creado=false).
function ED.agregar_nodo(m, x, y)
  if not (num(x) and num(y)) then return nil, "Coordenadas no validas" end
  if abs(x) > ED.MAXCOORD or abs(y) > ED.MAXCOORD then
    return nil, "Coordenada fuera de rango (max 10000 m)"
  end
  local i = ED.nodo_cerca(m, x, y, TOL)
  if i then return i, false end
  m.nodos[#m.nodos + 1] = { x = x, y = y }
  return #m.nodos, true
end

function ED.mover_nodo(m, i, x, y)
  local n = m.nodos[i]
  if not n then return nil, "El nodo no existe" end
  if not (num(x) and num(y)) then return nil, "Coordenadas no validas" end
  if abs(x) > ED.MAXCOORD or abs(y) > ED.MAXCOORD then
    return nil, "Coordenada fuera de rango (max 10000 m)"
  end
  local j = ED.nodo_cerca(m, x, y, TOL)
  if j and j ~= i then return nil, "Ya existe un nodo en esa posicion" end
  n.x, n.y = x, y
  return true
end

function ED.borrar_nodo(m, i)
  if not m.nodos[i] then return nil, "El nodo no existe" end
  for e = #m.barras, 1, -1 do
    local b = m.barras[e]
    if b.ni == i or b.nj == i then table.remove(m.barras, e) end
  end
  table.remove(m.nodos, i)
  for e = 1, #m.barras do
    local b = m.barras[e]
    if b.ni > i then b.ni = b.ni - 1 end
    if b.nj > i then b.nj = b.nj - 1 end
  end
  return true
end

-- ----------------------------------------------------------------- barras
function ED.barra_existe(m, i, j)
  for e = 1, #m.barras do
    local b = m.barras[e]
    if (b.ni == i and b.nj == j) or (b.ni == j and b.nj == i) then return e end
  end
  return nil
end

function ED.longitud(m, e)
  local b = m.barras[e]
  local a, c = m.nodos[b.ni], m.nodos[b.nj]
  return sqrt((c.x - a.x) ^ 2 + (c.y - a.y) ^ 2)
end

function ED.agregar_barra(m, i, j, props)
  if not (m.nodos[i] and m.nodos[j]) then return nil, "Selecciona dos nodos existentes" end
  if i == j then return nil, "Selecciona dos nodos distintos" end
  if ED.barra_existe(m, i, j) then return nil, "La barra ya existe" end
  local p = props or ED.props
  m.barras[#m.barras + 1] = {
    ni = i, nj = j, tipo = p.tipo or "portico",
    E = p.E or ED.props.E, A = p.A or ED.props.A, I = p.I or ED.props.I,
    rot_i = false, rot_j = false, cargas = {},
  }
  return #m.barras
end

function ED.borrar_barra(m, e)
  if not m.barras[e] then return nil, "La barra no existe" end
  table.remove(m.barras, e)
  return true
end

-- Tras mover/editar nodos: recorta las cargas que quedaron fuera de la barra
function ED.ajustar_cargas(m, e)
  local b = m.barras[e]
  if not b then return false end
  local L = ED.longitud(m, e)
  local cambio = false
  for k = #b.cargas, 1, -1 do
    local c = b.cargas[k]
    if c.t == "T" then
      -- la carga termica afecta a toda la barra: no tiene posicion
    elseif c.t == "w" then
      local a, bb = c.a, c.b
      if c.a > L then c.a = L end
      if c.b > L then c.b = L end
      if c.b - c.a < 1e-9 then table.remove(b.cargas, k); cambio = true
      elseif a ~= c.a or bb ~= c.b then cambio = true end
    else
      if c.a > L then c.a = L; cambio = true end
    end
  end
  return cambio
end

function ED.ajustar_todas(m)
  local n = 0
  for e = 1, #m.barras do
    if ED.ajustar_cargas(m, e) then n = n + 1 end
  end
  return n
end

local DIRS = { GY = true, GX = true, L = true, LX = true }

-- Valida una carga de barra; devuelve true o nil, msg
function ED.validar_carga(m, e, c)
  local b = m.barras[e]
  if not b then return nil, "La barra no existe" end
  local L = ED.longitud(m, e)
  local Ls = ED.fmt(L, 2)
  if c.t == "P" then
    if not (num(c.a) and num(c.p)) then return nil, "Valores no validos" end
    if c.a < -1e-9 or c.a > L + 1e-9 then return nil, "La posicion debe estar entre 0 y " .. Ls .. " m" end
    if c.p == 0 then return nil, "La carga no puede ser cero" end
    if not DIRS[c.dir] then return nil, "Direccion no valida" end
  elseif c.t == "M" then
    if not (num(c.a) and num(c.m)) then return nil, "Valores no validos" end
    if c.a < -1e-9 or c.a > L + 1e-9 then return nil, "La posicion debe estar entre 0 y " .. Ls .. " m" end
    if c.m == 0 then return nil, "El momento no puede ser cero" end
  elseif c.t == "w" then
    if not (num(c.a) and num(c.b) and num(c.w1) and num(c.w2)) then return nil, "Valores no validos" end
    if c.a < -1e-9 or c.b > L + 1e-9 then return nil, "El tramo debe estar entre 0 y " .. Ls .. " m" end
    if c.b - c.a < 1e-6 then return nil, "El tramo debe tener b mayor que a" end
    if c.w1 == 0 and c.w2 == 0 then return nil, "La carga no puede ser cero" end
    if not DIRS[c.dir] then return nil, "Direccion no valida" end
  elseif c.t == "T" then
    if not (num(c.du) and num(c.dg)) then return nil, "Valores no validos" end
    if c.alfa ~= nil and not (num(c.alfa) and c.alfa > 0) then return nil, "alfa debe ser mayor que 0" end
    if c.du == 0 and c.dg == 0 then return nil, "La variacion de temperatura no puede ser cero" end
    if c.dg ~= 0 and not (num(c.h) and c.h > 0) then
      return nil, "Con gradiente (dg) el canto h debe ser mayor que 0"
    end
  else
    return nil, "Tipo de carga desconocido"
  end
  return true
end

function ED.agregar_carga_barra(m, e, c)
  local ok, msg = ED.validar_carga(m, e, c)
  if not ok then return nil, msg end
  local b = m.barras[e]
  if c.a and c.a < 0 then c.a = 0 end
  b.cargas[#b.cargas + 1] = c
  return true
end

-- Sustituye la carga k de la barra e (validada); la original queda intacta si falla
function ED.reemplazar_carga_barra(m, e, k, c)
  local b = m.barras[e]
  if not (b and b.cargas[k]) then return nil, "La carga ya no existe" end
  local ok, msg = ED.validar_carga(m, e, c)
  if not ok then return nil, msg end
  if c.a and c.a < 0 then c.a = 0 end
  b.cargas[k] = c
  return true
end

function ED.borrar_carga_barra(m, e, k)
  local b = m.barras[e]
  if not (b and b.cargas[k]) then return nil, "La carga ya no existe" end
  table.remove(b.cargas, k)
  return true
end

-- Divide la barra e en el punto a (m desde el nodo i) creando un nodo. La primera mitad conserva el
-- indice e y la rotula i; la segunda (barra nueva, al final) conserva la rotula j. Cargas: P y M van al
-- tramo que las contiene (si caen justo en el corte pasan al nodo nuevo como carga nodal); w se recorta
-- por tramo interpolando w1/w2; T se copia a ambas. Una barra "cercha" pasa a "portico" con extremos
-- articulados (equivalente, y evita un mecanismo en el nodo colineal).
-- Devuelve nodo_nuevo, barra_nueva | nil, msg.
local MINSEG, EPSA = 1e-3, 1e-6
function ED.dividir_barra(m, e, a)
  local b = m.barras[e]
  if not b then return nil, "La barra no existe" end
  if not num(a) then return nil, "Posicion no valida" end
  local L = ED.longitud(m, e)
  if a < MINSEG or a > L - MINSEG then return nil, "Demasiado cerca de un nodo: usa el nodo existente" end
  local na, nb = m.nodos[b.ni], m.nodos[b.nj]
  local f = a / L
  local x, y = na.x + (nb.x - na.x) * f, na.y + (nb.y - na.y) * f
  if ED.nodo_cerca(m, x, y, TOL) then return nil, "Ya hay un nodo en ese punto" end
  local cb, sb = (nb.x - na.x) / L, (nb.y - na.y) / L
  m.nodos[#m.nodos + 1] = { x = x, y = y }
  local nn = #m.nodos
  local nuevo = ED.copiar(b)
  local c1, c2 = {}, {}
  local fx, fy, mz = 0, 0, 0
  for k = 1, #b.cargas do
    local c = b.cargas[k]
    if c.t == "P" or c.t == "M" then
      if abs(c.a - a) <= EPSA then
        if c.t == "M" then mz = mz + c.m
        elseif c.dir == "GX" then fx = fx + c.p
        elseif c.dir == "L" then fx = fx - sb * c.p; fy = fy + cb * c.p
        elseif c.dir == "LX" then fx = fx + cb * c.p; fy = fy + sb * c.p
        else fy = fy + c.p end
      elseif c.a < a then c1[#c1 + 1] = ED.copiar(c)
      else
        local q = ED.copiar(c); q.a = c.a - a; c2[#c2 + 1] = q
      end
    elseif c.t == "w" then
      if c.b <= a + 1e-9 then c1[#c1 + 1] = ED.copiar(c)
      elseif c.a >= a - 1e-9 then
        local q = ED.copiar(c); q.a, q.b = c.a - a, c.b - a; c2[#c2 + 1] = q
      else
        local ws = c.w1 + (c.w2 - c.w1) * (a - c.a) / (c.b - c.a)
        local q1 = ED.copiar(c); q1.b, q1.w2 = a, ws
        local q2 = ED.copiar(c); q2.a, q2.b, q2.w1 = 0, c.b - a, ws
        if q1.b - q1.a > 1e-6 then c1[#c1 + 1] = q1 end
        if q2.b - q2.a > 1e-6 then c2[#c2 + 1] = q2 end
      end
    else
      c1[#c1 + 1] = ED.copiar(c)
      c2[#c2 + 1] = ED.copiar(c)
    end
  end
  if fx ~= 0 or fy ~= 0 or mz ~= 0 then
    local nd = m.nodos[nn]
    nd.carga = { fx = fx, fy = fy, mz = mz }
  end
  nuevo.ni, nuevo.nj = nn, b.nj
  nuevo.rot_i, nuevo.rot_j = false, b.rot_j and true or false
  nuevo.cargas = c2
  b.nj, b.rot_j, b.cargas = nn, false, c1
  if b.tipo == "cercha" then
    b.tipo, nuevo.tipo = "portico", "portico"
    b.rot_i, nuevo.rot_j = true, true
  end
  m.barras[#m.barras + 1] = nuevo
  return nn, #m.barras
end

-- ----------------------------------------------------------------- apoyos
function ED.apoyo_nuevo(tipo)
  local a = { ux = false, uy = false, rz = false, kx = 0, ky = 0, kr = 0, dx = 0, dy = 0, drz = 0 }
  if tipo == "articulado" then a.ux, a.uy = true, true
  elseif tipo == "rodilloX" then a.uy = true            -- libre en X, restringe Y
  elseif tipo == "rodilloY" then a.ux = true            -- libre en Y, restringe X
  elseif tipo == "empotrado" then a.ux, a.uy, a.rz = true, true, true
  end
  return a
end

-- "libre" | "articulado" | "rodilloX" | "rodilloY" | "empotrado" | "resorte" | "otro"
function ED.apoyo_tipo(a)
  if not a then return "libre" end
  local resorte = (a.kx or 0) > 0 or (a.ky or 0) > 0 or (a.kr or 0) > 0
  local ux, uy, rz = a.ux and true or false, a.uy and true or false, a.rz and true or false
  if resorte then
    if not (ux or uy or rz) then return "resorte" end
    return "otro"
  end
  if ux and uy and rz then return "empotrado" end
  if ux and uy and not rz then return "articulado" end
  if uy and not ux and not rz then return "rodilloX" end
  if ux and not uy and not rz then return "rodilloY" end
  if ux or uy or rz then return "otro" end
  return "libre"
end

function ED.set_apoyo_tipo(m, i, tipo)
  local n = m.nodos[i]
  if not n then return nil, "El nodo no existe" end
  if tipo == "libre" then n.apoyo = nil else n.apoyo = ED.apoyo_nuevo(tipo) end
  return true
end

function ED.set_resorte(m, i, kx, ky, kr)
  local n = m.nodos[i]
  if not n then return nil, "El nodo no existe" end
  if not (num(kx) and num(ky) and num(kr)) or kx < 0 or ky < 0 or kr < 0 then
    return nil, "Las rigideces deben ser numeros >= 0"
  end
  if kx == 0 and ky == 0 and kr == 0 then
    return nil, "Ingresa al menos una rigidez mayor que 0"
  end
  local a = ED.apoyo_nuevo("libre")
  a.kx, a.ky, a.kr = kx, ky, kr
  n.apoyo = a
  return true
end

function ED.set_asentamiento(m, i, dx, dy, drz)
  local n = m.nodos[i]
  if not n or not n.apoyo then return nil, "Primero asigna un apoyo a este nodo" end
  if not (num(dx) and num(dy) and num(drz)) then return nil, "Valores no validos" end
  n.apoyo.dx, n.apoyo.dy, n.apoyo.drz = dx, dy, drz
  return true
end

function ED.set_carga_nodo(m, i, fx, fy, mz)
  local n = m.nodos[i]
  if not n then return nil, "El nodo no existe" end
  if not (num(fx) and num(fy) and num(mz)) then return nil, "Valores no validos" end
  if fx == 0 and fy == 0 and mz == 0 then n.carga = nil
  else n.carga = { fx = fx, fy = fy, mz = mz } end
  return true
end

-- ---------------------------------------------------- normalizar / validar
-- Devuelve un modelo nuevo y completo a partir de una tabla guardada, o nil, msg.
function ED.normalizar(t)
  if type(t) ~= "table" or type(t.nodos) ~= "table" or type(t.barras) ~= "table" then
    return nil, "Modelo invalido"
  end
  local m = ED.nuevo()
  for i = 1, #t.nodos do
    local n = t.nodos[i]
    if type(n) ~= "table" or not num(n.x) or not num(n.y) then return nil, "Nodo " .. i .. " invalido" end
    local nn = { x = n.x, y = n.y }
    if type(n.apoyo) == "table" then
      local a = ED.apoyo_nuevo("libre")
      a.ux, a.uy, a.rz = n.apoyo.ux and true or false, n.apoyo.uy and true or false, n.apoyo.rz and true or false
      for _, k in ipairs({ "kx", "ky", "kr", "dx", "dy", "drz" }) do
        if num(n.apoyo[k]) then a[k] = n.apoyo[k] end
      end
      nn.apoyo = a
    end
    if type(n.carga) == "table" then
      local c = { fx = num(n.carga.fx) and n.carga.fx or 0, fy = num(n.carga.fy) and n.carga.fy or 0,
                  mz = num(n.carga.mz) and n.carga.mz or 0 }
      if c.fx ~= 0 or c.fy ~= 0 or c.mz ~= 0 then nn.carga = c end
    end
    m.nodos[i] = nn
  end
  for e = 1, #t.barras do
    local b = t.barras[e]
    if type(b) ~= "table" or not m.nodos[b.ni] or not m.nodos[b.nj] or b.ni == b.nj then
      return nil, "Barra " .. e .. " invalida"
    end
    local nb = {
      ni = b.ni, nj = b.nj,
      tipo = (b.tipo == "cercha") and "cercha" or "portico",
      E = (num(b.E) and b.E > 0) and b.E or ED.props.E,
      A = (num(b.A) and b.A > 0) and b.A or ED.props.A,
      I = (num(b.I) and b.I > 0) and b.I or ED.props.I,
      rot_i = b.rot_i and true or false, rot_j = b.rot_j and true or false, cargas = {},
    }
    m.barras[e] = nb
  end
  for e = 1, #t.barras do
    local cs = t.barras[e].cargas
    if type(cs) == "table" then
      for k = 1, #cs do
        local c = ED.copiar(cs[k])
        if type(c) == "table" and ED.validar_carga(m, e, c) then
          local b = m.barras[e]
          b.cargas[#b.cargas + 1] = c
        end
      end
    end
  end
  return m
end

-- ------------------------------------------------------ deshacer / rehacer
local undo, redo = {}, {}
ED.m = ED.nuevo()

local function cambio()
  if ED.on_cambio then ED.on_cambio() end
end
ED.cambio = cambio

local function limpiar_redo()
  redo = {}
end

-- Guarda una instantanea del modelo actual (llamar ANTES de modificarlo)
function ED.snap()
  undo[#undo + 1] = ED.copiar(ED.m)
  if #undo > ED.MAX_UNDO then table.remove(undo, 1) end
  limpiar_redo()
end

-- Retira la ultima instantanea y restaura ese estado sin crear "rehacer" (cancelar un gesto)
function ED.cancelar_snap()
  local s = table.remove(undo)
  if s then ED.m = s; cambio() end
end

-- Aplica fn(modelo) con instantanea previa. fn devuelve true (hubo cambio) o nil, msg.
-- Si falla, el modelo queda como estaba. Devuelve true | nil, msg.
function ED.hacer(fn)
  local antes = ED.copiar(ED.m)
  local ok, msg = fn(ED.m)
  if not ok then
    ED.m = antes
    return nil, msg
  end
  undo[#undo + 1] = antes
  if #undo > ED.MAX_UNDO then table.remove(undo, 1) end
  limpiar_redo()
  cambio()
  return true
end

function ED.puede_deshacer() return #undo > 0 end
function ED.puede_rehacer() return #redo > 0 end
function ED.n_undo() return #undo, #redo end

function ED.deshacer()
  if #undo == 0 then return nil, "No hay nada que deshacer" end
  redo[#redo + 1] = ED.m
  ED.m = table.remove(undo)
  cambio()
  return true
end

function ED.rehacer()
  if #redo == 0 then return nil, "No hay nada que rehacer" end
  undo[#undo + 1] = ED.m
  ED.m = table.remove(redo)
  cambio()
  return true
end

function ED.reiniciar_historial()
  undo, redo = {}, {}
end

-- Sustituye todo el modelo (Nuevo, Abrir, Ejemplos) de forma deshacible
function ED.reemplazar(m)
  return ED.hacer(function() ED.m = m; return true end)
end

-- --------------------------------------------------------------- biblioteca
ED.bib = {}   -- { {nombre=, modelo=}, ... }

function ED.nombres()
  local t = {}
  for i = 1, #ED.bib do t[i] = ED.bib[i].nombre end
  return t
end

function ED.nombre_libre()
  local k = 1
  while true do
    local nom = "Modelo" .. k
    local libre = true
    for i = 1, #ED.bib do if ED.bib[i].nombre == nom then libre = false end end
    if libre then return nom end
    k = k + 1
  end
end

function ED.guardar_como(nombre)
  nombre = (nombre or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if nombre == "" then return nil, "Escribe un nombre" end
  if #nombre > 14 then return nil, "Nombre demasiado largo (max 14)" end
  for i = 1, #ED.bib do
    if ED.bib[i].nombre == nombre then
      ED.bib[i].modelo = ED.copiar(ED.m)
      return true, "reemplazado"
    end
  end
  if #ED.bib >= ED.MAX_BIB then return nil, "Biblioteca llena (max 10): borra un modelo guardado" end
  ED.bib[#ED.bib + 1] = { nombre = nombre, modelo = ED.copiar(ED.m) }
  return true
end

function ED.abrir(nombre)
  for i = 1, #ED.bib do
    if ED.bib[i].nombre == nombre then
      local m, msg = ED.normalizar(ED.bib[i].modelo)
      if not m then return nil, msg end
      return ED.reemplazar(m)
    end
  end
  return nil, "No existe el modelo '" .. tostring(nombre) .. "'"
end

function ED.borrar_guardado(nombre)
  for i = 1, #ED.bib do
    if ED.bib[i].nombre == nombre then table.remove(ED.bib, i); return true end
  end
  return nil, "No existe el modelo"
end

-- --------------------------------------------------------- (de)serializar
-- Datos planos para el documento (on.save): modelo, propiedades globales y biblioteca
function ED.serializar(m)
  return ED.copiar(m or ED.m)
end

function ED.deserializar(t)
  return ED.normalizar(t)
end

function ED.exportar()
  return { ver = 1, modelo = ED.serializar(ED.m), props = ED.copiar(ED.props), bib = ED.copiar(ED.bib) }
end

function ED.importar(t)
  if type(t) ~= "table" then return nil, "Datos invalidos" end
  if type(t.props) == "table" then
    local p = t.props
    if num(p.E) and p.E > 0 then ED.props.E = p.E end
    if num(p.A) and p.A > 0 then ED.props.A = p.A end
    if num(p.I) and p.I > 0 then ED.props.I = p.I end
    ED.props.tipo = (p.tipo == "cercha") and "cercha" or "portico"
  end
  ED.bib = {}
  if type(t.bib) == "table" then
    for i = 1, #t.bib do
      local b = t.bib[i]
      if type(b) == "table" and type(b.nombre) == "string" and ED.normalizar(b.modelo) and #ED.bib < ED.MAX_BIB then
        ED.bib[#ED.bib + 1] = { nombre = b.nombre, modelo = ED.copiar(b.modelo) }
      end
    end
  end
  local m = ED.normalizar(t.modelo)
  if not m then m = ED.nuevo() end
  ED.m = m
  ED.reiniciar_historial()
  cambio()
  return true
end

-- ----------------------------------------------------------------- ejemplos
ED.ejemplos = { "Viga apoyada", "Voladizo", "Viga continua", "Cercha", "Portal" }

local function barra(m, i, j, tipo)
  local e = ED.agregar_barra(m, i, j, ED.PROPS_DEFECTO)
  if tipo then m.barras[e].tipo = tipo end
  return e
end

local function carga_w(m, e, w, dir)
  ED.agregar_carga_barra(m, e, { t = "w", a = 0, b = ED.longitud(m, e), w1 = w, w2 = w, dir = dir or "GY" })
end

local CONSTRUCTORES = {
  ["Viga apoyada"] = function(m)
    local a = ED.agregar_nodo(m, 0, 0)
    local b = ED.agregar_nodo(m, 6, 0)
    local e = barra(m, a, b)
    ED.set_apoyo_tipo(m, a, "articulado")
    ED.set_apoyo_tipo(m, b, "rodilloX")
    carga_w(m, e, -10)
  end,
  ["Voladizo"] = function(m)
    local a = ED.agregar_nodo(m, 0, 0)
    local b = ED.agregar_nodo(m, 4, 0)
    barra(m, a, b)
    ED.set_apoyo_tipo(m, a, "empotrado")
    ED.set_carga_nodo(m, b, 0, -10, 0)
  end,
  ["Viga continua"] = function(m)
    local a = ED.agregar_nodo(m, 0, 0)
    local b = ED.agregar_nodo(m, 5, 0)
    local c = ED.agregar_nodo(m, 10, 0)
    local e1 = barra(m, a, b)
    local e2 = barra(m, b, c)
    ED.set_apoyo_tipo(m, a, "articulado")
    ED.set_apoyo_tipo(m, b, "rodilloX")
    ED.set_apoyo_tipo(m, c, "rodilloX")
    carga_w(m, e1, -8)
    carga_w(m, e2, -8)
  end,
  ["Cercha"] = function(m)
    local n1 = ED.agregar_nodo(m, 0, 0)
    local n2 = ED.agregar_nodo(m, 3, 0)
    local n3 = ED.agregar_nodo(m, 6, 0)
    local n4 = ED.agregar_nodo(m, 1.5, 2)
    local n5 = ED.agregar_nodo(m, 4.5, 2)
    barra(m, n1, n2, "cercha"); barra(m, n2, n3, "cercha"); barra(m, n4, n5, "cercha")
    barra(m, n1, n4, "cercha"); barra(m, n4, n2, "cercha"); barra(m, n2, n5, "cercha")
    barra(m, n5, n3, "cercha")
    ED.set_apoyo_tipo(m, n1, "articulado")
    ED.set_apoyo_tipo(m, n3, "rodilloX")
    ED.set_carga_nodo(m, n4, 0, -10, 0)
    ED.set_carga_nodo(m, n5, 0, -10, 0)
  end,
  ["Portal"] = function(m)
    local n1 = ED.agregar_nodo(m, 0, 0)
    local n2 = ED.agregar_nodo(m, 0, 4)
    local n3 = ED.agregar_nodo(m, 6, 4)
    local n4 = ED.agregar_nodo(m, 6, 0)
    barra(m, n1, n2); local viga = barra(m, n2, n3); barra(m, n3, n4)
    ED.set_apoyo_tipo(m, n1, "empotrado")
    ED.set_apoyo_tipo(m, n4, "empotrado")
    ED.set_carga_nodo(m, n2, 20, 0, 0)
    carga_w(m, viga, -10)
  end,
}

function ED.ejemplo(nombre)
  local f = CONSTRUCTORES[nombre]
  if not f then return nil, "Ejemplo desconocido" end
  local m = ED.nuevo()
  f(m)
  return m
end

return ED
