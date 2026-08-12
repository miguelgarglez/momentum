# Models Guidelines

## Scope
- SwiftData models and lightweight domain types.
- No UI, no AppKit side effects.

## v0 models
- `Project` — name, color, timestamps
- `FocusSession` — open when `endAt == nil`; stores paused duration and interrupt flag

## Conventions
- Prefer immutability for value types; keep mutation explicit on reference types.
- Avoid UI concerns in models (use hex strings, not `Color`).
