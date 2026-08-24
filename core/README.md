# Cuttings core

The Rust engine for **Cuttings**, the native macOS reading manager. This monorepo component is a
Cargo workspace containing:

- **`core`** (`cuttings-core`) — the engine: library scanning/indexing, full-text search
  (SQLite + FTS5), tags, item state, and reading read/write. Embedded by the macOS client via
  UniFFI.
- **`native-host`** (`cuttings-native-host`) — the browser **native messaging host**: receives
  cleaned Markdown + image URLs from the extension and writes them into the library folder
  (files only, never the index).

## Prerequisites

- [Rust](https://rustup.rs) (stable toolchain via `rustup`)
- For the macOS XCFramework build: `rustup target add aarch64-apple-darwin x86_64-apple-darwin`

## Build & test

```bash
cargo build
cargo test
cargo clippy --all-targets --all-features -- -D warnings
cargo fmt --check
```

## Native messaging host

The native host is what the browser extension talks to when saving a page.

```bash
cargo build -p cuttings-native-host --release

# install browser manifests so Chrome/Edge/Firefox can find the host:
./target/release/cuttings-native-host --install-manifest --extension-id <your-32-char-id>
```

The `--extension-id` gates which extension may connect (get it from `chrome://extensions` after
loading the unpacked Cuttings extension). Re-run it whenever the ID changes or you rebuild the
binary at a new path.

## XCFramework (for the macOS app)

The macOS client embeds `core` as an XCFramework via UniFFI bindings:

```bash
./scripts/build-xcframework.sh --release   # outputs dist/CuttingsCore.xcframework + dist/swift/
```

The macOS app's `Makefile` (`make xcframework`) runs this automatically.

## Debugging: SQL tracing

Set `SQL_TRACE=1` to log every executed SQL statement (with duration) to **stderr** — useful for
spotting chatty callers and N+1 patterns. It's a no-op when unset.

```bash
SQL_TRACE=1 cargo test -p cuttings-core -- --nocapture
```

The macOS app embeds this crate, so the same variable works there too.
