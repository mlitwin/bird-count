.PHONY: help generate test list-dests simulators core-test prep-beta fastlane-beta

# Configurable variables
SCHEME ?= BirdCount
PROJECT ?= BirdCount.xcodeproj
SIMULATOR ?= iPhone 16
OS ?= latest
DEST ?= platform=iOS Simulator,name=$(SIMULATOR),OS=$(OS)
CONFIGURATION ?= Debug

.DEFAULT_GOAL := help

help:
	@echo "Targets:"
	@echo "  generate   Regenerate Xcode project from project.yml using XcodeGen"
	@echo "  test       Build and run unit tests on the iOS Simulator (\"$(SIMULATOR)\", OS=$(OS))"
	@echo "  core-test  Build and run macOS unit tests for pure Swift logic (no Simulator)"
	@echo "  list-dests Show valid destinations for the scheme (useful for -destination)"
	@echo "  simulators List available Booted/Shutdown simulators via simctl"
	@echo "  prep-beta  Bump CFBundleVersion in project.yml and regenerate the Xcode project"
	@echo "Variables (override with VAR=value): SCHEME, PROJECT, SIMULATOR, DEST, CONFIGURATION"

# Regenerate the Xcode project from project.yml
generate:
	@command -v xcodegen >/dev/null 2>&1 || { echo "Error: xcodegen not found. Install with: brew install xcodegen" >&2; exit 127; }
	@xcodegen generate

# Build and run tests for the app
# Example: make test SIMULATOR="iPhone 15"
test:
	@xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIGURATION)" \
		-destination "$(DEST)" \
		test

# Show the valid destinations xcodebuild sees for this scheme/project
list-dests:
	@xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -showdest

# Raw simctl list of available devices
simulators:
	@xcrun simctl list devices available

# Build and run macOS-native core tests (fast, no simulator)
test-core:
	@xcodebuild \
		-project "$(PROJECT)" \
		-scheme "BirdCountCore" \
		-configuration "$(CONFIGURATION)" \
		test

fastlane-beta:
	op run --env-file apple.env -- bundle exec fastlane beta

prep-beta:
	@./scripts/bump-build.sh

build-test: generate
	@xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIGURATION)" \
		-destination "$(DEST)" \
		-quiet \
		build-for-testing
