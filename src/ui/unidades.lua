-- ui/unidades.lua - Unidades de presentacion (docs/arquitectura.md §4.1).
-- El modelo SIEMPRE esta en kN, m, rad (E en kN/m2, A en m2, I en m4). Este modulo solo convierte
-- lo que se ve y lo que se teclea.
--   U.actual                   "kN-m" | "N-m" | "tf-m"        U.ver  sube con cada cambio de sistema
--   U.set(nombre) -> bool      U.siguiente() -> nombre        U.indice() -> 1..3
--   U.factor(cant)             presentacion = interna * factor
--   U.de_interna(cant, v)      U.a_interna(cant, v)           U.etiqueta(cant) -> "kN", "kN/m", ...
--   U.num(v, sig)              numero con cifras significativas (sin notacion cientifica)
--   U.txt(cant, v, sig)        "45 kN·m"                      U.defecto(cant) valor tipico para formularios
-- cant: fuerza, long, dist, momento, E, A, I, desp, giro, temp, alfa, canto, rig (fuerza/long), rigrot.
local U = {}

local floor, abs, log10 = math.floor, math.abs, math.log10
local format = string.format

local TF = 9.80665                       -- 1 tf = 9.80665 kN
U.TF = TF
U.sistemas = { "kN-m", "N-m", "tf-m" }
U.nombres = { "kN, m (E en GPa)", "N, m (SI: E en Pa)", "tf, m (E en kgf/cm2)" }

-- cant = { factor de interna a presentacion, etiqueta }
local T = {
  ["kN-m"] = {
    fuerza = { 1, "kN" }, long = { 1, "m" }, dist = { 1, "kN/m" }, momento = { 1, "kN·m" },
    E = { 1e-6, "GPa" }, A = { 1e4, "cm²" }, I = { 1e8, "cm4" },
    desp = { 1000, "mm" }, giro = { 1000, "mrad" }, temp = { 1, "°C" }, alfa = { 1e6, "1e-6/°C" },
    canto = { 100, "cm" }, rig = { 1, "kN/m" }, rigrot = { 1, "kN·m/rad" },
  },
  ["N-m"] = {
    fuerza = { 1000, "N" }, long = { 1, "m" }, dist = { 1000, "N/m" }, momento = { 1000, "N·m" },
    E = { 1000, "Pa" }, A = { 1, "m²" }, I = { 1, "m4" },
    desp = { 1, "m" }, giro = { 1, "rad" }, temp = { 1, "°C" }, alfa = { 1e6, "1e-6/°C" },
    canto = { 1, "m" }, rig = { 1000, "N/m" }, rigrot = { 1000, "N·m/rad" },
  },
  ["tf-m"] = {
    fuerza = { 1 / TF, "tf" }, long = { 1, "m" }, dist = { 1 / TF, "tf/m" }, momento = { 1 / TF, "tf·m" },
    E = { 1000 / TF / 1e4, "kgf/cm²" }, A = { 1e4, "cm²" }, I = { 1e8, "cm4" },
    desp = { 1000, "mm" }, giro = { 1000, "mrad" }, temp = { 1, "°C" }, alfa = { 1e6, "1e-6/°C" },
    canto = { 100, "cm" }, rig = { 1 / TF, "tf/m" }, rigrot = { 1 / TF, "tf·m/rad" },
  },
}
-- valor "redondo" por omision (equivale a ~10 kN) para los formularios
local DEFECTO = { ["kN-m"] = 10, ["N-m"] = 10000, ["tf-m"] = 1 }

U.actual = "kN-m"
U.ver = 0
local cur = T["kN-m"]

function U.set(nombre)
  if not T[nombre] then return false end
  if nombre ~= U.actual then
    U.actual = nombre
    cur = T[nombre]
    U.ver = U.ver + 1
  end
  return true
end

function U.indice()
  for i = 1, #U.sistemas do if U.sistemas[i] == U.actual then return i end end
  return 1
end

function U.siguiente()
  local i = U.indice() % #U.sistemas + 1
  U.set(U.sistemas[i])
  return U.actual
end

function U.factor(cant) return cur[cant][1] end
function U.etiqueta(cant) return cur[cant][2] end
function U.de_interna(cant, v) return v * cur[cant][1] end
function U.a_interna(cant, v) return v / cur[cant][1] end
function U.defecto(cant)
  if cant == "fuerza" or cant == "dist" or cant == "momento" then return DEFECTO[U.actual] end
  return 1
end

-- Cifras significativas sin notacion cientifica; |v| < 1e-6 se muestra 0.
function U.num(v, sig)
  if v ~= v then return "nan" end
  local a = abs(v)
  if a < 1e-6 then return "0" end
  sig = sig or 4
  local d = sig - 1 - floor(log10(a) + 1e-12)
  if d < 0 then d = 0 elseif d > 8 then d = 8 end
  local s = format("%." .. d .. "f", v)
  if s:find(".", 1, true) then
    s = s:gsub("0+$", "")
    s = s:gsub("%.$", "")
  end
  if s == "-0" then s = "0" end
  return s
end

-- valor interno -> "45 kN·m" en el sistema actual
function U.txt(cant, v, sig)
  return U.num(v * cur[cant][1], sig) .. " " .. cur[cant][2]
end

return U
