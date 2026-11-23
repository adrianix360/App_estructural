-- ui/dialogo.lua - Dialogos modales propios (formularios numericos, menus de lista, texto).
-- Un solo dialogo activo a la vez (D.activo()). main.lua le enruta todos los eventos mientras exista.
--   D.form{ titulo=, campos={ {id=,etq=,tipo="num"|"texto"|"opcion",valor=,opciones={..},min=,max=} },
--           aceptar=function(v) -> nil | "mensaje de error" , cancelar=fn }
--      v[id] = numero | texto | indice de opcion. Num: ENTER aceptar, ESC cancelar, flechas arriba/abajo
--      cambian de campo, izquierda/derecha cambian la opcion, el primer caracter reemplaza el valor.
--   D.menu{ titulo=, items={..}, sel=, elegir=function(i) }   (digitos 1-9 eligen directo)
--   D.texto(titulo, lineas)   visor con desplazamiento       D.aviso(msg, titulo)   mensaje con ajuste
local D = {}

local floor, min, max = math.floor, math.min, math.max

local W, H = 318, 212
local cur = nil
D.lh = 12

local ROWH = 17
local TITH = 17
local BTNH = 20

function D.size(w, h) W, H = w, h; if cur then D.colocar(cur) end end
function D.activo() return cur end
function D.cerrar() cur = nil end

-- ---------------------------------------------------------------- numeros
local function parse_num(s)
  if type(s) ~= "string" then return nil end
  s = s:gsub("\226\136\146", "-"):gsub(",", "."):gsub("%s", "")
  if s == "" or s:find("[xXnN]") then return nil end
  local v = tonumber(s)
  if not v then
    local a, b = s:match("^([^/]+)/([^/]+)$")
    a, b = tonumber(a or ""), tonumber(b or "")
    if a and b and b ~= 0 then v = a / b end
  end
  if v and (v ~= v or v == math.huge or v == -math.huge) then return nil end
  return v
end
D.parse_num = parse_num

local function fmt_num(v)
  if type(v) ~= "number" then return "" end
  local s = string.format("%.6g", v)
  if s:find("e", 1, true) then return s end
  return s
end
D.fmt_num = fmt_num

-- Ajuste de texto por numero de caracteres (aprox. 6.2 px por caracter a 9 pt)
function D.ajustar(texto, ancho_px)
  local n = floor(ancho_px / 6.2)
  local out = {}
  for parte in (texto .. "\n"):gmatch("(.-)\n") do
    local linea = ""
    for palabra in parte:gmatch("%S+") do
      if linea == "" then linea = palabra
      elseif #linea + 1 + #palabra <= n then linea = linea .. " " .. palabra
      else out[#out + 1] = linea; linea = palabra end
    end
    out[#out + 1] = linea
  end
  return out
end

-- -------------------------------------------------------------- geometria
function D.colocar(d)
  local bw
  if d.kind == "form" then
    bw = min(W - 8, 292)
    local reservado = TITH + 14 + BTNH + 8
    local vis = min(#d.campos, floor((H - reservado - 6) / ROWH))
    if vis < 1 then vis = 1 end
    d.vis = vis
    d.bh = TITH + vis * ROWH + 14 + BTNH + 6
  elseif d.kind == "menu" then
    bw = min(W - 8, d.ancho or 250)
    local vis = min(#d.items, floor((H - TITH - 14) / ROWH))
    d.vis = vis
    d.bh = TITH + vis * ROWH + 8
  else
    bw = min(W - 8, 286)
    local vis = min(#d.lineas, floor((H - TITH - BTNH - 16) / 12))
    d.vis = vis
    d.bh = TITH + vis * 12 + BTNH + 10
  end
  d.bw = bw
  d.bx = floor((W - bw) / 2)
  d.by = max(2, floor((H - d.bh) / 2))
end

local function abrir(d)
  cur = d
  D.colocar(d)
  if platform and platform.window then platform.window:invalidate() end
  return d
end

-- --------------------------------------------------------------- creacion
function D.form(spec)
  local d = { kind = "form", titulo = spec.titulo or "", campos = {}, idx = 1, top = 1,
              aceptar = spec.aceptar, cancelar = spec.cancelar, msg = nil }
  for i, c in ipairs(spec.campos) do
    local f = { id = c.id, etq = c.etq, tipo = c.tipo or "num", opciones = c.opciones,
                min = c.min, max = c.max, fresh = true }
    if f.tipo == "opcion" then f.opt = c.valor or 1
    elseif f.tipo == "texto" then f.buf = c.valor or ""
    else f.buf = fmt_num(c.valor) end
    d.campos[i] = f
  end
  return abrir(d)
end

function D.menu(spec)
  local d = { kind = "menu", titulo = spec.titulo or "", items = spec.items, sel = spec.sel or 1,
              top = 1, elegir = spec.elegir, ancho = spec.ancho, txt = {} }
  for i, it in ipairs(d.items) do
    d.txt[i] = (i <= 9) and (i .. "  " .. it) or ("    " .. it)
  end
  abrir(d)
  D.asegurar_visible(d)
  return d
end

function D.texto(titulo, lineas)
  return abrir({ kind = "texto", titulo = titulo or "", lineas = lineas, top = 1 })
end

function D.aviso(msg, titulo)
  local l = D.ajustar(msg, 270)
  return abrir({ kind = "texto", titulo = titulo or "Aviso", lineas = l, top = 1, corto = true })
end

function D.asegurar_visible(d)
  local n = (d.kind == "menu") and #d.items or #d.campos
  local sel = (d.kind == "menu") and d.sel or d.idx
  if sel < d.top then d.top = sel end
  if sel > d.top + d.vis - 1 then d.top = sel - d.vis + 1 end
  if d.top < 1 then d.top = 1 end
end

-- ----------------------------------------------------------------- cierre
local function cerrar_con(d, ok)
  if cur == d then cur = nil end
  if not ok and d.cancelar then d.cancelar() end
  if platform and platform.window then platform.window:invalidate() end
end

local function aceptar_form(d)
  local v = {}
  for i, f in ipairs(d.campos) do
    if f.tipo == "opcion" then v[f.id] = f.opt
    elseif f.tipo == "texto" then v[f.id] = f.buf
    else
      local x = parse_num(f.buf)
      if not x then
        d.idx = i; D.asegurar_visible(d)
        d.msg = "'" .. f.etq .. "' no es un numero valido"
        return
      end
      if f.min and x < f.min then
        d.idx = i; D.asegurar_visible(d)
        d.msg = "'" .. f.etq .. "' debe ser >= " .. fmt_num(f.min); return
      end
      if f.max and x > f.max then
        d.idx = i; D.asegurar_visible(d)
        d.msg = "'" .. f.etq .. "' debe ser <= " .. fmt_num(f.max); return
      end
      v[f.id] = x
    end
  end
  cur = nil
  local err = d.aceptar and d.aceptar(v)
  if err then
    if cur == nil then cur = d end
    d.msg = err
  end
  if platform and platform.window then platform.window:invalidate() end
end

-- ----------------------------------------------------------------- eventos
-- Todas devuelven true si hay dialogo (el evento queda consumido).
local function cambiar_opcion(f, delta)
  local n = #f.opciones
  f.opt = (f.opt - 1 + delta) % n + 1
end

local NUMCH = "0123456789.,-+/eE"

function D.charIn(c)
  local d = cur
  if not d then return false end
  if d.kind == "menu" then
    local k = tonumber(c)
    if k and k >= 1 and k <= 9 and k <= #d.items then
      cur = nil
      if d.elegir then d.elegir(k) end
      if platform and platform.window then platform.window:invalidate() end
    end
  elseif d.kind == "form" then
    local f = d.campos[d.idx]
    if f.tipo == "num" then
      if NUMCH:find(c, 1, true) or c == "\226\136\146" then
        if f.fresh then f.buf = ""; f.fresh = false end
        if #f.buf < 14 then f.buf = f.buf .. (c == "\226\136\146" and "-" or c) end
        d.msg = nil
      end
    elseif f.tipo == "texto" then
      if f.fresh then f.buf = ""; f.fresh = false end
      if #f.buf < 14 and (#c > 1 or c:byte() >= 32) then f.buf = f.buf .. c end
      d.msg = nil
    elseif c == " " then cambiar_opcion(f, 1) end
  end
  if platform and platform.window then platform.window:invalidate() end
  return true
end

function D.arrow(k)
  local d = cur
  if not d then return false end
  if d.kind == "form" then
    local n = #d.campos
    if k == "up" then d.idx = (d.idx - 2) % n + 1
    elseif k == "down" then d.idx = d.idx % n + 1
    else
      local f = d.campos[d.idx]
      if f.tipo == "opcion" then cambiar_opcion(f, k == "right" and 1 or -1) end
    end
    D.asegurar_visible(d)
  elseif d.kind == "menu" then
    local n = #d.items
    if k == "up" then d.sel = (d.sel - 2) % n + 1
    elseif k == "down" then d.sel = d.sel % n + 1 end
    D.asegurar_visible(d)
  else
    if k == "up" then d.top = max(1, d.top - 1)
    elseif k == "down" then d.top = max(1, min(#d.lineas - d.vis + 1, d.top + 1)) end
  end
  if platform and platform.window then platform.window:invalidate() end
  return true
end

function D.tab()
  local d = cur
  if not d then return false end
  if d.kind == "form" then d.idx = d.idx % #d.campos + 1; D.asegurar_visible(d) end
  if platform and platform.window then platform.window:invalidate() end
  return true
end

function D.enter()
  local d = cur
  if not d then return false end
  if d.kind == "form" then aceptar_form(d)
  elseif d.kind == "menu" then
    local i = d.sel
    cur = nil
    if d.elegir then d.elegir(i) end
    if platform and platform.window then platform.window:invalidate() end
  else cerrar_con(d, true) end
  return true
end

function D.esc()
  local d = cur
  if not d then return false end
  cerrar_con(d, false)
  return true
end

function D.backspace()
  local d = cur
  if not d then return false end
  if d.kind == "form" then
    local f = d.campos[d.idx]
    if f.tipo ~= "opcion" then
      if f.fresh then f.buf = ""; f.fresh = false
      else f.buf = f.buf:sub(1, #f.buf - 1) end
      d.msg = nil
    end
  end
  if platform and platform.window then platform.window:invalidate() end
  return true
end

-- Posiciones de botones del formulario
local function botones(d)
  local y = d.by + d.bh - BTNH - 4
  local bw = floor((d.bw - 24) / 2)
  return d.bx + 8, y, bw, d.bx + 16 + bw, bw   -- x1, y, w, x2, w
end

local function dentro(x, y, rx, ry, rw, rh)
  return x >= rx and x < rx + rw and y >= ry and y < ry + rh
end

function D.mouseDown(x, y)
  local d = cur
  if not d then return false end
  if d.kind == "form" then
    local x1, by, bw, x2 = botones(d)
    if dentro(x, y, x1, by, bw, BTNH) then aceptar_form(d); return true end
    if dentro(x, y, x2, by, bw, BTNH) then cerrar_con(d, false); return true end
    for k = 0, d.vis - 1 do
      local i = d.top + k
      local ry = d.by + TITH + k * ROWH
      if i <= #d.campos and dentro(x, y, d.bx, ry, d.bw, ROWH) then
        d.idx = i
        local f = d.campos[i]
        if f.tipo == "opcion" and x > d.bx + floor(d.bw * 0.45) then cambiar_opcion(f, 1) end
        break
      end
    end
  elseif d.kind == "menu" then
    for k = 0, d.vis - 1 do
      local i = d.top + k
      local ry = d.by + TITH + k * ROWH
      if i <= #d.items and dentro(x, y, d.bx, ry, d.bw, ROWH) then
        cur = nil
        if d.elegir then d.elegir(i) end
        break
      end
    end
  else
    local bx = d.bx + floor(d.bw / 2) - 40
    local by = d.by + d.bh - BTNH - 4
    if dentro(x, y, bx, by, 80, BTNH) then cerrar_con(d, true) end
  end
  if platform and platform.window then platform.window:invalidate() end
  return true
end

function D.mouseMove(x, y)
  local d = cur
  if not d then return false end
  if d.kind == "menu" then
    for k = 0, d.vis - 1 do
      local i = d.top + k
      local ry = d.by + TITH + k * ROWH
      if i <= #d.items and dentro(x, y, d.bx, ry, d.bw, ROWH) then
        if d.sel ~= i then
          d.sel = i
          if platform and platform.window then platform.window:invalidate() end
        end
        break
      end
    end
  end
  return true
end

-- ------------------------------------------------------------------ dibujo
local lastc, lastf
local function col(gc, r, g, b)
  gc:setColorRGB(r, g, b)
end
local function font(gc, style, size)
  gc:setFont("sansserif", style, size)
end

local function recortar(gc, s, ancho)
  if gc:getStringWidth(s) <= ancho then return s end
  while #s > 1 and gc:getStringWidth(s .. "..") > ancho do s = s:sub(1, #s - 1) end
  return s .. ".."
end

local function marco(gc, d)
  col(gc, 120, 120, 135); gc:fillRect(d.bx + 3, d.by + 3, d.bw, d.bh)
  col(gc, 247, 247, 252); gc:fillRect(d.bx, d.by, d.bw, d.bh)
  col(gc, 0, 70, 140); gc:fillRect(d.bx, d.by, d.bw, TITH)
  gc:setPen("thin", "smooth")
  gc:drawRect(d.bx, d.by, d.bw, d.bh)
  font(gc, "b", 9); col(gc, 255, 255, 255)
  gc:drawString(recortar(gc, d.titulo, d.bw - 12), d.bx + 6, d.by + 2, "top")
end

local function boton(gc, x, y, w, texto, principal)
  if principal then col(gc, 0, 90, 190) else col(gc, 225, 225, 232) end
  gc:fillRect(x, y, w, BTNH)
  col(gc, 0, 70, 140); gc:drawRect(x, y, w, BTNH)
  if principal then col(gc, 255, 255, 255) else col(gc, 20, 20, 20) end
  font(gc, "r", 9)
  gc:drawString(texto, x + floor((w - gc:getStringWidth(texto)) / 2), y + 4, "top")
end

local function flecha_scroll(gc, x, y, arriba)
  col(gc, 90, 90, 110)
  if arriba then gc:fillPolygon({ x, y + 4, x + 8, y + 4, x + 4, y })
  else gc:fillPolygon({ x, y, x + 8, y, x + 4, y + 4 }) end
end

function D.pintar(gc)
  local d = cur
  if not d then return end
  marco(gc, d)
  if d.kind == "form" then
    local vx = d.bx + floor(d.bw * 0.46)
    local vw = d.bx + d.bw - 8 - vx
    for k = 0, d.vis - 1 do
      local i = d.top + k
      local f = d.campos[i]
      if not f then break end
      local ry = d.by + TITH + k * ROWH
      if i == d.idx then col(gc, 205, 228, 255); gc:fillRect(d.bx + 1, ry, d.bw - 2, ROWH) end
      font(gc, "r", 9); col(gc, 20, 20, 20)
      gc:drawString(recortar(gc, f.etq, vx - d.bx - 8), d.bx + 6, ry + 2, "top")
      col(gc, 255, 255, 255); gc:fillRect(vx, ry + 1, vw, ROWH - 3)
      if i == d.idx then col(gc, 0, 90, 190) else col(gc, 150, 150, 160) end
      gc:drawRect(vx, ry + 1, vw, ROWH - 3)
      col(gc, 0, 0, 0)
      local t
      if f.tipo == "opcion" then t = "< " .. f.opciones[f.opt] .. " >"
      else t = f.buf .. ((i == d.idx and not f.fresh) and "|" or "") end
      if f.tipo ~= "opcion" and i == d.idx and f.fresh then
        -- valor "seleccionado": se reemplaza al teclear
        col(gc, 0, 90, 190); gc:fillRect(vx + 2, ry + 3, min(vw - 4, gc:getStringWidth(t) + 2), ROWH - 7)
        col(gc, 255, 255, 255)
      end
      gc:drawString(recortar(gc, t, vw - 6), vx + 3, ry + 2, "top")
    end
    if d.top > 1 then flecha_scroll(gc, d.bx + d.bw - 12, d.by + TITH + 1, true) end
    if d.top + d.vis - 1 < #d.campos then
      flecha_scroll(gc, d.bx + d.bw - 12, d.by + TITH + d.vis * ROWH - 5, false)
    end
    if d.msg then
      font(gc, "r", 9); col(gc, 190, 0, 0)
      gc:drawString(recortar(gc, d.msg, d.bw - 12), d.bx + 6, d.by + TITH + d.vis * ROWH + 1, "top")
    end
    local x1, by, bw, x2 = botones(d)
    boton(gc, x1, by, bw, "Aceptar (ENTER)", true)
    boton(gc, x2, by, bw, "Cancelar (ESC)", false)
  elseif d.kind == "menu" then
    for k = 0, d.vis - 1 do
      local i = d.top + k
      local it = d.txt[i]
      if not it then break end
      local ry = d.by + TITH + k * ROWH
      if i == d.sel then
        col(gc, 0, 90, 190); gc:fillRect(d.bx + 2, ry, d.bw - 4, ROWH); col(gc, 255, 255, 255)
      else col(gc, 20, 20, 20) end
      font(gc, "r", 9)
      gc:drawString(recortar(gc, it, d.bw - 14), d.bx + 8, ry + 2, "top")
    end
    if d.top > 1 then flecha_scroll(gc, d.bx + d.bw - 12, d.by + TITH + 1, true) end
    if d.top + d.vis - 1 < #d.items then
      flecha_scroll(gc, d.bx + d.bw - 12, d.by + TITH + d.vis * ROWH - 5, false)
    end
  else
    font(gc, "r", 9); col(gc, 20, 20, 20)
    for k = 0, d.vis - 1 do
      local l = d.lineas[d.top + k]
      if not l then break end
      gc:drawString(l, d.bx + 8, d.by + TITH + 3 + k * 12, "top")
    end
    if d.top > 1 then flecha_scroll(gc, d.bx + d.bw - 12, d.by + TITH + 1, true) end
    if d.top + d.vis - 1 < #d.lineas then
      flecha_scroll(gc, d.bx + d.bw - 12, d.by + d.bh - BTNH - 12, false)
    end
    boton(gc, d.bx + floor(d.bw / 2) - 40, d.by + d.bh - BTNH - 4, 80, "OK (ENTER)", true)
  end
end

return D
