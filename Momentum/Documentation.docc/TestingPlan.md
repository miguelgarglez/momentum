# Plan de pruebas

Este repositorio incluye suites `MomentumTests` y `MomentumUITests` con casos alineados al PRD.

## Unit Tests

- Resolución de proyectos por dominio/bundle (`ProjectAssignmentResolver`).
- Cálculo de racha y agregados semanales (`Project` + `DailySummary`).
- Normalización de solapamientos (`SessionOverlapResolver`).

## Integration Tests

- Escenarios activos/idle con `ActivityTracker` usando contenedores en memoria.
- Cambios rápidos de apps para garantizar que los flujos de flush + persist no crean huecos.
- Manejo de fallos en AppleScript (dominio nulo) degradando a tracking sólo por app.

## UI Tests

- Creación de proyecto desde el panel lateral (botón “Nuevo proyecto”).
- Edición de contexto (apps/dominos) verificando chips en `ProjectDetailView`.
- Lectura del dashboard y navegación entre proyectos mediante `NavigationSplitView`.

Consulta las clases de test para encontrar ejemplos concretos y utilidades reutilizables (`InMemoryModelContainerFactory`, `TrackerScenario`, etc.).
