# Arquitectura

Momentum se organiza en capas claras:

- **UI (SwiftUI)**: `ContentView`, vistas derivadas y `MomentumApp` renderizan dashboard, detalle de proyectos y hojas de edición. Usa `ActivityTracker` y `TrackerSettings` como `EnvironmentObject` para reaccionar al estado del sistema.
- **Servicios de dominio**: `ActivityTracker`, `ProjectAssignmentResolver`, `AppCatalog` y `DataProtectionCoordinator` aíslan la lógica de tracking automático, resolución de proyectos y protección de datos.
- **Persistencia (SwiftData)**: `Project`, `TrackingSession` y `DailySummary` modelan la base de datos local. Los servicios operan siempre contra `ModelContainer.mainContext` para permitir inyección de contenedores en tests.
- **Integraciones de sistema**: `BrowserDomainResolver`, `SystemPermissionsCenter` y el delegado de la app escuchan notificaciones de `NSWorkspace`, AppleScript y permisos del sistema.

## Puntos clave

- `ActivityTracker` es `@MainActor` y concentra la orquestación de sesiones. Todos los efectos secundarios (persistencia, timers, monitoreo de idle) pasan por este objeto, lo que permite desacoplar la UI.
- `TrackerSettings` centraliza la configuración y se propaga vía `EnvironmentObject` para que los formularios y pantallas de ajustes compartan estado.
- La modularización permite que los mismos servicios se puedan invocar desde extensiones headless (ej. raycast) sin duplicar lógica, cumpliendo con la sección 8 del PRD.

## Arquitectura de diagnósticos y rendimiento

Momentum incorpora una capa transversal de diagnóstico que vigila el coste del tracking y la estabilidad del sistema:

- **PerformanceBudgetMonitor**  
  Supervisa el uso de CPU e I/O mediante snapshots del proceso, envuelve operaciones críticas con `measure(_:work:)` y genera `MetricSample` que la UI o el subsistema de diagnósticos pueden observar.  
  También ejecuta polling pasivo cada 30s para capturar tendencias sostenidas de consumo.  
  Las violaciones de presupuesto (CPU excedido, I/O excesivo) se registran como `Violation` y se notifican vía `OSLog`.

- **MachResourceMetricsSource**  
  Fuente de bajo nivel que obtiene métricas del proceso usando `task_info` y `proc_pid_rusage`.  
  Su diseño permite reemplazarla por mocks ligeros en tests.

## Arquitectura de crash recovery

El sistema de crash recovery garantiza que ningún intervalo temporal se pierda incluso si la app es terminada de forma inesperada:

- **CrashRecoveryManager**  
  Serializa cualquier sesión activa (`currentContext`) cuando cambia el foco o se realiza un flush.  
  Marca el apagado limpio (`clean shutdown`) y, durante el arranque, expone un snapshot pendiente si la app no terminó correctamente.  
  El estado recuperado se reencamina por el pipeline de persistencia, asegurando continuidad temporal.

- **Integración en ActivityTracker**  
  `ActivityTracker` consume los snapshots pendientes al iniciar y los normaliza usando `SessionOverlapResolver`, garantizando que la línea temporal resultante esté libre de solapamientos.

## Resolución de proyectos y normalización temporal

Para mantener un modelado consistente de las sesiones:

- **ProjectAssignmentResolver**  
  Encapsula la lógica de decidir qué proyecto recibe una sesión según el dominio o bundle ID activos.  
  Si se resuelve un dominio, sólo se asigna cuando ese dominio aparece en el proyecto (sin caer al bundle para evitar registros en proyectos erróneos).  
  Cuando no hay dominio disponible, evalúa directamente los bundle IDs registrados y resuelve conflictos mediante reglas guardadas; si la app no está asignada, la sesión se descarta para evitar que caiga en el primer proyecto.  
  Aísla reglas y heurísticas que de otro modo vivirían dentro del tracker.

- **SessionOverlapResolver**  
  Detecta y resuelve solapamientos entre sesiones adyacentes antes de persistirlas.  
  Esto asegura que cálculos de rachas, resúmenes diarios o semanales operen sobre una línea temporal coherente.

## Consideraciones de testabilidad

La arquitectura está diseñada para pruebas integradas y unitarias:

- Todos los servicios aceptan dependencias inyectables (contendores SwiftData in‑memory, monitores mock, fuentes de métricas falsas).  
- `ActivityTracker` incluye ayudantes debug-only para exponer su estado interno sin comprometer la encapsulación.  
- El modo `--uitests-reset` permite que las suites de UI arranquen la app en estado limpio, sin datos previos.

Este enfoque modular permite validar el flujo completo —tracking, persistencia, diagnóstico y recuperación— sin acoplar tests a la UI.
