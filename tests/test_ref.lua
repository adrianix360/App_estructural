-- tests/test_ref.lua: compara el solver Lua con el solver de referencia NumPy (tests/ref/*.json).
-- Metrica: |a-b| / max|campo del caso|. Umbral 1e-6.
local json = require("json")
local S = require("core.solver")
local E = require("core.esfuerzos")
local abs, max = math.abs, math.max
local TOL = 1e-6

local idx = json.decode_file("tests/ref/indice.json")
local hay_fallo = false

local function fmt(x) return string.format("%.1e", x) end

for _, nombre in ipairs(idx) do
  local m = json.decode_file("tests/casos/" .. nombre .. ".json")
  local ref = json.decode_file("tests/ref/" .. nombre .. ".json")
  local peor = { d = 0, reac = 0, fl = 0, N = 0, V = 0, M = 0, v = 0 }
  local notas = {}
  local escala = { d = 0, reac = 0, fl = 0, N = 0, V = 0, M = 0, v = 0 }
  local function esc(k, x) if x ~= nil and x ~= json.null and abs(x) > escala[k] then escala[k] = abs(x) end end
  -- escalas (maximo absoluto del campo en la referencia)
  for _, r in ipairs(ref.d) do for _, x in ipairs(r) do esc("d", x) end end
  for _, r in pairs(ref.reac) do for _, x in ipairs(r) do esc("reac", x) end end
  for _, b in ipairs(ref.barras) do
    for _, x in ipairs(b.fl) do esc("fl", x) end
    for _, f in ipairs(b.muestras) do
      esc("N", f[2]); esc("V", f[3]); esc("M", f[4]); esc("v", f[5])
    end
  end
  for k, v in pairs(escala) do if v < 1e-12 then escala[k] = 1 end end
  local function cmp(k, a, b, que)
    if a == nil or a ~= a then
      notas[#notas + 1] = "falta " .. que
      peor[k] = math.huge
      return
    end
    local e = abs(a - b) / escala[k]
    if e > peor[k] then peor[k] = e end
  end

  local ok, res, err = pcall(S.resolver, m)
  if not ok or not res then
    hay_fallo = true
    print(string.format("%-24s ERROR resolver: %s", nombre, tostring(ok and (err and (err.cod .. " " .. tostring(err.msg))) or res)))
  else
    E.construir(m, res)
    if res.clasif.tipo ~= ref.clasif.tipo or res.clasif.grado ~= ref.clasif.grado then
      notas[#notas + 1] = string.format("clasif %s/%s vs ref %s/%s", tostring(res.clasif.tipo),
        tostring(res.clasif.grado), ref.clasif.tipo, tostring(ref.clasif.grado))
    end
    local nombres = { "ux", "uy", "rz" }
    for i, r in ipairs(ref.d) do
      for c = 1, 3 do
        local rv, lv = r[c], res.d[i] and res.d[i][nombres[c]]
        if rv == json.null then
          if lv ~= nil then notas[#notas + 1] = "d" .. i .. nombres[c] .. " deberia ser nulo" end
        else
          cmp("d", lv, rv, "d" .. i .. nombres[c])
        end
      end
    end
    local rn = { "rx", "ry", "mz" }
    for k, r in pairs(ref.reac) do
      local lr = res.reac[tonumber(k)]
      if not lr then notas[#notas + 1] = "falta reac " .. k; peor.reac = math.huge
      else for c = 1, 3 do cmp("reac", lr[rn[c]], r[c], "reac" .. k .. rn[c]) end end
    end
    for k in pairs(res.reac) do
      if not ref.reac[tostring(k)] then notas[#notas + 1] = "reac sobrante " .. k end
    end
    for e, b in ipairs(ref.barras) do
      local rb = res.barras[e]
      for c = 1, 6 do cmp("fl", rb.fl[c], b.fl[c], "fl" .. e .. "." .. c) end
      local L = b.L
      local n = #b.muestras
      for i, f in ipairs(b.muestras) do
        local x = f[1]
        local sig = b.muestras[i + 1]
        local xe = x
        if sig and sig[1] == x then xe = x - 1e-9 * L end -- fila izquierda de un salto
        local N, V, M, _, v = E.eval(res, e, xe)
        cmp("N", N, f[2], "N"); cmp("V", V, f[3], "V"); cmp("M", M, f[4], "M"); cmp("v", v, f[5], "v")
      end
    end
  end
  if ok and res then
    local mal = #notas > 0
    for _, v in pairs(peor) do if v > TOL then mal = true end end
    if mal then hay_fallo = true end
    print(string.format("%-24s d %s reac %s fl %s N %s V %s M %s v %s  %s", nombre, fmt(peor.d), fmt(peor.reac),
      fmt(peor.fl), fmt(peor.N), fmt(peor.V), fmt(peor.M), fmt(peor.v), mal and "FALLA" or "ok"))
    for _, t in ipairs(notas) do print("    ! " .. t) end
  end
end
print(hay_fallo and "== test_ref: FALLOS" or "== test_ref: todo ok")
if hay_fallo then os.exit(1) end
