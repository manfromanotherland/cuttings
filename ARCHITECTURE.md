# Architecture

Cuttings is three apps that share one data format and one Rust core: a browser **extension**
captures cleaned articles, standalone media, and selected-text quotes; a **native messaging host**
writes them into a plain-file library; and the **macOS app** (embedding the core) both accepts
paste/drop saves and shows the library as a visual card board. Files are the source of truth; the
index is a disposable, per-device cache.

## How it works

```
 ┌─────────────────┐   cleaned MD + assets    ┌──────────────────────────┐
 │ Browser ext.    │ ───────────────────────▶ │ Native messaging host    │
 │ (capture cards) │   (native messaging)     │ (wraps core)             │
 └─────────────────┘                          └───────────┬──────────────┘
                                                           │ writes files only
                                                           ▼
                                              ┌──────────────────────────┐
                                              │   Library folder (disk)  │  ◀── user syncs this
                                              │   articles/ assets/ ...  │      (Dropbox/iCloud…)
                                              └───────────┬──────────────┘
                                         write + watch +  │  reconcile on launch
                                                          ▼
 ┌─────────────────┐   UniFFI saves/queries   ┌──────────────────────────┐
 │  macOS app      │ ◀──────────────────────▶ │  core (Rust)             │
 │ paste/drop + UI │                          │ save • index • search   │
 └─────────────────┘                          └───────────┬──────────────┘
                                                          ▼
                                              SQLite + FTS5 (per-device, NOT synced)
```

The extension either extracts and cleans the current page, captures the right-clicked image, records
a right-clicked video plus its poster, or turns selected text into a quote. It hands Markdown,
metadata, and captured image bytes to a small native host that writes them into the library folder.
The macOS app also accepts dropped or pasted HTTP(S) links, text, and images. Both native entry
points call the same core save service: local bytes are copied into the library, source-less items
receive a private deterministic identity, and URL-only saves are marked lightweight so a later
full browser capture upgrades them. The app watches the folder and indexes every new file for the
masonry board, full-text search, type filters, and tags — so browser saves, in-app saves, and files
delivered by sync reconcile through the same index path.

Every card kind records its origin page in `url`/`canonical_url` plus its page title/site and save
date. `media_url` stores a durable image/video address in addition to that origin. If a video only
exposes a session-local `blob:`/`data:` source, the extension stores a compact opaque capture
reference for identity and links playback back to the origin page. It never substitutes a
CDN/media address for the origin page.

## Components

The system is a **monorepo** with three top-level components sharing one library format and one
Rust core. Keeping them in one Git history lets protocol and format changes land atomically across
every affected component.

### Browser extension (`extension`)
- **Responsibility:** extract readable page content; capture a selected image; record a selected
  video and poster; or capture selected text as a quote. Every path produces Markdown plus origin
  metadata and any local image bytes needed by the card.
- **Why cleanup happens here:** the extension has the *live, rendered DOM*, so it sees JS-rendered
  content and pages the user is logged into. The engine never sees the page.
- **Stack:** Manifest V3, TypeScript (Readability-style extraction + HTML→Markdown).
- **Hard constraint:** MV3 extensions can't write files to disk, so saving goes through a **native
  messaging host** — a small native binary (a thin wrapper over `core`) that receives the cleaned
  Markdown + assets and writes them into the library.
- **Video boundary:** direct video files and streams are not downloaded into the library. The card
  stores the page origin, a durable media URL when available (otherwise an identity-only capture
  reference), and a locally captured poster when available.

### Engine (`core`, Rust)
- **Responsibility:** owns the library format and all logic — validate and write extension or
  paste/drop saves, scan and index the library, full-text search, tags, personal Markdown notes,
  and reconcile changes that arrive via sync.
- **Shape:** a core library crate reused by the other native pieces (the macOS app and the native
  messaging host both link it). Not a long-running daemon.
- **Index:** local SQLite database with FTS5. Rebuildable; per-device; never synced.

### macOS client (`macos`, Swift)
- **Responsibility:** the native UI — browse a mixed masonry board, filter by favorites, card kind,
  and tag, open articles, inspect images/videos/quotes, search, favorite, and save supported
  drop/paste payloads; appearance settings.
- **Stack:** Swift / SwiftUI, embedding `core` via **UniFFI**-generated bindings.
- **Native rendering only — never a WebView.** The reader renders article Markdown as a native
  SwiftUI view tree via Apple's [`swift-markdown`](https://github.com/apple/swift-markdown) parser —
  proper macOS typography, text selection, Light/Dark, and accessibility with no web engine and no
  script-execution surface. The UI is specified in [DESIGN.md](./DESIGN.md).
- Card detail is a full-window native overlay: the existing Markdown reader handles articles and
  quote bodies; image/video cards use local preview assets and source/media actions. Every detail
  inspector exposes the origin page when one exists, identifies source-less cards as saved locally,
  and can edit that reading's personal Markdown note.
- Owns the local index and watches the library folder for changes (including files arriving via
  sync), reindexing incrementally.

### Why this shape
- One writer to the index (the app), so no SQLite contention. The host only writes files; the app
  picks them up via its folder watcher.
- The same Rust core powers both the save path and the UI — no duplicated logic.
- The index is fully rebuildable, so a fresh sync on a new device "just works" after a scan.

## Data model — the library

Each reading is a **self-contained folder** under a **library folder** the user chooses and syncs.
The folder is named by a deterministic content-addressed id under a two-character fan-out bucket so
no directory grows unbounded, and it holds everything for that reading:

```
<library-root>/
  articles/
    <prefix>/                 # first 2 chars of the id (fan-out bucket)
      <id>/                   # one folder per reading
        article.md            # Markdown body + YAML frontmatter (source of truth)
        assets/<hash>.<ext>   # captured images, linked as assets/<file> from article.md
        highlights.md         # optional — the reading's saved highlights
        note.md               # optional — the user's personal Markdown note
        original.html         # optional — raw HTML snapshot for re-processing
```

Keeping a reading in one folder makes image links trivially relative (`assets/<file>`, no `../`),
makes a reading one movable unit, and makes deletion a single guarded folder removal. Article
identity remains the normalized visited URL. Image/video identity combines the kind, normalized
origin page, and media identity. That identity is the durable media URL or, for session-local video
streams, a stable page-and-element reference. Quote identity combines the normalized origin page
and normalized selected Markdown. Exact repeat saves therefore deduplicate while multiple clips
from one page can coexist. Source-less pasted text and images use content-derived local identities;
their stored `cuttings://local/...` URLs are internal provenance, never openable web sources.

The optional `note.md` is a user-authored sidecar, kept separate from the captured article body and
its source hash. The core reads and atomically replaces it directly; blank Markdown removes it. It
is synced as part of the reading folder but is not mirrored in SQLite or included in full-text
search. Folder-watcher events still invalidate an open note even when the indexed article is
unchanged, and the editor requires an explicit choice before replacing a newer on-disk version.

The card metadata is additive and backwards compatible:

- `kind`: `article`, `image`, `video`, or `quote` (missing means `article`).
- `media_url`: optional image/video identity: normally a durable direct address, or an opaque stable
  reference for a session-local video stream. The page origin remains in `url`.
- `preview_asset`: optional safe `assets/<file>` path derived after the host writes captured image
  bytes. It drives the board thumbnail and is never a remote URL.
- `lightweight`: optional `true` marker for a URL-only app save. A later full browser capture
  replaces that placeholder at the same article id and clears the marker while preserving user
  state.

- **Frontmatter is the source of truth** for metadata (title, tags, favorite state, and legacy
  format-v1 state fields). The full, versioned schema is [`docs/library-format.md`](./docs/library-format.md); the
  native-messaging contract is [`docs/native-messaging.md`](./docs/native-messaging.md).
- **The index DB is a disposable cache** — derived from the files, rebuildable by re-scanning, and
  stored **outside** the library (per-device, never synced).
- **Mutations are file-first, index-second, and atomic.** Every metadata setter writes the `.md`
  frontmatter first, then syncs the derived index row from the re-read file. A folder watcher
  reconciles the index *from* the files, so writing the DB first would be clobbered on the next
  reconcile — treat each setter as one indivisible "persist" step.
