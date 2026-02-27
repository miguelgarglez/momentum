# Raycast Extension Go/No-Go Checklist

Use this checklist before running `npm run publish`.

## Scope Guardrails

- [ ] Notarization/distribution of Momentum app is tracked separately and out of this checklist.
- [ ] This checklist only covers Raycast extension submission readiness.

## Product Readiness

- [ ] Extension behavior is clear when Momentum is not installed.
- [ ] Extension behavior is clear when Momentum is installed but integration is unavailable.
- [ ] Pairing flow is working end-to-end.
- [ ] Token invalidation flow (401) re-prompts pairing correctly.
- [ ] Unsupported command flows show upgrade guidance.

## Metadata and Docs

- [ ] `package.json` metadata reflects current behavior and capabilities.
- [ ] Supported `platforms` is accurate.
- [ ] `README.md` includes prerequisites, setup, commands, troubleshooting, and compatibility.
- [ ] `CHANGELOG.md` is updated.
- [ ] `STORE_METADATA.md` is reviewed and current.

## Assets

- [ ] Extension icon is present and valid.
- [ ] Command-level icon usage is consistent.

## Verification

From `RaycastExtension/momentum`:

- [ ] `npm ci`
- [ ] `npm run lint`
- [ ] `npm run typecheck`
- [ ] `npm run build`
- [ ] `npm run test`

## CI

- [ ] `.github/workflows/raycast-extension-ci.yml` passes on PR branch.

## Final Manual Smoke Checks

- [ ] Missing-app simulation: `npm run simulate:no-app:setup && npm run simulate:no-app:verify`, then restore with `npm run simulate:no-app:restore`.
- [ ] If quarantine-based simulation is blocked in your environment, run destructive fallback: `npm run simulate:no-app:purge`.
- [ ] Open Momentum command.
- [ ] Open Momentum Settings command.
- [ ] Pair extension from scratch.
- [ ] List Projects and open one.
- [ ] Start Manual Tracking (existing project and create-new mode).
- [ ] Stop Manual Tracking.
- [ ] Resolve Conflicts.

## Go/No-Go

- [ ] GO: all checks above are green.
- [ ] NO-GO: any blocker is documented and fixed before publish.
