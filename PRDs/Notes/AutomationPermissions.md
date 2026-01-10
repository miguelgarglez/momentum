# Automation Permissions (Resumen de la situación)

## Contexto
- **AutomationPermissionPromptView** es un diálogo propio de la app.
- Ese diálogo **NO concede permisos**. Solo informa y, como mucho, abre Ajustes.
- Los permisos reales de Automation (Apple Events) los gestiona macOS.

## Lo que realmente habilita el permiso
1) **Info.plist**
   - `NSAppleEventsUsageDescription` (mensaje mostrado por macOS).

2) **Entitlements**
   - `com.apple.security.automation.apple-events = true`
   - `com.apple.security.temporary-exception.apple-events` con **bundle IDs permitidos**.

## Resultado actual
- El prompt propio no cambia permisos.
- El único prompt que “concede” es el de macOS cuando la app intenta automatizar otra app.
- Si falta el bundle ID en entitlements, **macOS no mostrará el prompt**.

## Soluciones propuestas
Opción A: Hacer el prompt realmente útil
- Añadir botón **“Solicitar permisos ahora”** que llama a `requestAutomationPermissions(...)`.
- Mantener botón de “Abrir Ajustes” como fallback.

Opción B: Eliminar el prompt
- Dejar solo un botón en Ajustes para solicitar permisos de Automation.

## Nota importante
- Los permisos de Automation se pueden “resetear” con:
  - `tccutil reset AppleEvents <bundle_id>`

