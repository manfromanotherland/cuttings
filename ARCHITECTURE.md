# Architecture

ReadControl is three apps that share one data format and one Rust core: a browser **extension**
captures and cleans pages, a **native messaging host** writes them into a plain-file library, and
the **macOS app** (embedding the core) reads and indexes that library. Files are the source of
truth; the index is a disposable, per-device cache.

## How it works

```
 ┌─────────────────┐   cleaned MD + assets    ┌──────────────────────────┐
 │ Browser plugin  │ ───────────────────────▶ │ Native messaging host    │
 │ (extract+clean) │   (native messaging)     │ (wraps core)             │
 └─────────────────┘                          └───────────┬──────────────┘
                                                           │ writes files only
                                                           ▼
                                              ┌──────────────────────────┐
                                              │   Library folder (disk)  │  ◀── user syncs this
                                              │   articles/ assets/ ...  │      (Dropbox/iCloud…)
                                              └───────────┬──────────────┘
                                            file-watch +  │  reconcile on launch
                                                          ▼
 ┌─────────────────┐   UniFFI bindings        ┌──────────────────────────┐
 │  macOS app      │ ◀──────────────────────▶ │  core (Rust)             │
 │  (SwiftUI)      │                          │  index • search • tags   │
 └─────────────────┘                          └───────────┬──────────────┘
                                                          ▼
                                              SQLite + FTS5 (per-device, NOT synced)
```

The plugin extracts and cleans the page (it has the live DOM), then hands the cleaned Markdown and
the captured assets to a small native host that writes them into your library folder. The macOS
app watches that folder and indexes new files for listing, full-text search, and tags — so a page
you saved and a file delivered by sync are handled by the same code path.

## Components

The system is a **polyrepo** — three components in their own repositories, sharing one library
format and one Rust core.

### Browser plugin (`extension`)
- **Responsibility:** extract the readable content of the current page, remove clutter (nav,
  banners, ads, popups, comments), convert to Markdown, and save it into the library.
- **Why cleanup happens here:** the extension has the *live, rendered DOM*, so it sees JS-rendered
  content and pages the user is logged into. The engine never sees the page.
- **Stack:** Manifest V3, TypeScript (Readability-style extraction + HTML→Markdown).
- **Hard constraint:** MV3 extensions can't write files to disk, so saving goes through a **native
  messaging host** — a small native binary (a thin wrapper over `core`) that receives the cleaned
  Markdown + assets and writes them into the library.

### Engine (`core`, Rust)
- **Responsibility:** owns the library format and all logic — scan & index the library, full-text
  search, tags, read/write readings, reconcile changes that arrive via sync.
- **Shape:** a core library crate reused by the other native pieces (the macOS app and the native
  messaging host both link it). Not a long-running daemon.
- **Index:** local SQLite database with FTS5. Rebuildable; per-device; never synced.

### macOS client (`macos`, Swift)
- **Responsibility:** the native UI — browse (All/Unread/Archive/Favorites), read, search, tag, and
  set read/favorite/archive/rating state; appearance settings.
- **Stack:** Swift / SwiftUI, embedding `core` via **UniFFI**-generated bindings.
- **Native rendering only — never a WebView.** The reader renders article Markdown as a native
  SwiftUI view tree via Apple's [`swift-markdown`](https://github.com/apple/swift-markdown) parser —
  proper macOS typography, text selection, Light/Dark, and accessibility with no web engine and no
  script-execution surface. The UI is specified in [DESIGN.md](./DESIGN.md).
- Owns the local index and watches the library folder for changes (including files arriving via
  sync), reindexing incrementally.

### Why this shape
- One writer to the index (the app), so no SQLite contention. The host only writes files; the app
  picks them up via its folder watcher.
- The same Rust core powers both the save path and the UI — no duplicated logic.
- The index is fully rebuildable, so a fresh sync on a new device "just works" after a scan.

## Data model — the library

Each reading is a Markdown file with YAML frontmatter, under a **library folder** the user chooses
and syncs:

```
<library-root>/
  articles/<id>.md          # one reading per file (Markdown + YAML frontmatter)
  assets/<id>/<hash>.<ext>  # captured images, relative-linked from the .md
  highlights/<id>.md        # optional — the reading's saved highlights
  originals/<id>.html       # optional — raw HTML snapshot for re-processing
```

- **Frontmatter is the source of truth** for metadata (title, tags, read/archive/favorite/rating
  state, …). The full, versioned schema is [`docs/library-format.md`](./docs/library-format.md); the
  native-messaging contract is [`docs/native-messaging.md`](./docs/native-messaging.md).
- **The index DB is a disposable cache** — derived from the files, rebuildable by re-scanning, and
  stored **outside** the library (per-device, never synced).
- **Mutations are file-first, index-second, and atomic.** Every metadata setter writes the `.md`
  frontmatter first, then syncs the derived index row from the re-read file. A folder watcher
  reconciles the index *from* the files, so writing the DB first would be clobbered on the next
  reconcile — treat each setter as one indivisible "persist" step.
