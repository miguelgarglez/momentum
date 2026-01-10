# Plan — File Tracking (material de estudio)

## 1) Modelo de datos
- Añadir `assignedFilesRaw` a `Project` + helpers `assignedFiles`, `addAssignedFile`.
- Añadir `filePath` a `TrackingSession` y `PendingTrackingSession`.
- Extender `AssignmentContextType` con `.file` y reflejar en `AssignmentRule` labels.
- Extender `SessionSnapshot` con `filePath`.

## 2) Resolución de archivo activo
- Crear `FileDocumentResolver` (similar a `BrowserDomainResolver`).
- Implementar resolutores por app (AppleScript/Automation):
  - Preview: documento activo (path).
  - Microsoft Word / PowerPoint.
  - Pages / Keynote / Numbers.
- Añadir whitelist de bundle IDs soportados.
 - Dejar `AXDocument` (Accesibilidad) para fase 2 si alguna app no expone ruta por AppleScript.

## 3) Integración con ActivityTracker
- Añadir `filePath` a `AppSessionContext` + `StatusSummary`.
- Añadir timer/polling para resolución de archivo.
- Cambiar `updateProjectAssociation` y `ProjectAssignmentResolver` para priorizar archivo.
- En `persistManualSession`, añadir `project.addAssignedFile(...)`.
- Incluir `filePath` en `persistSession`, `persistPendingSession` y `resolveConflict`.

## 4) Ajustes y UI
- `TrackerSettings`: toggle `isFileTrackingEnabled` + persistencia en UserDefaults.
- `TrackerSettingsView`: UI para activar/desactivar tracking de archivos.
- Proyecto: mostrar chips/lista de “Archivos asignados”.

## 5) Migración y compatibilidad
- Verificar que añadir campos no rompe sesiones existentes.
- Asegurar que sesiones antiguas sin `filePath` siguen funcionando.

## 6) Tests
- Tests del resolver de asignación (archivo > dominio > app).
- Tests básicos de manual tracking agregando `assignedFiles`.
- Tests del snapshot de crash con `filePath`.

## 7) Documentación
- Actualizar `Documentation.docc` si aplica.
- Añadir nota de permisos (Automation en fase 1; Accesibilidad solo si se añade en fase 2).
