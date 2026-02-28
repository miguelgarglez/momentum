# Momentum Public Release

## Distribution model (Phase 1)

Momentum is distributed through GitHub Releases as downloadable binaries.

Release assets:
- `Momentum-macOS-universal.dmg` and `Momentum-macOS-universal.zip` when universal build succeeds.
- `Momentum-macOS-arm64.dmg/.zip` + `Momentum-macOS-x86_64.dmg/.zip` when universal fallback is used.
- `checksums.txt` with SHA256 hashes for all release artifacts.

The release workflow uploads artifacts directly to the published tag release, so every public version can be installed without Xcode.

## CI release pipeline

Workflow: `.github/workflows/release-build.yml` (trigger: `release.published`)

Steps:
1. Lint + unit tests on macOS runner.
2. Build Release app (attempt universal first, fallback to split arch).
3. Package `.zip` and `.dmg`.
4. Verify archive integrity and binary architecture.
5. Upload release assets with `gh release upload --clobber`.

Triggers:
- Automatic on `push` of version tags (`v*`), including tags created by `release-please`.
- Manual via `workflow_dispatch` with `release_tag` input when backfilling assets for an existing release.

Core scripts:
- `scripts/release/build_and_package_macos.sh`
- `scripts/release/upload_release_assets.sh`

## Local build and packaging

For manual local packaging:
- Full archive + DMG:
  - `make archive-release`
- DMG from an existing app:
  - `make dmg DMG_APP_PATH="/path/to/Momentum.app"`

Local DMG output path:
- `~/Downloads/$(APP_NAME)-$(VERSION_SAFE).dmg`

## Installation guide for users (without notarization)

1. Download the latest `.dmg` from GitHub Releases.
2. Drag `Momentum.app` to `Applications`.
3. First launch:
   - If macOS blocks opening, go to `System Settings > Privacy & Security` and click `Open Anyway`.
4. Grant the requested permissions when prompted (Accessibility, Screen Recording, Automation) so tracking features work.

## Post-release QA checklist

Run on a clean macOS user/session:
1. Download and install from the released DMG.
2. Launch app from `/Applications`.
3. Complete onboarding and verify main dashboard appears.
4. Create a sample project and verify tracking starts.
5. Confirm status item appears and interactions respond.

## Retry and recovery

If asset upload fails:
1. Re-run the failed `release-build` workflow for the same release.
2. Upload step is idempotent (`--clobber` overwrites same filenames).
3. Verify release page contains DMG, ZIP, and `checksums.txt`.

If a release is bad:
1. Mark the GitHub release as pre-release or remove affected assets.
2. Ship a patch release with a new tag.
3. Keep old artifacts only if they are known good and documented.

## DMG customization (local create-dmg flow)

Background image for local Makefile DMG:
- `Packaging/dmg-background.png`

Layout settings:
- `DMG_WINDOW_SIZE`
- `DMG_ICON_SIZE`
- `DMG_APP_POS`
- `DMG_APPLICATIONS_POS`
