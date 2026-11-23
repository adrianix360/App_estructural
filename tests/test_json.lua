-- C:\dev\tools\lua51\lua.exe tests/test_json.lua  (LUA_PATH="./?.lua;./tests/?.lua;./src/?.lua")
local json = require("json")
local fallos = 0
local function ok(c, m) if not c then fallos = fallos + 1; print("FALLA: " .. m) end end

local v = json.decode('{"a":1,"b":[1,2.5,-3e2,null,{"x":null,"y":true}],"s":"h\\"o\\n\\u00e1\\\\","f":false,"n":null,"e":[],"o":{}}')
ok(v and v.a == 1, "a")
ok(v.b[2] == 2.5 and v.b[3] == -300, "numeros")
ok(v.b[4] == json.null and #v.b == 5, "null en arreglo = centinela")
ok(v.b[5].x == nil and v.b[5].y == true, "null en objeto = ausente")
ok(v.s == 'h"o\n\195\161\\', "cadena con escapes")
ok(v.f == false and v.n == nil, "bool/null objeto")
ok(#v.e == 0 and next(v.o) == nil, "vacios")
ok(json.decode("[1,2") == nil, "error en arreglo abierto")
ok(json.decode('{"a":}') == nil, "error valor")
ok(json.decode("[1] x") == nil, "texto sobrante")
ok(json.decode("null") == json.null, "null raiz")

local m, err = json.decode_file("tests/casos/viga_apoyada_w.json")
ok(m and #m.nodos == 2 and m.barras[1].cargas[1].w1 == -10 and m.nodos[1].apoyo.ux == true, "caso real: " .. tostring(err))
local r = json.decode_file("tests/ref/cercha_triangular.json")
ok(r and r.d[1][3] == json.null, "rz null en nudo articulado = json.null")
ok(math.abs(r.reac["1"][2] - 15) < 1e-9 and r.barras[1].muestras[1][1] == 0, "ref real")

if fallos > 0 then print(fallos .. " fallos"); os.exit(1) end
print("test_json OK")
