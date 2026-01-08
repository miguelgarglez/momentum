# Models Guidelines

## Scope
- Domain models, SwiftData types, and value objects.
- Keep models focused on data shape, invariants, and domain logic.
- Examples in this folder: `Project`, `TrackingSession`, `PendingTrackingSession`, `DailySummary`, `AssignmentRule`, `InstalledApp`.

## Conventions
- Prefer immutability for value types; keep mutation explicit on reference types.
- Validate and normalize input in model initializers or dedicated methods.
- Avoid direct UI concerns (colors, layout constants) unless they are true domain concepts.
- Keep computed properties side‑effect free.

## SwiftData
- Use `@Model` types for persisted entities and keep relationships consistent.
- Centralize migration-sensitive logic and avoid ad-hoc schema changes.
