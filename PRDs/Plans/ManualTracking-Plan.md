# Plan

Vamos a implementar el tracking manual con un flujo ligero de creación de proyecto y feedback tipo “toast de conflictos”, integrando estado/persistencia primero y luego UI/indicadores. El enfoque será asegurar que el modo manual anule reglas/conflictos, y que el stop por motivo (idle/lock/manual) sea claro.

## Scope
- In: estado manual del tracker y snapshot, creación rápida (título/color/icono con defaults), tracking directo al proyecto manual, agregado de apps/dominios, UI con botones cortos, indicador azul en status item, toasts estilo conflictos.
- Out: edición avanzada de reglas, manual+auto en paralelo, UI compleja durante sesión.

## Action items
[x] Revisar `ActivityTracker`, `CrashRecoveryManager`, `StatusItemController`, `ContentView` para definir puntos de entrada y estado manual.
[x] Extender `SessionSnapshot` para incluir estado manual y restauración coherente tras crash.
[x] Implementar inicio/stop manual en `ActivityTracker` con flush de sesión actual y reanudación automática.
[x] Crear flujo de “proyecto rápido” (título/color/icono opcionales, defaults si vacío) sin pasar por `ProjectFormView`.
[x] Ajustar persistencia en manual: guardar sesiones directo al proyecto y añadir apps/dominios (dominios solo si setting ON) sin conflictos.
[x] Integrar UI con “Manual: iniciar” / “Manual: detener” en ventana principal y status item, más indicador azul celeste cuando esté activo.
[x] Implementar toasts con el patrón visual/animación del toast de conflictos (reutilizar componente si aporta valor).
[x] Validar edge cases: idle/lock durante manual, cambios de app/dominio, recuperación tras crash.
[x] Ejecutar `make test-unit` si la lógica cambia de forma no trivial; si no, validar manualmente el flujo completo.

## Open questions
- Ninguna por ahora.
