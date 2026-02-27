# Changelog

All notable changes to this extension will be documented in this file.

## [Unreleased]

### Added
- Explicit companion-app prerequisite handling for missing Momentum installs.
- Recovery path that attempts to launch Momentum and retry local command transport.
- Store-readiness documentation with setup, troubleshooting, and validation guidance.
- Internal release checklist and Store metadata draft notes.
- Reversible automation script to simulate and verify missing Momentum app availability.
- Optional destructive `simulate:no-app:purge` command for hard clean-slate tests.

### Changed
- Extension platform declaration to macOS only.
- Command metadata (descriptions/subtitles) to clarify companion-app behavior.
- Error copy to provide concrete next actions for app availability, integration, and pairing.
- List Projects error state actions to open Momentum and Momentum settings directly.
- Missing-app simulation now disables app executables inside quarantine to prevent launches from quarantined bundles.
