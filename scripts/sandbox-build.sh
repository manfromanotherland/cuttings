#!/usr/bin/env bash
# Build the ReadControl Docker Sandbox template and load it into the local sbx
# CLI, so a fresh sandbox already has Node, Rust and the Swift lint/format tools.
#
# Tool versions are derived automatically from each repo's .mise.toml, so there
# is no version number to keep in sync between repos and the Dockerfile.
#
# Run on your host (not inside a sandbox — the build fetches from swift.org,
# github.com, sh.rustup.rs and the node image, which the sandbox firewall blocks).
#
# Usage:
#   ./scripts/sandbox-build.sh [--tag NAME] [--build-only]
#
# Then start a sandbox with it:
#   sbx run --template readcontrol/sandbox:1 claude
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Prerequisites ─────────────────────────────────────────────────────────────
need() { command -v "$1" >/dev/null 2>&1 || { echo "error: '$1' not found — please install it" >&2; exit 1; }; }
need docker
need awk
need sed

TAG="readcontrol/sandbox:1"
BUILD_ONLY=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --tag)        TAG="$2"; shift 2 ;;
        --build-only) BUILD_ONLY=1; shift ;;
        -h|--help)    sed -n '2,14p' "$0"; exit 0 ;;
        *)            echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

# ── Parse tool versions from .mise.toml (single source of truth) ─────────────
# Reads the value of `tool = "version"` within the [tools] section.
parse_tool() {
    local file="$1" tool="$2"
    awk -v tool="$tool" '
        /^\[tools\]/    { in_tools=1; next }
        /^\[/           { in_tools=0 }
        in_tools && $0 ~ "^" tool " *=" {
            sub(/^[^"]*"/, ""); sub(/".*$/, ""); print; exit
        }
    ' "$file"
}

# Expand a partial semver to a full git tag (e.g. "0.57" → "0.57.0").
# Only applied to swiftlint/swiftformat, whose GitHub tags use three parts.
expand_version() {
    local v="$1"
    case "$v" in
        *.*.*)  printf '%s' "$v" ;;
        *.*)    printf '%s.0' "$v" ;;
        *)      printf '%s.0.0' "$v" ;;
    esac
}

NODE_VERSION=$(parse_tool "$ROOT/extension/.mise.toml" "node")
RUST_VERSION=$(parse_tool "$ROOT/core/.mise.toml" "rust")
SWIFT_VERSION=$(parse_tool "$ROOT/macos/.mise.toml" "swift")
SWIFTLINT_VERSION=$(expand_version "$(parse_tool "$ROOT/macos/.mise.toml" "swiftlint")")
SWIFTFORMAT_VERSION=$(expand_version "$(parse_tool "$ROOT/macos/.mise.toml" "swiftformat")")

echo "==> Versions (from .mise.toml files):"
printf "    node        %-12s  extension/.mise.toml\n" "$NODE_VERSION"
printf "    rust        %-12s  core/.mise.toml\n"      "$RUST_VERSION"
printf "    swift       %-12s  macos/.mise.toml\n"     "$SWIFT_VERSION"
printf "    swiftlint   %-12s  macos/.mise.toml\n"     "$SWIFTLINT_VERSION"
printf "    swiftformat %-12s  macos/.mise.toml\n"     "$SWIFTFORMAT_VERSION"

# ── Rotate previous build log ─────────────────────────────────────────────────
BUILD_LOG="$ROOT/sandbox-build.log"
if [[ -f "$BUILD_LOG" ]]; then
    STAMP="$(date '+%Y%m%d-%H%M%S')"
    mv "$BUILD_LOG" "${BUILD_LOG%.log}-${STAMP}.log"
    echo "==> Rotated previous log to sandbox-build-${STAMP}.log"
fi

# ── Build ─────────────────────────────────────────────────────────────────────
echo "==> Building $TAG (SwiftLint + SwiftFormat compile from source; allow several minutes)"
BUILD_START=$SECONDS
set +e
DOCKER_BUILDKIT=1 docker build --progress=plain \
    --build-arg NODE_VERSION="$NODE_VERSION" \
    --build-arg RUST_VERSION="$RUST_VERSION" \
    --build-arg SWIFT_VERSION="$SWIFT_VERSION" \
    --build-arg SWIFTLINT_VERSION="$SWIFTLINT_VERSION" \
    --build-arg SWIFTFORMAT_VERSION="$SWIFTFORMAT_VERSION" \
    -t "$TAG" "$ROOT" 2>&1 | tee "$BUILD_LOG"
STATUS=${PIPESTATUS[0]}
set -e

ELAPSED=$(( SECONDS - BUILD_START ))
ELAPSED_FMT="${ELAPSED}s"
if (( ELAPSED >= 60 )); then
    ELAPSED_FMT="$(( ELAPSED / 60 ))m$(( ELAPSED % 60 ))s"
fi

if [[ "$STATUS" != "0" ]]; then
    echo "==> Build FAILED (exit $STATUS) after $ELAPSED_FMT. Full log: $BUILD_LOG"
    echo "    Last errors:"
    grep -nE 'error|not found|cannot open|fatal' "$BUILD_LOG" | tail -20
    exit "$STATUS"
fi

echo "==> Build succeeded in $ELAPSED_FMT"

if [[ "$BUILD_ONLY" == "1" ]]; then
    echo "==> Built $TAG (skipping sbx load)"
    exit 0
fi

if ! command -v sbx >/dev/null 2>&1; then
    echo "==> sbx CLI not found; image is built but cannot be loaded." >&2
    echo "    Install sbx, then:" >&2
    echo "      docker image save $TAG -o rc-sandbox.tar && sbx template load rc-sandbox.tar" >&2
    exit 1
fi

TAR="$(mktemp -t rc-sandbox-XXXX.tar)"
trap 'rm -f "$TAR"' EXIT
echo "==> Exporting image to $TAR"
docker image save "$TAG" -o "$TAR"
echo "==> Loading into sbx"
sbx template load "$TAR"

echo "==> Done. Start a sandbox with:"
echo "    sbx run --template $TAG claude"
