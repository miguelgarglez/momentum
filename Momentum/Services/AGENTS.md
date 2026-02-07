# Services Guidelines

## Scope
- App services, coordinators, trackers, and data providers.
- Encapsulate side effects and external interactions.
- Examples in this folder: `ActivityTracker`, `AppCatalog`, `ProjectAssignmentResolver`, `SessionOverlapResolver`, `StatusItemCoordinator`, `TrackerSettings`.

## Conventions
- Prefer dependency injection over singletons for testability.
- Keep service APIs cohesive and task‑oriented.
- Avoid leaking UI‑specific details into service interfaces.
- Be explicit about threading and `@MainActor` usage when needed.
- Centralize Dock visibility changes in a coordinator; UI should request reevaluation instead of mutating `NSApp` directly.
- Global exclusions live in `TrackerSettings` (`excludedApps`, `excludedDomains`, `excludedFiles`) and should be enforced in `ActivityTracker` when context changes.
- Raycast-triggered settings opening must go through `SettingsWindowPresenter` and not duplicate ad-hoc `NSApp` window code across services/views.
- Keep a single deep-link entry path per app lifecycle callback to avoid duplicate handling of the same URL event.
- If a settings-open path can unintentionally surface the main window, suppress/clean it via `MainWindowSuppression`/`SettingsWindowPresenter` rather than introducing view-level workarounds.
- Keep machine/API-facing Raycast HTTP messages in English for extension compatibility.
- Localize app-facing status/error strings emitted by services when they are shown in native UI.

## Observability
- Use `@Published`/`Observable` where state drives UI.
- Keep derived state in computed properties or dedicated helpers.
