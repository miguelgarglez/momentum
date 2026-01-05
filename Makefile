.PHONY: help build build-for-testing test test-unit test-ui run-dev run-release run reset-dev-data archive-release install-release clean

PROJECT := Momentum.xcodeproj
SCHEME := Momentum
DESTINATION := platform=macOS,arch=$(shell uname -m)
DERIVED_DATA ?= .derivedData
APP_NAME := Momentum
DEV_BUNDLE_ID ?= miguelgarglez.Momentum.dev
RELEASE_BUNDLE_ID ?= miguelgarglez.Momentum
RUN_BUNDLE_ID ?= $(DEV_BUNDLE_ID)
CONFIGURATION ?= Debug
DEV_STORE_DIR ?= $(HOME)/Library/Application\ Support/MomentumStore
ARCHIVE_DIR ?= build/archives
INSTALL_DIR ?= /Applications
ZIP_DIR ?= $(HOME)/Downloads
VERSION ?= $(shell cat version.txt 2>/dev/null | tr -d ' \n\r\t')
VERSION_SAFE := $(if $(strip $(VERSION)),$(strip $(VERSION)),0.0.0)

XCBEAUTIFY := $(shell command -v xcbeautify 2>/dev/null)
XCPRETTY := $(shell command -v xcpretty 2>/dev/null)

help:
	@echo "Targets:"
	@echo "  build             Build the app"
	@echo "  build-for-testing Build for testing (no tests run)"
	@echo "  test              Run all tests"
	@echo "  test-unit         Run unit tests only"
	@echo "  test-ui           Run UI tests only"
	@echo "  run-dev           Build and launch the dev app (quits running dev app first)"
	@echo "  run-release       Build and launch the release app (quits running release app first)"
	@echo "  reset-dev-data    Remove dev store + seed flag, then run dev app"
	@echo "  install-release   Build Release and copy app to /Applications"
	@echo "  archive-release   Archive Release, install app, and zip to ~/Downloads"
	@echo "  clean             Remove DerivedData (.derivedData)"

build:
	@set -euo pipefail; \
	if [ -n "$(XCBEAUTIFY)" ]; then \
		xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -destination "$(DESTINATION)" -derivedDataPath "$(DERIVED_DATA)" -configuration "$(CONFIGURATION)" build | xcbeautify; \
	elif [ -n "$(XCPRETTY)" ]; then \
		xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -destination "$(DESTINATION)" -derivedDataPath "$(DERIVED_DATA)" -configuration "$(CONFIGURATION)" build | xcpretty; \
	else \
		xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -destination "$(DESTINATION)" -derivedDataPath "$(DERIVED_DATA)" -configuration "$(CONFIGURATION)" build; \
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

run-dev:
	@$(MAKE) run CONFIGURATION=Debug RUN_BUNDLE_ID="$(DEV_BUNDLE_ID)"

run-release:
	@$(MAKE) run CONFIGURATION=Release RUN_BUNDLE_ID="$(RELEASE_BUNDLE_ID)"

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
	open "$$APP_PATH"

reset-dev-data:
	@set -euo pipefail; \
	osascript -e 'tell application id "$(DEV_BUNDLE_ID)" to quit' 2>/dev/null || true; \
	defaults delete "$(DEV_BUNDLE_ID)" Momentum.DebugSeeded >/dev/null 2>&1 || true; \
	rm -rf "$(DEV_STORE_DIR)"; \
	$(MAKE) run-dev

install-release:
	@set -euo pipefail; \
	$(MAKE) build CONFIGURATION=Release; \
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
	xcodebuild archive -project "$(PROJECT)" -scheme "$(SCHEME)" -destination "$(DESTINATION)" -derivedDataPath "$(DERIVED_DATA)" -configuration Release -archivePath "$$ARCHIVE_PATH" | { if [ -n "$(XCBEAUTIFY)" ]; then xcbeautify; elif [ -n "$(XCPRETTY)" ]; then xcpretty; else cat; fi; }; \
	APP_PATH="$$ARCHIVE_PATH/Products/Applications/$(APP_NAME).app"; \
	if [ ! -d "$$APP_PATH" ]; then \
		echo "App not found at $$APP_PATH"; \
		exit 1; \
	fi; \
	DMG_PATH="$(ZIP_DIR)/$(APP_NAME)-$(VERSION_SAFE).dmg"; \
	STAGING_DIR="$(ZIP_DIR)/.$(APP_NAME)-dmg"; \
	rm -rf "$$STAGING_DIR" "$$DMG_PATH"; \
	mkdir -p "$$STAGING_DIR"; \
	cp -R "$$APP_PATH" "$$STAGING_DIR/$(APP_NAME).app"; \
	hdiutil create -volname "$(APP_NAME)" -srcfolder "$$STAGING_DIR" -ov -format UDZO "$$DMG_PATH" >/dev/null; \
	rm -rf "$$STAGING_DIR"

clean:
	@rm -rf "$(DERIVED_DATA)"
