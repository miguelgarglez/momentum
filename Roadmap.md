# Momentum — Próximas funcionalidades clave

Este documento recoge las 3 iniciativas priorizadas para convertir Momentum en un producto completo.

## 1. Historial extendido + heatmap anual (completada)
- Historial de actividad por proyecto con rango mensual/anual.
- Vista tipo "contributions" basada en actividad diaria.
- Backfill de resúmenes desde sesiones existentes.
- Objetivo adicional: gráfica de tiempo en rangos mayores a una semana (mes, trimestre, año).
- Nota: planear alcance (modelo/aggregación/UI), visual, rendimiento y validación con datos reales.

## 2. Actualizaciones automáticas + pipeline de releases
- Detección de updates dentro de la app (p.ej. Sparkle).
- Pipeline automatizado (build, firma/notarización, appcast, release).
- Nota: planear tooling, credenciales, flujo de release y rollback.

## 3. Integración headless (CLI/Raycast + export JSON)
- Extraer lógica de dominio en un módulo reutilizable.
- CLI local para stats y control de tracking.
- Export JSON para dashboards rápidos y futuras integraciones.
- Prioridad: Raycast como integración principal.
- Objetivo principal: habilitar integración con una futura extensión de Raycast.
- Nota: planear arquitectura, contrato de integración y pruebas end-to-end.
