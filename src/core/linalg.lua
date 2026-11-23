-- core/linalg.lua: algebra lineal densa minima (sin dependencias).
-- Matrices = arreglo de filas (A[i][j]), base 1.
local M = {}

local abs = math.abs

-- Matriz n x m de ceros (m = n por omision).
function M.mat(n, m)
  m = m or n
  local A = {}
  for i = 1, n do
    local r = {}
    for j = 1, m do r[j] = 0 end
    A[i] = r
  end
  return A
end

-- Resuelve K x = F por Gauss con pivoteo parcial (por filas).
--   n        : tamano (por omision #F)
--   inplace  : si es true destruye K y F (ahorra memoria); si no, trabaja sobre copias.
-- Devuelve x, o nil + indice (1..n) de la incognita cuyo pivote es ~0
-- (tolerancia relativa 1e-12 * mayor |diagonal|). Matriz singular / mecanismo.
function M.solve(K, F, n, inplace)
  n = n or #F
  if n == 0 then return {} end
  local A, b
  if inplace then
    A, b = K, F
  else
    A, b = {}, {}
    for i = 1, n do
      local r, ri = {}, K[i]
      for j = 1, n do r[j] = ri[j] end
      A[i] = r
      b[i] = F[i]
    end
  end
  local dmax = 0
  for i = 1, n do
    local d = abs(A[i][i])
    if d > dmax then dmax = d end
  end
  if dmax == 0 then
    for i = 1, n do
      local ri = A[i]
      for j = 1, n do
        local v = abs(ri[j])
        if v > dmax then dmax = v end
      end
    end
    if dmax == 0 then return nil, 1 end
  end
  local tol = 1e-12 * dmax
  for k = 1, n do
    local p, pv = k, abs(A[k][k])
    for i = k + 1, n do
      local v = abs(A[i][k])
      if v > pv then p, pv = i, v end
    end
    if pv <= tol then return nil, k end
    if p ~= k then
      A[p], A[k] = A[k], A[p]
      b[p], b[k] = b[k], b[p]
    end
    local rk = A[k]
    local piv = rk[k]
    for i = k + 1, n do
      local ri = A[i]
      local f = ri[k]
      if f ~= 0 then
        f = f / piv
        for j = k + 1, n do ri[j] = ri[j] - f * rk[j] end
        b[i] = b[i] - f * b[k]
        ri[k] = 0
      end
    end
  end
  local x = {}
  for i = n, 1, -1 do
    local ri = A[i]
    local s = b[i]
    for j = i + 1, n do s = s - ri[j] * x[j] end
    x[i] = s / ri[i]
  end
  return x
end

-- Rango numerico de B (m filas x n columnas) por eliminacion con pivoteo completo.
-- Las columnas se normalizan a max|.| = 1 (las nulas se ignoran). tol por omision 1e-9.
-- No modifica B.
function M.rank(B, tol, m, n)
  m = m or #B
  n = n or (B[1] and #B[1] or 0)
  tol = tol or 1e-9
  if m == 0 or n == 0 then return 0 end
  local A = {}
  for i = 1, m do
    local r, bi = {}, B[i]
    for j = 1, n do r[j] = bi[j] end
    A[i] = r
  end
  for j = 1, n do
    local mx = 0
    for i = 1, m do
      local v = abs(A[i][j])
      if v > mx then mx = v end
    end
    if mx > 0 then
      for i = 1, m do A[i][j] = A[i][j] / mx end
    end
  end
  local r = 0
  local kmax = m < n and m or n
  for k = 1, kmax do
    local pi, pj, pv = k, k, 0
    for i = k, m do
      local ri = A[i]
      for j = k, n do
        local v = abs(ri[j])
        if v > pv then pi, pj, pv = i, j, v end
      end
    end
    if pv <= tol then break end
    if pi ~= k then A[pi], A[k] = A[k], A[pi] end
    if pj ~= k then
      for i = 1, m do
        local ri = A[i]
        ri[pj], ri[k] = ri[k], ri[pj]
      end
    end
    local rk = A[k]
    local piv = rk[k]
    for i = k + 1, m do
      local ri = A[i]
      local f = ri[k]
      if f ~= 0 then
        f = f / piv
        for j = k + 1, n do ri[j] = ri[j] - f * rk[j] end
        ri[k] = 0
      end
    end
    r = r + 1
  end
  return r
end

return M
