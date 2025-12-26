# Arquitectura preparada para integración con Raycast

Este documento describe cómo dejar Momentum listo para exponer su lógica a una futura extensión de Raycast sin reescribir funcionalidades clave.

## Objetivos
- Compartir la misma lógica de negocio (creación/cierre de sesiones, resolución de proyectos, métricas) entre la app macOS y cualquier cliente externo.
- Mantener los datos locales y controlados por Momentum, permitiendo a Raycast actuar como una interfaz adicional.
- Minimizar el trabajo futuro cuando llegue el momento de implementar la extensión TypeScript/React indicada en la [documentación oficial](https://developers.raycast.com).

## Componentes propuestos

### 1. MomentumCore (Swift Package/Framework)
- `SessionService`: orquesta abrir/cerrar sesiones y validar duración mínima.
- `ProjectService`: gestiona CRUD y reglas de asignación app/dominio → proyecto.
- `StatsService`: calcula totales diarios/semanales, rachas y resúmenes.
- `AssignmentEngine` (puro): encapsula la lógica de `Project.matches`.
- Protocolos `SessionRepository` y `ProjectRepository` para abstraer la persistencia.

### 2. Adaptadores de persistencia
- `SwiftDataSessionRepository` y `SwiftDataProjectRepository` implementan los protocolos contra la base local existente.
- Posibilidad de añadir adaptadores alternativos (por ejemplo, SQLite directa) si una CLI necesita acceder al mismo store sin levantar la app.

### 3. Integraciones del sistema
- `SystemActivityMonitor` (encapsula NSWorkspace, AppleScript, timers).
- `ActivityTracker` pasa a depender únicamente de los servicios de MomentumCore, de modo que pueda sustituirse por otras fuentes (p.ej. una CLI manual).

### 4. Canal de integración
1. **CLI local (`momentum-cli`)**  
   - Comandos `session start`, `session stop`, `stats summary`, `projects list`.  
   - Entradas/salidas en JSON para ser consumidas por Node.js (`child_process.execFile`).
2. **Exportador de estado**  
   - Servicio opcional que actualiza `/Users/<user>/Library/Application Support/Momentum/export/*.json` con métricas precalculadas.  
   - Raycast sólo lee los archivos para mostrar dashboards rápidos.
3. **Servidor local / socket** (futuro)  
   - Si se necesita comunicación en tiempo real, se podría exponer una API local basada en XPC o HTTP. No es requisito para el MVP.

## Flujo esperado
1. MomentumApp (SwiftUI) consume `SessionService` y `ProjectService` vía `Environment`.
2. `ActivityTracker` recibe eventos del sistema → delega en `SessionService`.
3. `momentum-cli` (nuevo target Swift) inicializa MomentumCore con los mismos adaptadores SwiftData y ejecuta comandos en el terminal.
4. La extensión Raycast llama al CLI/exportador usando `@raycast/api` (`execFile`, lectura de JSON) y renderiza resultados en componentes React.

## Raycast Extension (futuro)
- Tecnologías: Node.js ≥ 22, npm ≥ 7, React + TypeScript (`npx ray develop`, `npx ray build`).
- Comandos sugeridos:
  - `Momentum: Registrar sesión manual` → invoca `momentum-cli session start/stop`.
  - `Momentum: Ver progreso hoy` → lee `stats summary`.
  - `Momentum: Pausar/Reanudar tracking` → delega en CLI o escribe un flag que `ActivityTracker` observe.
- Reutiliza el conocimiento de Raycast sobre listas, forms y acciones rápidas para replicar flows esenciales sin duplicar lógica.

## Roadmap recomendado
1. Extraer MomentumCore y protocolos de repositorios.
2. Mover reglas de asignación/estadísticas desde `Project` y `TrackingSession` a servicios testeables.
3. Crear `momentum-cli` y validar lectura/escritura desde línea de comandos.
4. Añadir exportador JSON opcional para dashboards rápidos.
5. Documentar un contrato de integración (formatos JSON, comandos CLI) y crear ejemplos en la extensión Raycast.

## Referencias útiles
- [Introducción Raycast API](https://developers.raycast.com/readme.md)
- [Getting Started](https://developers.raycast.com/basics/getting-started.md)
- [Create Your First Extension](https://developers.raycast.com/basics/create-your-first-extension.md)
- [Raycast CLI](https://developers.raycast.com/information/developer-tools/cli.md)

Con esta estructura, la app queda preparada para conectar Raycast (o cualquier otra superficie) reutilizando exactamente los mismos servicios y reglas que ya usan las vistas nativas de Momentum.
