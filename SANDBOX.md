# Docker Sandbox template

A single reusable image that pre-installs the toolchains for the ReadControl
repos, so a fresh [Docker Sandbox](https://docs.docker.com/ai/sandboxes/) is ready
to build/test without per-session setup.

| Repo                    | Pre-installed                                  | Source of truth        |
| ----------------------- | ---------------------------------------------- | ---------------------- |
| `extension`             | Node 24.16.0                                   | `extension/.mise.toml` |
| `core`                  | Rust stable + C toolchain (for `rusqlite`)     | `core/.mise.toml`      |
| `macos`                 | Swift 6.3.2, SwiftLint 0.57.1, SwiftFormat 0.55.6 | `macos/.mise.toml`  |

Node, Rust and Swift are installed directly into the image (Node copied from the
official image, Rust via rustup, Swift from the swift.org tarball) — no mise in
the sandbox. The versions still come from each repo's `.mise.toml`:
`sandbox-build.sh` reads them on the host and passes them to the build. mise
still runs on developers' Macs; it just isn't needed in this Linux image, where
the firewall would block it from fetching anything at runtime anyway.

## Build and load

Run on your **host** (see [Why not inside a sandbox](#why-not-inside-a-sandbox)):

```bash
./scripts/sandbox-build.sh          # docker build + docker image save + sbx template load
```

Or manually, following the
[templates docs](https://docs.docker.com/ai/sandboxes/customize/templates/):

```bash
docker build -t readcontrol/sandbox:1 .
docker image save readcontrol/sandbox:1 -o rc-sandbox.tar
sbx template load rc-sandbox.tar
```

## Use

```bash
sbx run --template readcontrol/sandbox:1 claude
```

To brief the agent that it's in this Linux sandbox (macOS app can't be built
here — only linted/formatted), pass `initial_sandbox_prompt.txt` as the first prompt:

```bash
sbx run --template readcontrol/sandbox:1 claude -- "$(cat initial_sandbox_prompt.txt)" --dangerously-skip-permissions
```

We pass the note at run time rather than baking a Claude Code `SessionStart`
hook into the image: a root-owned `~/.claude/settings.json` in the image makes
the sandbox runtime fail to write that file as the `agent` user on startup, so
the container exits seconds after creation.

The three app repos are mounted into the sandbox at runtime (they are not copied
into the image), so your working tree is live. Inside a sandbox:

```bash
cd extension && npm run test        # Node 24.16.0
cd core      && cargo test           # Rust stable
cd macos     && swiftlint && swiftformat --lint .
```

Tools are on `PATH` in all shell contexts (login, non-login, and the Claude Code
Bash tool) — no `bash -lc` workaround needed.

The image bakes `LINUX_SOURCEKIT_LIB_PATH` (pointing SourceKitten at the Swift
toolchain's sourcekit libs under `/opt/swift/usr/lib`) so SwiftLint works without
manual setup — otherwise SourceKitten misdetects the toolchain and crashes.

## What does NOT work in the sandbox

The sandbox is a **Linux** microVM, so the macOS app cannot be built here:

- No `xcodebuild` / `xcodegen` / Xcode, and no SwiftUI/AppKit — those are
  macOS-only. `make all`, `make dmg`, `make test` in `macos` need a
  real Mac.
- The `core` XCFramework build (`scripts/build-xcframework.sh`,
  Apple-Darwin targets) also needs a Mac — it can't link against the Apple SDK on
  Linux.

What the sandbox *can* do for `macos`: **lint**, **format**, and
compile non-UI Swift logic.

## Notes

- **Architecture:** on Apple Silicon, `docker build` produces an **arm64** image.
  SwiftLint 0.57.1 and SwiftFormat 0.55.6 publish prebuilt Linux binaries for
  x86_64 only, so the Dockerfile **builds them from source** at those exact tags.
  It also copies a few Ubuntu-24.04 sonames the swift.org toolchain needs
  (`libxml2.so.2`, ICU 74, `libpython3.12`) that newer bases no longer ship.
- **Memory:** the SwiftSyntax compile is memory-hungry. The build serializes it
  (`SWIFT_BUILD_JOBS=1`) to avoid OOM, but still give Docker Desktop **≥6–8 GB**
  (Settings → Resources → Memory). With more RAM you can speed it up:
  `docker build --build-arg SWIFT_BUILD_JOBS=4 -t readcontrol/sandbox:1 .`
- **Updating a pinned version:** change it in the relevant repo's `.mise.toml`
  and rebuild — `sandbox-build.sh` reads versions directly from `.mise.toml`.
  The `ARG` defaults in the `Dockerfile` are fallbacks for manual `docker build`
  only; keep them loosely in sync but the script is the source of truth.

## Why not inside a sandbox

Build on your host, not inside a sandbox: the sandbox firewall blocks
`download.swift.org`, `sh.rustup.rs` and the like (HTTP 403), which the build
needs. Your host has open network access.
