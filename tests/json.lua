-- Decodificador JSON minimo para Lua 5.1 (solo pruebas de escritorio; usa io solo en decode_file).
-- json.decode(str) -> valor | nil, "error"
--   objeto  -> tabla con claves string; los valores null se OMITEN (clave ausente = nil)
--   arreglo -> tabla 1..n; los null se representan con el CENTINELA json.null (para no perder huecos)
--   null en la raiz -> json.null
-- json.decode_file(ruta) -> valor | nil, err
local json = {}
json.null = setmetatable({}, { __tostring = function() return "json.null" end })

local function utf8char(cp)
  if cp < 0x80 then return string.char(cp)
  elseif cp < 0x800 then return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64)
  else return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64) end
end

local ESC = { ['"'] = '"', ['\\'] = '\\', ['/'] = '/', b = '\b', f = '\f', n = '\n', r = '\r', t = '\t' }

local function skip(s, i)
  return s:find("[^ \t\r\n]", i) or (#s + 1)
end

local parse

local function parse_string(s, i) -- s:sub(i,i) == '"'
  local buf, j = {}, i + 1
  while true do
    local k = s:find('["\\]', j)
    if not k then error("cadena sin cerrar en " .. i, 0) end
    buf[#buf + 1] = s:sub(j, k - 1)
    if s:sub(k, k) == '"' then return table.concat(buf), k + 1 end
    local e = s:sub(k + 1, k + 1)
    if e == "u" then
      local hex = s:match("^%x%x%x%x", k + 2)
      if not hex then error("escape \\u invalido en " .. k, 0) end
      buf[#buf + 1] = utf8char(tonumber(hex, 16))
      j = k + 6
    elseif ESC[e] then
      buf[#buf + 1] = ESC[e]
      j = k + 2
    else
      error("escape invalido en " .. k, 0)
    end
  end
end

parse = function(s, i)
  i = skip(s, i)
  local c = s:sub(i, i)
  if c == "{" then
    local t = {}
    i = skip(s, i + 1)
    if s:sub(i, i) == "}" then return t, i + 1 end
    while true do
      if s:sub(i, i) ~= '"' then error("se esperaba clave en " .. i, 0) end
      local key
      key, i = parse_string(s, i)
      i = skip(s, i)
      if s:sub(i, i) ~= ":" then error("se esperaba ':' en " .. i, 0) end
      local val
      val, i = parse(s, i + 1)
      if val ~= json.null then t[key] = val end
      i = skip(s, i)
      local d = s:sub(i, i)
      if d == "}" then return t, i + 1 end
      if d ~= "," then error("se esperaba ',' o '}' en " .. i, 0) end
      i = skip(s, i + 1)
    end
  elseif c == "[" then
    local t, n = {}, 0
    i = skip(s, i + 1)
    if s:sub(i, i) == "]" then return t, i + 1 end
    while true do
      local val
      val, i = parse(s, i)
      n = n + 1
      t[n] = val
      i = skip(s, i)
      local d = s:sub(i, i)
      if d == "]" then return t, i + 1 end
      if d ~= "," then error("se esperaba ',' o ']' en " .. i, 0) end
      i = i + 1
    end
  elseif c == '"' then
    return parse_string(s, i)
  elseif s:sub(i, i + 3) == "true" then return true, i + 4
  elseif s:sub(i, i + 4) == "false" then return false, i + 5
  elseif s:sub(i, i + 3) == "null" then return json.null, i + 4
  else
    local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
    if not num or num == "" or not tonumber(num) then error("valor invalido en " .. i, 0) end
    return tonumber(num), i + #num
  end
end

function json.decode(s)
  local ok, v, i = pcall(parse, s, 1)
  if not ok then return nil, v end
  i = skip(s, i)
  if i <= #s then return nil, "texto sobrante en " .. i end
  return v
end

function json.decode_file(path)
  local f, err = io.open(path, "rb")
  if not f then return nil, err end
  local s = f:read("*a")
  f:close()
  return json.decode(s)
end

return json
