-- core/elemento.lua: elemento de porticos 2D Euler-Bernoulli (3 GDL por nodo).
-- GDL locales: 1 u_i, 2 v_i, 3 theta_i, 4 u_j, 5 v_j, 6 theta_j (ejes locales de la barra).
-- Convenio (docs/arquitectura.md §3): fl = k*dl + f0, fuerzas que los NODOS ejercen sobre la
-- barra; f0 = -(cargas equivalentes consistentes) = vector de empotramiento perfecto.
local M = {}

local sqrt = math.sqrt

-- Cuadratura de Gauss de 3 puntos (exacta hasta grado 5).
local G3X = { -0.7745966692414834, 0, 0.7745966692414834 }
local G3W = { 5 / 9, 8 / 9, 5 / 9 }

-- Direccion global (gx, gy) de una carga segun 'dir'; c, s = coseno y seno de la barra.
function M.dir_global(dir, c, s)
  if dir == "GX" then return 1, 0
  elseif dir == "L" then return -s, c
  elseif dir == "LX" then return c, s
  end
  return 0, 1 -- "GY" (por omision)
end

-- Componentes locales (kx, ky) de la direccion: q_local = w * (kx, ky).
function M.comp_local(dir, c, s)
  local gx, gy = M.dir_global(dir, c, s)
  return gx * c + gy * s, -gx * s + gy * c
end

-- Propiedades E, A, I de la barra. Si I falta (cercha), I ficticia solo para recuperar giros
-- de extremos liberados (no afecta N ni la rigidez axial).
function M.props(b, L)
  local I = b.I
  if not I or I <= 0 then I = (b.A or 0) * L * L * 1e-3 end
  return b.E, b.A, I
end

-- Rigidez local 6x6 (sin liberaciones).
function M.rigidez(E, A, I, L)
  local a = E * A / L
  local b = 12 * E * I / (L * L * L)
  local c = 6 * E * I / (L * L)
  local d = 4 * E * I / L
  local e = 2 * E * I / L
  return {
    { a, 0, 0, -a, 0, 0 },
    { 0, b, c, 0, -b, c },
    { 0, c, d, 0, -c, e },
    { -a, 0, 0, a, 0, 0 },
    { 0, -b, -c, 0, b, -c },
    { 0, c, e, 0, -c, d },
  }
end

local function acotar(a, L)
  if a < 0 then return 0 elseif a > L then return L end
  return a
end

-- Deformaciones impuestas de una carga termica {t="T"}: eps = alfa*du (axial) y
-- kappa = -alfa*dg/h (curvatura, con v'' = M/EI + kappa). Si dg = 0 no hace falta h.
function M.termica(q)
  local alfa = q.alfa or 1.2e-5
  local dg = q.dg or 0
  local kap = 0
  if dg ~= 0 then kap = -alfa * dg / q.h end
  return alfa * (q.du or 0), kap
end

-- Vector de empotramiento perfecto local f0 (6) por las cargas de la barra:
-- puntual P, momento M, distribuida lineal w (a..b), en dir GY/GX/L/LX.
function M.empotramiento(b, L, c, s)
  local f = { 0, 0, 0, 0, 0, 0 }
  local cargas = b.cargas
  if not cargas then return f end
  for k = 1, #cargas do
    local q = cargas[k]
    local t = q.t
    if t == "P" then
      local kx, ky = M.comp_local(q.dir, c, s)
      local p = q.p or 0
      local px, py = p * kx, p * ky
      local xi = acotar(q.a or 0, L) / L
      local x2 = xi * xi
      local x3 = x2 * xi
      f[1] = f[1] - px * (1 - xi)
      f[4] = f[4] - px * xi
      f[2] = f[2] - py * (1 - 3 * x2 + 2 * x3)
      f[3] = f[3] - py * L * (xi - 2 * x2 + x3)
      f[5] = f[5] - py * (3 * x2 - 2 * x3)
      f[6] = f[6] - py * L * (-x2 + x3)
    elseif t == "T" then
      -- Extremos empotrados: f0 = -EA*eps (axial) y -EI*kappa (giros), con signos de las
      -- fuerzas que los nodos ejercen sobre la barra: du>0 -> compresion (Fxi>0, Fxj<0).
      local E, A, I = M.props(b, L)
      local eps, kap = M.termica(q)
      f[1] = f[1] + E * A * eps
      f[4] = f[4] - E * A * eps
      f[3] = f[3] + E * I * kap
      f[6] = f[6] - E * I * kap
    elseif t == "M" then
      local m0 = q.m or 0
      local xi = acotar(q.a or 0, L) / L
      local x2 = xi * xi
      f[2] = f[2] - m0 * (-6 * xi + 6 * x2) / L
      f[3] = f[3] - m0 * (1 - 4 * xi + 3 * x2)
      f[5] = f[5] - m0 * (6 * xi - 6 * x2) / L
      f[6] = f[6] - m0 * (-2 * xi + 3 * x2)
    elseif t == "w" then
      local aa = acotar(q.a or 0, L)
      local bb = acotar(q.b or L, L)
      local l = bb - aa
      if l > 1e-12 then
        local kx, ky = M.comp_local(q.dir, c, s)
        local w1, w2 = q.w1 or 0, q.w2 or q.w1 or 0
        local wx1, wx2, wy1, wy2 = w1 * kx, w2 * kx, w1 * ky, w2 * ky
        for g = 1, 3 do
          local sp = aa + 0.5 * l * (1 + G3X[g])
          local wt = 0.5 * l * G3W[g]
          local r = (sp - aa) / l
          local qx = wx1 + (wx2 - wx1) * r
          local qy = wy1 + (wy2 - wy1) * r
          local xi = sp / L
          local x2 = xi * xi
          local x3 = x2 * xi
          f[1] = f[1] - wt * qx * (1 - xi)
          f[4] = f[4] - wt * qx * xi
          f[2] = f[2] - wt * qy * (1 - 3 * x2 + 2 * x3)
          f[3] = f[3] - wt * qy * L * (xi - 2 * x2 + x3)
          f[5] = f[5] - wt * qy * (3 * x2 - 2 * x3)
          f[6] = f[6] - wt * qy * L * (-x2 + x3)
        end
      end
    end
  end
  return f
end

-- Condensacion estatica de las liberaciones de momento (ri: theta_i, rj: theta_j).
-- Devuelve kc, fc nuevas (6x6 y 6) con filas/columnas liberadas = 0.
-- Con ambos liberados la rigidez transversal y de giro queda exactamente en cero.
function M.condensar(k, f, ri, rj)
  local kc, fc = {}, {}
  for i = 1, 6 do
    local r = {}
    local ki = k[i]
    for j = 1, 6 do r[j] = ki[j] end
    kc[i] = r
    fc[i] = f[i]
  end
  if not ri and not rj then return kc, fc end
  if ri and rj then
    local k33, k36, k66 = k[3][3], k[3][6], k[6][6]
    local det = k33 * k66 - k36 * k36
    local f3, f6 = f[3], f[6]
    for a = 1, 6 do
      local a3, a6 = k[a][3], k[a][6]
      -- inv(kbb) * [k3c; k6c] aplicado fila a fila
      local y3 = (k66 * a3 - k36 * a6) / det
      local y6 = (-k36 * a3 + k33 * a6) / det
      for cc = 1, 6 do
        kc[a][cc] = k[a][cc] - (y3 * k[3][cc] + y6 * k[6][cc])
      end
      fc[a] = f[a] - (y3 * f3 + y6 * f6)
    end
    for a = 1, 6 do
      kc[2][a], kc[a][2] = 0, 0
      kc[5][a], kc[a][5] = 0, 0
      kc[3][a], kc[a][3] = 0, 0
      kc[6][a], kc[a][6] = 0, 0
    end
    fc[3], fc[6] = 0, 0
  else
    local r = ri and 3 or 6
    local krr = k[r][r]
    local fr = f[r]
    for a = 1, 6 do
      local f1 = k[a][r] / krr
      for cc = 1, 6 do kc[a][cc] = k[a][cc] - f1 * k[r][cc] end
      fc[a] = f[a] - f1 * fr
    end
    for a = 1, 6 do kc[r][a], kc[a][r] = 0, 0 end
    fc[r] = 0
  end
  return kc, fc
end

-- Recupera los giros de extremo liberados en dl (EN SITIO) a partir de k, f SIN condensar
-- y de los demas desplazamientos locales de dl.
function M.recuperar(k, f, ri, rj, dl)
  if not ri and not rj then return end
  if ri and rj then
    local s3, s6 = f[3], f[6]
    local idx = { 1, 2, 4, 5 }
    for n = 1, 4 do
      local a = idx[n]
      s3 = s3 + k[3][a] * dl[a]
      s6 = s6 + k[6][a] * dl[a]
    end
    local k33, k36, k66 = k[3][3], k[3][6], k[6][6]
    local det = k33 * k66 - k36 * k36
    dl[3] = -(k66 * s3 - k36 * s6) / det
    dl[6] = -(-k36 * s3 + k33 * s6) / det
  else
    local r = ri and 3 or 6
    local sm = f[r]
    for a = 1, 6 do
      if a ~= r then sm = sm + k[r][a] * dl[a] end
    end
    dl[r] = -sm / k[r][r]
  end
end

-- Transforma k (6x6 local) y f (6 local) a ejes globales: kg = T' k T, fg = T' f.
function M.transformar(k, f, c, s)
  local T = {
    { c, s, 0, 0, 0, 0 },
    { -s, c, 0, 0, 0, 0 },
    { 0, 0, 1, 0, 0, 0 },
    { 0, 0, 0, c, s, 0 },
    { 0, 0, 0, -s, c, 0 },
    { 0, 0, 0, 0, 0, 1 },
  }
  local A = {}
  for i = 1, 6 do
    local r, ki = {}, k[i]
    for j = 1, 6 do
      local sm = 0
      for m = 1, 6 do sm = sm + ki[m] * T[m][j] end
      r[j] = sm
    end
    A[i] = r
  end
  local kg = {}
  for i = 1, 6 do
    local r = {}
    for j = 1, 6 do
      local sm = 0
      for m = 1, 6 do sm = sm + T[m][i] * A[m][j] end
      r[j] = sm
    end
    kg[i] = r
  end
  local fg = {}
  for i = 1, 6 do
    local sm = 0
    for m = 1, 6 do sm = sm + T[m][i] * f[m] end
    fg[i] = sm
  end
  return kg, fg
end

-- Vector local (6) a global: v_g = T' v_l  (fuerzas o desplazamientos).
function M.a_global(v, c, s)
  return {
    c * v[1] - s * v[2], s * v[1] + c * v[2], v[3],
    c * v[4] - s * v[5], s * v[4] + c * v[5], v[6],
  }
end

-- Desplazamientos globales (6) a locales: d_l = T d_g.
function M.a_local(d, c, s)
  return {
    c * d[1] + s * d[2], -s * d[1] + c * d[2], d[3],
    c * d[4] + s * d[5], -s * d[4] + c * d[5], d[6],
  }
end

-- Resultante de las cargas de una barra en ejes globales:
-- devuelve Fx, Fy, M (respecto al origen global, antihorario +) y suma de |F| y |F|*brazo
-- (escalas para medir el residuo de equilibrio). (xi, yi) = coordenadas del nodo i.
function M.resultante(b, xi, yi, c, s, L)
  local fx, fy, mo, sf, sm = 0, 0, 0, 0, 0
  local cargas = b.cargas
  if not cargas then return fx, fy, mo, sf, sm end
  for k = 1, #cargas do
    local q = cargas[k]
    local t = q.t
    if t == "P" then
      local gx, gy = M.dir_global(q.dir, c, s)
      local p = q.p or 0
      local a = acotar(q.a or 0, L)
      local x, y = xi + c * a, yi + s * a
      local px, py = p * gx, p * gy
      fx = fx + px
      fy = fy + py
      mo = mo + x * py - y * px
      sf = sf + math.abs(px) + math.abs(py)
      sm = sm + math.abs(x * py) + math.abs(y * px)
    elseif t == "M" then
      local m0 = q.m or 0
      mo = mo + m0
      sm = sm + math.abs(m0)
    elseif t == "w" then
      local aa = acotar(q.a or 0, L)
      local bb = acotar(q.b or L, L)
      local l = bb - aa
      if l > 1e-12 then
        local gx, gy = M.dir_global(q.dir, c, s)
        local w1, w2 = q.w1 or 0, q.w2 or q.w1 or 0
        for g = 1, 3 do
          local sp = aa + 0.5 * l * (1 + G3X[g])
          local wt = 0.5 * l * G3W[g]
          local w = w1 + (w2 - w1) * (sp - aa) / l
          local x, y = xi + c * sp, yi + s * sp
          local px, py = wt * w * gx, wt * w * gy
          fx = fx + px
          fy = fy + py
          mo = mo + x * py - y * px
          sf = sf + math.abs(px) + math.abs(py)
          sm = sm + math.abs(x * py) + math.abs(y * px)
        end
      end
    end
  end
  return fx, fy, mo, sf, sm
end

return M
