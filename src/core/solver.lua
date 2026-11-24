-- core/solver.lua: validacion, clasificacion y solucion (metodo de rigidez) de estructuras 2D.
-- Contrato: docs/arquitectura.md §4 (modelo) y §5 (API).
local LA = require("core.linalg")
local Elem = require("core.elemento")
local Esf = require("core.esfuerzos")

local S = {}
local sqrt, abs = math.sqrt, math.abs

local NOMBRE_GDL = { "horizontal", "vertical", "de giro" }

local function mkerr(cod, msg, nodo, barra)
  return { cod = cod, msg = msg, nodo = nodo, barra = barra }
end

local function num(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- Estado de un GDL de apoyo: 2 = restringido, 1 = resorte, 0 = libre.
local function estado_apoyo(ap, k)
  if not ap then return 0 end
  if k == 1 then
    if ap.ux then return 2 end
    if (ap.kx or 0) > 0 then return 1 end
  elseif k == 2 then
    if ap.uy then return 2 end
    if (ap.ky or 0) > 0 then return 1 end
  else
    if ap.rz then return 2 end
    if (ap.kr or 0) > 0 then return 1 end
  end
  return 0
end

local function valor_resorte(ap, k)
  if k == 1 then return ap.kx or 0 elseif k == 2 then return ap.ky or 0 end
  return ap.kr or 0
end

local function valor_presc(ap, k)
  if k == 1 then return ap.dx or 0 elseif k == 2 then return ap.dy or 0 end
  return ap.drz or 0
end

-- Validacion y datos geometricos. Devuelve pr, nil  o  nil, err.
--   pr = { nn, nb, geo[e] = {L,c,s,ri,rj}, elim[i] = true si el GDL de giro se elimina }
local function preparar(modelo)
  if type(modelo) ~= "table" or type(modelo.nodos) ~= "table" or #modelo.nodos == 0 then
    return nil, mkerr("SIN_NODOS", "No hay nodos: agregue nodos y barras")
  end
  local nodos = modelo.nodos
  local barras = modelo.barras or {}
  local nn, nb = #nodos, #barras
  local cuenta, libera = {}, {}
  for i = 1, nn do
    local nd = nodos[i]
    if type(nd) ~= "table" or not num(nd.x) or not num(nd.y) then
      return nil, mkerr("DATO", "El nodo " .. i .. " tiene coordenadas no validas", i)
    end
    cuenta[i], libera[i] = 0, 0
  end
  local geo = {}
  for e = 1, nb do
    local b = barras[e]
    local ni, nj = b.ni, b.nj
    if not num(ni) or not num(nj) or ni < 1 or nj < 1 or ni > nn or nj > nn
      or ni ~= math.floor(ni) or nj ~= math.floor(nj) then
      return nil, mkerr("DATO", "La barra " .. e .. " referencia un nodo inexistente", nil, e)
    end
    local n1, n2 = nodos[ni], nodos[nj]
    local dx, dy = n2.x - n1.x, n2.y - n1.y
    local L = sqrt(dx * dx + dy * dy)
    if ni == nj or L < 1e-9 then
      return nil, mkerr("LONG_CERO", "La barra " .. e .. " tiene longitud cero", nil, e)
    end
    local ri, rj = b.rot_i and true or false, b.rot_j and true or false
    if b.tipo == "cercha" then ri, rj = true, true end
    if not num(b.E) or b.E <= 0 then
      return nil, mkerr("DATO", "La barra " .. e .. " no tiene modulo E valido", nil, e)
    end
    if not num(b.A) or b.A <= 0 then
      return nil, mkerr("DATO", "La barra " .. e .. " no tiene area A valida", nil, e)
    end
    if not (ri and rj) and (not num(b.I) or b.I <= 0) then
      return nil, mkerr("DATO", "La barra " .. e .. " no tiene inercia I valida", nil, e)
    end
    local cargas = b.cargas
    if cargas then
      for k = 1, #cargas do
        local q = cargas[k]
        local t = q.t
        local dir = q.dir
        if dir ~= nil and dir ~= "GY" and dir ~= "GX" and dir ~= "L" and dir ~= "LX" then
          return nil, mkerr("DATO", "Direccion de carga no valida en la barra " .. e, nil, e)
        end
        local tolx = 1e-9 * L
        if t == "P" then
          if not num(q.a) or not num(q.p) or q.a < -tolx or q.a > L + tolx then
            return nil, mkerr("DATO", "Carga puntual no valida en la barra " .. e, nil, e)
          end
        elseif t == "M" then
          if not num(q.a) or not num(q.m) or q.a < -tolx or q.a > L + tolx then
            return nil, mkerr("DATO", "Momento puntual no valido en la barra " .. e, nil, e)
          end
        elseif t == "w" then
          if not num(q.a) or not num(q.b) or not num(q.w1) or not num(q.w2 or q.w1)
            or q.a < -tolx or q.b > L + tolx or q.b < q.a then
            return nil, mkerr("DATO", "Carga distribuida no valida en la barra " .. e, nil, e)
          end
        elseif t == "T" then
          local du, dg = q.du or 0, q.dg or 0
          if not num(du) or not num(dg) or (q.alfa ~= nil and not num(q.alfa))
            or (q.h ~= nil and not num(q.h)) then
            return nil, mkerr("DATO", "Carga termica no valida en la barra " .. e, nil, e)
          end
          if dg ~= 0 and not (q.h and q.h > 0) then
            return nil, mkerr("DATO", "La carga termica de la barra " .. e
              .. " tiene gradiente y necesita el canto h > 0", nil, e)
          end
        else
          return nil, mkerr("DATO", "Tipo de carga desconocido en la barra " .. e, nil, e)
        end
      end
    end
    geo[e] = { L = L, c = dx / L, s = dy / L, ri = ri, rj = rj }
    cuenta[ni] = cuenta[ni] + 1
    cuenta[nj] = cuenta[nj] + 1
    if ri then libera[ni] = libera[ni] + 1 end
    if rj then libera[nj] = libera[nj] + 1 end
  end
  for i = 1, nn do
    if cuenta[i] == 0 then
      return nil, mkerr("NODO_SUELTO", "El nodo " .. i .. " no esta conectado a ninguna barra", i)
    end
  end
  local hay = false
  for i = 1, nn do
    local ap = nodos[i].apoyo
    if ap and (estado_apoyo(ap, 1) > 0 or estado_apoyo(ap, 2) > 0 or estado_apoyo(ap, 3) > 0) then
      hay = true
      break
    end
  end
  if not hay then
    return nil, mkerr("SIN_APOYOS", "Falta un apoyo: la estructura es inestable")
  end
  local elim = {}
  for i = 1, nn do
    local nd = nodos[i]
    if libera[i] == cuenta[i] and estado_apoyo(nd.apoyo, 3) == 0 then
      elim[i] = true
      if nd.carga and (nd.carga.mz or 0) ~= 0 then
        return nil, mkerr("MECANISMO", "El nodo " .. i
          .. " tiene un momento aplicado y todas sus barras son articuladas: mecanismo", i)
      end
    else
      elim[i] = false
    end
  end
  return { nn = nn, nb = nb, geo = geo, elim = elim }
end

-- Clasificacion numerica por el rango de la matriz de equilibrio B (docs §1).
local function clasificar_datos(modelo, pr)
  local nn, nb, geo, elim = pr.nn, pr.nb, pr.geo, pr.elim
  local nodos, barras = modelo.nodos, modelo.barras
  -- filas (ecuaciones)
  local fila = {}
  local n_ec = 0
  for i = 1, nn do
    fila[i] = { 0, 0, 0 }
    for k = 1, 3 do
      if not (k == 3 and elim[i]) then
        n_ec = n_ec + 1
        fila[i][k] = n_ec
      end
    end
  end
  -- columnas (incognitas)
  local n_inc = 0
  local colb = {}
  for e = 1, nb do
    local g = geo[e]
    local c0 = n_inc + 1
    n_inc = n_inc + 1
    local ci, cj = 0, 0
    if not g.ri then n_inc = n_inc + 1; ci = n_inc end
    if not g.rj then n_inc = n_inc + 1; cj = n_inc end
    colb[e] = { c0, ci, cj }
  end
  local colr = {}
  for i = 1, nn do
    colr[i] = { 0, 0, 0 }
    local ap = nodos[i].apoyo
    for k = 1, 3 do
      if estado_apoyo(ap, k) > 0 then
        n_inc = n_inc + 1
        colr[i][k] = n_inc
      end
    end
  end
  local B = LA.mat(n_ec, n_inc)
  for e = 1, nb do
    local g, cb = geo[e], colb[e]
    local L, c, s = g.L, g.c, g.s
    local bi, bj = barras[e].ni, barras[e].nj
    -- N
    local r = fila[bi]
    B[r[1]][cb[1]] = B[r[1]][cb[1]] + c
    B[r[2]][cb[1]] = B[r[2]][cb[1]] + s
    r = fila[bj]
    B[r[1]][cb[1]] = B[r[1]][cb[1]] - c
    B[r[2]][cb[1]] = B[r[2]][cb[1]] - s
    if cb[2] > 0 then -- Mi
      r = fila[bi]
      B[r[1]][cb[2]] = B[r[1]][cb[2]] + s / L
      B[r[2]][cb[2]] = B[r[2]][cb[2]] - c / L
      if r[3] > 0 then B[r[3]][cb[2]] = B[r[3]][cb[2]] - 1 end
      r = fila[bj]
      B[r[1]][cb[2]] = B[r[1]][cb[2]] - s / L
      B[r[2]][cb[2]] = B[r[2]][cb[2]] + c / L
    end
    if cb[3] > 0 then -- Mj
      r = fila[bi]
      B[r[1]][cb[3]] = B[r[1]][cb[3]] + s / L
      B[r[2]][cb[3]] = B[r[2]][cb[3]] - c / L
      r = fila[bj]
      B[r[1]][cb[3]] = B[r[1]][cb[3]] - s / L
      B[r[2]][cb[3]] = B[r[2]][cb[3]] + c / L
      if r[3] > 0 then B[r[3]][cb[3]] = B[r[3]][cb[3]] - 1 end
    end
  end
  for i = 1, nn do
    for k = 1, 3 do
      local col = colr[i][k]
      if col > 0 then B[fila[i][k]][col] = 1 end
    end
  end
  local rango = LA.rank(B, 1e-9, n_ec, n_inc)
  local cl = { n_ec = n_ec, n_inc = n_inc, rango = rango }
  cl.grado = n_inc - rango
  if rango < n_ec then
    cl.tipo = "inestable"
    local f = n_ec - rango
    cl.msg = "Inestable: mecanismo (faltan " .. f .. (f == 1 and " restriccion)" or " restricciones)")
  elseif cl.grado == 0 then
    cl.tipo = "isostatica"
    cl.msg = "Isostatica"
  else
    cl.tipo = "hiperestatica"
    cl.msg = "Hiperestatica de grado " .. cl.grado
  end
  return cl
end

-- cl = { tipo, grado, n_ec, n_inc, rango, msg }. Si el modelo no es valido, tipo = "inestable"
-- y msg = mensaje de error; el segundo resultado es el error (como en S.resolver).
function S.clasificar(modelo)
  local pr, err = preparar(modelo)
  if not pr then
    return { tipo = "inestable", grado = 0, n_ec = 0, n_inc = 0, rango = 0, msg = err.msg }, err
  end
  return clasificar_datos(modelo, pr), nil
end

-- Resuelve el modelo. Devuelve res, nil  o  nil, err.  (res: docs/arquitectura.md §5)
-- Extensiones: res.equilibrio.rel (residuo relativo), res.barras[e].{ni,nj,xi,yi,tramos,verif}.
function S.resolver(modelo)
  local pr, err = preparar(modelo)
  if not pr then return nil, err end
  local cl = clasificar_datos(modelo, pr)
  local nn, nb, geo, elim = pr.nn, pr.nb, pr.geo, pr.elim
  local nodos, barras = modelo.nodos, modelo.barras

  -- numeracion: g = 3*(i-1)+k;  tg: 1 libre, 2 restringido, 3 eliminado
  local ng = 3 * nn
  local tg, libre, presc, kres, carga = {}, {}, {}, {}, {}
  local nf = 0
  local inv = {}
  for i = 1, nn do
    local nd = nodos[i]
    local ap = nd.apoyo
    local ca = nd.carga
    for k = 1, 3 do
      local g = 3 * (i - 1) + k
      kres[g], presc[g] = 0, 0
      carga[g] = 0
      if ca then
        if k == 1 then carga[g] = ca.fx or 0 elseif k == 2 then carga[g] = ca.fy or 0
        else carga[g] = ca.mz or 0 end
      end
      if k == 3 and elim[i] then
        tg[g], libre[g] = 3, 0
      else
        local est = estado_apoyo(ap, k)
        if est == 2 then
          tg[g], libre[g] = 2, 0
          presc[g] = valor_presc(ap, k)
        else
          nf = nf + 1
          tg[g], libre[g] = 1, nf
          inv[nf] = g
          if est == 1 then kres[g] = valor_resorte(ap, k) end
        end
      end
    end
  end

  -- ensamblaje
  local K = LA.mat(nf, nf)
  local F = {}
  for f = 1, nf do F[f] = carga[inv[f]] + 0 end
  for g = 1, ng do
    local f = libre[g]
    if f > 0 and kres[g] > 0 then K[f][f] = K[f][f] + kres[g] end
  end
  local gi = { 0, 0, 0, 0, 0, 0 }
  for e = 1, nb do
    local b, g = barras[e], geo[e]
    local Em, Am, Im = Elem.props(b, g.L)
    local k0 = Elem.rigidez(Em, Am, Im, g.L)
    local f0 = Elem.empotramiento(b, g.L, g.c, g.s)
    local kc, fc = Elem.condensar(k0, f0, g.ri, g.rj)
    local kg, fg = Elem.transformar(kc, fc, g.c, g.s)
    local bi, bj = 3 * (b.ni - 1), 3 * (b.nj - 1)
    gi[1], gi[2], gi[3] = bi + 1, bi + 2, bi + 3
    gi[4], gi[5], gi[6] = bj + 1, bj + 2, bj + 3
    for a = 1, 6 do
      local fa = libre[gi[a]]
      if fa > 0 then
        F[fa] = F[fa] - fg[a]
        local Ka, kga = K[fa], kg[a]
        for c2 = 1, 6 do
          local gc = gi[c2]
          local fcI = libre[gc]
          if fcI > 0 then
            Ka[fcI] = Ka[fcI] + kga[c2]
          elseif tg[gc] == 2 then
            local dp = presc[gc]
            if dp ~= 0 then F[fa] = F[fa] - kga[c2] * dp end
          end
        end
      end
    end
  end

  local x, fallo = LA.solve(K, F, nf, true)
  if not x then
    local g = inv[fallo]
    local nodo = math.floor((g - 1) / 3) + 1
    local k = g - 3 * (nodo - 1)
    if cl.tipo == "inestable" then
      return nil, mkerr("MECANISMO", cl.msg .. ". Revise cerca del nodo " .. nodo
        .. " (movimiento " .. NOMBRE_GDL[k] .. " sin restringir)", nodo)
    end
    return nil, mkerr("SINGULAR", "Matriz de rigidez singular cerca del nodo " .. nodo
      .. " (GDL " .. NOMBRE_GDL[k] .. ")", nodo)
  end
  if cl.tipo == "inestable" then
    return nil, mkerr("MECANISMO", cl.msg)
  end

  -- desplazamientos
  local dg = {}
  for g = 1, ng do
    if libre[g] > 0 then dg[g] = x[libre[g]]
    elseif tg[g] == 2 then dg[g] = presc[g]
    else dg[g] = 0 end
  end
  local res = { clasif = cl, d = {}, reac = {}, barras = {} }
  for i = 1, nn do
    local b0 = 3 * (i - 1)
    res.d[i] = { ux = dg[b0 + 1], uy = dg[b0 + 2], rz = (not elim[i]) and dg[b0 + 3] or nil }
  end

  -- fuerzas de extremo, reacciones por equilibrio de nudo
  local suma = {}
  for g = 1, ng do suma[g] = 0 end
  local dgl = { 0, 0, 0, 0, 0, 0 }
  for e = 1, nb do
    local b, g = barras[e], geo[e]
    local Em, Am, Im = Elem.props(b, g.L)
    local k0 = Elem.rigidez(Em, Am, Im, g.L)
    local f0 = Elem.empotramiento(b, g.L, g.c, g.s)
    local kc, fc = Elem.condensar(k0, f0, g.ri, g.rj)
    local bi, bj = 3 * (b.ni - 1), 3 * (b.nj - 1)
    gi[1], gi[2], gi[3] = bi + 1, bi + 2, bi + 3
    gi[4], gi[5], gi[6] = bj + 1, bj + 2, bj + 3
    for a = 1, 6 do dgl[a] = dg[gi[a]] end
    local dl = Elem.a_local(dgl, g.c, g.s)
    if g.ri then dl[3] = 0 end
    if g.rj then dl[6] = 0 end
    local fl = {}
    for a = 1, 6 do
      local sm = fc[a]
      local ka = kc[a]
      for c2 = 1, 6 do sm = sm + ka[c2] * dl[c2] end
      fl[a] = sm
    end
    Elem.recuperar(k0, f0, g.ri, g.rj, dl)
    local flg = Elem.a_global(fl, g.c, g.s)
    for a = 1, 6 do suma[gi[a]] = suma[gi[a]] + flg[a] end
    local n1 = nodos[b.ni]
    res.barras[e] = { L = g.L, c = g.c, s = g.s, fl = fl, dl = dl,
      ni = b.ni, nj = b.nj, xi = n1.x, yi = n1.y }
  end

  local rx, ry, rm = 0, 0, 0
  local sF, sM = 0, 0
  for i = 1, nn do
    local nd = nodos[i]
    local ap = nd.apoyo
    if ap then
      local r = { 0, 0, 0 }
      local hay = false
      for k = 1, 3 do
        local g = 3 * (i - 1) + k
        if tg[g] == 2 then
          r[k] = suma[g] - carga[g]
          hay = true
        elseif tg[g] == 1 and kres[g] > 0 then
          r[k] = -kres[g] * dg[g]
          hay = true
        end
      end
      if hay then
        res.reac[i] = { rx = r[1], ry = r[2], mz = r[3] }
        rx = rx + r[1]
        ry = ry + r[2]
        rm = rm + r[3] + nd.x * r[2] - nd.y * r[1]
        sF = sF + abs(r[1]) + abs(r[2])
        sM = sM + abs(r[3]) + abs(nd.x * r[2]) + abs(nd.y * r[1])
      end
    end
    local ca = nd.carga
    if ca then
      local fx, fy, mz = ca.fx or 0, ca.fy or 0, ca.mz or 0
      rx = rx + fx
      ry = ry + fy
      rm = rm + mz + nd.x * fy - nd.y * fx
      sF = sF + abs(fx) + abs(fy)
      sM = sM + abs(mz) + abs(nd.x * fy) + abs(nd.y * fx)
    end
  end
  for e = 1, nb do
    local g, rb = geo[e], res.barras[e]
    local fx, fy, mo, sf, sm = Elem.resultante(barras[e], rb.xi, rb.yi, g.c, g.s, g.L)
    rx = rx + fx
    ry = ry + fy
    rm = rm + mo
    sF = sF + sf
    sM = sM + sm
  end
  local rel = 0
  if sF > 0 then rel = math.max(abs(rx), abs(ry)) / sF end
  if sM > 0 and abs(rm) / sM > rel then rel = abs(rm) / sM end
  res.equilibrio = { fx = rx, fy = ry, m = rm, rel = rel }

  Esf.construir(modelo, res)
  return res, nil
end

return S
