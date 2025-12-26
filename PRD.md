# MOMENTUM — PRD TÉCNICO (Funcional + No Funcional)

## 📌 1. Descripción General
Momentum es una app nativa de macOS que registra **automáticamente** el tiempo dedicado a proyectos personales mediante la detección de:
- Aplicación activa (foreground)
- Dominio web activo
- Cambios de contexto de actividad

Su objetivo es convertir ese tiempo en **progreso visible**, manteniendo los datos **100% locales**.

---

# ⚙️ 2. Requisitos Funcionales (FR)

## FR-1. Gestión de Proyectos
- **FR-1.1** Crear un proyecto con:
  - nombre (obligatorio)
  - color o icono (opcional)
- **FR-1.2** Editar proyecto existente.
- **FR-1.3** Eliminar proyecto junto con sus registros.
- **FR-1.4** Asignar apps a un proyecto.
- **FR-1.5** Asignar dominios web a un proyecto.
- **FR-1.6** Un app/dominio puede pertenecer a varios proyectos y Momentum debe gestionar conflictos mediante reglas de asignacion guardadas.

## FR-2. Tracking Automático
- **FR-2.1** Detectar app activa en foreground cada X segundos (configurable, default 5 s).
- **FR-2.2** Identificar dominio web activo:
  - Safari: mediante AppleScript/gestor de pestañas.
  - Chrome: AppleScript.
  - Otros navegadores opcionados más adelante.
  > **Nota MVP:** La versión actual sólo lee dominios en Safari y Chrome usando AppleScript.
- **FR-2.3** Asociar cada intervalo detectado al proyecto correspondiente.
- **FR-2.3.1** Si existe conflicto sin regla, acumular tiempo pendiente y solicitar resolucion en UI.
- **FR-2.4** Pausa automática del tracking si:
  - No hay interacción durante N minutos (idle).
  - Se bloquea pantalla.
- **FR-2.5** Reanudación automática al volver de idle.

## FR-3. Agregación de Tiempo
- **FR-3.1** Guardar registros en intervalos (timestamp inicio, timestamp fin, tipo de actividad).
- **FR-3.2** Agregación diaria, semanal, mensual y total por proyecto.
- **FR-3.3** Cálculo automático de racha (días consecutivos con actividad > X minutos).
- **FR-3.4** Prevención de duplicación (detectar solapamientos de intervalos).

## FR-4. Interfaz Principal
- **FR-4.1** Vista “Dashboard”:
  - listado de proyectos
  - horas totales
  - horas semanales
  - última actividad
- **FR-4.2** Vista de proyecto:
  - horas totales
  - horas recientes (últimos 7/30 días)
  - gráfico semanal simple
  - racha actual
  - historial reciente
- **FR-4.3** Barra de menú:
  - tiempo del día
  - actividad actual detectada
  - acceso rápido al proyecto activo

## FR-5. Configuración
- **FR-5.1** Elegir si registrar dominios o solo apps.
- **FR-5.2** Configurar tiempo de detección (5–15 s).
- **FR-5.3** Configurar umbral de inactividad.
- **FR-5.4** Posibilidad de excluir apps/dominios globalmente.

## FR-6. Privacidad y Datos
- **FR-6.1** Todos los datos se guardan localmente en almacenamiento seguro (NSUserDefaults/CoreData/SQLite).
- **FR-6.2** Opción “Borrar todos los datos”.
- **FR-6.3** Opción para borrar actividad por proyecto.

## FR-7. Persistencia
- **FR-7.1** Base de datos local (CoreData o SQLite).
- **FR-7.2** Migraciones automáticas en actualizaciones.
- **FR-7.3** Integridad de datos (validaciones en intervalos).

## FR-8. Integraciones y Automatización
- **FR-8.1** La lógica de negocio (crear/cerrar sesiones, asignar proyectos, calcular métricas) debe vivir en servicios desacoplados de la UI.
- **FR-8.2** Esos servicios deben poder ser invocados por clientes headless (ej. extensión de Raycast, CLI o servidor local) sin duplicar lógica.
- **FR-8.3** Documentar un canal de integración local (archivo JSON, CLI o socket) para exponer acciones rápidas y lectura de progreso.

> **Nota (nov/25)**: Las métricas de CPU/I/O ya se registran mediante `PerformanceBudgetMonitor`, pero la visualización para usuarios finales (panel en UI o CLI/export) se pospone para una siguiente iteración. El objetivo inmediato es usar los datos internamente durante el desarrollo y retomar la exposición de alerts cuando avancemos con la integración Raycast.

---

# ⚡ 3. Requisitos No Funcionales (NFR)

## NFR-1. Rendimiento
- **NFR-1.1** El monitoreo debe consumir < 3% CPU promedio.
- **NFR-1.2** Escrituras de datos deben agruparse en batch para reducir I/O.
- **NFR-1.3** La app debe iniciar en < 2 s.

## NFR-2. Privacidad y Seguridad
- **NFR-2.1** No enviar datos a ningún servidor sin opt-in explícito.
- **NFR-2.2** No registrar URLs completas; solo dominio + título (opcional).
- **NFR-2.3** Encriptación opcional de la base de datos.
- **NFR-2.4** Respetar permisos de automatización y accesibilidad de macOS.

## NFR-3. Estabilidad
- **NFR-3.1** La app debe manejar cierres inesperados sin perder registros.
- **NFR-3.2** Ante conflictos en intervalos, debe prevalecer el más reciente.
- **NFR-3.3** Degradación suave: si no se puede obtener dominio web, seguir registrando app.

## NFR-4. UX / Diseño
- **NFR-4.1** UI nativa SwiftUI, minimalista, estilo macOS moderno.
- **NFR-4.2** Animaciones ligeras, sin sobrecargar CPU.
- **NFR-4.3** Accesible desde la barra de menús.

## NFR-5. Compatibilidad Técnica
- **NFR-5.1** macOS 13+ (Ventura en adelante).
- **NFR-5.2** Apple Silicon optimizado.
- **NFR-5.3** Permisos requeridos:
  - Accesibilidad (para detectar app activa)
  - Automatización (para Chrome/Safari)
  - Screen Recording (opcional para captura precisa en algunos navegadores)
  > **Nota MVP:** La app obtiene la app activa a través de `NSWorkspace` y no necesita el permiso de Accesibilidad. Sólo se solicita Automatización para Safari/Chrome.
  > **Seguimiento futuro:** Accesibilidad y Screen Recording se evaluarán más adelante si añadimos detección profunda dentro de apps o navegadores que no expongan AppleScript. Por ahora solo documentamos el requisito y mantenemos la UX libre de estos permisos adicionales.

## NFR-6. Mantenibilidad
- **NFR-6.1** Arquitectura: MVVM + servicios modularizados.
- **NFR-6.2** Capas separadas:
  - Tracking
  - Persistencia
  - UI
  - Integraciones
- **NFR-6.3** Código documentado con DocC.

---

# 🧱 4. Arquitectura Técnica (Resumen)

## 4.1. Capas
- **App Layer (SwiftUI)**  
  UI + lógica de presentación (MVVM)

- **Domain Layer**
  - ProjectManager  
  - TrackingManager  
  - ActivityAggregator  
  - PrivacyService  

- **Data Layer**
  - CoreData/SQLite  
  - LocalStorageService  
  - MigrationService  

- **System Integration**
  - App foreground detector (NSWorkspace)  
  - Browser domain extractor (AppleScript → handler interno)  
  - Idle detector (IOKit)  

---

# 🗂️ 5. Modelo de Datos

### Entidad Project
- id (UUID)
- name (String)
- color/icon (String)
- apps [String]
- domains [String]
- createdAt (Date)

### Entidad AssignmentRule (MVP)
- id (UUID)
- contextType ("app" | "domain")
- contextValue (String)
- projectId (UUID)
- createdAt (Date)
- lastUsedAt (Date)

### Entidad PendingContextTime (MVP)
- id (UUID)
- contextType ("app" | "domain")
- contextValue (String)
- totalSeconds (Int)
- lastSeenAt (Date)
- createdAt (Date)

### Entidad ActivityRecord
- id (UUID)
- projectId (UUID)
- startTime (Date)
- endTime (Date)
- sourceType (“app” | “domain”)
- sourceName (String)

### Entidad DailySummary (cache)
- date (Date)
- projectId (UUID)
- totalSeconds (Int)

---

# 🔄 6. Flujos Principales

## 6.1. Tracking Automático
1. Timer cada 5 segundos → detecta app activa  
2. Si navegador activo → obtener dominio  
3. Resolver proyecto asociado o detectar conflicto  
4. Registrar intervalo o acumular tiempo pendiente  
5. Si idle → cerrar intervalo y pausar tracking  
6. Al volver → crear nuevo intervalo

## 6.2. Vista de Proyecto
1. Cargar proyecto  
2. Calcular agregados (cache)  
3. Mostrar gráfico semanal  
4. Mostrar racha (últimos días con > X min)

---

# 🧪 7. Testing

## Unit Tests
- Mapping app/dominio → proyecto  
- Cálculo de rachas  
- Agregación semanal  
- Detección de solapamientos

## Integration Tests
- Tracking activo/idle  
- Cambios rápidos de apps  
- Fallos en AppleScript (dominio no disponible)

## UI Tests
- Flujo de creación de proyectos  
- Edición de apps/dominos  
- Lectura de dashboards

---

# 📅 8. Riesgos Técnicos

- AppleScript frágil en navegadores (Chrome/Safari).  
- Permisos de macOS pueden complicar onboarding.  
- Tracking demasiado frecuente podría consumir CPU.  
- Usuarios con múltiples escritorios/Spaces → detección inconsistente.  

---

# 🚀 9. Criterios de Aceptación Final del MVP

- App detecta apps y dominios y guarda tiempo sin intervención.  
- Un usuario puede crear proyectos y asignar fuentes.  
- Dashboard y vistas de proyecto funcionan con datos reales.  
- La app no sube nada a la nube.  
- Consumo CPU estable (<3–5%).  
- No crashea con cambios rápidos de aplicaciones.  

---
