# PRD — Raycast Integration (Local API)

## Objetivo
- Permitir que una extensión de Raycast ejecute acciones en Momentum con respuesta inmediata.
- Reutilizar la lógica existente (ActivityTracker, SwiftData) sin duplicar reglas.
- Soportar acciones en background y, cuando sea necesario, abrir la UI.

## Contexto y hallazgos del repo
- `ActivityTracker` (Services) es `@MainActor` y concentra tracking, manual y resolución de conflictos.
- `PendingConflictResolutionView` agrupa conflictos con `PendingConflict.grouped` definido dentro de la view.
- La UI principal abre la hoja de conflictos desde `ContentView` (`showConflictSheet`).
- Las acciones del status item se disparan vía `NotificationCenter` (`StatusItemController`).
- El ciclo de vida está en `AppEnvironment` (bootstrap de tracker, status item, dock visibility).
- La app está sandboxed (`Momentum.entitlements`), lo que limita compartir archivos con Raycast.
- PRDs/Overview exige que la lógica pueda ser invocada por clientes headless (FR-8.2).
- Hubo un enfoque previo basado en CLI/export; este PRD define un canal HTTP local para respuestas bidireccionales.

## Alcance (MVP)
- Servidor HTTP local en `127.0.0.1`.
- Puerto fijo `51637`.
- Pairing con código de 4 dígitos y expiración 10 minutos.
- Token de acceso no expira, revocable manualmente.
- Endpoints mínimos: `health`, `pairing`, `commands`, `settings/open`.
- Comando base inicial implementado: `projects.list`.
- Apertura de ajustes desde extensión vía endpoint dedicado.

## Estado actual de implementación (fase activa)
- App:
  - `RaycastIntegrationManager` centraliza servidor, pairing y comandos.
  - `SettingsWindowPresenter` centraliza apertura de ajustes y evita duplicados de ventanas.
  - El deep link `momentum://settings?section=raycast` sigue soportado.
  - El manejo de URL se procesa por AppDelegate para evitar doble handling del mismo evento.
- Extensión:
  - Comandos activos: `list-projects` y `open-settings`.
  - `open-settings` está en modo `no-view`.
  - El flujo de abrir ajustes se canaliza por `openMomentumSettings()` (HTTP local).
  - Se descarta link visible para abrir ajustes en la vista de pairing por comportamiento inconsistente/prompt de seguridad de Raycast al abrir comandos vía URL.

## No alcance
- Sin cloud ni sync.
- Sin multi-usuario.
- Sin API pública remota.
- Sin refactor completo a `MomentumCore` en esta fase.

## Principios
- Reusar servicios actuales y mantener dependencia: Views -> Services -> Models -> Utilities.
- No introducir side effects en Views; usar notificaciones para activar UI.
- Mantener el servidor idle sin polling (CPU ~0).

## Arquitectura propuesta
- `Momentum/Services/Raycast/`
- `RaycastServer`: arranque/parada, binding al puerto, HTTP minimal.
- `RaycastTokenStore`: almacena tokens válidos y pairing code.
- `RaycastIntegrationManager`: valida payload, ejecuta acciones (MainActor) y expone estado observable para Settings.
- `SettingsWindowPresenter` (Services): punto único para abrir ajustes sin side effects de ventanas.

## Ciclo de vida
- El servidor solo se inicia si `TrackerSettings.isRaycastIntegrationEnabled` es `true`.
- Arranque posterior a `AppEnvironment.configure` (cuando existe `ActivityTracker`).
- No iniciar en UI tests ni en diagnóstico (`MomentumApp.isUITestRun`, `MOM_DIAG_PRESEED`).

## Ajustes / Settings
- Nuevo toggle: `Enable Raycast Integration`.
- Nueva sección en Settings (ej. “Integraciones” o “Tracking”).
- Mostrar estado: código de pairing, botón “Regenerar código”, botón “Revocar tokens”.

## Puertos y descubrimiento (sandbox constraint)
- La app está sandboxed.
- Para escuchar en un puerto local se requiere el entitlement `com.apple.security.network.server`.
- Se usa puerto fijo `51637`, compartido por app y extensión (hardcodeado).
- Si el bind falla (puerto ocupado), se muestra error en Settings.

## Autenticación y pairing
- El usuario abre Momentum > Settings > Raycast y obtiene un código de 4 dígitos.
- Código válido 10 min o hasta regeneración.
- La extensión envía el código y obtiene un token.
- El token se guarda en Raycast LocalStorage.
- La app guarda tokens válidos (Keychain o UserDefaults seguro).

## Contrato HTTP
- Base: `http://127.0.0.1:51637`
- Headers: `Authorization: Bearer <token>`
- JSON en request/response.

### Endpoints
- `GET /health`
- `POST /v1/pairing/confirm`
- `POST /v1/settings/open`
- `POST /v1/commands`

### Response envelope
```json
{ "ok": true, "data": { ... } }
```
```json
{ "ok": false, "error": "ErrorCode", "message": "..." }
```

### Errores estándar
- `401` token inválido.
- `409` conflicto de estado (ej. manual ya activo).
- `422` payload inválido.
- `503` servidor iniciando.

## Comandos MVP
- `tracking.set`
- Payload: `{ "enabled": true }`
- Implementación: `ActivityTracker.toggleTracking()` según estado actual.

- `manual.start`
- Payload: `{ "projectId": "..." }`
- Implementación: `ActivityTracker.startManualTracking(project:)`.

- `manual.stop`
- Payload: `{ "reason": "manual" }`
- Implementación: `ActivityTracker.stopManualTracking(reason: .manual)`.

- `projects.list`
- Response: lista con `id`, `name`, `colorHex`, `iconName`.

- `projects.create`
- Payload: `{ "name": "...", "iconName": "..." }`
- Implementación: nueva utilidad en Services para crear proyecto sin UI.

- `conflicts.list`
- Response: lista de conflictos agrupados (context, candidates).

- `conflicts.resolve`
- Payload: `{ "contextType": "app|domain|file", "contextValue": "...", "projectId": "..." }`
- Implementación: `ActivityTracker.resolveConflict(context:project:)`.

## IDs de proyecto
- Usar una representación estable del `PersistentIdentifier`.
- Recomendación: `persistentModelID.uriRepresentation().absoluteString`.
- Añadir helper para codificar/decodificar IDs.

## UI y navegación
- Campo `present: true|false` en `POST /v1/commands`.
- Si `present` es `true`, la app debe:
- Activar la app (`NSApplication.shared.activate`) sin romper la política de Dock.
- Postear `.momentumWindowVisibilityNeedsUpdate`.
- Enviar notificaciones para abrir ventanas/hojas.

Propuesta de notificaciones nuevas:
- `Notification.Name.raycastShowConflicts` → `ContentView` abre `showConflictSheet`.
- `Notification.Name.raycastShowMainWindow` → reusar lógica de status item.

Decisión vigente de UX en extensión:
- Abrir ajustes mediante comando o Action Panel (Cmd+K), no mediante link URL visible en la vista.
- Motivo: evitar prompts de “triggered from outside of Raycast” y resultados inconsistentes de foco.

## Reutilización de lógica de conflicto
- Extraer `PendingConflict` y `grouped` a un helper en `Models/` o `Services/`.
- Reutilizar para `conflicts.list` sin depender de Views.

## Rendimiento
- Server idle sin polling.
- Acciones encola en `MainActor` solo para operaciones necesarias.

## Observabilidad
- `OSLog` category `Raycast`.
- Loggear pairing, comandos y errores de validación.

## Tests (mínimos)
- Tests unitarios de `RaycastIntegrationManager` (routing/validación de comandos) con `ModelContainer` in‑memory.
- Tests de pairing (expiración 10 min).
- Tests de serialización de IDs.

## Fases sugeridas
1. Añadir toggle en Settings + modelo `TrackerSettings`.
2. Crear `RaycastServer` + `health` + pairing.
3. Implementar `projects.list` + `settings/open` y validar flujo end-to-end app/extensión.
4. Extraer `PendingConflict` a helper reusable.
5. Ampliar comandos (`manual.start`, `manual.stop`, `projects.create`, `conflicts.list`, `conflicts.resolve`).
6. Endurecer tests de integración y abrir fase de publicación.

## Decisiones cerradas
- Código de pairing: 4 dígitos.
- Expiración de código: 10 min.
- Token: sin expiración, revocable manualmente.
- `present` determina apertura de UI.
- Puerto fijo: `51637`.
