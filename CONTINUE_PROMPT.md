# Continuar refactor UI (nuevo chat)

Queremos seguir modularizando `Momentum/ContentView.swift` porque estaba todo en un solo archivo. Ya se empezó a mover a una estructura por features.

## Estado actual (hecho)
- `DashboardHeaderView` y `DashboardMetricsView` se movieron a `Momentum/Views/Dashboard/DashboardHeaderView.swift`.
- Estilos compartidos se movieron a `Momentum/Views/Styles/DetailCardStyles.swift` (`detailCardStyle` y `detailInsetStyle`).
- `ProjectDetailView` y sus piezas (MetricCard, ContextUsage*, LastUsedCard, HighlightMetricRow, AssignedAppsChips, WrappingChips, UsageWindow, DetailMetaPill) se movieron a `Momentum/Views/Projects/ProjectDetailView.swift`.
- `FlowLayout` se movió a `Momentum/Views/Components/FlowLayout.swift`.
- `ContentView.swift` ahora solo compone y ya no define esos componentes.

## Build
- `make build` pasó correctamente al final del refactor.

## Qué falta / siguientes pasos
1) Seguir sacando más componentes desde `Momentum/ContentView.swift` hacia `Views/Components/` o subcarpetas por feature:
   - `SelectedAppChips` (usa `FlowLayout`).
   - Vistas auxiliares de settings o formularios que hoy sigan en `ContentView.swift`.
2) Revisar `ContentView.swift` para identificar otros grupos grandes de views que puedan ir a `Views/Projects/`, `Views/Tracking/`, etc.

## Contexto relevante
- Estructura recomendada: `Views/Dashboard`, `Views/Projects`, `Views/Components`, `Views/Styles`.
- Mantener estilo SwiftUI y naming actual.
- No romper el diseño ni comportamiento.

## Notas UI (del trabajo previo)
- La tarjeta de resumen en sidebar quedó colapsable, persiste estado (`@AppStorage`), y adapta métricas en modo compacto.
- Ajustes visuales de tiles: tamaño reducido, sin iconos, contenido alineado abajo‑izquierda, alturas uniformes.

## Archivos clave
- `Momentum/ContentView.swift`
- `Momentum/Views/Dashboard/DashboardHeaderView.swift`
- `Momentum/Views/Projects/ProjectDetailView.swift`
- `Momentum/Views/Components/FlowLayout.swift`
- `Momentum/Views/Styles/DetailCardStyles.swift`

## Instrucción
Continúa el refactor con el mismo estilo. Asegura `make build` antes de finalizar.
