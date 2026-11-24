"""Genera tests/casos/*.json (modelos en el formato de docs/arquitectura.md Sec. 4) con valores
analiticos 'esperado'. Uso: python tools/gen_casos.py   (los JSON se versionan; esto es solo para
reproducirlos). 'esperado' es una lista de comprobaciones (ver tools/ref_numpy.py)."""
import json, math, os

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tests", "casos")
E, A, I = 2e8, 0.01, 1e-4
EI = E * I


def nodo(x, y, apoyo=None, carga=None):
    n = {"x": x, "y": y}
    if apoyo is not None:
        n["apoyo"] = apoyo
    if carga is not None:
        n["carga"] = carga
    return n


PIN = {"ux": True, "uy": True, "rz": False}
ROD = {"ux": False, "uy": True, "rz": False}
EMP = {"ux": True, "uy": True, "rz": True}


def barra(ni, nj, tipo="portico", rot_i=False, rot_j=False, cargas=None, A_=A, I_=I):
    return {"ni": ni, "nj": nj, "tipo": tipo, "E": E, "A": A_, "I": I_,
            "rot_i": rot_i, "rot_j": rot_j, "cargas": cargas or []}


def guardar(nombre, desc, nodos, barras, esperado):
    m = {"ver": 1, "nombre": nombre, "desc": desc, "nodos": nodos, "barras": barras, "esperado": esperado}
    with open(os.path.join(OUT, nombre + ".json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(m, f, indent=1, ensure_ascii=False)
        f.write("\n")


def rc(n, c, v, tol=1e-6): return {"t": "reac", "nodo": n, "c": c, "v": v, "tol": tol}
def dd(n, c, v, tol=1e-6): return {"t": "d", "nodo": n, "c": c, "v": v, "tol": tol}
def es(b, x, c, v, lado="+", tol=1e-6): return {"t": "esf", "barra": b, "x": x, "c": c, "v": v, "lado": lado, "tol": tol}
def cl(tipo, grado): return {"t": "clasif", "tipo": tipo, "grado": grado}
def sr(c, v, tol=1e-6): return {"t": "sumaR", "c": c, "v": v, "tol": tol}


def wu(a, b, w, d="GY"): return {"t": "w", "a": a, "b": b, "w1": w, "w2": w, "dir": d}


# 1 viga apoyada, w uniforme
L, w = 6.0, -10.0
guardar("viga_apoyada_w", "Viga simplemente apoyada L=6, w=-10 kN/m GY (1 barra)",
        [nodo(0, 0, PIN), nodo(L, 0, ROD)],
        [barra(1, 2, cargas=[wu(0, L, w)])],
        [rc(1, "ry", -w * L / 2), rc(2, "ry", -w * L / 2),
         es(1, L / 2, "M", -w * L * L / 8), es(1, L / 2, "v", 5 * w * L**4 / (384 * EI)),
         es(1, L / 2, "V", 0.0), cl("isostatica", 0)])

# 2 viga apoyada, P al centro
P = -20.0
guardar("viga_apoyada_P", "Viga simplemente apoyada L=6, P=-20 kN GY en el centro (carga en barra)",
        [nodo(0, 0, PIN), nodo(L, 0, ROD)],
        [barra(1, 2, cargas=[{"t": "P", "a": L / 2, "p": P, "dir": "GY"}])],
        [rc(1, "ry", -P / 2), rc(2, "ry", -P / 2), es(1, L / 2, "M", -P * L / 4),
         es(1, L / 2, "v", P * L**3 / (48 * EI)), es(1, L / 2, "V", -P / 2, "-"), es(1, L / 2, "V", P / 2, "+"),
         cl("isostatica", 0)])

# 3 voladizo, P en extremo (carga nodal)
L, P = 4.0, -15.0
guardar("voladizo_P", "Voladizo L=4, empotrado en 1, carga nodal fy=-15 en el extremo",
        [nodo(0, 0, EMP), nodo(L, 0, None, {"fx": 0, "fy": P, "mz": 0})],
        [barra(1, 2)],
        [rc(1, "ry", -P), rc(1, "mz", -P * L), es(1, 0.0, "M", P * L), es(1, L, "M", 0.0),
         dd(2, "uy", P * L**3 / (3 * EI)), dd(2, "rz", P * L**2 / (2 * EI)),
         es(1, L, "v", P * L**3 / (3 * EI)), cl("isostatica", 0)])

# 4 empotrada-apoyada, w
L, w = 6.0, -10.0
guardar("empotrada_apoyada_w", "Viga empotrada (1) - apoyo simple (2), L=6, w=-10",
        [nodo(0, 0, EMP), nodo(L, 0, ROD)],
        [barra(1, 2, cargas=[wu(0, L, w)])],
        [rc(2, "ry", -3 * w * L / 8), rc(1, "ry", -5 * w * L / 8), rc(1, "mz", -w * L * L / 8),
         es(1, 0.0, "M", w * L * L / 8), es(1, L, "M", 0.0), cl("hiperestatica", 1)])

# 5 continua 2 tramos
L, w = 5.0, -10.0
guardar("continua_2tramos_w", "Viga continua 2 tramos de 5 m, w=-10 en ambos",
        [nodo(0, 0, PIN), nodo(L, 0, ROD), nodo(2 * L, 0, ROD)],
        [barra(1, 2, cargas=[wu(0, L, w)]), barra(2, 3, cargas=[wu(0, L, w)])],
        [rc(2, "ry", -5 * w * L / 4), rc(1, "ry", -3 * w * L / 8), rc(3, "ry", -3 * w * L / 8),
         es(1, L, "M", w * L * L / 8, "-"), es(2, 0.0, "M", w * L * L / 8), dd(2, "uy", 0.0, 1e-9),
         cl("hiperestatica", 1)])

# 6 cercha triangular base 4, altura 3, carga en el vertice
Pv = -30.0
c13 = math.hypot(2, 3)
Fb = -Pv / 2 * (2 / 3)          # traccion base = R*cot
Fd = -(-Pv / 2) * c13 / 3       # compresion diagonal (negativa)
guardar("cercha_triangular", "Cercha triangular base 4 altura 3, carga vertical -30 en el vertice",
        [nodo(0, 0, PIN), nodo(4, 0, ROD), nodo(2, 3, None, {"fx": 0, "fy": Pv, "mz": 0})],
        [barra(1, 2, "cercha"), barra(1, 3, "cercha"), barra(3, 2, "cercha")],
        [rc(1, "ry", -Pv / 2), rc(2, "ry", -Pv / 2), rc(1, "rx", 0.0, 1e-9),
         es(1, 0.0, "N", Fb), es(2, 0.0, "N", Fd), es(3, 0.0, "N", Fd), es(2, c13 / 2, "M", 0.0, "+", 1e-9),
         cl("isostatica", 0)])

# 7 portal empotrado h=4 L=6, carga lateral 20 en nodo 2. A=1000 (axil casi rigido) para que valga la
# solucion de pendiente-deflexion con barras axialmente rigidas (tol 1e-4).
h, Lb, H = 4.0, 6.0, 20.0
Ar = 1000.0
# FB = H/2 = (M_AB+M_BA)/h ; M_AB = 2EI/h (th + 3D/h) ; M_BA = 2EI/h (2th + 3D/h) ; th = -6D/(4h+6h^2/L)
f = -6.0 / (4 * h + 6 * h * h / Lb)           # th = f * D
D = (H / 2) * h * h / (2 * EI) / (3 * f + 6 / h)
th = f * D
MAB = 2 * EI / h * (th + 3 * D / h)
ry4 = (H * h - 2 * MAB) / Lb                    # suma de momentos en nodo 1: 6*ry4 + 2*mz - 20*4 = 0
guardar("portal_lateral", "Portal empotrado h=4 L=6 EI constante, carga lateral fx=20 en nodo 2 (A=1000)",
        [nodo(0, 0, EMP), nodo(0, h, None, {"fx": H, "fy": 0, "mz": 0}), nodo(Lb, h), nodo(Lb, 0, EMP)],
        [barra(1, 2, A_=Ar), barra(2, 3, A_=Ar), barra(3, 4, A_=Ar)],
        [sr("rx", -H, 1e-9), sr("ry", 0.0, 1e-9), rc(1, "rx", -H / 2, 1e-4), rc(4, "rx", -H / 2, 1e-4),
         rc(1, "mz", MAB, 1e-4), rc(4, "mz", MAB, 1e-4), rc(4, "ry", ry4, 1e-4), rc(1, "ry", -ry4, 1e-4),
         dd(2, "ux", D, 1e-4), dd(2, "rz", th, 1e-4), cl("hiperestatica", 3)])

# 8 Gerber: empotrado + rotula interna + apoyo simple
w = -10.0
L1, L2 = 6.0, 4.0
Rv = -w * L2 / 2                       # cortante transmitido por la rotula
R1 = -w * L1 + Rv
M1 = -(-w * L1 * L1 / 2 + Rv * L1)     # M(x=0) (hogging, negativo)
tip = w * L1**4 / (8 * EI) - Rv * L1**3 / (3 * EI)
guardar("viga_gerber", "Empotrada (1) - rotula en 2 (x=6) - rodillo en 3 (x=10), w=-10 en todo",
        [nodo(0, 0, EMP), nodo(L1, 0), nodo(L1 + L2, 0, ROD)],
        [barra(1, 2, rot_j=True, cargas=[wu(0, L1, w)]),
         barra(2, 3, rot_i=True, cargas=[wu(0, L2, w)])],
        [rc(3, "ry", Rv), rc(1, "ry", R1), rc(1, "mz", -M1), es(1, 0.0, "M", M1), es(1, L1, "M", 0.0, "-", 1e-9),
         es(2, 0.0, "M", 0.0, "+", 1e-9), es(2, L2 / 2, "M", -w * L2 * L2 / 8), dd(2, "uy", tip),
         cl("isostatica", 0)])

# 9 viga con resorte intermedio
L, w, k = 6.0, -10.0, 5000.0
d0 = 5 * (-w) * L**4 / (384 * EI)
Rs = d0 / (L**3 / (48 * EI) + 1 / k)
guardar("viga_resorte", "Viga L=6 w=-10, apoyos 1 y 3 y resorte vertical k=5000 en nodo 2 (centro)",
        [nodo(0, 0, PIN), nodo(L / 2, 0, {"ux": False, "uy": False, "rz": False, "ky": k}), nodo(L, 0, ROD)],
        [barra(1, 2, cargas=[wu(0, L / 2, w)]), barra(2, 3, cargas=[wu(0, L / 2, w)])],
        [rc(2, "ry", Rs), dd(2, "uy", -Rs / k), rc(1, "ry", (-w * L - Rs) / 2), rc(3, "ry", (-w * L - Rs) / 2),
         es(1, L / 2, "M", (-w * L - Rs) / 2 * L / 2 + w * (L / 2) ** 2 / 2, "-"), cl("hiperestatica", 1)])

# 10 asentamiento en empotrada-empotrada
L, dl = 6.0, -0.01
Vs = 12 * EI * (-dl) / L**3
Ms = 6 * EI * (-dl) / L**2
guardar("asentamiento_empotrada", "Empotrada-empotrada L=6, asentamiento dy=-0.01 en el nodo 2",
        [nodo(0, 0, EMP), nodo(L, 0, {"ux": True, "uy": True, "rz": True, "dy": dl})],
        [barra(1, 2)],
        [rc(1, "ry", Vs), rc(2, "ry", -Vs), rc(1, "mz", Ms), rc(2, "mz", Ms), dd(2, "uy", dl, 1e-9),
         es(1, 0.0, "M", -Ms), es(1, L, "M", Ms), es(1, L / 2, "M", 0.0, "+", 1e-6), cl("hiperestatica", 3)])

# 11 carga trapezoidal parcial en viga apoyada L=8
L, a, b, w1, w2 = 8.0, 2.0, 6.0, -4.0, -12.0
W = (w1 + w2) / 2 * (b - a)
xc = a + (b - a) * (w1 + 2 * w2) / (3 * (w1 + w2))
R2 = -W * xc / L
R1 = -W - R2
guardar("viga_trapezoidal", "Viga apoyada L=8, carga trapezoidal parcial 2..6 de -4 a -12",
        [nodo(0, 0, PIN), nodo(L, 0, ROD)],
        [barra(1, 2, cargas=[{"t": "w", "a": a, "b": b, "w1": w1, "w2": w2, "dir": "GY"}])],
        [rc(1, "ry", R1), rc(2, "ry", R2), es(1, a, "M", R1 * a), es(1, b, "M", R2 * (L - b)),
         es(1, 1.0, "V", R1), es(1, 7.0, "V", -R2), es(1, L, "M", 0.0, "+", 1e-9), cl("isostatica", 0)])

# 12 marco con barras inclinadas, cargas GY, GX, L y puntuales
L23 = math.hypot(4, 2)
L34 = math.hypot(3, 3)
n = [nodo(0, 0, EMP), nodo(0, 3), nodo(4, 5), nodo(7, 2, PIN)]
b1 = barra(1, 2, cargas=[{"t": "P", "a": 1.5, "p": 10, "dir": "GX"}])
b2 = barra(2, 3, cargas=[wu(0, L23, -6), wu(0, 2.0, 3, "GX")])
b3 = barra(3, 4, cargas=[{"t": "P", "a": 2.0, "p": -15, "dir": "GY"}, {"t": "P", "a": 1.0, "p": 8, "dir": "GX"},
                         {"t": "w", "a": 0, "b": L34, "w1": -2, "w2": -5, "dir": "L"}])
# barra 3-4: ex=(1,-1)/sqrt2, +y local=(1,1)/sqrt2 ; carga L de resultante (-2-5)/2*L34
wL = (-2 + -5) / 2 * L34
Fx = 10 + 3 * 2.0 + 8 + wL * math.sqrt(0.5)
Fy = -6 * L23 - 15 + wL * math.sqrt(0.5)
guardar("marco_inclinado", "Marco 4 nodos con barras inclinadas (2-3, 3-4), cargas GY, GX, L, puntuales",
        n, [b1, b2, b3],
        [sr("rx", -Fx, 1e-9), sr("ry", -Fy, 1e-9), cl("hiperestatica", 2)])

# 13 cercha de 7 barras
P4, P5 = -20.0, -40.0
R3 = -(P4 * 2 + P5 * 6) / 8
R1 = -(P4 + P5) - R3
c14 = math.hypot(2, 3)
C14 = R1 * c14 / 3                       # compresion
T12 = C14 * 2 / c14
guardar("cercha_7barras", "Cercha de 5 nodos y 7 barras (2 cordones, 2 diagonales extremas, 2 interiores), cargas -20 y -40",
        [nodo(0, 0, PIN), nodo(4, 0), nodo(8, 0, ROD), nodo(2, 3, None, {"fx": 0, "fy": P4, "mz": 0}),
         nodo(6, 3, None, {"fx": 0, "fy": P5, "mz": 0})],
        [barra(1, 2, "cercha"), barra(2, 3, "cercha"), barra(4, 5, "cercha"), barra(1, 4, "cercha"),
         barra(3, 5, "cercha"), barra(2, 4, "cercha"), barra(2, 5, "cercha")],
        [rc(1, "ry", R1), rc(3, "ry", R3), es(1, 1.0, "N", T12), es(4, 0.0, "N", -C14),
         sr("ry", -(P4 + P5), 1e-9), cl("isostatica", 0)])

# 14 marco de 2 pisos, 2 vanos (9 nodos, 10 barras)
h1, h2, Lv = 3.5, 3.5, 5.0
nn = []
apo = [EMP, PIN, EMP]
for i in range(3):
    nn.append(nodo(i * Lv, 0, apo[i]))
for i in range(3):
    nn.append(nodo(i * Lv, h1, None, {"fx": 25, "fy": 0, "mz": 0} if i == 0 else None))
for i in range(3):
    nn.append(nodo(i * Lv, h1 + h2, None, {"fx": 15, "fy": 0, "mz": 0} if i == 0 else None))
bb = []
for i in range(3):
    bb.append(barra(1 + i, 4 + i))
    bb.append(barra(4 + i, 7 + i))
for (r, wv) in ((4, -20.0), (7, -12.0)):
    for i in range(2):
        bb.append(barra(r + i, r + i + 1, cargas=[wu(0, Lv, wv)]))
guardar("marco_2pisos", "Marco de 2 pisos y 2 vanos, 9 nodos 10 barras, w=-20/-12 en vigas, fx=25 y 15 laterales",
        nn, bb,
        [sr("rx", -40.0, 1e-9), sr("ry", 2 * Lv * (20 + 12), 1e-9), cl("hiperestatica", 11)])

# 15-17 carga termica (docs/arquitectura.md Sec. 4): eps = alfa*du, kappa = -alfa*dg/h
def term(du=0.0, dg=0.0, alfa=1.2e-5, h=0.3):
    q = {"t": "T", "du": du, "alfa": alfa}
    if dg:
        q["dg"] = dg
        q["h"] = h
    return q


al, hh, L, du, dg = 1.2e-5, 0.3, 5.0, 30.0, 20.0
EA = E * A
guardar("termica_empotrada", "Barra empotrada-empotrada L=5, du=30 y dg=20 (h=0.3): N=-EA*alfa*du, M=EI*alfa*dg/h constante, v=0",
        [nodo(0, 0, EMP), nodo(L, 0, EMP)],
        [barra(1, 2, cargas=[term(du, dg, al, hh)])],
        [es(1, L / 2, "N", -EA * al * du), es(1, L / 2, "M", EI * al * dg / hh), es(1, L / 2, "v", 0.0, "+", 1e-9),
         rc(1, "rx", EA * al * du), rc(1, "mz", -EI * al * dg / hh), rc(2, "mz", EI * al * dg / hh),
         cl("hiperestatica", 3)])

R = 3 * EI * al * dg / (2 * hh * L)
guardar("termica_empotrada_apoyada", "Viga empotrada (1) - rodillo (2) L=5, dg=20 (h=0.3): R=3EI*alfa*dg/(2hL), M(0)=R*L",
        [nodo(0, 0, EMP), nodo(L, 0, ROD)],
        [barra(1, 2, cargas=[term(0.0, dg, al, hh)])],
        [rc(2, "ry", R), rc(1, "ry", -R), rc(1, "mz", -R * L), es(1, 0.0, "M", R * L), es(1, L / 2, "M", R * L / 2),
         dd(2, "rz", -al * dg * L / (4 * hh)), cl("hiperestatica", 1)])

hp, Lp = 4.0, 6.0
guardar("portal_termico", "Portal empotrado: viga con du=40 (alfa 1.2e-5), columna derecha con dg=15 (h=0.4), rotula en cabeza de la columna izquierda",
        [nodo(0, 0, EMP), nodo(0, hp), nodo(Lp, hp), nodo(Lp, 0, EMP)],
        [barra(1, 2, rot_j=True), barra(2, 3, cargas=[term(40.0)]), barra(4, 3, cargas=[term(0.0, 15.0, al, 0.4)])],
        [sr("rx", 0.0, 1e-9), sr("ry", 0.0, 1e-9), cl("hiperestatica", 2)])
print("ok")
