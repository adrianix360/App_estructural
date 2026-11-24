# Fase 0 — Investigación y decisiones

Fecha: 2026-11-23. Resúmenes de agentes Haiku; decisiones de Opus. "NC" = no confirmado (probar en la calculadora real).

## 1. Plataforma Nspire (Lua)

| Hallazgo | Fuente | Decisión |
|---|---|---|
| Lua 5.1 sin `io`/`os`; `collectgarbage` disponible | wiki.inspired-lua.org/Overview_of_the_API | Nada de `io`/`os` en `src/` |
| `gc`: drawLine, drawPolyLine, fillPolygon, drawArc/fillArc, drawRect/fillRect, drawString, setColorRGB, setPen(thin/medium/thick, smooth/dotted/dashed). `setAlpha` no existe en 3.2+ | wiki.inspired-lua.org | Solo esas primitivas; enteros siempre (el mock lo exige) |
| `timer.start(seg)`, `timer.stop`, `getMilliSecCounter`, `on.timer` | wiki.inspired-lua.org | Timer solo para mensajes temporales |
| Pantalla 318x212 (medida en el port PERDIDAS en equipo real); memoria y ops/s: NC | port PERDIDAS (`C:\dev\nspire`) | Diseñar para 318x212; leer `platform.window:width()/height()` |
| `toolpalette.register`: ≤15 menús, ≤30 items, callback (menú, item); no llamar en paint | education.ti.com … toolpalettelib/register.htm | Menú principal en la tecla `menu` |
| `on.charIn(c)`, `on.arrowKey(k)`, `on.enterKey`, `on.escapeKey`, `on.backspaceKey`, `on.tabKey`, `on.contextMenu` | education.ti.com … eventhandlinglib, wiki Events | Atajos de una letra + flechas + enter/esc |

## 2. Touchpad

| Hallazgo | Fuente | Decisión |
|---|---|---|
| `on.mouseMove(x,y)` llega **sin botón pulsado** | education.ti.com … mousemove.htm | Cursor "hover": coordenadas en barra de estado y **valor al apuntar** sin clic |
| `on.mouseDown/Up(x,y)` en px relativos a la ventana | … mousedown.htm, mouseup.htm | Clic = crear/seleccionar |
| `on.grabDown` (mantener clic / ctrl+clic), x,y = 0; suprime el mouseUp; `grabMove` no existe desde 3.2 | … grabdown.htm, wiki Events | Arrastre = `mouseDown` sobre nodo + `mouseMove` + `mouseUp`; si llega `grabDown`, entrar en "modo arrastre" hasta el siguiente clic (NC en equipo) |
| `cursor.set`: default, pointer, crosshair, hand open/closed, drag grab, zoom in/out… | … cursorlib | crosshair en Nodo/Barra, pointer en Seleccionar, hand en arrastre |

## 3. CAS desde Lua

| Hallazgo | Fuente | Decisión |
|---|---|---|
| `math.eval(expr)` devuelve tipo Lua o nil + error; `math.evalStr(expr)` devuelve cadena; no disponibles durante la inicialización del script | education.ti.com … mathlibexten/eval.htm, evalstr.htm | Llamar solo tras eventos de usuario, dentro de `pcall` |
| Que `expand(...)`, `∫(...)` o modo exacto funcionen vía evalStr: NC | — | Ecuaciones generadas por `core.poly` (exactas, numéricas); CAS opcional para simplificar/presentar, con respaldo automático |

## 4. Ftool (UX de referencia)

Manuales: tecgraf.puc-rio.br/ftool (ftoolman_pt.pdf v4.01, ftoolman_en.pdf v4.00). Texto no extraído (NC detalles).
Rasgos conocidos y adoptados: modos de inserción de nodos/barras con rejilla y snap; atributos (apoyos, cargas nodales,
cargas distribuidas uniformes/lineales, material, sección) asignados al elemento seleccionado; resultados como
diagramas N/Q/M con el momento del lado traccionado, deformada con factor de escala, reacciones, valores al pasar el cursor.

## 5. Rigidez directa

| Tema | Fuente | Decisión |
|---|---|---|
| Matriz local 6x6 pórtico, transformación por bloques [c s 0; −s c 0; 0 0 1] | en.wikipedia.org/wiki/Direct_stiffness_method; Kassimali | Elemento único de pórtico |
| FEF: puntual Pab²/L², Pa²b/L²; uniforme qL²/12; trapezoidal (3q1+2q2)L²/60, (2q1+3q2)L²/60 | engineeringtoolbox.com (fixed-both-ends); CalcpadCE fully-restrained-beams | FEF por **integración numérica exacta** (Gauss de 3–4 puntos sobre funciones de forma de Hermite), válida para cargas parciales y lineales; las fórmulas cerradas se usan como pruebas |
| Rótulas: matriz modificada o condensación estática | Vukazich (SJSU) lab 11; apuntes "Frames with internal hinges" | Condensación estática de k y FEF |
| Resortes: sumar k a la diagonal; asentamiento = desplazamiento prescrito | ccaprani.github.io/pycba/theory.html; NPTEL m4l29 | Igual |
| Indeterminación: cercha b+r−2j; pórtico 3b+r−3j−c | UMD ENCE353; SJSU 160.4.2 | Se calcula **numéricamente** con el rango de la matriz de equilibrio (ver arquitectura §1) y las fórmulas sirven de prueba |
| Mecanismo = pivote ≈ 0 / rango deficiente | conocimiento estándar (NC en fuente) | Tolerancia relativa al máximo de la diagonal; mensaje con el nudo y GDL implicados |

## 6. Pendiente de probar en el equipo real

`mouseMove` sin clic, `grabDown`, `math.evalStr("expand(...)")` y `"∫(...)"`, velocidad de `on.paint` con diagramas de 20 barras.

**Prueba en equipo real (2026-11-23):** Adrián transfirió `Estructural.tns` (v0.4) a su CX II CAS y reporta que funciona correctamente. Aún falta confirmar uno por uno los puntos de arriba (origen de las ecuaciones: CAS o motor propio; glifos δ, θ, ²).

**Prueba de v1.0 en equipo real (2026-11-23):** Adrián cargó `Estructural.tns` v1.0 en su CX II CAS y reporta que funciona bien.
