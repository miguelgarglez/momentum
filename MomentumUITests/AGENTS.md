# Momentum UI Tests Guidelines

## Scope
- UI tests and helpers under `MomentumUITests/`.
- Keep UI tests stable and focused on user-visible flows.

## Conventions
- Prefer accessibility identifiers over labels for element lookup.
- Reuse shared helpers in `MomentumUITests.swift` for launching and window handling.
- Use deterministic seeds (`--seed-conflicts`, `--seed-rules`) for data-dependent tests.
- Skip onboarding unless the test explicitly validates onboarding behavior.

## Launch Stability
- Disable macOS state restoration during UI tests:
  - `-ApplePersistenceIgnoreState YES`
  - `-ApplePersistenceIgnoreStateQuietly YES`
- Ensure the main window is visible before asserting UI state.
