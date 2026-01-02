# Repository Guidelines

## Project Structure & Module Organization
- `Momentum/` holds the Swift/SwiftUI app source. Core areas: `Models/`, `Services/`, `Utilities/`, and `Views/`.
- `Momentum/Assets.xcassets` stores images and color assets.
- `Momentum/Documentation.docc` contains in-app documentation.
- Tests live in `MomentumTests/` (unit) and `MomentumUITests/` (UI).
- `Momentum.xcodeproj` is the Xcode project entry point.

## Build, Test, and Development Commands
Use `xcodebuild` with the project and scheme:
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
