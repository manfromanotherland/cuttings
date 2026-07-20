# readcontrol-core

The Rust engine for **Read Control**, a local-first read-it-later system. This repo is a Cargo
workspace containing two crates:

- **`core`** (`readcontrol-core`) — the engine: library scanning/indexing, full-text search
  (SQLite + FTS5), tags, item state, and reading read/write. Embedded by the macOS client via
  UniFFI.
- **`native-host`** — the browser **native messaging host**: receives cleaned Markdown + image
  URLs from the extension and writes them into the library folder (it writes files only, never
  the index).

**License:** MIT — see [LICENSE](./LICENSE).

Part of the **Read Control** project →
[github.com/boniattirodrigo/readcontrol-main](https://github.com/boniattirodrigo/readcontrol-main)
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

## Debugging: SQL tracing

Set the `SQL_TRACE` environment variable to log every executed SQL statement — with its
wall-clock duration and a running counter — to **stderr**. It's a no-op unless the variable is
set, so normal builds pay nothing. Useful for spotting chatty callers and N+1 patterns: a query
that repeats dozens of times per action shows up as an obvious run of identical lines.

```bash
SQL_TRACE=1 cargo test -p readcontrol-core -- --nocapture
```

Each line is one statement SQLite ran (including the FTS-sync triggers). Durations under 1ms are
printed in microseconds for granularity, otherwise in milliseconds:

```
[sql #1  38.00µs] SELECT ... FROM readings WHERE id = ?
[sql #2   1.20ms] SELECT id, title FROM readings ORDER BY saved_at DESC
```

To find the worst offenders, capture stderr to a file and collapse duplicates so the most
frequent statements float to the top:

```bash
SQL_TRACE=1 cargo test -p readcontrol-core -- --nocapture 2> /tmp/sql.log
grep '^\[sql' /tmp/sql.log \
  | sed -E 's/^\[sql #[0-9]+ +[^]]*\] //' \
  | sort | uniq -c | sort -rn | head -20
```

The macOS app embeds this crate, so the same variable works there — see the
[app's README](../readcontrol-macos/README.md#debugging-sql-tracing) for how to launch it with
`SQL_TRACE` set.

## Native messaging host

The native host is what the browser extension talks to when saving a page.

**Build:**
```bash
cargo build -p native-host --release
```

**Install** (writes browser manifest files so Chrome/Edge/Firefox can find the host):
```bash
./target/release/native-host --install-manifest --extension-id <your-32-char-id>
```

This creates `app.readcontrol.host.json` in the appropriate native messaging manifest directories
for Chrome, Edge, Chromium, and Firefox on macOS.

**Wiring the extension ID:** the `--extension-id` value gates which extension may connect — it
becomes `chrome-extension://<id>/` in the manifest's `allowed_origins` (Chrome/Edge) and the
`allowed_extensions` entry (Firefox). Get the ID from `chrome://extensions` after loading the
unpacked extension (see [readcontrol-extension](https://github.com/boniattirodrigo/readcontrol-extension)).

If you omit `--extension-id`, the manifest is written with a placeholder origin
(`chrome-extension://PLACEHOLDER_EXTENSION_ID/`) and the browser will refuse to connect — useful
only as a dry run. Re-run the command whenever the extension ID changes or you rebuild the binary
at a new path (the manifest records the absolute path to the host binary).

## XCFramework (for the macOS app)

The macOS SwiftUI client embeds `readcontrol-core` as an XCFramework via UniFFI bindings.

```bash
./scripts/build-xcframework.sh --release
```

Outputs:
- `dist/ReadControlCore.xcframework` — linkable XCFramework
- `dist/swift/` — generated Swift bindings

The macOS app's `Makefile` (`make xcframework`) runs this automatically.
