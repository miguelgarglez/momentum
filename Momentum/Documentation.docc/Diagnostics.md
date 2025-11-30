# Diagnósticos y NFR

La sección 7 del PRD exige métricas para CPU/I/O (<3 %) y resiliencia ante caídas. Estas son las piezas que lo automatizan:

## `PerformanceBudgetMonitor`

- Mide CPU y uso de disco del proceso usando APIs de Mach (`task_info`) y `proc_pid_rusage`.
- Expone `MetricSample` y `Violation` que registran la fracción de CPU consumida y el throughput de I/O por operación.
- Se integra con `ActivityTracker` en puntos críticos (`persistSession` y recuperación post-crash) mediante `measure(_, work:)`, garantizando que cada escritura queda auditada.
- Incluye un `Timer` de polling (30 s) que graba muestras periódicas para garantizar que el consumo sostenido sigue bajo el umbral (<3 % CPU, <32 KB/s de I/O).

## `CrashRecoveryManager`

- Serializa el contexto activo (`SessionSnapshot`) en `UserDefaults` cada vez que cambia `ActivityTracker.currentContext`.
- Marca el estado de apagado limpio vía las notificaciones `NSApplication.willTerminateNotification`/`UIApplication.willTerminateNotification`.
- Si la app se cerró de forma inesperada, en el siguiente arranque `ActivityTracker` consume el snapshot, vuelve a asociar el proyecto correcto y persiste la sesión pendiente para que no se pierdan segundos registrados.

## Uso en la UI

Ambos servicios están aislados en `Services/` y pueden exponerse fácilmente a paneles de depuración o métricas externas. Basta con observar (`@Published`) las muestras/violaciones del monitor o consultar el snapshot pendiente durante la secuencia de arranque.

> **Pendiente**: La visualización de estas métricas (por ejemplo, un panel de diagnóstico en la app o un comando CLI) se ejecutará en una iteración futura. Por ahora los datos quedan disponibles para desarrolladores vía `PerformanceBudgetMonitor` y los logs de `OSLog`.

## Almacenes aislados para pruebas

- Momentum acepta una ruta personalizada para la base de datos mediante `--store-path <directorio>` o la variable `MOMENTUM_STORE_PATH`.
- Los UITests fijan este parámetro a un directorio temporal y, si incluyen `--uitests-reset`, Momentum elimina esa carpeta antes de inicializar SwiftData.
- Ejecutar la app sin flags utiliza el store tradicional (`~/Library/Application Support/MomentumStore`), por lo que tus datos reales no se ven afectados por las suites automatizadas.

## Flujo detallado de diagnóstico y recuperación

### Ciclo de medición
1. `PerformanceBudgetMonitor` toma un snapshot inicial de recursos (CPU/I/O).
2. Una operación crítica —como `persistSession`— se ejecuta dentro de `measure(_:work:)`.
3. Se toma un snapshot final y se calcula:
   - `cpuLoad = cpuDelta / duration`
   - `ioBytesPerSecond = ioDelta / duration`
4. El monitor registra un `MetricSample` y evalúa si excede el presupuesto definido.
5. Si hay exceso, genera una `Violation` observable por herramientas de depuración.

### Polling pasivo
Además de medir operaciones concretas, el monitor:
- Ejecuta un `Timer` cada 30s.
- Compara el snapshot actual con el previo.
- Registra muestras de fondo para detectar consumo sostenido.

Esto permite capturar picos y también usos prolongados que podrían afectar a la UX.

## Flujo de crash recovery

1. **Durante el uso normal:**  
   Cada vez que `ActivityTracker.currentContext` cambia, `CrashRecoveryManager` escribe una versión serializada del estado en `UserDefaults`.
2. **En apagado limpio:**  
   Al recibir `willTerminateNotification`, el estado se marca como “clean shutdown”.
3. **En arranque posterior:**  
   - Si el apagado anterior fue limpio → no hay recuperación que hacer.  
   - Si fue inesperado → el manager expone el `SessionSnapshot` pendiente.
4. **Reproducción:**  
   `ActivityTracker` toma el snapshot, reconstruye la sesión, la reasigna a su proyecto y ejecuta un `persistSession` para que no se pierda ningún intervalo temporal.

## Integración con `ActivityTracker`

`ActivityTracker` actúa como orquestador:
- Llama a `measure(_:work:)` alrededor de escrituras en disco.
- Invoca a `CrashRecoveryManager` al arrancar para consumir sesiones pendientes.
- Usa `ProjectAssignmentResolver` para asignar correctamente la sesión recuperada.
- Limpia y normaliza la línea temporal mediante `SessionOverlapResolver`.

## Consideraciones de rendimiento

- Todo el módulo está diseñado para ser **ligero**: snapshots usan APIs nativas eficientes (`task_info`, `proc_pid_rusage`).
- El polling es poco frecuente (30s) y seguro incluso en hardware modesto.
- Las estructuras de datos (`MetricSample`, `Violation`) son pequeñas y limitadas a los últimos 60 samples.

## Testing y validación

Ambos servicios cuentan con:
- Implementaciones mock (`NoopPerformanceBudgetMonitor`, fuentes de métricas simuladas).
- Tests unitarios que verifican:
  - Deltas de CPU/I/O.
  - Detección de violaciones.
  - Persistencia y restauración tras crash.
- Tests de integración que garantizan que `ActivityTracker` reproduce correctamente sesiones incompletas.

Estas herramientas permiten demostrar que Momentum cumple los NFR del PRD sin degradar la experiencia del usuario.
