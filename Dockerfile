# syntax=docker/dockerfile:1
# Cuttings — Docker Sandbox template
#
#   extension  Node (pinned in extension/.mise.toml)
#   core       Rust stable    (core/.mise.toml)
#   macos      Swift + swiftlint + swiftformat  (macos/.mise.toml)
#
# Toolchains are installed directly (no mise in the image): Node is copied from
# the official node image, Rust via rustup, and Swift from the swift.org tarball.
# The components' .mise.toml files stay the version source of truth — sandbox-build.sh
# reads them on the host and passes each version in as a --build-arg. (mise still
# runs on developers' Macs; it just isn't needed inside this Linux image, where
# the firewall would block it from fetching anything at runtime anyway.)
#
# Build/load/use: see SANDBOX.md (or scripts/sandbox-build.sh).

# ── Pinned versions (defaults; sandbox-build.sh overrides from .mise.toml) ───
ARG NODE_VERSION=24.16.0
ARG RUST_VERSION=stable
ARG SWIFT_VERSION=6.3.2
ARG SWIFTLINT_VERSION=0.57.1
ARG SWIFTFORMAT_VERSION=0.55.6
# Keep SWIFT_BUILD_JOBS=1 on low-RAM builders; raise with --build-arg if you
# have ≥8 GB available (e.g. --build-arg SWIFT_BUILD_JOBS=4).
ARG SWIFT_BUILD_JOBS=1

# ── Node source image (copied into base below) ───────────────────────────────
FROM node:${NODE_VERSION} AS node-src

# ── Stage 1: Ubuntu 24.04 compat libs ────────────────────────────────────────
# The swift.org toolchain is built for Ubuntu 24.04 and links against sonames
# that the newer sandbox base (Ubuntu 26.04) no longer ships (libxml2.so.2,
# ICU 74, libpython3.12). Extract them here and copy into the base below.
FROM ubuntu:24.04 AS swiftcompatlibs
RUN apt-get update && apt-get install -y --no-install-recommends \
        libxml2 libicu74 libpython3.12t64 \
    && rm -rf /var/lib/apt/lists/*

# ── Stage 2: Swift toolchain download + signature check ──────────────────────
# Download the swift.org Ubuntu-24.04 toolchain, verify its GPG signature, and
# extract to /opt/swift (relocatable — /opt/swift/usr/bin/swift, libs under
# /opt/swift/usr/lib). Done on ubuntu:24.04 so curl/gnupg are trivial to get;
# the extracted bytes are identical regardless of the stage's distro.
FROM ubuntu:24.04 AS swift-dl
ARG SWIFT_VERSION
ARG TARGETARCH
# Swift 6.x Release Signing Key (matches swiftlang/swift-docker). Fetched from a
# keyserver rather than swift.org/keys/all-keys.asc, whose endpoint is unreliable.
# Named ...FINGERPRINT (not ...KEY) to avoid BuildKit's false-positive
# "secret in ARG" lint — a public GPG fingerprint is not sensitive.
ARG SWIFT_SIGNING_FINGERPRINT=52BB7E3DE28A71BE22EC05FFEF80A866B47A981F
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl gnupg dirmngr ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN set -eux; \
    case "${TARGETARCH}" in \
        arm64) dir=ubuntu2404-aarch64; sfx=ubuntu24.04-aarch64 ;; \
        amd64) dir=ubuntu2404;         sfx=ubuntu24.04 ;; \
        *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    base="https://download.swift.org/swift-${SWIFT_VERSION}-release/${dir}/swift-${SWIFT_VERSION}-RELEASE"; \
    file="swift-${SWIFT_VERSION}-RELEASE-${sfx}.tar.gz"; \
    curl -fSL "${base}/${file}"     -o /tmp/swift.tar.gz; \
    curl -fSL "${base}/${file}.sig" -o /tmp/swift.tar.gz.sig; \
    gpg --batch --quiet --keyserver keyserver.ubuntu.com --recv-keys "${SWIFT_SIGNING_FINGERPRINT}"; \
    gpg --batch --verify /tmp/swift.tar.gz.sig /tmp/swift.tar.gz; \
    mkdir -p /opt/swift; \
    tar -xzf /tmp/swift.tar.gz -C /opt/swift --strip-components=1; \
    rm -f /tmp/swift.tar.gz /tmp/swift.tar.gz.sig; \
    test -x /opt/swift/usr/bin/swift   # runtime check runs in the base stage, which has swift's libs

# ── Stage 3: base toolchains ──────────────────────────────────────────────────
# Assembles Node (from node-src), Swift (from swift-dl) and Rust (rustup) onto
# the sandbox base, plus the Swift-on-Linux system deps and the 24.04 compat libs.
FROM docker/sandbox-templates:claude-code AS base
ARG RUST_VERSION

# System packages (as root).
# build-essential + clang: rusqlite compiles bundled SQLite from C; Swift-from-
# source builds (swiftlint/swiftformat) also need a linker. The remaining libs
# are Swift-on-Linux runtime/build deps listed by swift.org for Debian.
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        clang \
        pkg-config \
        git \
        curl \
        ca-certificates \
        unzip \
        libcurl4-openssl-dev \
        libedit2 \
        libncurses-dev \
        libpython3-dev \
        libsqlite3-0 \
        libxml2-dev \
        libz3-dev \
        zlib1g-dev \
        tzdata \
    && rm -rf /var/lib/apt/lists/*

# Ubuntu-24.04 sonames the swift.org toolchain links (see swiftcompatlibs).
COPY --from=swiftcompatlibs /usr/lib/*/libxml2.so.2*        /usr/local/lib/
COPY --from=swiftcompatlibs /usr/lib/*/libicudata.so.74*    /usr/local/lib/
COPY --from=swiftcompatlibs /usr/lib/*/libicui18n.so.74*    /usr/local/lib/
COPY --from=swiftcompatlibs /usr/lib/*/libicuuc.so.74*      /usr/local/lib/
COPY --from=swiftcompatlibs /usr/lib/*/libpython3.12.so.1.0* /usr/local/lib/
RUN ldconfig

# Node: copy the binary + npm/npx from the official image (checksummed by the
# image digest). The node binary is glibc-backward-compatible, so a bookworm
# build runs fine on the newer base.
COPY --from=node-src /usr/local/bin/node          /usr/local/bin/node
COPY --from=node-src /usr/local/lib/node_modules  /usr/local/lib/node_modules
RUN ln -sf ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -sf ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

# Swift: relocatable toolchain from the swift-dl stage.
COPY --from=swift-dl /opt/swift /opt/swift

# Rust: rustup, installed system-wide with a world-writable CARGO_HOME so the
# agent can populate the registry cache at runtime (mirrors the official rust
# image). RUST_VERSION is "stable" by default, resolved at build time.
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo
RUN curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs \
    | sh -s -- -y --no-modify-path --profile minimal --default-toolchain "${RUST_VERSION}" \
    && chmod -R a+w "${RUSTUP_HOME}" "${CARGO_HOME}"

# PATH + SourceKitten lib path for every context. /usr/local/bin (node) is
# already on the default PATH; cargo and swift bins are not, so add them.
# LINUX_SOURCEKIT_LIB_PATH stops SourceKitten misdetecting the toolchain as
# swiftenv and crashing when swiftlint runs.
ENV PATH=/usr/local/cargo/bin:/opt/swift/usr/bin:${PATH}
ENV LINUX_SOURCEKIT_LIB_PATH=/opt/swift/usr/lib

# Login shells reset PATH via /etc/profile, so re-add the non-standard bin dirs
# there. The Claude Code Bash tool sources /etc/sandbox-persistent.sh (via
# CLAUDE_ENV_FILE) before each command; add them there too, guarded so PATH does
# not grow on repeated sourcing. Both files set the SAME values as the ENV above.
RUN cat > /etc/profile.d/10-toolchains.sh <<'EOF'
export PATH="/usr/local/cargo/bin:/opt/swift/usr/bin:${PATH}"
export LINUX_SOURCEKIT_LIB_PATH=/opt/swift/usr/lib
EOF
RUN cat >> /etc/sandbox-persistent.sh <<'EOF'
# toolchains — added by Dockerfile (guarded to avoid duplicate PATH entries)
if [ -z "${_RC_TOOLCHAINS_PATH_DONE:-}" ]; then
  export PATH="/usr/local/cargo/bin:/opt/swift/usr/bin:${PATH}"
  export LINUX_SOURCEKIT_LIB_PATH=/opt/swift/usr/lib
  export _RC_TOOLCHAINS_PATH_DONE=1
fi
EOF

# Fail fast if the swift.org toolchain references any soname the base OS no
# longer provides. Checks all toolchain binaries in one pass.
RUN set -eu; \
    root=/opt/swift; \
    export LD_LIBRARY_PATH="$root/usr/lib/swift/linux:$root/usr/lib"; \
    miss="$(for f in "$root"/usr/bin/*; do [ -f "$f" ] && ldd "$f" 2>/dev/null; done \
        | awk '/not found/{print $1}' | sort -u)"; \
    if [ -n "$miss" ]; then echo "=== MISSING EXTERNAL LIBS ==="; echo "$miss"; exit 1; fi; \
    echo "all toolchain external shared-lib deps resolved"

USER agent
RUN node --version && cargo --version && swift --version

# ── Stage 4: SwiftLint builder ────────────────────────────────────────────────
FROM base AS swiftlint-builder
ARG SWIFTLINT_VERSION
ARG SWIFT_BUILD_JOBS
# Cache the SwiftPM package-source downloads across rebuilds. sharing=locked
# because swiftlint-builder and swiftformat-builder may run in parallel and both
# write to this directory.
RUN --mount=type=cache,uid=1000,gid=1000,sharing=locked,target=/home/agent/.cache/org.swift.swiftpm \
    set -eux; \
    git clone --depth 1 --branch ${SWIFTLINT_VERSION} \
        https://github.com/realm/SwiftLint /tmp/swiftlint; \
    cd /tmp/swiftlint; \
    swift build -c release --product swiftlint -j ${SWIFT_BUILD_JOBS}

# ── Stage 5: SwiftFormat builder ─────────────────────────────────────────────
FROM base AS swiftformat-builder
ARG SWIFTFORMAT_VERSION
ARG SWIFT_BUILD_JOBS
RUN --mount=type=cache,uid=1000,gid=1000,sharing=locked,target=/home/agent/.cache/org.swift.swiftpm \
    set -eux; \
    git clone --depth 1 --branch ${SWIFTFORMAT_VERSION} \
        https://github.com/nicklockwood/SwiftFormat /tmp/swiftformat; \
    cd /tmp/swiftformat; \
    swift build -c release --product swiftformat -j ${SWIFT_BUILD_JOBS}

# ── Stage 6: final image ──────────────────────────────────────────────────────
FROM base AS final

# Install SwiftLint and SwiftFormat from their builder stages.
USER root
COPY --chmod=0755 --from=swiftlint-builder \
    /tmp/swiftlint/.build/release/swiftlint /usr/local/bin/swiftlint
COPY --chmod=0755 --from=swiftformat-builder \
    /tmp/swiftformat/.build/release/swiftformat /usr/local/bin/swiftformat

# ── Smoke test ────────────────────────────────────────────────────────────────
USER agent
RUN node --version \
    && cargo --version \
    && swift --version \
    && swiftlint version \
    && swiftformat --version
