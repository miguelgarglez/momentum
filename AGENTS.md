# Repository Guidelines

## Project Structure & Module Organization
- `Momentum/` holds the Swift/SwiftUI app source. Core areas: `Models/`, `Services/`, `Utilities/`, and `Views/`.
- Core areas include their own `AGENTS.md` with focused guidelines (`Models/`, `Services/`, `Utilities/`, `Views/`).
- `Momentum/Views/` is organized by feature and shared UI:
  - `Views/Dashboard/` (dashboard header/metrics)
  - `Views/Projects/` (project detail, activity charts, forms, list views)
  - `Views/Tracking/` (pending conflict resolution views)
  - `Views/Components/` (reusable UI like `ActionPanelView`, `ToastView`, `FlowLayout`, `LTRTextField`)
  - `Views/Styles/` (shared view modifiers/styles like `DetailCardStyles`)
- Subfolders under `Momentum/Views/` include their own `AGENTS.md` with focused guidelines.
- `Momentum/Assets.xcassets` stores images and color assets.
- `Momentum/Documentation.docc` contains in-app documentation.
- `PRDs/` stores product requirement docs and plans (see `PRDs/README.md`).
- `RaycastExtension/momentum/` contains the Raycast extension (TypeScript).
- Tests live in `MomentumTests/` (unit) and `MomentumUITests/` (UI).
- `MomentumUITests/` includes its own `AGENTS.md` with UI test-specific guidance.
- `Momentum.xcodeproj` is the Xcode project entry point.

## Build, Test, and Development Commands
Prefer `Makefile` targets for local development:
- `make build`
- `make build-for-testing`
- `make test`
- `make test-unit`
- `make test-ui`
- `make test-only` (use `TEST=Target/Class/testName`)
- `make lint` (SwiftLint, errors only)
- `make format` (SwiftFormat, writes changes)
- `make format-lint` (SwiftFormat lint mode, no changes)
- `make check-localization` (validates string catalog + Raycast English copy policy)
- `make run-dev`
- `make run-dev-lang` (forces app language/locale for dev bundle)
- `make run-dev-system-lang` (clears language overrides and uses system language)
- `make run-release`
- `make run-release-lang` (forces app language/locale for release bundle)
- `make reset-dev-data`
- `make install-release`
- `make archive-release`
- `make clean`
- For the Raycast extension:
  - `cd RaycastExtension/momentum && npm run dev`
  - `cd RaycastExtension/momentum && npm run build`
  - `cd RaycastExtension/momentum && npm run lint`
  - `cd RaycastExtension/momentum && npm run simulate:no-app:setup` (quarantine local `Momentum.app` copies to simulate missing companion app)
  - `cd RaycastExtension/momentum && npm run simulate:no-app:verify` (returns non-zero when a runnable `Momentum.app` is still physically present)
  - `cd RaycastExtension/momentum && npm run simulate:no-app:restore` (restores quarantined apps to original paths)
  - `cd RaycastExtension/momentum && npm run simulate:no-app:status` (prints state + verification report)
  - `cd RaycastExtension/momentum && npm run simulate:no-app:purge` (destructive: permanently deletes discovered `Momentum.app` bundles)
  - `cd RaycastExtension/momentum && npm run simulate:no-app:test` (runs setup + verify in one command)
- For local builds in this environment, the agent needs full filesystem access (danger-full-access).
- If builds fail with SwiftData macro errors (`swift-plugin-server` malformed response), the issue is typically the local Xcode toolchain rather than project code.

### DMG packaging note
- The `archive-release`/`dmg` targets use `create-dmg`, which briefly opens a Finder window while applying the DMG layout (background/icon positions). This is expected for local builds.
Raw `xcodebuild` commands are still valid and occasionally useful:
- List schemes/destinations:
  ```bash
  xcodebuild -list -project Momentum.xcodeproj
  ```
- Build for testing (no tests run):
  ```bash
  xcodebuild -project Momentum.xcodeproj -scheme Momentum -destination 'platform=macOS' build-for-testing
  ```
- Run all tests:
  ```bash
  xcodebuild -project Momentum.xcodeproj -scheme Momentum -destination 'platform=macOS' test
  ```
- Run a subset:
  - `-only-testing:MomentumTests`
  - `-only-testing:MomentumUITests`

## GitHub Actions (CI + Release)
- CI workflow: `.github/workflows/ci.yml`
  - Triggers: `push` and `pull_request` on `main`, plus manual runs.
  - Uses `xcodebuild` on `macos-latest` with `-derivedDataPath $RUNNER_TEMP/DerivedData`.
  - Build number: `CURRENT_PROJECT_VERSION` set to UTC timestamp `YYYYMMDDHHmmss`.
  - Code signing disabled for CI: `CODE_SIGNING_ALLOWED=NO`, `CODE_SIGNING_REQUIRED=NO`, `CODE_SIGN_IDENTITY=""`.
  - Runs `MomentumTests` only; UI tests are manual.
- Release-please workflow: `.github/workflows/release-please.yml`
  - Uses `release-please-config.json` and `.release-please-manifest.json`.
  - Generates release PRs, tags, and GitHub Releases on `main`.
  - Uses `CHANGELOG.md`, `version.txt`, and `Momentum.xcodeproj/project.pbxproj` (via `x-release-please-version`).
  - No PAT configured; PRs created by release-please do not trigger CI.
- Release build workflow: `.github/workflows/release-build.yml`
  - Triggers on GitHub Release creation.
  - Same build/test settings as CI (DerivedData, build number, no signing).
  - Runs `MomentumTests` only.

## Coding Style & Naming Conventions
- Use Xcode’s default Swift formatting with 4-space indentation.
- Types use `UpperCamelCase`; properties and methods use `lowerCamelCase`.
- Name files after their primary type (e.g., `ProjectManager.swift`).
- Prefer small, composable SwiftUI view structs.

## Localization & Language Policy
- App UI supports English and Spanish through `Momentum/Localizable.xcstrings`.
- Keep all user-visible Swift/SwiftUI copy localizable; avoid hardcoded single-language text.
- For dynamic/interpolated UI text, prefer `String(localized:)` or `String.localizedStringWithFormat(...)` so translations are applied reliably.
- Keep placeholder parity between EN/ES entries in `Localizable.xcstrings`.
- Raycast extension runtime/command copy should remain English-only for consistency.
- Before shipping localization-related changes, run `make check-localization`.

## Architecture & Dependencies
- Dependency direction: `Views` → `Services` → `Models` → `Utilities`.
- Allowed cross-usage:
  - `Views` can use `Services`, `Models`, `Utilities`.
  - `Services` can use `Models`, `Utilities`.
  - `Models` can use `Utilities` only when it represents domain concepts.
- Avoid upward dependencies (e.g., `Models` importing `Services`, `Views` inside `Services`).
- Keep `Utilities` free of app-specific state or side effects.

## Testing Guidelines
- Tests are written with XCTest in `MomentumTests/` and `MomentumUITests/`.
- Name test classes after module and feature (e.g., `ProjectManagerTests`).
- No explicit coverage threshold is defined; add tests for new behavior and regressions.
- Run the relevant test suite when a feature/fix is effectively finished to confirm behavior; avoid running tests on every tiny edit during active development.
- For non-trivial changes (logic, persistence, tracking), run at least `make test-unit`.
- For small UI tweaks, skip tests unless behavior could regress.
- UI tests should disable state restoration and onboarding when they are not explicitly under test, so the main window always appears.

## Verification Expectations (local)
- For non-trivial changes (logic, persistence, tracking), run at least `make test-unit`.
- For refactors or medium changes, also run `make build` to confirm the app compiles.
- For small UI tweaks, skip tests unless behavior could regress.

## Commit & Pull Request Guidelines
- Commit messages follow Conventional Commits (`feat:`, `fix:`, `chore:`) with concise subjects.
- PRs should include a clear description, linked issue (if applicable), and screenshots/recordings for UI changes.
- Note manual testing performed and the simulator/device used.

## macOS Text Field Handling
- On macOS, editable fields should use `LTRTextField` from `Momentum/Views/Components/LTRTextField.swift`.
- Reapply border styling with `macRoundedTextFieldStyle()` from `Momentum/Views/Components/MacTextFieldStyle.swift`.

## macOS Status Item
- The menu bar status item is created when `AppEnvironment` finishes bootstrapping the `ActivityTracker` via `StatusItemCoordinator`.
- Avoid wiring status item creation through `NSApplicationDelegate`; keep the lifecycle owned by `AppEnvironment` so it is deterministic.

## macOS Dock Visibility
- Dock visibility is coordinated centrally; views should post `MomentumWindowVisibilityNeedsUpdate` instead of changing activation policy directly.

## Tooling Notes
- Optional: create `.vscode/tasks.json` entries for the `xcodebuild` commands.
- If installed, `xcpretty` can be used to format `xcodebuild` output.
- SwiftLint config lives in `.swiftlint.yml` (rules are error-level only).
- SwiftFormat config lives in `.swiftformat`, with Swift version set via `.swift-version`.
- Raycast extension metadata lives in `RaycastExtension/momentum/package.json`.

## Local Dev Convenience
- For cleaner local `xcodebuild` output, use `xcbeautify` (preferred) or `xcpretty`.
  - Install: `brew install xcbeautify` (or `gem install xcpretty`).
  - Example: `xcodebuild ... | xcbeautify`
- `Makefile` targets: `make build`, `make build-for-testing`, `make test`, `make test-unit`, `make test-ui`, `make run-dev`, `make run-release`, `make clean`.
- Language targets: `make run-dev-lang APP_LANGUAGE=en|es [APP_LOCALE=...]`, `make run-release-lang ...`, `make run-dev-system-lang`.
- `make install-release` builds Release and copies `Momentum.app` into `/Applications`.
- `make archive-release` creates a `.xcarchive`, installs the app, and writes a zip to `~/Downloads`.
- Debug builds use bundle id `miguelgarglez.Momentum.dev`; expect to re-grant macOS permissions (Accessibility, Screen Recording, etc.).
- Debug builds auto-seed sample data once when the store is empty (projects, sessions, conflicts, summaries).
- `make reset-dev-data` clears the dev store and seed flag, then re-launches the dev app.
- Raycast missing-app simulation workflow (for testing extension fallback/error paths):
  - Run `npm run simulate:no-app:setup`.
  - `setup` disables app executables inside quarantine so `open -b` cannot launch from quarantine paths.
  - Test extension commands in Raycast while the app is unavailable.
  - Run `npm run simulate:no-app:restore` immediately after testing.
  - Use `npm run simulate:no-app:status` before/after to confirm state.
  - For verification, trust `physical_apps: 0` + `result: PASS` even if LaunchServices bundle lookups still show `FOUND`.
  - Use `npm run simulate:no-app:purge` only when you intentionally want irreversible cleanup.

## Performance Diagnostics (Deterministic)
- Use `make diag-cpu-release` / `make diag-cpu-release-focus` for CPU diagnostics.
- For deterministic workload: `SCENARIO_DRIVER_PATH=./scripts/diag_scenario_driver.sh make diag-cpu-release-focus`.
- Driver details and phase guide: `diagnostics/SCENARIO_GUIDE.md`.
- Diagnostics workflow guide: `diagnostics/AGENTS.md`.
- Runner/driver script notes: `scripts/AGENTS.md`.
- The runner uses an isolated store per scenario inside the app container and seeds deterministic data (`MOM_DIAG_SEED=1`).
- Default driver keeps the system active (`caffeinate -u`) and the runner can disable idle checks (`DIAG_FORCE_ACTIVE=1`) for stability.
 - Known hotspots/fixes summary: `diagnostics/AGENTS.md` (2026-01-18).
