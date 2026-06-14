# Build helpers for the read-later macOS app.
# Run these on macOS from the read-later-macos/ directory.
#
# Prerequisites:
#   brew install xcodegen
#   rustup target add aarch64-apple-darwin x86_64-apple-darwin

CORE_DIR := ../read-later-core
FRAMEWORKS_DIR := Frameworks
BINDINGS_DIR := GeneratedBindings

.PHONY: all xcframework bindings xcodegen clean

all: xcframework bindings xcodegen

## Build the XCFramework and copy it into Frameworks/
xcframework:
	cd $(CORE_DIR) && ./scripts/build-xcframework.sh --release
	mkdir -p $(FRAMEWORKS_DIR)
	rm -rf $(FRAMEWORKS_DIR)/ReadLaterCore.xcframework
	cp -R $(CORE_DIR)/dist/ReadLaterCore.xcframework $(FRAMEWORKS_DIR)/

## Copy generated Swift bindings into GeneratedBindings/
bindings: xcframework
	mkdir -p $(BINDINGS_DIR)
	cp $(CORE_DIR)/dist/swift/*.swift $(BINDINGS_DIR)/
	cp $(CORE_DIR)/dist/swift/*.h $(BINDINGS_DIR)/
	cp $(CORE_DIR)/dist/swift/*.modulemap $(BINDINGS_DIR)/

## Regenerate the Xcode project from project.yml
xcodegen:
	xcodegen generate

clean:
	rm -rf $(FRAMEWORKS_DIR) $(BINDINGS_DIR) ReadLater.xcodeproj
