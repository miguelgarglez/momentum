# Repository Guidelines

## Project Structure & Module Organization
- `Momentum/` holds the Swift/SwiftUI app source. Core areas: `Models/`, `Services/`, `Utilities/`, and `Views/`.
- `Momentum/Assets.xcassets` stores images and color assets.
- `Momentum/Documentation.docc` contains in-app documentation.
- Tests live in `MomentumTests/` (unit) and `MomentumUITests/` (UI).
- `Momentum.xcodeproj` is the Xcode project entry point.

## Build, Test, and Development Commands
Prefer `Makefile` targets for local development:
- `make build`
- `make build-for-testing`
- `make test`
- `make test-unit`
- `make test-ui`
- `make run-dev`
- `make run-release`
- `make reset-dev-data`
- `make install-release`
- `make archive-release`
- `make clean`
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

## Testing Guidelines
- Tests are written with XCTest in `MomentumTests/` and `MomentumUITests/`.
- Name test classes after module and feature (e.g., `ProjectManagerTests`).
- No explicit coverage threshold is defined; add tests for new behavior and regressions.
- Run the relevant test suite when a feature/fix is effectively finished to confirm behavior; avoid running tests on every tiny edit during active development.
- For non-trivial changes (logic, persistence, tracking), run at least `make test-unit`.
- For small UI tweaks, skip tests unless behavior could regress.

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

## Tooling Notes
- Optional: create `.vscode/tasks.json` entries for the `xcodebuild` commands.
- If installed, `xcpretty` can be used to format `xcodebuild` output.

## Local Dev Convenience
- For cleaner local `xcodebuild` output, use `xcbeautify` (preferred) or `xcpretty`.
  - Install: `brew install xcbeautify` (or `gem install xcpretty`).
  - Example: `xcodebuild ... | xcbeautify`
- `Makefile` targets: `make build`, `make build-for-testing`, `make test`, `make test-unit`, `make test-ui`, `make run-dev`, `make run-release`, `make clean`.
- `make install-release` builds Release and copies `Momentum.app` into `/Applications`.
- `make archive-release` creates a `.xcarchive`, installs the app, and writes a zip to `~/Downloads`.
- Debug builds use bundle id `miguelgarglez.Momentum.dev`; expect to re-grant macOS permissions (Accessibility, Screen Recording, etc.).
- Debug builds auto-seed sample data once when the store is empty (projects, sessions, conflicts, summaries).
- `make reset-dev-data` clears the dev store and seed flag, then re-launches the dev app.
