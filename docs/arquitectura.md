# Arquitectura — Calculadora estructural (TI-Nspire CX II CAS)

Autor: Claude Opus 5.5 (orquestador), 2026-11-23. Este documento es el **contrato** entre módulos:
quien implemente un módulo respeta los formatos y firmas de aquí. Cambios: se editan aquí primero.

## 1. Decisiones

| Tema | Decisión | Motivo |
|---|---|---|
| Lenguaje | Lua 5.1, `platform.apiLevel = '2.4'`, sin Ndless | Corre en cualquier SO de la CX II |
| Build | `tools/build.py` (copiado de `C:\dev\nspire`): concatena `src/**.lua` con `require` propio, verifica sintaxis con `luac -p`, empaqueta con Luna a `build/Estructural.tns` | Flujo ya probado en la calculadora real |
| Pruebas | `tools/run_tests.sh`: Lua 5.1 de escritorio (`C:\dev\tools\lua51\lua.exe`) + `tests/mock_nspire.lua` (API simulada) | Sin emulador; render a PNG con `tools/render_png.py` |
| Elemento | **Un solo elemento de pórtico 2D** Euler-Bernoulli (3 GDL/nodo: ux, uy, rz) con liberaciones de momento por extremo. Viga = pórtico horizontal; barra de cercha = pórtico con ambos extremos liberados | Un solo solver para vigas, marcos y cerchas; menos código y menos errores |
| Rótulas | Condensación estática de la matriz local 6x6 (y del vector de empotramiento) sobre los GDL liberados; el giro del extremo liberado se recupera para dibujar la deformada | Estándar (Kassimali / McGuire) |
| GDL de giro sin rigidez | Nudo cuyas barras llegan todas liberadas y sin apoyo de giro: su GDL rz se elimina (giro indefinido, no se muestra). Si ese nudo tiene momento aplicado → error "mecanismo" | Evita matriz singular espuria en cerchas y rótulas |
| Matriz global | Densa, Gauss con pivoteo parcial. ≤ 20 nodos = ≤ 60 GDL: ~72 k operaciones, despreciable | Simple y robusta; banda no hace falta a este tamaño |
| Clasificación | **Numérica** por la matriz de equilibrio B (ecuaciones nodales × fuerzas incógnitas): `r = rango(B)`; inestable si `r < n_ec`; grado = `n_inc − r` (0 = isostática) | Vale para cualquier mezcla de barras, rótulas y apoyos, sin fórmulas por caso |
| Esfuerzos | Por barra, **polinomios por tramos** exactos (cargas lineales ⇒ M cúbico, y quíntico) obtenidos integrando desde el extremo i; el valor en j sirve de verificación | Valores al apuntar, máximos, ceros y ecuaciones salen del mismo objeto |
| CAS | Opcional: `math.evalStr` solo para presentar/verificar ecuaciones; si falla, las ecuaciones salen del módulo `poly` propio | El solver nunca depende del CAS (velocidad y robustez) |
| UI | Orientada a eventos (no corrutina): estado de herramienta + lienzo con cámara (zoom/pan) + barra de herramientas + barra de estado + diálogos numéricos propios | El modelado gráfico es naturalmente por eventos |
| Persistencia | `on.save` / `on.restore` con `{ver, modelo, cfg, biblioteca}`; deshacer por instantáneas serializadas (máx. 30) | Mecanismo estándar; probado en PERDIDAS |

## 2. Supuestos (se muestran en Ayuda)

Elementos Euler-Bernoulli, pequeñas deformaciones, material lineal elástico, análisis 2D estático,
un solo estado de carga, sin P-Δ, sin deformación por cortante.

## 3. Unidades y signos

- Internas: **kN, m, rad** (E en kN/m², A en m², I en m⁴, w en kN/m, M en kN·m). La UI convierte.
- Ejes globales: X a la derecha, Y hacia arriba, giros antihorarios positivos. Carga hacia abajo = `p < 0` en dirección `GY`.
- Ejes locales de barra: x de i a j; y local = x local girado 90° antihorario.
- Fuerzas de extremo locales `fl = {Fxi, Fyi, Mi, Fxj, Fyj, Mj}`: fuerzas que los **nodos ejercen sobre la barra**, en ejes locales (`fl = k·d_local + f_empotramiento`).
- Esfuerzos internos (para diagramas, valores y ecuaciones), con x local:
  - `N(x)` positivo = **tracción**: `N(x) = −Fxi − ∫₀ˣ qx`.
  - `V(x)` = `Fyi + ∫₀ˣ qy` (+ cargas puntuales a la izquierda). Cumple `V = dM/dx`.
  - `M(x)` positivo = **comprime la fibra +y local** (en viga horizontal i→j: positivo = tracción abajo, "sonrisa"): `M(x) = −Mi + Fyi·x + ∫₀ˣ qy(s)(x−s)ds` (+ cargas/momentos puntuales).
  - Momento puntual `m` (antihorario +) en `a`: para `x > a`, `M(x)` recibe `−m`. En un salto (P o m interiores) se reportan ambos límites (izquierda y derecha) en el mismo x.
  - Resorte en un GDL cuenta como una reacción incógnita en la clasificación; la reacción reportada es la total del GDL (apoyo + resorte).
  - `θ(x) = θi + ∫ M/EI`, `v(x) = vi + ∫ θ` (desplazamiento transversal local), `u(x) = ui + ∫ N/EA`. Comprobación: `v(L)`, `θ(L)`, `u(L)` deben coincidir con el extremo j (tolerancia relativa 1e-9).
- Dibujo: M se dibuja **del lado traccionado** (como Ftool); N y V positivos hacia +y local. Leyenda en pantalla.

## 4. Formato del modelo (tablas planas, serializables)

```lua
modelo = {
  ver = 1,
  nodos = {                -- arreglo; el índice es el número de nodo (base 1)
    { x = 0, y = 0,
      apoyo = nil | { ux = true, uy = true, rz = false,     -- GDL restringidos
                      kx = 0, ky = 0, kr = 0,                -- resortes (kN/m, kN·m/rad); >0 activa
                      dx = 0, dy = 0, drz = 0 },             -- asentamientos prescritos (m, rad) en GDL restringidos
      carga = nil | { fx = 0, fy = 0, mz = 0 } },            -- carga nodal (kN, kN·m)
  },
  barras = {               -- arreglo
    { ni = 1, nj = 2,
      tipo = "portico" | "cercha",        -- cercha ⇒ rot_i = rot_j = true implícito
      E = 2e8, A = 0.01, I = 1e-4,
      rot_i = false, rot_j = false,       -- rótula (momento liberado) en el extremo
      cargas = {                          -- cargas en la barra (a, b medidos desde i, en m)
        { t = "P", a = 2.0, p = -10, dir = "GY" },                     -- puntual
        { t = "M", a = 2.0, m = 5 },                                   -- momento puntual (antihorario +)
        { t = "w", a = 0, b = 4, w1 = -5, w2 = -5, dir = "GY" },       -- distribuida lineal (uniforme si w1 = w2)
      } },
  },
}
```
- `dir`: `"GY"` (global Y), `"GX"` (global X), `"L"` (perpendicular local, +y local), `"LX"` (axial local). Intensidad `w` por **unidad de longitud de barra**.
- Falta un campo ⇒ valor por omisión (`apoyo.k* = 0`, `d* = 0`, `cargas = {}`).
- **Carga térmica** (v1.0), en `barra.cargas`: `{ t = "T", du = 20, dg = 10, alfa = 1.2e-5, h = 0.3 }`
  - `du` (°C): incremento uniforme de temperatura en el eje (positivo = calentamiento ⇒ alarga la barra).
  - `dg` (°C): diferencia `T(cara −y local) − T(cara +y local)`; en viga horizontal i→j, `dg > 0` = cara inferior más caliente ⇒ la barra se curva hacia arriba (centro sube si está simplemente apoyada).
  - `alfa` (1/°C, por omisión 1.2e-5), `h` (m, canto de la sección; obligatorio si `dg ≠ 0`).
  - Deformaciones impuestas: `ε_T = alfa·du`, curvatura `κ_T = −alfa·dg/h` (con `v'' = M/EI + κ_T`); `u' = N/EA + ε_T`. Comprobaciones: empotrada-empotrada con `du` ⇒ `N = −EA·alfa·du`; con `dg` ⇒ `M` constante, `|M| = EI·alfa·dg/h`, y `v ≡ 0`; simplemente apoyada con `dg` ⇒ flecha central `alfa·dg·L²/(8h)` hacia arriba, sin esfuerzos; libre axialmente con `du` ⇒ alargamiento `alfa·du·L` sin esfuerzos.

## 4.1 Unidades de presentación (v1.0)

Internas siempre kN, m, rad. La UI ofrece sistemas (menú Ajustes → Unidades), guardados en `cfg.unidades`:

| Sistema | Fuerza | Longitud | Distribuida | Momento | E | A | I | Desplazamiento |
|---|---|---|---|---|---|---|---|---|
| `kN-m` (omisión) | kN | m | kN/m | kN·m | GPa | cm² | cm⁴ | mm |
| `N-m` (SI) | N | m | N/m | N·m | Pa | m² | m⁴ | m |
| `tf-m` | tf (9.80665 kN) | m | tf/m | tf·m | kgf/cm² | cm² | cm⁴ | mm |

Conversión centralizada en `src/ui/unidades.lua`: `U.a_interna(cant, valor)`, `U.de_interna(cant, valor)`, `U.etiqueta(cant)`, con `cant` ∈ fuerza, long, dist, momento, E, A, I, desp, giro, temp.

## 5. API del núcleo (`src/core/`)

```lua
local S = require("core.solver")
local cl  = S.clasificar(modelo)
--  cl = { tipo = "isostatica" | "hiperestatica" | "inestable", grado = n, n_ec, n_inc, rango, msg = "texto en español" }
local res, err = S.resolver(modelo)
--  err = nil | { cod = "SIN_NODOS"|"LONG_CERO"|"NODO_SUELTO"|"SIN_APOYOS"|"MECANISMO"|"SINGULAR"|"DATO", msg = "...", nodo = i?, barra = e? }
--  res.clasif = cl
--  res.d[i]    = { ux, uy, rz }         -- rz = nil si el GDL se eliminó (nudo articulado)
--  res.reac[i] = { rx, ry, mz }         -- solo nodos con apoyo (incluye resortes: R = −k·d)
--  res.barras[e] = { L, c, s, fl = {6}, dl = {6} (desplazamientos locales de extremo, con giros de extremo recuperados en rótulas), tramos = {...} }
--  res.equilibrio = { fx, fy, m }       -- residuo global ΣFx, ΣFy, ΣM(origen) de cargas + reacciones
local E = require("core.esfuerzos")
E.eval(res, e, x)            --> N, V, M, theta, v, u   (x local en m, 0..L)
E.muestras(res, e, campo, n) --> {x1, val1, x2, val2, ...}  campo = "N"|"V"|"M"|"v"|"u"; incluye los quiebres
E.extremos(res, e, campo)    --> { {x=, val=, tipo="max"|"min"}, ... } (incluye extremos de la barra)
E.ceros(res, e, campo)       --> { x1, x2, ... }   (V = 0, M = 0 → puntos de inflexión)
E.ecuaciones(res, e)         --> { {x0=, x1=, V=poly, M=poly, th=poly, y=poly, N=poly}, ... }  poly en x local del tramo global (no desplazado)
E.global(res, e, x, escala)  --> X, Y   -- posición deformada en coordenadas globales (para dibujar)
local P = require("core.poly")  -- polinomios {c0, c1, ...}: eval, add, scale, integ(p, c), deriv, roots_in(p, a, b), tostring(p, "x", dec)
local LA = require("core.linalg") -- mat(n,m), solve(K, F) -> x | nil, info ; rank(B, tol) -> r
```
Extensiones del contrato (implementadas en `src/core/`):
- `S.clasificar(modelo)` devuelve `cl, err`; si el modelo no valida, `cl.tipo = "inestable"` y `cl.msg = err.msg`.
- `res.equilibrio` añade `rel` (residuo relativo = máx(|ΣFx|,|ΣFy|)/Σ|F| y |ΣM|/Σ|F·brazo|).
- `res.barras[e]` añade `ni, nj, xi, yi`, `tramos[k] = {x0, x1, N, V, M, th, y, u}` (polinomios en x local sin desplazar; `y` = v) y `verif = {v, th, u, rel}` (error de v(L), θ(L), u(L) frente a `dl`). Los construye `E.construir(modelo, res)`, llamado por `S.resolver`.
- `E.ecuaciones` añade `u`; `E.eval` en un quiebre devuelve el lado derecho; `E.muestras` repite el x en saltos (valor izquierdo y derecho); el campo `"th"` (giro) también es válido en muestras/extremos/ceros.
- Polinomios: `p[1]` = término independiente. Extras en `core.poly`: `sub, mul, shift, trim, grado`. `core.linalg`: `solve(K, F, n, inplace)` → `x | nil, indice_gdl`.
- Carga térmica `{t="T"}` (implementada, sin cambio de contrato): fuerzas de empotramiento `f0 = {+EA·ε, 0, +EI·κ, −EA·ε, 0, −EI·κ}` (ε = alfa·du, κ = −alfa·dg/h), condensadas como cualquier carga; en `esfuerzos`, `u' = N/EA + ε` y `θ' = M/EI + κ`. Validación (cod `DATO`, mensaje en español, con `barra`): `du`, `dg`, `alfa`, `h` numéricos; `dg ≠ 0` exige `h > 0`; `du` solo no necesita `h`. No introduce quiebres ni afecta `res.equilibrio`. Referencia NumPy: cargas nodales equivalentes ∫BᵀDε₀dx con funciones de forma de Hermite (casos `termica_empotrada`, `termica_empotrada_apoyada`, `portal_termico`).
- Asentamientos (`dx, dy, drz`) solo se aplican a GDL restringidos (`ux/uy/rz = true`); en GDL con resorte se ignoran. Barras `cercha` pueden omitir `I`.
- `E.extremos`: extremos de barra, puntos críticos y picos en quiebres; una meseta se informa una sola vez.

Restricciones: sin variables globales; módulos devuelven tabla; nada de `io`/`os` en `src/` (no existen en la calculadora).

## 6. UI (`src/ui/`, `src/main.lua`)

- `ui.modelo_ed` (M): edición del modelo: `nuevo()`, `agregar_nodo(m,x,y)`, `nodo_cerca(m,x,y,tol)`, `agregar_barra(m,i,j,props)`, `borrar_nodo` (renumera y borra barras que lo usan), `borrar_barra`, `mover_nodo`, `deshacer`/`rehacer` (pila de instantáneas serializadas), `serializar`/`deserializar`, ejemplos predefinidos.
- `ui.vista`: cámara (escala px/m, origen), `a_pantalla(x,y)`, `a_mundo(px,py)`, `zoom(f, px, py)`, `pan(dx,dy)`, `encuadrar(modelo)`, rejilla y snap configurable (0.1, 0.25, 0.5, 1 m).
- `ui.dibujo`: estructura, apoyos (articulado, rodillo, empotrado, resorte), rótulas, cargas, reacciones, diagramas N/V/M y deformada escalada, leyenda, cursor y coordenadas. Colores: N morado, V rojo, M azul, deformada verde, cargas naranja, reacciones magenta.
- `ui.herramientas`: modos Seleccionar/Mover, Nodo, Barra, Apoyo, Carga, Resultados (N, V, M, Def, Reacc). Barra de herramientas arriba (iconos con clic), barra de estado abajo (modo, coordenadas, clasificación).
- `ui.dialogo`: formularios numéricos propios (campos, edición con teclado, ENTER aceptar, ESC cancelar).
- `ui.cas`: ecuaciones por tramo vía `math.evalStr` con respaldo `core.poly`.
- Recalcular automáticamente tras cada cambio (estructuras ≤ 20 nodos); cachear muestras de diagramas por (resultado, cámara) para no asignar memoria en `on.paint`.

### 6.1 Modo resultados (`ui.resultados`, `ui.cas`)

- `r` / botón Resolver entra en modo resultados (la herramienta pasa a Seleccionar y se restaura al salir). Cada cambio del modelo (`ED.on_cambio` → `R.invalidar`) re-resuelve al instante si hay ≤ 20 nodos; si no, avisa y `r` fuerza el cálculo. La clasificación (`S.clasificar`) se muestra siempre a la derecha de la barra de estado; los errores del solver se traducen a mensajes accionables y se muestran en un recuadro.
- Vistas (barra de herramientas: Reac, N, V, M, Def, Tabla, Ecs, +, −, Modelar): teclas `r n v m d t e`, TAB cicla, `+`/`-` escala del diagrama o factor de la deformada, `0` deformada real, `?`/`l` leyenda, `f` encuadrar, `z`/`x` zoom, ESC quita el cursor y luego vuelve a modelar (`s a c b` vuelven a modelar con esa herramienta). Flechas: ←/→ mueven el cursor por la barra, ↑/↓ cambian de barra; en Tabla/Ecs desplazan (←/→ cambian de barra en Ecs).
- Valor al apuntar: `on.mouseMove` sin clic (o clic/flechas) sobre barra (≤ 8 px) o nodo (≤ 7 px) → recuadro y barra de estado con N, V, M, δ en ese x.
- Cache por resultado en coordenadas de barra (x local, valor): la cámara solo interviene al pintar, sin crear tablas (≈ 0.4 KB de basura por `on.paint`).
- `ui.cas.ecuacion`: `math.evalStr("expand(...)")` dentro de `pcall`; solo se acepta si coincide numéricamente en 2 puntos con `core.poly`; se indica el motor ("CAS" o "propio"). Texto de los polinomios: `poly.tostring_sig` (4 cifras significativas).

## 7. Verificación

`tests/test_solver.lua` (casos analíticos de PROMPT §7 con error relativo < 1e-6) y
`tests/test_ref.lua` (compara con `tools/ref_numpy.py` sobre `tests/casos/*.json`). Equilibrio global en
todas las soluciones (< 1e-8 relativo). Cada entrega se reporta con la salida real de `tools/run_tests.sh`.
