# Build helpers for the readcontrol macOS app.
# Run these on macOS from the readcontrol-macos/ directory.
#
# Prerequisites:
#   brew install xcodegen
#   rustup target add aarch64-apple-darwin x86_64-apple-darwin

CORE_DIR := ../readcontrol-core
FRAMEWORKS_DIR := Frameworks
BINDINGS_DIR := GeneratedBindings

.PHONY: all xcframework bindings xcodegen test dmg clean format format-check lint lint-fix

all: xcframework bindings xcodegen

## Build the XCFramework and copy it into Frameworks/
xcframework:
	cd $(CORE_DIR) && ./scripts/build-xcframework.sh --release
	mkdir -p $(FRAMEWORKS_DIR)
	rm -rf $(FRAMEWORKS_DIR)/ReadControlCore.xcframework
	cp -R $(CORE_DIR)/dist/ReadControlCore.xcframework $(FRAMEWORKS_DIR)/

## Copy generated Swift bindings into GeneratedBindings/
bindings: xcframework
	mkdir -p $(BINDINGS_DIR)
	cp $(CORE_DIR)/dist/swift/*.swift $(BINDINGS_DIR)/
	cp $(CORE_DIR)/dist/swift/*.h $(BINDINGS_DIR)/
	cp $(CORE_DIR)/dist/swift/*.modulemap $(BINDINGS_DIR)/

## Regenerate the Xcode project from project.yml
xcodegen:
	xcodegen generate

## Run the test suites. The scheme runs the fast, hostless unit tests
## (ReadControlTests) before the UI suite, so logic regressions surface first.
## Assumes `make all` has generated the framework, bindings, and project.
test:
	xcodebuild test -scheme ReadControl

## Build a Release .app and wrap it in a distributable .dmg (dist/ReadControl.dmg).
## Ad-hoc signed only — see scripts/package-dmg.sh. Assumes `make all` has run.
dmg: all
	./scripts/package-dmg.sh

## Reformat Swift sources in place (config: .swiftformat). Run this before `lint`;
## SwiftFormat is configured to agree with SwiftLint, so it won't create new
## SwiftLint violations.
format:
	swiftformat .

## Verify formatting without editing — fails if anything is unformatted (CI/hooks).
format-check:
	swiftformat --lint .

## Lint Swift sources with SwiftLint (config: .swiftlint.yml).
lint:
	swiftlint lint

## Auto-fix the SwiftLint violations that are safe to correct in place.
lint-fix:
	swiftlint --fix

clean:
	rm -rf $(FRAMEWORKS_DIR) $(BINDINGS_DIR) ReadControl.xcodeproj build dist
