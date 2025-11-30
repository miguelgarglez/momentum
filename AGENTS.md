# AGENTS

## Alcance
Este archivo aplica a todo el repositorio. Sigue estas notas al realizar cualquier tarea en la base de código.

## Comandos útiles para build y pruebas (iOS/macOS)
- Lista de esquemas y destinos disponibles:
  ```bash
  xcodebuild -list -project Momentum.xcodeproj
  ```
- Compilar para pruebas (prepara el workspace sin ejecutar tests):
  ```bash
  xcodebuild \
    -project Momentum.xcodeproj \
    -scheme Momentum \
    -destination 'platform=iOS Simulator,name=iPhone 15' \
    build-for-testing
  ```
- Ejecutar pruebas unitarias y de UI:
  ```bash
  xcodebuild \
    -project Momentum.xcodeproj \
    -scheme Momentum \
    -destination 'platform=iOS Simulator,name=iPhone 15' \
    test
  ```
- Ejecutar sólo un tipo de pruebas:
  - Unitarias: `-only-testing:MomentumTests`
  - UI: `-only-testing:MomentumUITests`
- Limpieza de artefactos derivados si hay corrupciones:
  ```bash
  xcodebuild clean -project Momentum.xcodeproj -scheme Momentum
  ```
- Destinos alternativos:
  - macOS: `-destination 'platform=macOS,arch=x86_64'`
  - Cambiar simulador iOS: ajusta `name=` y opcionalmente `OS=`.

## Notas de uso en VS Code/Codex
- Puedes crear tareas en `.vscode/tasks.json` que invoquen los comandos anteriores.
- Si instalas `xcpretty`, puedes canalizar la salida de `xcodebuild` para mayor legibilidad.

## Campos de texto (macOS)
- Los `TextField` de SwiftUI pueden heredar dirección `RTL` del sistema en macOS.
- Usa siempre `LTRTextField` (`Momentum/Views/Components/LTRTextField.swift`) para cualquier campo editable en la app (incluidas vistas de ajustes) excepto cuando se demuestre que el control nativo funciona correctamente.
- Reaplica el estilo de borde usando el modificador `macRoundedTextFieldStyle()` (`Momentum/Views/Components/MacTextFieldStyle.swift`) para mantener el look and feel anterior.
- El wrapper expone parámetros para placeholder, fuente y multitexto; ajústalos para que coincida el diseño previo al migrar un campo.
