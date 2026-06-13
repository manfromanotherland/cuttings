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

Part of the read-later project. Architecture (`AGENTS.md`), the library-format contract, and the
backlog (`TICKETS.md`) live in the project's meta/spec repo.
