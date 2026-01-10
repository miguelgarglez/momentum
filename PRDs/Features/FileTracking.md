# PRD — File Tracking

## Objetivo
- Registrar tiempo por archivo concreto (PDF, Word, PPT, etc.) como señal equivalente a apps/dominios.
- Permitir asignar proyectos por archivo exacto.
- En tracking manual, auto‑aprender archivos usados igual que apps/dominios.

## Alcance
- Detección de archivo activo en un conjunto reducido de apps de documentos compatibles.
- Persistencia del “contexto de archivo” en sesiones y en conflictos.
- Resolución de proyecto por archivo con prioridad sobre dominio/app.
- Controles básicos en Ajustes (activar/desactivar tracking de archivos y exclusiones).

## No alcance
- Monitorización de todo el sistema (FSEvents global).
- Clasificación semántica automática de temas.
- Soporte universal para todas las apps desde el día 1.

## Apps compatibles
- Preview (PDF/imagenes)
- Microsoft Word
- Microsoft PowerPoint
- Apple Pages
- Apple Keynote
- Apple Numbers

> Nota: se prioriza AppleScript (Automation) y se evita pedir permisos de Accesibilidad.

## Futuro (potencial)
- Ampliar compatibilidad a más apps si exponen documento activo.
- Valorar permisos adicionales (p. ej. Accesibilidad) solo si es imprescindible y con UX/privacidad claras.

## Flujo principal
- Usuario activa “Registrar archivos”.
- Al cambiar app o en polling, se intenta resolver el archivo activo.
- Si hay archivo:
  - Se usa como contexto principal para asignación.
  - Se guarda en la sesión (igual que dominio/app).
- Si cambia el archivo dentro de la misma app:
  - Se cierra sesión actual y se inicia otra con el nuevo archivo.

## Reglas clave
- Prioridad de asignación: archivo > dominio > app.
- Manual tracking:
  - sesiones persisten directo al proyecto manual.
  - el archivo detectado se añade al proyecto (auto‑aprendizaje).
- Respeta exclusiones globales de apps (si la app está excluida no se rastrea archivo).
- Respeta exclusiones globales de archivos (rutas exactas o terminaciones).
- Archivos sólo se registran si el toggle “Registrar archivos” está ON.

## UX
- Ajustes: toggle “Registrar archivos”.
- Ajustes: lista de exclusiones de archivos con rutas exactas y terminaciones (ej. `.key`, `*.pdf`), más selector de archivos.
- Proyecto: chips/lista con “Archivos asignados” (similar a dominios/apps).
- Conflictos: si un archivo coincide con múltiples proyectos, se encola como conflicto.

## Datos
- Project: nueva lista `assignedFiles` (archivo exacto) almacenada en raw JSON.
- TrackingSession: nuevo campo `filePath` (ruta completa).
- PendingTrackingSession: añadir `filePath` y resolver conflicto por archivo.
- AssignmentRule: nuevo `contextType = file`.
- SessionSnapshot: incluir archivo activo para recuperación post‑crash.

## Privacidad
- Por defecto se guarda la ruta completa del archivo (local). Se puede considerar anonimizar con hash en el futuro.
- No se monitoriza el contenido del archivo.
- Permisos: se utiliza Automation (AppleScript) en fase 1, sin requerir Accesibilidad.

## Criterios de aceptación
- Con tracking de archivos activado, se crean sesiones con archivo activo en apps soportadas.
- Si el archivo cambia dentro de la misma app, se registra una nueva sesión.
- Se puede asignar un archivo concreto a un proyecto y se respeta esa prioridad.
- En tracking manual, los archivos usados se añaden al proyecto.
- Conflictos por archivo aparecen en el flujo existente.
