"""Solver de REFERENCIA (NumPy) para la calculadora estructural 2D. Independiente del solver Lua.

Uso:  python -I tools/ref_numpy.py [caso ...]   (lee tests/casos/*.json, escribe tests/ref/<caso>.json)

Metodo (distinto al de Lua a proposito):
  * Rigidez directa con portico 6x6; las rotulas NO se condensan: cada extremo liberado recibe un
    GDL de giro propio (independiente del giro del nudo). Si el nudo no tiene ninguna barra rigida
    ni apoyo/resorte de giro, su GDL rz se elimina (d.rz = null).
  * Fuerzas de empotramiento: integrales exactas con polinomios de Hermite (numpy.polynomial), sin
    cuadratura numerica. Equilibrio global de las cargas con cuadratura Gauss-Legendre (independiente).
  * Esfuerzos: equilibrio de cuerpo libre desde el extremo i, polinomios exactos por tramos.
  * Deflexion v(x): integracion EXACTA (polinomica por tramos) de M/EI dos veces desde (v_i, theta_i);
    error ~1e-12 relativo. Se verifica v(L), theta(L) contra el extremo j.
  * Clasificacion: rango (numpy.linalg.matrix_rank) de la matriz de equilibrio B.
Convenciones: docs/arquitectura.md Sec. 3 y 4.
"""
import glob
import json
import math
import os
import sys

import numpy as np
from numpy.polynomial import Polynomial as Pl

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOL_COORD = 1e-9


class ErrorModelo(Exception):
    pass


# ----------------------------------------------------------------------------- geometria / cargas

def geom(m, b):
    ni, nj = m["nodos"][b["ni"] - 1], m["nodos"][b["nj"] - 1]
    dx, dy = nj["x"] - ni["x"], nj["y"] - ni["y"]
    L = math.hypot(dx, dy)
    if L < 1e-12:
        raise ErrorModelo("barra de longitud cero")
    return L, dx / L, dy / L


def rot_local(c, s):
    """local = R @ global (3x3, giro invariante)."""
    return np.array([[c, s, 0], [-s, c, 0], [0, 0, 1.0]])


def klocal(E, A, I, L):
    EA, EI = E * A / L, E * I
    k = np.zeros((6, 6))
    k[0, 0] = k[3, 3] = EA
    k[0, 3] = k[3, 0] = -EA
    a, bb, cc, dd = 12 * EI / L**3, 6 * EI / L**2, 4 * EI / L, 2 * EI / L
    k[1, 1] = k[4, 4] = a
    k[1, 4] = k[4, 1] = -a
    k[1, 2] = k[2, 1] = bb
    k[1, 5] = k[5, 1] = bb
    k[2, 4] = k[4, 2] = -bb
    k[4, 5] = k[5, 4] = -bb
    k[2, 2] = k[5, 5] = cc
    k[2, 5] = k[5, 2] = dd
    return k


def comp_local(dir_, v, c, s):
    """Componentes locales (axial, transversal) de una intensidad v con direccion dir_."""
    if dir_ == "GY":
        return v * s, v * c
    if dir_ == "GX":
        return v * c, -v * s
    if dir_ == "L":
        return 0.0, v
    if dir_ == "LX":
        return v, 0.0
    raise ErrorModelo("dir desconocida: %r" % (dir_,))


def cargas_locales(b, c, s):
    """Lista de cargas con componentes locales:
    ('P', a, px, py) ; ('M', a, m) ; ('w', a, b, (qx0,qx1), (qy0,qy1))"""
    out = []
    for ld in b.get("cargas") or []:
        t = ld["t"]
        if t == "P":
            px, py = comp_local(ld.get("dir", "GY"), ld["p"], c, s)
            out.append(("P", ld["a"], px, py))
        elif t == "M":
            out.append(("M", ld["a"], ld["m"]))
        elif t == "w":
            x1, y1 = comp_local(ld.get("dir", "GY"), ld["w1"], c, s)
            x2, y2 = comp_local(ld.get("dir", "GY"), ld["w2"], c, s)
            out.append(("w", ld["a"], ld["b"], (x1, x2), (y1, y2)))
        elif t == "T":
            # deformaciones iniciales: eps0 = alfa*du (axial), kappa0 = -alfa*dg/h (curvatura)
            alfa = ld.get("alfa", 1.2e-5)
            dg = ld.get("dg", 0.0) or 0.0
            if dg != 0 and not ld.get("h"):
                raise ErrorModelo("carga termica con dg y sin canto h")
            out.append(("T", alfa * (ld.get("du", 0.0) or 0.0), -alfa * dg / ld["h"] if dg != 0 else 0.0))
        else:
            raise ErrorModelo("tipo de carga desconocido: %r" % (t,))
    return out


def lin(a, b, v1, v2):
    """Polinomio (en x absoluta) de la recta que vale v1 en a y v2 en b."""
    if b - a < 1e-14:
        return Pl([v1])
    sl = (v2 - v1) / (b - a)
    return Pl([v1 - sl * a, sl])


def hermite(L):
    x = Pl([0, 1])
    xi = x / L
    n1 = 1 - 3 * xi**2 + 2 * xi**3
    n2 = L * (xi - 2 * xi**2 + xi**3)
    n3 = 3 * xi**2 - 2 * xi**3
    n4 = L * (-(xi**2) + xi**3)
    return [n1, n2, n3, n4], [1 - xi, xi]


def fef_local(cl, L, EA=0.0, EI=0.0):
    """Fuerzas de empotramiento (nodos sobre barra, extremos fijos) = - cargas nodales equivalentes."""
    (n1, n2, n3, n4), (a1, a2) = hermite(L)
    feq = np.zeros(6)

    def integ(p, a, b):
        q = p.integ()
        return q(b) - q(a)

    for ld in cl:
        if ld[0] == "P":
            _, a, px, py = ld
            feq += np.array([a1(a) * px, n1(a) * py, n2(a) * py, a2(a) * px, n3(a) * py, n4(a) * py])
        elif ld[0] == "M":
            _, a, m = ld
            feq += m * np.array([0, n1.deriv()(a), n2.deriv()(a), 0, n3.deriv()(a), n4.deriv()(a)])
        elif ld[0] == "T":
            # Cargas nodales equivalentes de deformaciones iniciales: integral de B^T * D * e0,
            # con B = derivadas de las funciones de forma (axial: N', flexion: N'').
            _, eps0, kap0 = ld
            feq += np.array([integ(a1.deriv(), 0, L) * EA * eps0,
                             integ(n1.deriv(2), 0, L) * EI * kap0,
                             integ(n2.deriv(2), 0, L) * EI * kap0,
                             integ(a2.deriv(), 0, L) * EA * eps0,
                             integ(n3.deriv(2), 0, L) * EI * kap0,
                             integ(n4.deriv(2), 0, L) * EI * kap0])
        else:
            _, a, b, (qx1, qx2), (qy1, qy2) = ld
            qx, qy = lin(a, b, qx1, qx2), lin(a, b, qy1, qy2)
            feq += np.array([integ(a1 * qx, a, b), integ(n1 * qy, a, b), integ(n2 * qy, a, b),
                             integ(a2 * qx, a, b), integ(n3 * qy, a, b), integ(n4 * qy, a, b)])
    return -feq


# ----------------------------------------------------------------------------- solucion

def resolver(m):
    nodos, barras = m["nodos"], m["barras"]
    nn = len(nodos)
    if nn == 0:
        raise ErrorModelo("sin nodos")
    ndof = 3 * nn
    # GDL de giro propio por extremo liberado
    extra = {}
    for e, b in enumerate(barras):
        tipo = b.get("tipo", "portico")
        ri = b.get("rot_i") or tipo == "cercha"
        rj = b.get("rot_j") or tipo == "cercha"
        b["_ri"], b["_rj"] = bool(ri), bool(rj)
        if ri:
            extra[(e, 0)] = ndof
            ndof += 1
        if rj:
            extra[(e, 1)] = ndof
            ndof += 1

    K = np.zeros((ndof, ndof))
    F = np.zeros(ndof)            # cargas nodales
    FE = np.zeros(ndof)           # fuerzas de empotramiento (nodos sobre barras), globales
    info = []
    rigido_rz = [False] * nn      # el nudo tiene alguna barra con giro rigido en el
    for e, b in enumerate(barras):
        L, c, s = geom(m, b)
        i, j = b["ni"] - 1, b["nj"] - 1
        gi = [3 * i, 3 * i + 1, extra.get((e, 0), 3 * i + 2)]
        gj = [3 * j, 3 * j + 1, extra.get((e, 1), 3 * j + 2)]
        dofs = gi + gj
        if not b["_ri"]:
            rigido_rz[i] = True
        if not b["_rj"]:
            rigido_rz[j] = True
        R = rot_local(c, s)
        T = np.zeros((6, 6))
        T[:3, :3] = R
        T[3:, 3:] = R
        kl = klocal(b["E"], b["A"], b["I"], L)
        cl = cargas_locales(b, c, s)
        fe = fef_local(cl, L, b["E"] * b["A"], b["E"] * b["I"])
        K[np.ix_(dofs, dofs)] += T.T @ kl @ T
        FE[dofs] += T.T @ fe
        info.append(dict(L=L, c=c, s=s, T=T, kl=kl, fe=fe, dofs=dofs, cl=cl))

    restr = {}                    # gdl -> valor prescrito
    resorte_rz = [False] * nn
    kres = np.zeros(ndof)         # rigidez de resortes por GDL
    for n, nd in enumerate(nodos):
        ap = nd.get("apoyo")
        ca = nd.get("carga")
        if ca:
            F[3 * n] += ca.get("fx", 0) or 0
            F[3 * n + 1] += ca.get("fy", 0) or 0
            F[3 * n + 2] += ca.get("mz", 0) or 0
        if ap:
            for q, (fl, kk, dk) in enumerate((("ux", "kx", "dx"), ("uy", "ky", "dy"), ("rz", "kr", "drz"))):
                kv = ap.get(kk) or 0
                if kv > 0:
                    K[3 * n + q, 3 * n + q] += kv
                    kres[3 * n + q] += kv
                    if q == 2:
                        resorte_rz[n] = True
                if ap.get(fl):
                    restr[3 * n + q] = ap.get(dk) or 0.0
    # GDL de giro sin rigidez -> eliminado
    elim = set()
    for n in range(nn):
        q = 3 * n + 2
        if not rigido_rz[n] and not resorte_rz[n] and q not in restr:
            if abs(F[q]) > 0:
                raise ErrorModelo("mecanismo: momento aplicado en nudo articulado %d" % (n + 1))
            elim.add(q)
    # nudos sin barras
    conectado = set()
    for b in barras:
        conectado.add(b["ni"] - 1)
        conectado.add(b["nj"] - 1)
    for n in range(nn):
        if n not in conectado:
            raise ErrorModelo("nodo suelto %d" % (n + 1))
    if not restr:
        raise ErrorModelo("sin apoyos")

    libres = [q for q in range(ndof) if q not in restr and q not in elim]
    d = np.zeros(ndof)
    for q, v in restr.items():
        d[q] = v
    dr = list(restr.keys())
    rhs = F[libres] - FE[libres] - K[np.ix_(libres, dr)] @ d[dr] if dr else F[libres] - FE[libres]
    Kff = K[np.ix_(libres, libres)]
    if libres:
        cond = np.linalg.cond(Kff)
        if not np.isfinite(cond) or cond > 1e14:
            raise ErrorModelo("matriz singular (mecanismo), cond=%.2e" % cond)
        d[libres] = np.linalg.solve(Kff, rhs)
    else:
        cond = 1.0

    # fuerzas de extremo, reacciones
    S = np.zeros(ndof)
    barras_out = []
    for e, b in enumerate(barras):
        inf = info[e]
        dg = d[inf["dofs"]]
        dl = inf["T"] @ dg
        fl = inf["kl"] @ dl + inf["fe"]
        S[inf["dofs"]] += inf["T"].T @ fl
        inf["dl"], inf["fl"] = dl, fl
    R = S - F                     # reaccion total (apoyo + resorte) en cada GDL
    reac = {}
    for n, nd in enumerate(nodos):
        if nd.get("apoyo"):
            reac[n + 1] = [float(R[3 * n]), float(R[3 * n + 1]), 0.0 if (3 * n + 2) in elim else float(R[3 * n + 2])]
    # equilibrio nodal de los GDL libres (comprobacion del solve)
    res_nodal = max([abs(R[q] + kres[q] * d[q]) for q in libres] + [0.0])

    dn = [[float(d[3 * n]), float(d[3 * n + 1]), None if (3 * n + 2) in elim else float(d[3 * n + 2])]
          for n in range(nn)]
    return dict(d=dn, reac=reac, info=info, F=F, res_nodal=res_nodal, dfull=d, R=R, cond=cond)


# ----------------------------------------------------------------------------- esfuerzos

def esfuerzos_barra(b, inf):
    """Polinomios exactos por tramos. Devuelve (quiebres, tramos, saltos).
    tramo = dict(x0, x1, N, V, M, th, v) con polinomios en x local absoluta."""
    L, cl, fl, dl = inf["L"], inf["cl"], inf["fl"], inf["dl"]
    EI, EA = b["E"] * b["I"], b["E"] * b["A"]
    Fxi, Fyi, Mi = fl[0], fl[1], fl[2]
    pts = {0.0, L}
    saltos = []
    for ld in cl:
        if ld[0] == "T":
            continue
        if ld[0] in ("P", "M"):
            pts.add(ld[1])
            if 1e-12 < ld[1] < L - 1e-12:
                saltos.append(ld[1])
        else:
            pts.add(ld[1])
            pts.add(ld[2])
    pts = sorted(p for p in pts if -1e-12 <= p <= L + 1e-12)
    q = [pts[0]]
    for p in pts[1:]:
        if p - q[-1] > 1e-10:
            q.append(p)
    q[-1] = L
    x = Pl([0, 1])
    tramos = []
    th0, v0 = dl[2], dl[1]
    for x0, x1 in zip(q[:-1], q[1:]):
        xm = 0.5 * (x0 + x1)
        N = Pl([-Fxi])
        V = Pl([Fyi])
        M = Pl([-Mi]) + Fyi * x
        for ld in cl:
            if ld[0] == "T":
                continue
            if ld[0] == "P":
                _, a, px, py = ld
                if a < xm:
                    N = N - px
                    V = V + py
                    M = M + py * (x - a)
            elif ld[0] == "M":
                _, a, mz = ld
                if a < xm:
                    M = M - mz
            else:
                _, a, bq, (qx1, qx2), (qy1, qy2) = ld
                if xm <= a:
                    continue
                qx, qy = lin(a, bq, qx1, qx2), lin(a, bq, qy1, qy2)
                Gx, Gy = qx.integ(), qy.integ()
                Hy = (x * qy).integ()
                if xm < bq:   # dentro de la carga: limite superior x
                    N = N - (Gx - Gx(a))
                    V = V + (Gy - Gy(a))
                    M = M + x * (Gy - Gy(a)) - (Hy - Hy(a))
                else:         # pasada: limite superior bq (constante)
                    N = N - (Gx(bq) - Gx(a))
                    V = V + (Gy(bq) - Gy(a))
                    M = M + x * (Gy(bq) - Gy(a)) - (Hy(bq) - Hy(a))
        kap0 = sum(ld[2] for ld in cl if ld[0] == "T")
        P1 = (M / EI + kap0).integ()
        th = P1 - P1(x0) + th0
        P2 = th.integ()
        v = P2 - P2(x0) + v0
        th0, v0 = th(x1), v(x1)
        tramos.append(dict(x0=x0, x1=x1, N=N, V=V, M=M, th=th, v=v))
    return q, tramos, saltos


def evalt(tramos, xq, campo, lado="+"):
    L = tramos[-1]["x1"]
    idx = None
    for k, t in enumerate(tramos):
        if lado == "+":
            if t["x0"] - 1e-12 <= xq < t["x1"] - 1e-12:
                idx = k
                break
        else:
            if t["x0"] + 1e-12 < xq <= t["x1"] + 1e-12:
                idx = k
                break
    if idx is None:
        idx = len(tramos) - 1 if lado == "+" else 0
    return float(tramos[idx][campo](xq))


# ----------------------------------------------------------------------------- clasificacion

def clasificar(m):
    nodos, barras = m["nodos"], m["barras"]
    nn = len(nodos)
    cols = []

    def col(vec):
        cols.append(vec)

    for b in barras:
        L, c, s = geom(m, b)
        i, j = b["ni"] - 1, b["nj"] - 1
        tipo = b.get("tipo", "portico")
        ri = bool(b.get("rot_i")) or tipo == "cercha"
        rj = bool(b.get("rot_j")) or tipo == "cercha"
        R = rot_local(c, s)
        T = np.zeros((6, 6))
        T[:3, :3] = R
        T[3:, 3:] = R
        base = [np.array([1, 0, 0, -1, 0, 0.0]),
                np.array([0, 1 / L, 1, 0, -1 / L, 0.0]),
                np.array([0, 1 / L, 0, 0, -1 / L, 1.0])]
        use = [base[0]] + ([] if ri else [base[1]]) + ([] if rj else [base[2]])
        for fl in use:
            fg = T.T @ fl
            v = np.zeros(3 * nn)
            v[3 * i:3 * i + 3] += fg[:3]
            v[3 * j:3 * j + 3] += fg[3:]
            col(v)
    for n, nd in enumerate(nodos):
        ap = nd.get("apoyo") or {}
        for q, (fl, kk) in enumerate((("ux", "kx"), ("uy", "ky"), ("rz", "kr"))):
            if ap.get(fl) or (ap.get(kk) or 0) > 0:
                v = np.zeros(3 * nn)
                v[3 * n + q] = -1.0
                col(v)
    B = np.array(cols).T
    filas = [r for r in range(3 * nn) if np.abs(B[r]).max() > 1e-12]
    n_ec = len(filas)
    n_inc = B.shape[1]
    r = int(np.linalg.matrix_rank(B[filas], tol=1e-9)) if n_ec else 0
    if r < n_ec:
        tipo = "inestable"
    elif n_inc == r:
        tipo = "isostatica"
    else:
        tipo = "hiperestatica"
    return dict(tipo=tipo, grado=n_inc - r, n_ec=n_ec, n_inc=n_inc, rango=r)


# ----------------------------------------------------------------------------- equilibrio global

def resultante_cargas(m, info):
    """Fx, Fy, M(origen) de TODAS las cargas aplicadas (nodales + barras), por definicion
    (cuadratura Gauss-Legendre exacta), sin usar fuerzas de empotramiento."""
    fx = fy = mo = 0.0
    for nd in m["nodos"]:
        ca = nd.get("carga")
        if ca:
            f1, f2, mz = ca.get("fx", 0) or 0, ca.get("fy", 0) or 0, ca.get("mz", 0) or 0
            fx += f1
            fy += f2
            mo += nd["x"] * f2 - nd["y"] * f1 + mz
    gx, gw = np.polynomial.legendre.leggauss(6)
    for b, inf in zip(m["barras"], info):
        ni = m["nodos"][b["ni"] - 1]
        c, s = inf["c"], inf["s"]
        for ld in inf["cl"]:
            if ld[0] == "T":
                continue
            if ld[0] == "P":
                _, a, px, py = ld
                Fx, Fy = px * c - py * s, px * s + py * c
                X, Y = ni["x"] + a * c, ni["y"] + a * s
                fx += Fx
                fy += Fy
                mo += X * Fy - Y * Fx
            elif ld[0] == "M":
                mo += ld[2]
            else:
                _, a, bq, (qx1, qx2), (qy1, qy2) = ld
                for g, wg in zip(gx, gw):
                    sx = 0.5 * (bq - a) * g + 0.5 * (bq + a)
                    ww = 0.5 * (bq - a) * wg
                    t = (sx - a) / (bq - a) if bq > a else 0
                    qx, qy = qx1 + (qx2 - qx1) * t, qy1 + (qy2 - qy1) * t
                    Fx, Fy = (qx * c - qy * s) * ww, (qx * s + qy * c) * ww
                    X, Y = ni["x"] + sx * c, ni["y"] + sx * s
                    fx += Fx
                    fy += Fy
                    mo += X * Fy - Y * Fx
    return fx, fy, mo


# ----------------------------------------------------------------------------- caso completo

def procesar(nombre, m):
    sol = resolver(m)
    cl = clasificar(m)
    fallos = []
    barras_out = []
    for e, (b, inf) in enumerate(zip(m["barras"], sol["info"])):
        L = inf["L"]
        q, tramos, saltos = esfuerzos_barra(b, inf)
        xs = sorted(set(list(np.linspace(0, L, 11)) + q))
        dedup = []
        for xv in xs:
            if not dedup or xv - dedup[-1] > 1e-9:
                dedup.append(xv)
        dedup[-1] = L
        muestras = []
        for xv in dedup:
            lados = ("-", "+") if any(abs(xv - sj) < 1e-9 for sj in saltos) else ("+",)
            for lado in lados:
                muestras.append([float(xv)] + [evalt(tramos, xv, cmp_, lado) for cmp_ in ("N", "V", "M", "v")])
        fl, dl = inf["fl"], inf["dl"]
        # verificaciones extremo j (limite a la izquierda de L ~ valor en L del ultimo tramo)
        N_L, V_L, M_L = (evalt(tramos, L, k, "+") for k in ("N", "V", "M"))
        v_L, th_L = evalt(tramos, L, "v", "+"), evalt(tramos, L, "th", "+")
        sc = max(1.0, np.abs(fl).max())
        for nom, a_, b_ in (("N(L)", N_L, fl[3]), ("V(L)", V_L, -fl[4]), ("M(L)", M_L, fl[5])):
            if abs(a_ - b_) > 1e-9 * sc:
                fallos.append("barra %d: %s=%.12g != extremo j %.12g" % (e + 1, nom, a_, b_))
        scv = max(abs(dl[1]), abs(dl[4]), 1e-12)
        if abs(v_L - dl[4]) > 1e-9 * scv + 1e-13:
            fallos.append("barra %d: v(L)=%.12g != dl_j %.12g" % (e + 1, v_L, dl[4]))
        sct = max(abs(dl[2]), abs(dl[5]), 1e-12)
        if abs(th_L - dl[5]) > 1e-9 * sct + 1e-13:
            fallos.append("barra %d: theta(L)=%.12g != dl_j %.12g" % (e + 1, th_L, dl[5]))
        barras_out.append(dict(L=L, fl=[float(v) for v in fl], dl=[float(v) for v in dl],
                               quiebres=[float(v) for v in q], saltos=[float(v) for v in saltos],
                               muestras=muestras))
    fx, fy, mo = resultante_cargas(m, sol["info"])
    rx = sum(r[0] for r in sol["reac"].values())
    ry = sum(r[1] for r in sol["reac"].values())
    mr = sum(r[2] + m["nodos"][n - 1]["x"] * r[1] - m["nodos"][n - 1]["y"] * r[0] for n, r in sol["reac"].items())
    # momentos de resortes de giro/apoyos ya incluidos en r[2]
    esc = max(1.0, abs(fx), abs(fy), abs(mo), abs(rx), abs(ry))
    eq = dict(fx=fx + rx, fy=fy + ry, m=mo + mr)
    for k, v in eq.items():
        if abs(v) > 1e-9 * esc * (10 if k == "m" else 1):
            fallos.append("equilibrio global %s = %.3e" % (k, v))
    if sol["res_nodal"] > 1e-8 * esc:
        fallos.append("residuo nodal %.3e" % sol["res_nodal"])
    out = dict(nombre=nombre, d=sol["d"], reac={str(k): v for k, v in sol["reac"].items()},
               barras=barras_out, clasif=dict(tipo=cl["tipo"], grado=cl["grado"]),
               equilibrio=eq, diag=dict(n_ec=cl["n_ec"], n_inc=cl["n_inc"], rango=cl["rango"], cond=sol["cond"]))
    # esperado
    qt = {}
    for e, (b, inf) in enumerate(zip(m["barras"], sol["info"])):
        qt[e] = esfuerzos_barra(b, inf)[1]
    nchk = 0
    for ex in m.get("esperado") or []:
        t = ex["t"]
        tol = ex.get("tol", 1e-6)
        if t == "reac":
            got = sol["reac"][ex["nodo"]]["rx ry mz".split().index(ex["c"])]
        elif t == "d":
            got = sol["d"][ex["nodo"] - 1]["ux uy rz".split().index(ex["c"])]
        elif t == "esf":
            got = evalt(qt[ex["barra"] - 1], ex["x"], ex["c"], ex.get("lado", "+"))
        elif t == "fl":
            got = sol["info"][ex["barra"] - 1]["fl"][ex["i"]]
        elif t == "sumaR":
            got = sum(r["rx ry mz".split().index(ex["c"])] for r in sol["reac"].values())
        elif t == "clasif":
            nchk += 1
            if cl["tipo"] != ex["tipo"] or cl["grado"] != ex["grado"]:
                fallos.append("clasif %s/%d != esperado %s/%d" % (cl["tipo"], cl["grado"], ex["tipo"], ex["grado"]))
            continue
        else:
            raise ErrorModelo("esperado desconocido %r" % t)
        nchk += 1
        want = ex["v"]
        if got is None or abs(got - want) > tol * abs(want) + (1e-9 if tol >= 1e-9 else 1e-12) * (1.0 if abs(want) < 1e-12 else 0.0) + 1e-12:
            fallos.append("esperado %s: obtenido %.10g vs %.10g (tol rel %.0e)" % (json.dumps(ex), got, want, tol))
    return out, fallos, nchk


def main(argv):
    os.makedirs(os.path.join(RAIZ, "tests", "ref"), exist_ok=True)
    archivos = sorted(glob.glob(os.path.join(RAIZ, "tests", "casos", "*.json")))
    with open(os.path.join(RAIZ, "tests", "ref", "indice.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump([os.path.splitext(os.path.basename(a))[0] for a in archivos], f)
        f.write("\n")
    if argv:
        archivos = [a for a in archivos if os.path.splitext(os.path.basename(a))[0] in argv]
    if not archivos:
        print("no hay casos")
        return 1
    mal = 0
    print("%-24s %-14s %2s %-6s %-9s %-10s %-10s %s" % ("caso", "clasif", "gr", "esp.", "eq.max", "|d|max", "|R|max", "estado"))
    for a in archivos:
        nombre = os.path.splitext(os.path.basename(a))[0]
        with open(a, encoding="utf-8") as f:
            m = json.load(f)
        try:
            out, fallos, nchk = procesar(nombre, m)
        except (ErrorModelo, np.linalg.LinAlgError, KeyError) as ex:
            print("%-24s ERROR: %s" % (nombre, ex))
            mal += 1
            continue
        with open(os.path.join(RAIZ, "tests", "ref", nombre + ".json"), "w", encoding="utf-8", newline="\n") as f:
            json.dump(out, f, indent=None, separators=(",", ":"))
            f.write("\n")
        dmax = max(abs(v) for r in out["d"] for v in r if v is not None)
        rmax = max([abs(v) for r in out["reac"].values() for v in r] + [0])
        eqm = max(abs(v) for v in out["equilibrio"].values())
        print("%-24s %-14s %2d %-6s %-9.1e %-10.3e %-10.3e %s" % (
            nombre, out["clasif"]["tipo"], out["clasif"]["grado"], "%d/%d" % (nchk - len([f for f in fallos if f.startswith("esperado") or f.startswith("clasif")]), nchk),
            eqm, dmax, rmax, "OK" if not fallos else "FALLA"))
        for f_ in fallos:
            print("    !", f_)
        if fallos:
            mal += 1
    print("casos: %d, con fallos: %d" % (len(archivos), mal))
    return 1 if mal else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
