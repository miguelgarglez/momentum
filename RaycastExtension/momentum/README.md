# Momentum for Raycast

Control the Momentum macOS companion app from Raycast.

This extension lets you:
- Open Momentum and open Momentum settings focused on Raycast integration.
- List projects and open a selected project in Momentum.
- Start and stop manual tracking.
- Open pending conflict resolution.

## Prerequisites

- macOS.
- Momentum app installed.
- Momentum app running.
- Raycast integration enabled in Momentum (`Settings > Raycast Extension`).

Without these prerequisites, commands will fail with actionable guidance.

## Pairing Setup

1. Open the `List Projects` command (or any command that requires auth).
2. In Momentum, go to `Settings > Raycast Extension` and generate a 4-digit pairing code.
3. In Raycast, paste or type the 4-digit code.
4. After successful pairing, the extension stores a token in Raycast local storage.

If pairing fails:
- Confirm Momentum is running.
- Confirm Raycast integration is enabled in Momentum.
- Generate a fresh code and retry.

## Commands

- `Open Momentum`: Brings the Momentum app to front.
- `Open Momentum Settings`: Opens Momentum settings focused on Raycast integration.
- `List Projects`: Lists projects from Momentum and allows opening one.
- `Resolve Conflicts`: Checks pending conflicts and opens resolution when needed.
- `Start Manual Tracking`: Starts manual tracking with an existing project or opens the create-new flow in Momentum.
- `Stop Manual Tracking`: Stops the current manual tracking session.

## Troubleshooting

### "Momentum Required"
Cause: Momentum is not installed or cannot be found.

Action:
- Install Momentum on macOS.
- Re-run the command.

### "Momentum Integration Unavailable"
Cause: Momentum is open but local integration is unreachable.

Action:
- Open Momentum.
- Verify `Settings > Raycast Extension` is enabled.
- Retry the command.

### "Invalid Token"
Cause: Pairing token expired or invalid.

Action:
- Pair again with a new 4-digit code from Momentum settings.

### "Command Not Supported"
Cause: Running a Momentum build that does not support the requested command.

Action:
- Update Momentum to a newer build and pair again.

## Compatibility

- Supported platform: macOS only.
- Communication model: local HTTP on loopback (`127.0.0.1`) with fallback between ports used by Momentum.
- Commands require a compatible Momentum build that exposes the required command capabilities.

## Local Validation

From `RaycastExtension/momentum`:

```bash
npm ci
npm run lint
npm run typecheck
npm run build
npm run test
```

## Simulate Missing App (reversible)

To test how the extension behaves when Momentum is unavailable on the Mac:

```bash
npm run simulate:no-app:setup
npm run simulate:no-app:verify
```

This moves discovered `Momentum.app` bundles (including DerivedData/archive copies) into a quarantine folder and stops running Momentum processes.
During quarantine, the app executable inside each bundle is disabled so `open -b ...` cannot launch from quarantine.

After testing in Raycast, restore everything:

```bash
npm run simulate:no-app:restore
```

Useful command at any time:

```bash
npm run simulate:no-app:status
```

Notes:
- `simulate:no-app:verify` exits non-zero if a physical `Momentum.app` is still present or a Momentum process is still running.
- `simulate:no-app:test` runs setup + verify in one command.
- On macOS, LaunchServices bundle lookups can still report `FOUND` temporarily even when no runnable `Momentum.app` exists. Trust `physical_apps: 0` + `result: PASS`.

Destructive option (no restore):

```bash
npm run simulate:no-app:purge
```

`simulate:no-app:purge` deletes discovered `Momentum.app` bundles permanently. Use only for hard clean-slate testing.

## Publish Workflow (when ready)

1. Ensure all checks above pass.
2. Ensure Store metadata and release notes are updated.
3. Run:

```bash
npm run publish
```

This repository intentionally blocks `npm publish` to npm and uses Raycast publish flow only.
