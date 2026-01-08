# PRD — Manual Tracking (proyecto)

## Objetivo
- Iniciar tracking manual para un proyecto (existente o nuevo) ignorando reglas de exclusión y conflicto.
- Registrar sesiones normales + aprender apps/dominios usados para auto-configurar el proyecto.

## Alcance
- Iniciar desde ventana principal y desde status item.
- Crear proyecto rápido (titulo opcional + icono opcional).
- Mientras manual activo: solo se trackea al proyecto manual, sin reglas ni conflictos.
- Al detener o idle: se cierra manual y vuelve tracking automático.

## No alcance
- Preferencias avanzadas (mezclar manual y auto en paralelo).
- UI compleja de edición de reglas durante sesión.

## Flujo principal
- Usuario elige "Iniciar tracking manual".
- Selecciona proyecto existente o crea nuevo rápido.
- Tracking manual activo:
  - sesiones se guardan directo al proyecto.
  - apps/dominios detectados se añaden al proyecto.
- Stop manual o idle:
  - sesión se cierra.
  - se reanuda tracking automático.
  - toast info: motivo de stop.

## Reglas clave
- Manual ignora exclusiones globales (apps/dominios) mientras activo.
- Dominios solo si setting "Registrar dominios web" está ON.
- Solo app/dominio activo (no historial).
- Idle o screen lock => detener manual (no pausa).

## UX
- Ventana principal: botón iniciar manual (acción nueva). Botón stop ya existente sirve para detener manual.
- Status item: opción iniciar manual + opción detener manual.
- Indicador: dot azul celeste en icono status item mientras manual activo (solo activo).
- Toast: "Tracking manual detenido (idle)" / "(manual)" / "(bloqueo)".

## Datos
- TrackingSession: sin cambios, sesiones normales.
- Project: añadir apps/dominios detectados durante manual.
- SessionSnapshot: debe restaurar estado manual si crash (si aplica).

## Estados (tracker)
- manualActive: Bool
- manualProjectID: PersistentIdentifier?
- manualStartDate: Date

## Iniciar manual
- Si proyecto existente:
  - set manualActive true
  - set manualProjectID
  - flush session actual
  - iniciar contexto con app activa
- Si nuevo proyecto:
  - name default: "New cool project (X)" si vacío/duplicado
  - icon default: random ProjectIcon
  - color default: ProjectPalette.defaultColor
  - insert + save + usar como manualProjectID

## Sesiones durante manual
- persist directo al proyecto manual (sin resolver reglas).
- al cerrar sesión: añadir app bundleID al proyecto si no existe.
- añadir dominio si existe y setting enabled.
- guardar proyecto (apps/domains) + sesiones en batch razonable.

## Conflictos
- No generar PendingTrackingSession durante manual.
- No mostrar UI conflictos por sesiones manuales.

## Criterios de aceptación
- Se puede iniciar manual desde app y status item.
- Se puede detener manual desde app y status item.
- Manual detiene tracking automático mientras activo.
- Idle/lock detiene manual y muestra toast.
- Indicador azul celeste en status item solo mientras manual activo.
- Apps/dominios usados se agregan al proyecto.
