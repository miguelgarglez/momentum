# Tracking Views Guidelines

## Scope
- Views related to tracking status, conflicts, and assignment flows.
- Keep resolution UI deterministic and data-driven.
 - Examples in this folder: `PendingConflictResolutionView`.

## Conventions
- Avoid side effects in view builders; call tracker actions from explicit button handlers.
- Keep identifiers stable for UI tests (accessibility identifiers).
- Keep conflict grouping logic in a model/helper (e.g. `PendingConflict.grouped`).

## UX
- Provide clear empty states and concise guidance text.
- Preserve existing layout and tone; avoid large visual changes without intent.
