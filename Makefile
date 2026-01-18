.PHONY: help build build-for-testing test test-unit test-ui test-only lint format format-lint run-dev run-dev-onboarding run-release run reset-dev-data run-dev-reset-permissions run-release-reset-permissions archive-release install-release dmg clean clean-release diag-cpu-release diag-cpu-release-focus

PROJECT := Momentum.xcodeproj
SCHEME := Momentum
DESTINATION := platform=macOS,arch=$(shell uname -m)
DERIVED_DATA ?= .derivedData
APP_NAME := Momentum
DEV_BUNDLE_ID ?= miguelgarglez.Momentum.dev
RELEASE_BUNDLE_ID ?= miguelgarglez.Momentum
RUN_BUNDLE_ID ?= $(DEV_BUNDLE_ID)
CONFIGURATION ?= Debug
DEV_STORE_DIR ?= $(HOME)/Library/Containers/$(DEV_BUNDLE_ID)/Data/Library/Application Support/MomentumStore
LEGACY_DEV_STORE_DIR ?= $(HOME)/Library/Application Support/MomentumStore
ARCHIVE_DIR ?= build/archives
INSTALL_DIR ?= /Applications
ZIP_DIR ?= $(HOME)/Downloads
VERSION ?= $(shell cat version.txt 2>/dev/null | tr -d ' \n\r\t')
VERSION_SAFE := $(if $(strip $(VERSION)),$(strip $(VERSION)),0.0.0)
BUILD_NUMBER_CMD := date -u +%Y%m%d%H%M%S
RELEASE_BUILD_NUMBER_SNIPPET := BUILD_NUMBER=$$($(BUILD_NUMBER_CMD)); BUILD_NUMBER_FLAG="CURRENT_PROJECT_VERSION=$$BUILD_NUMBER"
DMG_BACKGROUND ?= Packaging/dmg-background.png
DMG_WINDOW_SIZE ?= 660 440
DMG_ICON_SIZE ?= 128
DMG_APP_POS ?= 180 220
DMG_APPLICATIONS_POS ?= 480 220
DMG_STAGING_DIR ?= $(ARCHIVE_DIR)/.dmg-staging

XCBEAUTIFY := $(shell command -v xcbeautify 2>/dev/null)
XCPRETTY := $(shell command -v xcpretty 2>/dev/null)
SWIFTLINT := $(shell command -v swiftlint 2>/dev/null)
SWIFTFORMAT := $(shell command -v swiftformat 2>/dev/null)

help:
	@echo "Targets:"
	@echo "  build             Build the app"
	@echo "  build-for-testing Build for testing (no tests run)"
	@echo "  test              Run all tests"
	@echo "  test-unit         Run unit tests only"
	@echo "  test-ui           Run UI tests only"
	@echo "  test-only         Run a single test (TEST=Target/Class/testName)"
	@echo "  lint              Run SwiftLint (errors only)"
	@echo "  format            Format Swift files with SwiftFormat"
	@echo "  format-lint       Verify SwiftFormat formatting without changes"
	@echo "  run-dev           Build and launch the dev app (quits running dev app first)"
	@echo "  run-dev-onboarding Run dev app with fresh store, no debug seed, and clean onboarding"
	@echo "  run-release       Build and launch the release app (quits running release app first)"
	@echo "  diag-cpu-release  Run automated CPU diagnostics for Release"
	@echo "  diag-cpu-release-focus Run focused CPU diagnostics (baseline + top suspects)"
	@echo "  reset-dev-data    Remove dev store + seed flag, then run dev app"
	@echo "  run-dev-reset-permissions     Reset Automation permissions, then run dev app"
	@echo "  run-release-reset-permissions Reset Automation permissions, then run release app"
	@echo "  install-release   Build Release and copy app to /Applications"
	@echo "  archive-release   Archive Release, install app, and .dmg to ~/Downloads"
	@echo "  dmg               Build a drag-and-drop DMG from an existing .app"
	@echo "  clean             Remove DerivedData (.derivedData)"
	@echo "  clean-release     Remove release build artifacts"

build:
	@set -euo pipefail; \
	if [ "$(CONFIGURATION)" = "Release" ]; then \
		$(RELEASE_BUILD_NUMBER_SNIPPET); \
	else \
		BUILD_NUMBER_FLAG=""; \
	fi; \
	if [ -n "$(XCBEAUTIFY)" ]; then \
		xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -destination "$(DESTINATION)" -derivedDataPath "$(DERIVED_DATA)" -configuration "$(CONFIGURATION)" $$BUILD_NUMBER_FLAG build | xcbeautify; \
	elif [ -n "$(XCPRETTY)" ]; then \
		xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -destination "$(DESTINATION)" -derivedDataPath "$(DERIVED_DATA)" -configuration "$(CONFIGURATION)" $$BUILD_NUMBER_FLAG build | xcpretty; \
	else \
		xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -destination "$(DESTINATION)" -derivedDataPath "$(DERIVED_DATA)" -configuration "$(CONFIGURATION)" $$BUILD_NUMBER_FLAG build; \
	fi

build-for-testing:
	@set -euo pipefail; \
	if [ -n "$(XCBEAUTIFY)" ]; then \
		xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -destination "$(DESTINATION)" -derivedDataPath "$(DERIVED_DATA)" -configuration "$(CONFIGURATION)" build-for-testing | xcbeautify; \
	elif [ -n "$(XCPRETTY)" ]; then \
		xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -destination "$(DESTINATION)" -derivedDataPath "$(DERIVED_DATA)" -configuration "$(CONFIGURATION)" build-for-testing | xcpretty; \
	else \
		xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -destination "$(DESTINATION)" -derivedDataPath "$(DERIVED_DATA)" -configuration "$(CONFIGURATION)" build-for-testing; \
	fi

test:
	@set -euo pipefail; \
	if [ -n "$(XCBEAUTIFY)" ]; then \
		xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -destination "$(DESTINATION)" -derivedDataPath "$(DERIVED_DATA)" -configuration "$(CONFIGURATION)" test | xcbeautify; \
	elif [ -n "$(XCPRETTY)" ]; then \
		xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -destination "$(DESTINATION)" -derivedDataPath "$(DERIVED_DATA)" -configuration "$(CONFIGURATION)" test | xcpretty; \
	else \
		xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -destination "$(DESTINATION)" -derivedDataPath "$(DERIVED_DATA)" -configuration "$(CONFIGURATION)" test; \
	fi

test-unit:
	@set -euo pipefail; \
	if [ -n "$(XCBEAUTIFY)" ]; then \
		xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -destination "$(DESTINATION)" -derivedDataPath "$(DERIVED_DATA)" -configuration "$(CONFIGURATION)" test -only-testing:MomentumTests | xcbeautify; \
	elif [ -n "$(XCPRETTY)" ]; then \
		xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -destination "$(DESTINATION)" -derivedDataPath "$(DERIVED_DATA)" -configuration "$(CONFIGURATION)" test -only-testing:MomentumTests | xcpretty; \
	else \
		xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -destination "$(DESTINATION)" -derivedDataPath "$(DERIVED_DATA)" -configuration "$(CONFIGURATION)" test -only-testing:MomentumTests; \
	fi

test-ui:
	@set -euo pipefail; \
	if [ -n "$(XCBEAUTIFY)" ]; then \
		xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -destination "$(DESTINATION)" -derivedDataPath "$(DERIVED_DATA)" -configuration "$(CONFIGURATION)" test -only-testing:MomentumUITests | xcbeautify; \
	elif [ -n "$(XCPRETTY)" ]; then \
		xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -destination "$(DESTINATION)" -derivedDataPath "$(DERIVED_DATA)" -configuration "$(CONFIGURATION)" test -only-testing:MomentumUITests | xcpretty; \
	else \
		xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -destination "$(DESTINATION)" -derivedDataPath "$(DERIVED_DATA)" -configuration "$(CONFIGURATION)" test -only-testing:MomentumUITests; \
	fi

test-only:
	@set -euo pipefail; \
	if [ -z "$(TEST)" ]; then \
		echo "Usage: make test-only TEST=Target/Class/testName"; \
		exit 1; \
	fi; \
	if [ -n "$(XCBEAUTIFY)" ]; then \
		xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -destination "$(DESTINATION)" -derivedDataPath "$(DERIVED_DATA)" -configuration "$(CONFIGURATION)" test -only-testing:$(TEST) | xcbeautify; \
	elif [ -n "$(XCPRETTY)" ]; then \
		xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -destination "$(DESTINATION)" -derivedDataPath "$(DERIVED_DATA)" -configuration "$(CONFIGURATION)" test -only-testing:$(TEST) | xcpretty; \
	else \
		xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -destination "$(DESTINATION)" -derivedDataPath "$(DERIVED_DATA)" -configuration "$(CONFIGURATION)" test -only-testing:$(TEST); \
	fi

lint:
	@set -euo pipefail; \
	if [ -z "$(SWIFTLINT)" ]; then \
		echo "swiftlint not found. Install with: brew install swiftlint"; \
		exit 1; \
	fi; \
	SWIFTLINT_CACHE_PATH=.swiftlint-cache swiftlint --config .swiftlint.yml

format:
	@set -euo pipefail; \
	if [ -z "$(SWIFTFORMAT)" ]; then \
		echo "swiftformat not found. Install with: brew install swiftformat"; \
		exit 1; \
	fi; \
	swiftformat .

format-lint:
	@set -euo pipefail; \
	if [ -z "$(SWIFTFORMAT)" ]; then \
		echo "swiftformat not found. Install with: brew install swiftformat"; \
		exit 1; \
	fi; \
	swiftformat --lint .

run-dev:
	@$(MAKE) run CONFIGURATION=Debug RUN_BUNDLE_ID="$(DEV_BUNDLE_ID)"

run-release:
	@$(MAKE) run CONFIGURATION=Release RUN_BUNDLE_ID="$(RELEASE_BUNDLE_ID)"

diag-cpu-release:
	@./scripts/diag_run_release.sh

diag-cpu-release-focus:
	@SCENARIOS="baseline,disable_swiftdata_writes,disable_backfill,disable_crash_recovery" \
	DIAG_FORCE_ACTIVE=1 \
	CPU_SAMPLE_S=360 \
	TIMEPROFILER_S=60 \
	./scripts/diag_run_release.sh

run: build
	@set -euo pipefail; \
	osascript -e 'tell application id "$(RUN_BUNDLE_ID)" to quit' 2>/dev/null || true; \
	BUILD_DIR=$$(xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -destination "$(DESTINATION)" -derivedDataPath "$(DERIVED_DATA)" -configuration "$(CONFIGURATION)" -showBuildSettings | awk -F ' = ' '/BUILT_PRODUCTS_DIR/ {print $$2; exit}'); \
	FULL_PRODUCT_NAME=$$(xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -destination "$(DESTINATION)" -derivedDataPath "$(DERIVED_DATA)" -configuration "$(CONFIGURATION)" -showBuildSettings | awk -F ' = ' '/FULL_PRODUCT_NAME/ {print $$2; exit}'); \
	APP_PATH="$$BUILD_DIR/$$FULL_PRODUCT_NAME"; \
	if [ ! -d "$$APP_PATH" ]; then \
		echo "App not found at $$APP_PATH"; \
		exit 1; \
	fi; \
	if [ -n "$(RUN_ARGS)" ]; then \
		open "$$APP_PATH" --args $(RUN_ARGS); \
	else \
		open "$$APP_PATH"; \
	fi

run-dev-onboarding:
	@set -euo pipefail; \
	osascript -e 'tell application id "$(DEV_BUNDLE_ID)" to quit' 2>/dev/null || true; \
	defaults delete "$(DEV_BUNDLE_ID)" Momentum.DebugSeeded >/dev/null 2>&1 || true; \
	defaults delete "$(DEV_BUNDLE_ID)" Onboarding.hasSeenWelcome >/dev/null 2>&1 || true; \
	defaults delete "$(DEV_BUNDLE_ID)" Onboarding.hasCreatedProject >/dev/null 2>&1 || true; \
	defaults delete "$(DEV_BUNDLE_ID)" Onboarding.hasAccessibilityPermissionPrompted >/dev/null 2>&1 || true; \
	rm -rf "$(DEV_STORE_DIR)" "$(LEGACY_DEV_STORE_DIR)"; \
	$(MAKE) run-dev RUN_ARGS="--skip-debug-seed"

reset-dev-data:
	@set -euo pipefail; \
	osascript -e 'tell application id "$(DEV_BUNDLE_ID)" to quit' 2>/dev/null || true; \
	defaults delete "$(DEV_BUNDLE_ID)" Momentum.DebugSeeded >/dev/null 2>&1 || true; \
	rm -rf "$(DEV_STORE_DIR)" "$(LEGACY_DEV_STORE_DIR)"; \
	$(MAKE) run-dev

run-dev-reset-permissions:
	@set -euo pipefail; \
	echo "Resetting macOS Automation permissions for $(DEV_BUNDLE_ID)"; \
	tccutil reset AppleEvents "$(DEV_BUNDLE_ID)"; \
	$(MAKE) run-dev

run-release-reset-permissions:
	@set -euo pipefail; \
	echo "Resetting macOS Automation permissions for $(RELEASE_BUNDLE_ID)"; \
	tccutil reset AppleEvents "$(RELEASE_BUNDLE_ID)"; \
	$(MAKE) run-release

install-release:
	@set -euo pipefail; \
	$(RELEASE_BUILD_NUMBER_SNIPPET); \
	if [ -n "$(XCBEAUTIFY)" ]; then \
		xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -destination "$(DESTINATION)" -derivedDataPath "$(DERIVED_DATA)" -configuration Release $$BUILD_NUMBER_FLAG build | xcbeautify; \
	elif [ -n "$(XCPRETTY)" ]; then \
		xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -destination "$(DESTINATION)" -derivedDataPath "$(DERIVED_DATA)" -configuration Release $$BUILD_NUMBER_FLAG build | xcpretty; \
	else \
		xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -destination "$(DESTINATION)" -derivedDataPath "$(DERIVED_DATA)" -configuration Release $$BUILD_NUMBER_FLAG build; \
	fi; \
	BUILD_DIR=$$(xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -destination "$(DESTINATION)" -derivedDataPath "$(DERIVED_DATA)" -configuration Release -showBuildSettings | awk -F ' = ' '/BUILT_PRODUCTS_DIR/ {print $$2; exit}'); \
	FULL_PRODUCT_NAME=$$(xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -destination "$(DESTINATION)" -derivedDataPath "$(DERIVED_DATA)" -configuration Release -showBuildSettings | awk -F ' = ' '/FULL_PRODUCT_NAME/ {print $$2; exit}'); \
	APP_PATH="$$BUILD_DIR/$$FULL_PRODUCT_NAME"; \
	if [ ! -d "$$APP_PATH" ]; then \
		echo "App not found at $$APP_PATH"; \
		exit 1; \
	fi; \
	osascript -e 'tell application id "$(RELEASE_BUNDLE_ID)" to quit' 2>/dev/null || true; \
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"; \
	cp -R "$$APP_PATH" "$(INSTALL_DIR)/$(APP_NAME).app"

archive-release:
	@set -euo pipefail; \
	mkdir -p "$(ARCHIVE_DIR)" "$(ZIP_DIR)"; \
	ARCHIVE_PATH="$(ARCHIVE_DIR)/$(APP_NAME)-$(VERSION_SAFE).xcarchive"; \
	rm -rf "$$ARCHIVE_PATH"; \
	$(RELEASE_BUILD_NUMBER_SNIPPET); \
	xcodebuild archive -project "$(PROJECT)" -scheme "$(SCHEME)" -destination "$(DESTINATION)" -derivedDataPath "$(DERIVED_DATA)" -configuration Release $$BUILD_NUMBER_FLAG -archivePath "$$ARCHIVE_PATH" | { if [ -n "$(XCBEAUTIFY)" ]; then xcbeautify; elif [ -n "$(XCPRETTY)" ]; then xcpretty; else cat; fi; }; \
	APP_PATH="$$ARCHIVE_PATH/Products/Applications/$(APP_NAME).app"; \
	if [ ! -d "$$APP_PATH" ]; then \
		echo "App not found at $$APP_PATH"; \
		exit 1; \
	fi; \
	$(MAKE) dmg DMG_APP_PATH="$$APP_PATH"

dmg:
	@set -euo pipefail; \
	if ! command -v create-dmg >/dev/null 2>&1; then \
		echo "create-dmg not found. Install with: brew install create-dmg"; \
		exit 1; \
	fi; \
	if [ -z "$(DMG_APP_PATH)" ]; then \
		echo "DMG_APP_PATH is required (path to .app)"; \
		exit 1; \
	fi; \
	if [ ! -d "$(DMG_APP_PATH)" ]; then \
		echo "App not found at $(DMG_APP_PATH)"; \
		exit 1; \
	fi; \
	if [ ! -f "$(DMG_BACKGROUND)" ]; then \
		echo "DMG background not found at $(DMG_BACKGROUND)"; \
		exit 1; \
	fi; \
	DMG_PATH="$(ZIP_DIR)/$(APP_NAME)-$(VERSION_SAFE).dmg"; \
	STAGING_DIR="$(DMG_STAGING_DIR)"; \
	rm -rf "$$STAGING_DIR" "$$DMG_PATH"; \
	mkdir -p "$$STAGING_DIR"; \
	cp -R "$(DMG_APP_PATH)" "$$STAGING_DIR/$(APP_NAME).app"; \
	create-dmg \
		--volname "$(APP_NAME)" \
		--background "$(DMG_BACKGROUND)" \
		--window-size $(DMG_WINDOW_SIZE) \
		--icon-size $(DMG_ICON_SIZE) \
		--icon "$(APP_NAME).app" $(DMG_APP_POS) \
		--app-drop-link $(DMG_APPLICATIONS_POS) \
		--format UDZO \
		--hdiutil-quiet \
		--no-internet-enable \
		"$$DMG_PATH" \
		"$$STAGING_DIR" >/dev/null; \
	rm -rf "$$STAGING_DIR"

clean:
	@rm -rf "$(DERIVED_DATA)"

clean-release:
	@rm -rf "$(ARCHIVE_DIR)" "$(DMG_STAGING_DIR)"
