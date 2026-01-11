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

## Observability
- Use `@Published`/`Observable` where state drives UI.
- Keep derived state in computed properties or dedicated helpers.
