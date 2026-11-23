-- ui/resultados.lua - PUNTO DE ENGANCHE de resultados (fase posterior). Hoy son stubs.
--
-- Contrato con la UI de modelado:
--   R.resolver(S, modelo) -> ok, msg   S = require("core.solver"). Debe llamar S.resolver(modelo),
--                                      guardar el resultado y devolver true | false, "mensaje".
--   R.invalidar()          la UI lo llama tras CUALQUIER cambio del modelo (descartar resultados).
--   R.limpiar()            borra los resultados (volver a modo modelado).
--   R.activo() -> bool     true si hay resultados vigentes para el modelo actual.
--   R.pintar(gc, V, m)     se llama desde on.paint tras dibujar el modelo; dibuja diagramas,
--                          reacciones y deformada usando V.a_pantalla (cache por camara).
--   R.estado() -> texto    texto corto para la barra de estado (p. ej. "Hiperestatica grado 1").
--   R.mouse(x, y) -> texto valor al apuntar sobre una barra (o nil).
local R = {}

R.res = nil

function R.resolver(S, modelo)
  return false, "Resultados: interfaz pendiente de implementar"
end

function R.invalidar()
  R.res = nil
end

function R.limpiar()
  R.res = nil
end

function R.activo()
  return R.res ~= nil
end

function R.pintar(gc, V, m)
end

function R.estado()
  return nil
end

function R.mouse(x, y)
  return nil
end

return R
