# Momentum

<p align="center">
  <img src="Momentum/Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png" alt="Momentum App Icon" width="128" height="128" />
</p>

<p align="center">
  <strong>Marca tus sesiones de foco. Ve el progreso de tus proyectos.</strong><br/>
  App nativa de macOS, local-first, menu-bar-first — sin adivinar qué app eras.
</p>

## Estado (rewrite Focus Session v0)

La rama activa de producto es [`rewrite/focus-v0`](PRDs/Rewrite/FocusSession-v0.md).

Momentum v0 es un **cronómetro de foco intencional**:
- Start / stop desde la barra de menús (tiempo vivo mientras corre)
- Proyectos con totales de hoy y 7 días
- Nota opcional al parar
- Pausa por inactividad (IOKit, sin Automation)
- Atajo global ⌃⌥⌘M (último proyecto)

**Fuera de v0:** auto-tracking de apps/dominios/archivos, conflictos, Raycast, mascota.

El historial del auto-tracker v1 permanece en `main`.

## Desarrollo

```bash
make build
make run-dev
make test-unit
```

PRD: [PRDs/Rewrite/FocusSession-v0.md](PRDs/Rewrite/FocusSession-v0.md)

## Dogfood

Tras un build usable: úsala ≥14 días antes de añadir Raycast, landing monorepo u otras features.
