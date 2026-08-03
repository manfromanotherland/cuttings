# Library Format Specification

**Version:** `1`  
**Status:** implemented — the contract the shipped components (`core`, `extension`, `macos`) conform to.

This document is the **shared contract** between all ReadControl components. Every component that
reads or writes library files must conform to it. Treat breaking changes as a major version bump;
announce them in all three repos.

---

## Folder layout

```
<library-root>/
  articles/
    <id>.md               # one reading per file (Markdown + YAML frontmatter)
  assets/
    <id>/
      <sha256>.<ext>      # captured image for that reading
  highlights/
    <id>.md               # optional — the reading's saved highlights (§ Highlights)
  originals/              # optional — raw HTML snapshot for future re-processing
    <id>.html
```

- `<library-root>` is the folder the user chooses (Dropbox, iCloud Drive, Google Drive, etc.).
- The per-device SQLite index lives **outside** this folder (e.g.
  `~/Library/Application Support/ReadControl/`) and is **never synced**.
- Paths stored in the database must be **relative to the library root** — never absolute.

---

## Article file (`articles/<id>.md`)

Each saved reading is a single UTF-8 Markdown file with YAML frontmatter.

### Frontmatter schema

```yaml
---
format_version: 1                          # integer — bumped on breaking schema changes
id: 01J9Z8X7Q2VBKN3P4HXYZ01AB             # ULID (see § ID scheme) — also the filename stem
url: https://example.com/post/slug         # original URL as visited
canonical_url: https://example.com/post/slug  # normalized URL (see § URL normalization)
title: The Title of the Article            # required; extracted from page or og:title
author: Jane Doe                           # optional; extracted byline
site: example.com                          # eTLD+1 of canonical_url
saved_at: 2026-06-13T15:00:00Z            # ISO-8601 UTC; set once at save time; never updated
read_at: 2026-06-14T09:00:00Z             # optional ISO-8601 UTC; present == read, absent == unread
archived: false                            # bool — moved out of the active list?
favorite: false                            # bool — starred?
rating: 0                                  # integer 0–5; 0 means unrated
tags: [rust, local-first]                  # string[]; elements are lowercase, no spaces
excerpt: One-sentence summary.             # optional; shown in the list view
word_count: 1234                           # integer; word count of the cleaned body
lang: en                                   # BCP-47 language tag; optional
source_hash: sha256:abc123...              # sha256 of the cleaned Markdown body (hex); for change detection
---
```

#### Required fields
`format_version`, `id`, `url`, `canonical_url`, `title`, `saved_at`, `archived`, `favorite`,
`rating`, `tags`, `source_hash`.

#### Optional fields
`author`, `site`, `read_at`, `excerpt`, `word_count`, `lang`.

#### Rules
- `saved_at` is set once at save time and **never updated**, even when metadata is edited.
- **Read state is the presence of `read_at`**: a timestamp means read (its value is when it was
  last marked read); an absent field means unread. There is no separate `read` boolean.
- `archived`, `favorite`, and `rating` are the source of truth for those states — the DB mirrors them.
- `tags` elements must be lowercase, trimmed, and contain no spaces (use `-` as separator).
- `source_hash` is recomputed on any edit to the body; the DB uses it to detect stale index entries.

### Body

The article body follows immediately after the closing `---` of the frontmatter, separated by a
blank line. It is **Markdown** (CommonMark), cleaned of navigation, ads, banners, and popups.

- The body carries **no top-level `#` heading**: the frontmatter `title` is the reading's single
  title, which the reader renders as the sole h1. The extension demotes any `#` the source used to
  `##`, so body headings start at `##`.
- Image references use **relative paths** pointing into `../assets/<id>/`: e.g.
  `![alt](../assets/01J9Z8X7Q2VBKN3P4HXYZ01AB/3f4a1b.jpg)`.
- Do not embed images as base64.

---

## Complete example

```
articles/01J9Z8X7Q2VBKN3P4HXYZ01AB.md
```

```markdown
---
format_version: 1
id: 01J9Z8X7Q2VBKN3P4HXYZ01AB
url: https://blog.example.com/posts/local-first?utm_source=hn
canonical_url: https://blog.example.com/posts/local-first
title: Local-First Software
author: Martin Kleppmann
site: blog.example.com
saved_at: 2026-06-13T15:00:00Z
archived: false
favorite: false
rating: 0
tags: [local-first, distributed-systems]
excerpt: An argument for software that works offline and gives users ownership of their data.
word_count: 3812
lang: en
source_hash: sha256:e3b0c44298fc1c149afb4c8996fb92427ae41e4649b934ca495991b7852b855
---

An argument for software that works offline and gives users ownership of their data.

## Ownership

Paragraph text…

![Diagram](../assets/01J9Z8X7Q2VBKN3P4HXYZ01AB/3f4a1b.jpg)

More content…
```

---

## Asset files (`assets/<id>/<sha256>.<ext>`)

- One sub-folder per reading, named with the reading's `id`.
- Filename is the **lowercase hex SHA-256** of the file's raw bytes, with an extension chosen from
  the image's `Content-Type` (falling back to the URL): e.g. `3f4a1b8e....jpg`.
- Images are **captured by the browser extension** (from the page's cache where possible) and sent
  to the host, which only writes them — the host performs no network requests. An image the
  extension couldn't capture is left as a remote URL in the Markdown and is never re-fetched; the
  reader shows a labelled placeholder for it.
- The `originals/` folder is optional. If kept, `originals/<id>.html` holds the raw HTML
  snapshot at save time for future re-processing.

---

## Highlights (`highlights/<id>.md`)

A reading's saved highlights live in `highlights/<id>.md` — one file per reading, absent when the
reading has none. Each highlight is the verbatim selected text as a Markdown block quote, ended by
an HTML comment carrying a stable id:

```markdown
> The exact text the user highlighted.
<!-- hl 01J9Z8X7Q2VBKN3P4HXYZ01AB -->
```

The library scanner only walks `articles/`, so highlight files are never mistaken for readings.

---

## ID scheme

IDs are **ULIDs** (Universally Unique Lexicographically Sortable Identifiers):

- 26 characters, Crockford Base32, e.g. `01J9Z8X7Q2VBKN3P4HXYZ01AB`.
- Monotonically sortable by creation time — the file list sorted by filename is automatically
  sorted by save date.
- The ULID is the **filename stem** (`<id>.md`) and the frontmatter `id` field. They must match.

---

## URL normalization (`canonical_url`)

The `canonical_url` is used for deduplication. Apply these rules in order to produce it from the
`url`:

1. Prefer `<link rel="canonical">` or `og:url` from the page; fall back to the browser URL.
2. Lowercase the scheme and host.
3. Strip tracking query parameters: `utm_*`, `fbclid`, `gclid`, `mc_cid`, `mc_eid`, `ref`,
   `source`, `campaign` (exact match).
4. Strip the fragment (`#...`).
5. Remove a trailing `/` from the path **unless** the path is just `/`.
6. Do not strip other query parameters — they may be meaningful (pagination, article IDs).

The original `url` (pre-normalization) is always preserved separately.

---

## Smart-view semantics

The macOS app's sidebar views are defined by frontmatter field values:

| View | Filter |
|------|--------|
| **All** | `archived == false` |
| **Unread** | `archived == false AND read_at is absent` |
| **Archive** | `archived == true` |
| **Favorites** | `favorite == true` (regardless of archived) |

---

## Format versioning

- `format_version` starts at `1`.
- **Additive changes** (new optional frontmatter fields, new asset conventions) are backwards
  compatible — do not bump the version.
- **Breaking changes** (renamed/removed required fields, changed semantics) bump the integer.
- Readers must reject files with a `format_version` higher than the version they support, rather
  than silently misread them.
- All three repos (`core`, `extension`, `macos`) must be
  updated in lockstep on a version bump.

---

## What lives in the library vs. outside it

| Belongs in library (synced) | Belongs outside library (per-device, never synced) |
|-----------------------------|----------------------------------------------------|
| `articles/*.md` | SQLite index (`~/Library/Application Support/ReadControl/`) |
| `assets/<id>/*` | App preferences (theme, font, library path) |
| `highlights/<id>.md` | Native messaging host manifest |
| `originals/<id>.html` (optional) | |
