# Momentum UI Tests

## Launch flags used by the suite
- `--uitests`
- `--store-path <dir>`
- `--uitests-reset` (optional, clears the test store)
- `--seed-conflicts` / `--seed-rules` (optional, deterministic data)
- `--skip-onboarding` (skip welcome flow unless under test)
- `-ApplePersistenceIgnoreState YES`
- `-ApplePersistenceIgnoreStateQuietly YES`

## Local runs
Run the whole UI suite:
```bash
make test-ui
```

Run a single UI test:
```bash
xcodebuild -project Momentum.xcodeproj -scheme Momentum -destination 'platform=macOS' \
  test -only-testing:MomentumUITests/MomentumUITests/testCreateProjectFlow
```

## Notes
- The app can run without windows on macOS if the previous session was closed. The suite forces a new window when needed.
- Use accessibility identifiers (e.g., `action-panel-create-project`) instead of localized labels.
