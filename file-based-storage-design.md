# File-Based Storage Design

## Goal

Implement a file-based storage system where the **files are the source of truth** and **SQLite is only a cache/search index** that can always be rebuilt from the files.

## Object Identity

Use the **SHA-256 hash of the canonical URL** as the primary identifier for every saved page.

```
id = SHA256(canonical_url)
```

This ID should be used for:

* Filename
* Primary key in SQLite
* Browser extension lookup
* Internal references

Because the ID is deterministic, saving the same URL twice produces the same ID and prevents duplicate files.

## URL Canonicalization

Before hashing, normalize the URL so equivalent URLs generate the same ID.

Canonicalization should:

* Lowercase the scheme and hostname.
* Remove default ports (`:80` for HTTP, `:443` for HTTPS).
* Remove the URL fragment (`#...`).
* Remove **known tracking query parameters** (e.g. `utm_*`, `fbclid`, `gclid`, `msclkid`, `mc_cid`, `mc_eid`).
* **Preserve query parameters that are part of the resource identity.** For example, `?q=rust`, `?v=abc123`, or `?page=2` should remain because they identify different content.
* Sort the remaining query parameters into a deterministic order so equivalent URLs produce the same canonical representation.
* Normalize trailing slashes where appropriate.

**Important:** Do **not** remove all query parameters. Only remove parameters known to be used for tracking or analytics. Many websites rely on query parameters to identify the actual resource, and stripping them would incorrectly merge distinct pages.

The canonicalization function should be centralized and versioned so it can evolve without affecting unrelated code.

## File Layout

Each reading is a **self-contained folder** whose name is the reading's id, placed
under a two-character fan-out bucket so no single directory grows huge. Everything
that belongs to one reading — its article file, captured images, and highlights —
lives inside that one folder.

```
articles/
    8f/
        8f4b0d9a3d.../
            article.md          # frontmatter + cleaned Markdown body
            assets/             # captured images, linked as assets/<file>
                <sha256>.<ext>
            highlights.md       # optional — the reading's saved highlights
    c2/
        c2a91ef8b1.../
            article.md
```

The first two characters of the SHA-256 id are the bucket directory name; the full
id is the reading-folder name. Because assets sit *beside* `article.md`, image
links are simply `assets/<file>` — relative to the article file, with no `../`
climbing. Making a reading one folder also makes two operations trivial: **moving**
a reading is a single directory move, and **deleting** one is a single
`remove_dir_all` of its folder (guarded so a malformed id can never target a
bucket or the `articles/` root — see the engine's `delete_reading`).

## File Contents

Each file should contain all metadata required to reconstruct the application state.

Example:

```yaml
---
id: 8f4b0d9a3d...
url: https://example.com/article
saved_at: 2026-08-03T23:41:12Z
title: Example Article
tags:
  - ai
  - rust
---
```

The file should contain at least:

* id
* canonical URL
* original URL (if different)
* saved timestamp
* title
* tags
* other metadata needed by the application

Do **not** rely on filesystem creation timestamps, since they are not portable or reliable across platforms.

## Browser Extension

When the extension loads a page:

1. Read the current URL.
2. Canonicalize it.
3. Compute SHA-256.
4. Check whether the corresponding file exists.
5. If it exists, display "Already Saved".

This avoids querying SQLite entirely.

## SQLite

SQLite is **not** the source of truth.

It is a disposable cache used for:

* Full-text search (FTS5)
* Fast metadata queries
* Sorting and filtering
* Search indexes
* Future embeddings or semantic search

The database should contain records keyed by the same SHA-256 ID.

If the database is deleted or corrupted, it must be rebuilt by scanning all files.

## Collision Handling

SHA-256 collisions are effectively impossible for this application.

For additional safety:

* If a file already exists for a computed hash, read its stored canonical URL.
* Verify it matches the computed canonical URL.
* If it does, treat the page as already saved.
* If it does not, report a hash collision or data corruption (this should never occur in practice).

## Advantages

* Files are the single source of truth.
* SQLite can always be regenerated.
* Duplicate URL detection is deterministic.
* Browser extension performs an O(1)-style lookup (hash + file existence check).
* No separate URL-to-ID mapping is required.
* Architecture remains simple, portable, and resilient.

## Implementation status & known gaps

Implemented on branch `content-addressed-storage` (in the `core` repo): content-addressed ids
(`SHA256(normalize(visited url))`), the fan-out layout, an O(1) `find_by_url` (hash the URL → `stat`
one file, no scan), and extended URL normalization (`www.`, default ports, sorted params).

Identity is the **normalized visited URL**, not the page's `rel=canonical` — the toolbar only knows
the address-bar URL and can't read a page's canonical link without extraction. `canonical_url` is
still stored as metadata, just not used as the key. Accepted trade-off: the same content reached via
two different normalized URLs can be saved twice (a harmless duplicate entry).

### How the index (SQLite) stays in sync
The host writes files only; it never touches the DB. Sync is file-driven: the macOS app's
`FolderWatcher` watches `articles/` with FSEvents (which is **recursive**, so an `article.md` landing
in a fan-out reading folder still fires the callback) → `rebuild()` → Rust `scan_library` (walks
`articles/<bucket>/<reading>/article.md`) → `diff` + `apply_diffs` reconcile the on-disk snapshot
into SQLite by `id` + `source_hash`. This path works for the normal save flow.

### The two follow-ups are resolved by the per-reading folder

An earlier iteration kept three parallel top-level trees (`articles/`, `assets/`, `highlights/`) and
put the article file one directory deeper as `articles/<prefix>/<id>.md`. That created two macOS-side
bugs — broken image links and an invisible, re-seeding welcome article. Consolidating each reading
into a single folder (`articles/<prefix>/<id>/`) dissolves both at the source rather than patching
each symptom:

**1. Reader images — fixed by co-locating assets with the article.**
Assets now live in `assets/` *beside* `article.md`, so the emitted link is just `assets/<file>` —
relative to the article file, no `../` to climb. The core `write_images` emits that link, and the
reader resolves it against the reading's own folder. `AssetImageLoader` gained a
`readingFolderURL(libraryURL:readingID:)` helper (the one place that knows the fan-out layout) and
`localURL(source:assetBaseURL:)` resolves the relative link under it; the reader threads the reading's
folder URL (`assetBaseURL`) down instead of the library root.

**2. Welcome seed — fixed by content-addressing it through the standard layout.**
`WelcomeArticle.swift` now hashes its source URL (`SHA256(normalize("https://readcontrol.app/welcome"))`,
matching core's `url_id`) to get a real content-addressed id, and writes to the standard
`articles/<prefix>/<id>/article.md` with its highlight at `.../highlights.md`. The scanner therefore
indexes it like any reading, and because the id is now the content address, a later save of the same
URL dedupes against it. The "is the library empty?" check walks the two shallow fan-out levels for an
`article.md`, so seeding never fires into a populated library and the welcome folder counts as a
reading (no re-seed).

There is **no** need to make `scan_library` tolerate a stray top-level `.md`: writers always use the
per-reading folder, so the reader can key strictly on `articles/<bucket>/<reading>/article.md`.

### Deleting a reading
Because a reading is one folder, delete is one `remove_dir_all` of `articles/<prefix>/<id>/` (taking
`article.md`, `assets/`, and `highlights.md` with it), followed by dropping the index row. To keep a
folder-level delete from ever removing more than one reading, `delete_reading` guards the target: the
id must be non-empty and ASCII-alphanumeric (no `/`, `.`, or `..` to escape the folder), the folder
must still contain an `article.md`, and it must sit two levels below `articles/` (never the
`articles/` root or a bucket directory).
