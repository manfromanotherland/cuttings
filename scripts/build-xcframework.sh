#!/usr/bin/env bash
# Build core as an XCFramework for use in the macOS SwiftUI app.
#
# Prerequisites (macOS only):
#   rustup target add aarch64-apple-darwin x86_64-apple-darwin
#   cargo install uniffi-bindgen-go  # not needed — use uniffi-bindgen from crate
#
# Usage:
#   ./scripts/build-xcframework.sh [--release]
#
# Outputs:
#   dist/CuttingsCore.xcframework   — linkable XCFramework
#   dist/swift/                      — generated Swift bindings

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(dirname "$SCRIPT_DIR")"
CORE_DIR="$WORKSPACE_DIR/core"
DIST_DIR="$WORKSPACE_DIR/dist"
SWIFT_DIR="$DIST_DIR/swift"
FW_DIR="$DIST_DIR/CuttingsCore.xcframework"

PROFILE="${1:-debug}"
CARGO_FLAGS=()
if [[ "$PROFILE" == "--release" ]]; then
    PROFILE="release"
    CARGO_FLAGS+=(--release)
fi

LIB_NAME="libcuttings_core.a"
TARGET_DIR="$WORKSPACE_DIR/target"

echo "==> Building for aarch64-apple-darwin ($PROFILE)"
cargo build "${CARGO_FLAGS[@]}" \
    --manifest-path "$CORE_DIR/Cargo.toml" \
    --target aarch64-apple-darwin

echo "==> Building for x86_64-apple-darwin ($PROFILE)"
cargo build "${CARGO_FLAGS[@]}" \
    --manifest-path "$CORE_DIR/Cargo.toml" \
    --target x86_64-apple-darwin

ARM_LIB="$TARGET_DIR/aarch64-apple-darwin/$PROFILE/$LIB_NAME"
X86_LIB="$TARGET_DIR/x86_64-apple-darwin/$PROFILE/$LIB_NAME"
UNIVERSAL_LIB="$TARGET_DIR/universal-apple-darwin/$PROFILE/$LIB_NAME"

echo "==> Creating universal (fat) library"
mkdir -p "$(dirname "$UNIVERSAL_LIB")"
lipo -create "$ARM_LIB" "$X86_LIB" -output "$UNIVERSAL_LIB"

echo "==> Generating Swift bindings"
mkdir -p "$SWIFT_DIR"
cargo run \
    --manifest-path "$WORKSPACE_DIR/Cargo.toml" \
    --bin uniffi-bindgen \
    -- generate \
    --library "$ARM_LIB" \
    --language swift \
    --out-dir "$SWIFT_DIR"

echo "==> Packaging XCFramework"
rm -rf "$FW_DIR"
xcodebuild -create-xcframework \
    -library "$UNIVERSAL_LIB" \
    -headers "$SWIFT_DIR" \
    -output "$FW_DIR"

echo ""
echo "Done!"
echo "  XCFramework : $FW_DIR"
echo "  Swift bindings: $SWIFT_DIR"
