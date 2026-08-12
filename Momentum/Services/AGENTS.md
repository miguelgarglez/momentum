# Services Guidelines

## Scope
- Session state machine, persistence helpers, status item, Dock, hotkeys, idle monitor.
- Prefer dependency injection over singletons.
- UI observes services; services do not import SwiftUI views.

## v0 rules
- `FocusSessionController` is the single source of truth for in-progress elapsed time.
- Do not revive auto-tracking, AppleScript, or Raycast HTTP.
- Dock visibility stays in `DockVisibilityCoordinator`; views post `momentumWindowVisibilityNeedsUpdate`.
