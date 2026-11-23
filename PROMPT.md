# Prompt maestro — Calculadora estructural para TI-Nspire CX II CAS

## 1. Objetivo

Construir una **aplicación de análisis estructural interactiva** para la **TI-Nspire CX II CAS**, comparable en espíritu a **Ftool** (modelado gráfico, resultados inmediatos) y con la lógica de análisis de **SAP2000** (método de rigidez matricial), adaptada a las limitaciones de la calculadora.

Repositorio de trabajo: https://github.com/adrianix360/App_estructural
Carpeta local: esta misma carpeta del proyecto.

## 2. Esquema de trabajo agéntico

| Rol | Modelo | Responsabilidad |
|---|---|---|
| Orquestador / arquitecto | **Opus** | Piensa, planea, divide tareas, decide arquitectura, integra resultados, resuelve bloqueos |
| Ejecutor / revisor | **Sonnet** | Escribe el código, lo prueba, revisa diffs, corrige |
| Explorador / investigador | **Haiku** | Búsquedas, lectura de documentación, localizar APIs, resumir fuentes |
| Refuerzo | **Fable** | Solo para análisis profundo, decisiones de diseño difíciles o bugs numéricos exigentes |

Reglas del esquema:
- Opus no escribe código extenso: delega en Sonnet con briefs concretos (archivos, criterio de "terminado").
- Haiku entrega resúmenes cortos con fuente; Opus decide con ellos.
- Sonnet verifica **toda** entrega contra los casos de prueba (sección 7) antes de reportar.
- Tareas independientes se paralelizan; tareas que tocan los mismos archivos no.

## 3. Fase 0 — Investigación (antes de escribir código)

Haiku investiga y entrega un resumen corto de cada punto; Opus decide:

1. **Plataforma Nspire**: Lua scripting (API `platform`, `gc`, eventos `on.paint`, `on.mouseDown`, `on.mouseMove`, `on.mouseUp`, `on.arrowKey`, `on.charIn`, `on.enterKey`), resolución, memoria y límites de rendimiento de la CX II CAS, y si conviene TI-Basic/Python como apoyo. Referencias en `C:\dev\nspire` (port de la app PERDIDAS) para pipeline de build y pruebas ya resuelto.
2. **Acceso a CAS desde Lua**: `math.eval()` para derivar/integrar/resolver simbólicamente (ecuaciones V(x), M(x), deflexión). Límites de tiempo y de cadena.
3. **Ftool**: flujo de uso (crear nodos, barras, apoyos, cargas, ver diagramas N/V/M/deformada, valores al apuntar con el cursor, escalado de la deformada).
4. **SAP2000 / método de rigidez directa**: ensamblaje de matriz global, condensación de cargas de barra, cargas equivalentes en nodos, empotramiento perfecto, apoyos elásticos, rótulas (liberaciones), efectos de P-Δ fuera de alcance.
5. **Soporte táctil**: cómo la CX II reporta el touchpad (clic, arrastre, coordenadas), y diseño de gestos viables.

Entregable: `docs/investigacion.md` con decisiones y fuentes.

## 4. Requisitos funcionales

### 4.1 Tipos de estructura
- **Vigas** (continuas, en voladizo, con rótulas, apoyos elásticos opcionales).
- **Marcos 2D** (pórticos, con nudos rígidos y articulados, barras inclinadas).
- **Cerchas 2D** (barras solo axiales, nudos articulados).

### 4.2 Clasificación y solución
- Detectar y mostrar: **isostática, hiperestática (con grado de indeterminación) o inestable/mecanismo**.
- Resolver las tres con el **método de rigidez matricial**; para isostáticas verificar equilibrio estático.
- Detectar y avisar con mensaje claro: mecanismo, matriz singular, apoyos insuficientes, barras de longitud cero.

### 4.3 Entrada de datos (modelado)
- Colocar **nodos** directamente con el **touchpad** (clic para crear, arrastrar para mover) con ajuste a rejilla (snap) configurable, y alternativa por teclado numérico (coordenadas exactas).
- Crear **barras** seleccionando dos nodos; editar propiedades (E, A, I) por barra o globales, con unidades configurables (SI y kN·m).
- **Apoyos**: articulado, rodillo, empotrado, resorte; liberaciones en extremos de barra (rótulas).
- **Cargas**: puntual nodal (Fx, Fy, Mz), puntual en barra, distribuida uniforme, distribuida trapezoidal/triangular, momento aplicado, asentamiento de apoyo, carga térmica (opcional, fase tardía).
- Seleccionar, editar, borrar y **deshacer** elementos; guardar/cargar modelos en la calculadora.
- Menús táctiles y atajos de teclado; ayudas visibles en pantalla (barra de estado con la herramienta activa).

### 4.4 Resultados
- **Reacciones** en apoyos (valores y flechas dibujadas).
- **Diagramas**: axial N, cortante V, momento M, **deflexión real y escalada** (factor de escala visible y ajustable).
- **Valor al tocar/apuntar** cualquier punto de una barra: V, M, N, deflexión en ese x.
- **Máximos y mínimos** (con posición) y puntos de cortante cero / momento cero (puntos de inflexión).
- **Ecuaciones por tramo**: V(x), M(x), θ(x), y(x) en forma simbólica usando **CAS** (`math.eval`), con las constantes numéricas del problema sustituidas.
- Tabla resumen: desplazamientos nodales, reacciones, esfuerzos en extremos de cada barra.
- Convención de signos documentada y consistente en toda la app (mostrar leyenda).

## 5. Requisitos de UX / interfaz

- **Prioridad máxima: intuitiva.** Un estudiante debe poder modelar una viga simple en menos de 1 minuto sin leer manual.
- Aprovechar el touchpad: modo dibujo, modo selección, modo carga, modo apoyo; cursor visible con coordenadas.
- Pantalla organizada: lienzo principal + barra de herramientas + barra de estado; paleta de color legible en pantalla color de la CX II (rojo cortante, azul momento, verde deflexión, por ejemplo).
- Zoom y desplazamiento (pan) del lienzo; reencuadre automático ("zoom a la estructura").
- Retroalimentación inmediata: recalcular tras cada cambio cuando el costo lo permita; si no, botón "Resolver" con indicador de progreso.
- Mensajes de error en español, accionables ("Falta un apoyo: la estructura es inestable").
- Consistencia: mismos iconos y teclas en todas las pantallas.

## 6. Arquitectura sugerida (Opus puede cambiarla justificando)

- Lenguaje principal: **Lua (Nspire)**; CAS vía `math.eval` solo donde aporte (ecuaciones simbólicas, verificación), y **solver numérico propio en Lua** para velocidad.
- Módulos separados: `modelo` (datos), `solver` (rigidez, Gauss con pivoteo), `esfuerzos` (diagramas por barra), `dibujo` (gc), `entrada` (eventos táctiles y teclado), `cas` (ecuaciones), `ui` (menús y estado).
- Evitar recomputo innecesario y asignaciones en `on.paint` (límite de memoria y velocidad).
- Script de build que empaque a `.tns` (reutilizar el flujo de `C:\dev\nspire`).
- Un **emulador** (p. ej. TI-Nspire CX CAS Student Software / Firebird / Luna) para pruebas; si no hay, tests del solver en Lua de escritorio con la capa gráfica simulada.

## 7. Verificación (obligatoria)

Sonnet debe validar cada módulo contra **casos con respuesta analítica conocida** antes de avanzar:

| Caso | Resultado de referencia |
|---|---|
| Viga simplemente apoyada, carga uniforme w, luz L | R = wL/2; Mmax = wL²/8; ymax = 5wL⁴/(384EI) |
| Viga simplemente apoyada, carga puntual P al centro | Mmax = PL/4; ymax = PL³/(48EI) |
| Voladizo, carga puntual en extremo | M = −PL; ymax = PL³/(3EI) |
| Viga empotrada-apoyada con w uniforme (hiperestática) | R_apoyo = 3wL/8; M_emp = −wL²/8 |
| Viga continua de 2 tramos iguales con w | R_central = 5wL/4 |
| Cercha simple (triangular) | Fuerzas en barras por método de nudos |
| Marco portal simple con carga lateral | Equilibrio ΣFx, ΣFy, ΣM = 0 y comparación con valores de libro |

Además: comprobar equilibrio global en todas las soluciones, comparar con un solver de referencia en Python (NumPy) fuera de la calculadora, y reportar error relativo (< 1e-6 esperado).

## 8. Control de versiones

- Trabajar sobre el repositorio indicado; commits pequeños y frecuentes, mensajes en español con prefijo (`feat:`, `fix:`, `docs:`, `test:`).
- Un commit por hito: solver de vigas, apoyos y cargas, diagramas, entrada táctil, cerchas, marcos, ecuaciones CAS, pulido de UI.
- Etiquetar versiones estables (`v0.1` vigas isostáticas, `v0.2` hiperestáticas, `v0.3` cerchas, `v0.4` marcos, `v1.0` completo).
- Mantener `README.md` con instrucciones de instalación en la calculadora y capturas.
- Antes de cada `push` confirmar con el usuario si algo es sensible; no subir archivos temporales ni binarios innecesarios.

## 9. Hitos sugeridos

1. Investigación y arquitectura (Fase 0).
2. Solver de vigas + diagramas V/M + pruebas analíticas.
3. Interfaz táctil básica: nodos, barras, apoyos, cargas puntuales.
4. Deflexión real y escalada, hiperestáticas, cargas distribuidas.
5. Ecuaciones por tramo con CAS.
6. Cerchas.
7. Marcos (con axial, rótulas, barras inclinadas).
8. Pulido de UX, guardar/cargar, zoom/pan, ayuda en pantalla.
9. Pruebas finales, documentación, versión 1.0.

## 10. Criterios de aceptación

- Resuelve correctamente los 7 casos de la sección 7.
- Permite modelar viga, marco y cercha completamente con el touchpad.
- Muestra reacciones, N, V, M y deflexión (real y escalada) con valores al apuntar.
- Entrega ecuaciones por tramo simbólicas con CAS.
- Detecta y explica estructuras inestables.
- Corre fluido en la CX II CAS (tiempo de solución razonable para estructuras de hasta ~20 nodos).
- Repositorio con historial limpio, README y versión etiquetada.

## 11. Reglas de comportamiento

- No inventar resultados ni afirmar que algo funciona sin haberlo probado; reportar fallos con la salida real.
- Si una decisión de diseño es ambigua, Opus propone una recomendación y avanza; preguntar al usuario solo si el cambio es costoso.
- Preferir simplicidad: primero vigas funcionando de punta a punta, luego ampliar.
- Documentar supuestos (elementos de Euler-Bernoulli, pequeñas deformaciones, material lineal elástico, análisis 2D).
