# Release DMG

This repo ships a drag-and-drop DMG using `create-dmg`.

## Prerequisites

- Install create-dmg:
  - `brew install create-dmg`

## Build the DMG

- Full archive + DMG:
  - `make archive-release`
- DMG from an existing app:
  - `make dmg DMG_APP_PATH="/path/to/Momentum.app"`

The DMG will be written to `~/Downloads/$(APP_NAME)-$(VERSION_SAFE).dmg`.

## Customize the DMG

- Background image: `Packaging/dmg-background.png`
  - Replace this file with your final background.
  - If you change the image size, update `DMG_WINDOW_SIZE` in `Makefile` to match.
- Layout settings live in `Makefile`:
  - `DMG_WINDOW_SIZE`, `DMG_ICON_SIZE`, `DMG_APP_POS`, `DMG_APPLICATIONS_POS`

## Local verification

- `make archive-release`
- Open the DMG in Finder and verify:
  - Background renders.
  - `Momentum.app` is on the left.
  - `Applications` alias is on the right.
  - Drag-and-drop installs into `/Applications`.
