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

## Observability
- Use `@Published`/`Observable` where state drives UI.
- Keep derived state in computed properties or dedicated helpers.
