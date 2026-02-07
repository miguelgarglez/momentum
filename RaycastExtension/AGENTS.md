# Raycast Extension Guidelines

## Scope
- `RaycastExtension/momentum/` (TypeScript extension code + `package.json` command metadata).

## Commands
- Dev: `cd RaycastExtension/momentum && npm run dev`
- Build: `cd RaycastExtension/momentum && npm run build`
- Lint: `cd RaycastExtension/momentum && npm run lint`
- Test: `cd RaycastExtension/momentum && npm run test`

## Language Policy
- Keep Raycast extension UI/runtime copy in English.
- Centralize reusable copy in `RaycastExtension/momentum/src/copy.ts` instead of scattering literals.
- When changing user-facing copy, update related tests under `src/__tests__/`.
- Validate with `npm run lint`, `npm test`, and repo-level `make check-localization`.

## Integration Rules
- Use the local API (`http://127.0.0.1:51637`) as the primary integration channel.
- Open Momentum settings via `openMomentumSettings()` (`POST /v1/settings/open`) so behavior is consistent with app-side routing.
- For action handlers that hand off focus to Momentum, call `closeMainWindow()` before opening settings.
- Keep the dedicated settings command (`open-settings`) in `mode: "no-view"` to avoid leaving a stale Raycast view.
- Avoid using visible URL links to trigger Raycast commands (`raycast://extensions/...`) for this flow; Raycast may show external-trigger confirmation dialogs.

## Pairing View
- Keep pairing input constrained to 4 digits.
- Keep keyboard actions discoverable in the Action Panel (e.g. paste code, open settings via Cmd+K).
