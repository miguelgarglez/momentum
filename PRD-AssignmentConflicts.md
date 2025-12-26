# MOMENTUM — PRD Conflictos de Asignacion de Contexto

## 1. Problema
Cuando una misma app o dominio esta asignado a varios proyectos, Momentum no
puede decidir automaticamente a que proyecto corresponde el tiempo. Esto
provoca registros incorrectos y friccion para el usuario.

## 2. Objetivo
Permitir que el usuario resuelva conflictos de asignacion de forma simple y
no intrusiva, guardando la decision para usos futuros, y acumulando el tiempo
pendiente hasta que se resuelva.

## 3. Alcance MVP
- Detectar conflictos cuando un bundle ID o dominio coincide en mas de un
  proyecto.
- Guardar el tiempo en pendiente en lugar de asignarlo automaticamente.
- Mostrar un aviso discreto (badge en barra de menu y banner al abrir la app).
- Permitir seleccionar un proyecto y guardar la regla de asignacion.
- Aplicar el tiempo pendiente al proyecto elegido.
- Eliminar prioridad de proyectos como mecanismo de desempate.

## 4. No Objetivos (MVP)
- Expiracion automatica de reglas por inactividad.
- Notificaciones del sistema o popups intrusivos.
- Heuristicas basadas en historial o contexto de apps cercanas.
- Edicion avanzada de reglas (horarios, condiciones).

## 5. Historias de Usuario
- Como usuario, si una app esta en varios proyectos, quiero decidir a cual
  pertenece mi tiempo sin perderlo.
- Como usuario, quiero que Momentum recuerde mi eleccion para no repetirla.
- Como usuario, quiero enterarme del conflicto sin interrupciones.

## 6. Requisitos Funcionales
### FR-C1. Deteccion de conflicto
- Si un bundle ID o dominio coincide en varios proyectos, se marca como
  conflicto.
- Si existe una regla guardada para ese contexto, se usa directamente.

### FR-C2. Tiempo pendiente
- Cuando hay conflicto y no hay regla, el tiempo se acumula en pendiente para
  ese contexto.
- El tiempo pendiente se conserva hasta que el usuario elija un proyecto.

### FR-C3. Resolucion manual
- El usuario puede elegir el proyecto para un contexto en conflicto.
- Al confirmar, se crea una regla para ese contexto.
- El tiempo pendiente se reasigna al proyecto elegido.

### FR-C4. Aviso no intrusivo
- La barra de menu muestra un badge si hay conflictos pendientes.
- Al abrir Momentum, se muestra un banner con CTA para resolver.

## 7. Requisitos No Funcionales
- El registro pendiente no debe perderse ante cierres inesperados.
- La resolucion debe ser rapida y no bloquear el tracking general.
- No se deben mostrar popups que interrumpan al usuario.

## 8. Modelo de Datos (MVP)
### AssignmentRule
- id (UUID)
- contextType ("app" | "domain")
- contextValue (String normalizado)
- projectId (UUID)
- createdAt (Date)
- lastUsedAt (Date)

### PendingContextTime
- id (UUID)
- contextType ("app" | "domain")
- contextValue (String normalizado)
- appName (String?)
- bundleIdentifier (String?)
- domain (String?)
- totalSeconds (Int)
- lastSeenAt (Date)
- createdAt (Date)

## 9. Flujos
### 9.1 Tracking con conflicto
1. Se detecta app/dominio activo.
2. Si hay regla, se asigna a proyecto y se guarda sesion normal.
3. Si hay conflicto sin regla, se guarda tiempo en pendiente y no se asigna.
4. Se actualiza el badge de conflictos.

### 9.2 Resolucion de conflicto
1. El usuario abre Momentum y ve el banner de conflictos.
2. Entra a la pantalla de resolucion y selecciona el proyecto.
3. Se guarda la regla para el contexto.
4. Se reasigna el tiempo pendiente al proyecto elegido.

## 10. UX / UI (MVP)
- Badge en icono de barra de menu con contador de conflictos.
- Banner en la vista principal: "Tienes X contextos por resolver".
- Lista de conflictos con:
  - app/domain
  - tiempo pendiente
  - selector de proyecto y CTA "Asignar".

## 11. Metricas de Exito
- % de conflictos resueltos en menos de 24h.
- Reduccion de sesiones asignadas al proyecto incorrecto.
- Tasa de repeticiones del mismo conflicto (debe bajar con reglas guardadas).

## 12. Riesgos
- Conflictos muy frecuentes pueden saturar la lista.
- Si el usuario nunca resuelve, se acumula tiempo pendiente.
- Reglas mal elegidas pueden necesitar edicion futura.

## 13. Estado del MVP (Checklist)
- [x] Deteccion de conflicto por app y dominio.
- [x] Guardado de sesiones pendientes.
- [x] UI no intrusiva: banner + sheet de resolucion manual.
- [x] Regla guardada por contexto y backfill de pendientes.
- [x] Badge en barra de menu cuando hay conflictos.
- [x] Tests unitarios del flujo de conflicto/pending/regla.
- [ ] Tests de UI (banner, sheet, acciones).
- [ ] Ajuste de logs/ruido en tests (crash recovery + performance monitor).

## 14. Testing (pendiente)
- UI tests basicos para:
  - Aparicion de banner cuando hay pendientes.
  - Apertura de sheet y resolucion.
- Validar comportamiento con dominio y app en fixtures reales.
- Revisar el test existente `weeklyAggregationUsesDailySummaries` (falla actual).

## 15. Siguientes pasos (post-MVP)
- Expiracion automatica de reglas por inactividad (usa `lastUsedAt`).
- Pantalla de gestion/edicion de reglas (ver/editar/eliminar).
- Notificaciones opcionales y configurables.
- Ordenacion mejorada en la lista (tiempo pendiente, ultimo visto).
- Badge numerico en barra de menu.

## 16. Preguntas Abiertas (post-MVP)
- Expiracion automatica de reglas por inactividad.
- Posibilidad de reasignar reglas manualmente.
- Notificaciones opcionales o nudge configurable.
