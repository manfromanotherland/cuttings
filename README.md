# read-later-core

The Rust engine for **read-later**, a local-first read-it-later system. This repo is a Cargo
workspace containing two crates:

- **`core`** (`read-later-core`) — the engine: library scanning/indexing, full-text search
  (SQLite + FTS5), tags, item state, and reading read/write. Embedded by the macOS client via
  UniFFI.
- **`native-host`** — the browser **native messaging host**: receives cleaned Markdown + image
  URLs from the extension and writes them into the library folder (it writes files only, never
  the index).

**License:** MIT — see [LICENSE](./LICENSE).

Part of the **read-later** project →
[github.com/boniattirodrigo/read-later-main](https://github.com/boniattirodrigo/read-later-main)
(architecture, library-format contract, design, and backlog).

## Prerequisites

- [Rust](https://rustup.rs) (stable toolchain via `rustup`)
- For building the XCFramework (macOS app only): Apple silicon + Intel targets

```bash
rustup target add aarch64-apple-darwin x86_64-apple-darwin
```

## Build & test

```bash
cargo build
cargo test
cargo clippy --all-targets --all-features -- -D warnings
cargo fmt --check
```

## Native messaging host

The native host is what the browser extension talks to when saving a page.

**Build:**
```bash
cargo build -p native-host --release
```

**Install** (writes browser manifest files so Chrome/Edge/Firefox can find the host):
```bash
./target/release/native-host --install
```

This creates `com.readlater.host.json` in the appropriate native messaging manifest directories
for Chrome, Edge, Chromium, and Firefox on macOS.

## XCFramework (for the macOS app)

The macOS SwiftUI client embeds `read-later-core` as an XCFramework via UniFFI bindings.

```bash
./scripts/build-xcframework.sh --release
```

Outputs:
- `dist/ReadLaterCore.xcframework` — linkable XCFramework
- `dist/swift/` — generated Swift bindings

The macOS app's `Makefile` (`make xcframework`) runs this automatically.
