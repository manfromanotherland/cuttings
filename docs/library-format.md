# Library Format Specification

**Version:** `1`  
**Status:** implemented — the contract the shipped components (`core`, `extension`, `macos`) conform to.

This document is the **shared contract** between all Cuttings components. Every component that
reads or writes library files must conform to it. Treat breaking changes as a major version bump;
land them across all affected components in the same monorepo commit.

---

## Folder layout

```
<library-root>/
  .cuttings-locks/            # persistent operational advisory-lock sidecars
    <prefix>/                 # first 2 chars of SHA-256(reading id)
      <sha256-id>.lock        # empty; one stable lock inode per reading id
  articles/
    <prefix>/                 # first 2 chars of the id — a fan-out bucket
      <id>/                   # one self-contained folder per reading
        article.md            # the reading (Markdown + YAML frontmatter)
        assets/
          <sha256>.<ext>      # captured image, linked as assets/<file>
        highlights.md         # optional — the reading's saved highlights (§ Highlights)
        note.md               # optional — the user's personal Markdown note (§ Personal note)
        original.html         # optional — raw HTML snapshot for future re-processing
```

- `<library-root>` is the folder the user chooses (Dropbox, iCloud Drive, Google Drive, etc.).
- Each reading is one folder named by its id (see § ID scheme), under a two-character fan-out
  bucket so no directory grows unbounded. Everything for the reading lives inside it, so moving or
  deleting a reading is a single folder operation.
- The per-device SQLite index lives **outside** this folder (e.g.
  `~/Library/Application Support/Cuttings/`) and is **never synced**.
- Paths stored in the database must be **relative to the library root** — never absolute.
- `.cuttings-locks/` contains empty advisory-lock sidecars used to serialize Cuttings writers that
  share a library on one machine. They live outside reading folders so deleting a reading cannot
  replace its lock inode while another process is waiting. Sidecars deliberately persist after an
  operation or deletion, are not reading data, and are ignored by the scanner; syncing their empty
  files does not carry a live OS lock to another device.

---

## Article file (`articles/<prefix>/<id>/article.md`)

Each saved reading is a single UTF-8 Markdown file named `article.md` inside the reading's folder,
with YAML frontmatter.

### Frontmatter schema

```yaml
---
format_version: 1                          # integer — bumped on breaking schema changes
id: 1146c9a93631d1991af3252dbc49ecd8043ab354a4386e397d555d1ca21a7199  # content-addressed (see § ID scheme) — also the reading-folder name
url: https://example.com/post/slug         # original URL as visited
canonical_url: https://example.com/post/slug  # the page's own canonical URL when known (see § URL normalization)
title: The Title of the Article            # required; extracted from page or og:title
kind: article                              # article | image | video | quote; missing means article
lightweight: true                          # optional; URL-only app save awaiting full capture
media_url: https://cdn.example.com/image.jpg  # optional media identity; never the origin
preview_asset: assets/3f4a1b8e....jpg      # optional local card preview written by the host
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
`kind`, `lightweight`, `media_url`, `preview_asset`, `author`, `site`, `read_at`, `excerpt`,
`word_count`, `lang`.

`kind` is written for every new card but remains optional in the parser for backwards compatibility;
an older file without it is an `article`. `lightweight` is omitted/false for ordinary captures and
is true only for a URL-only paste/drop card.

#### Rules
- `saved_at` is set once at save time and **never updated**, even when metadata is edited.
- For a web save, `url`, `canonical_url`, `title`, and `site` describe the **origin page**. A media
  card's asset identity belongs in `media_url`; it never replaces the origin. A source-less local
  text/image save uses a deterministic `cuttings://local/...` URL in the two required URL fields,
  leaves `site` unset, and is presented as saved locally rather than as an openable web source.
- `lightweight: true` means the app had only an HTTP(S) URL, so the body is a link rather than
  cleaned page content. A later full browser capture at the same URL replaces the captured
  metadata/body and clears this marker while preserving `saved_at`, state, rating, and tags.
- `kind` is one of `article`, `image`, `video`, or `quote`.
- `media_url` is meaningful only for `image` and `video` cards. It is normally a durable HTTP(S)
  direct URL. When a video only exposes a session-local `blob:`/`data:` source, the extension stores
  a compact opaque `cuttings-video:` reference instead; raw transient URLs are never persisted.
- `preview_asset`, when present, must be the safe single-file shape `assets/<filename>`. It is
  derived only after captured image/poster bytes are written locally; it is never an HTTP URL.
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
- Image references use **relative paths** into the reading's own `assets/` folder: `assets/<file>`
  (the article file and its `assets/` folder are siblings), e.g. `![alt](assets/3f4a1b.jpg)`.
- Do not embed images as base64.
- An **image** body is a Markdown image whose captured source is rewritten to the local asset.
- A **video** body may contain its local poster plus a link to the durable media URL. For a
  session-local stream it links to the origin page instead. Video bytes are not downloaded.
- A **quote** body contains the selected text as Markdown block quotes. Its `excerpt` may carry a
  bounded preview for the board, but the body remains the full selection.
- A **lightweight article** body is one Markdown link to its HTTP(S) URL. It is intentionally
  distinguishable from a full extension capture and may later be upgraded in place.

---

## Complete example

```
articles/11/1146c9a93631d1991af3252dbc49ecd8043ab354a4386e397d555d1ca21a7199/article.md
```

```markdown
---
format_version: 1
id: 1146c9a93631d1991af3252dbc49ecd8043ab354a4386e397d555d1ca21a7199
url: https://blog.example.com/posts/local-first?utm_source=hn
canonical_url: https://blog.example.com/posts/local-first
title: Local-First Software
kind: article
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

![Diagram](assets/3f4a1b.jpg)

More content…
```

---

## Asset files (`articles/<prefix>/<id>/assets/<sha256>.<ext>`)

- Each reading's images live in an `assets/` sub-folder inside the reading's own folder, beside
  `article.md`, and are linked from the body as `assets/<file>`.
- Filename is the **lowercase hex SHA-256** of the file's raw bytes, with an extension chosen from
  the image's `Content-Type` (falling back to the URL): e.g. `3f4a1b8e....jpg`.
- Article images and video posters are **captured by the browser extension** (from the page's cache
  where possible) and sent to the host. Standalone images may also arrive from the app's paste/drop
  path. Both adapters hand bytes to the same core writer; the core performs no network requests. An
  image the extension couldn't capture is left as a remote URL in the Markdown and is never
  re-fetched; the reader shows a labelled placeholder for it.
- The original HTML snapshot is optional. If kept, it lives as `original.html` inside the reading's
  folder for future re-processing.

---

## Highlights (`articles/<prefix>/<id>/highlights.md`)

A reading's saved highlights live in `highlights.md` inside the reading's folder — one file per
reading, absent when the reading has none. Each highlight is the verbatim selected text as a
Markdown block quote, ended by an HTML comment carrying a stable id:

```markdown
> The exact text the user highlighted.
<!-- hl 01J9Z8X7Q2VBKN3P4HXYZ01AB -->
```

The scanner keys on the fixed `article.md` name, so a reading's `highlights.md` (and its `assets/`)
are never mistaken for readings.

---

## Personal note (`articles/<prefix>/<id>/note.md`)

A reading may have one personal note. It is a plain UTF-8 CommonMark document with no frontmatter,
stored as `note.md` beside the reading's article file and highlights. The app preserves the user's
Markdown as written and replaces the whole file atomically when saving. Saving an empty or
whitespace-only note removes the optional file.

The note is separate from the captured body: editing it never changes `article.md` or that file's
`source_hash`. It is read directly from the reading folder and is not mirrored in the disposable
index or included in full-text search. As with `highlights.md`, the scanner's fixed `article.md`
entry point ensures a note is never mistaken for another reading.

---

## ID scheme

A **reading id** is a deterministic lowercase-hex SHA-256 content address. The identity input
depends on the card kind:

- **Article:** normalized origin `url` (the existing `url_id` behavior).
- **Image/video:** kind + normalized origin `url` + `media_url` identity (a durable direct URL or a
  stable opaque reference for a session-local video).
- **Quote:** normalized origin `url` + normalized selected Markdown body.
- **Source-less text:** a `cuttings://local/quote/<hash>` origin derived from whitespace-normalized
  text, then the ordinary quote identity rule. Whitespace-only variations deduplicate.
- **Source-less image:** a `cuttings://local/image/<hash>` origin/media identity derived from the
  validated imported image bytes, then the ordinary image identity rule. File names do not affect
  identity.

This permits several media/quote cards from one origin while an exact repeat save deduplicates.

- 64 hex characters, e.g. `1146c9a93631d1991af3252dbc49ecd8043ab354a4386e397d555d1ca21a7199`.
- **Deterministic** — the same kind-specific identity input yields the same id, so the id doubles as
  the dedup key. The host hashes the input and stats the one folder it would occupy, with no scan or
  index lookup.
- The id is the **reading-folder name** (under its `<prefix>` bucket) and the frontmatter `id`
  field. They must match — a folder whose name disagrees with its `article.md`'s `id` is ignored.
- Not time-sortable: the reading list orders by `saved_at` via the index, not by id.

Highlight ids (the `<!-- hl ... -->` markers) are **ULIDs** — 26-character Crockford Base32,
sortable by creation time — because a highlight is identified by when it was made, not by content.

---

## URL normalization & identity

A reading's identity is the **normalized visited URL**: the host normalizes the `url` and the
reading id is its SHA-256 (§ ID scheme). Apply these rules in order:

1. Lowercase the scheme and host.
2. Strip a leading `www.` from the host.
3. Remove the default port (`:80` for http, `:443` for https).
4. Strip the fragment (`#...`).
5. Strip tracking query parameters: `utm_*` (prefix), `fbclid`, `gclid`, `mc_cid`, `mc_eid`, `ref`,
   `source`, `campaign` (exact match).
6. Sort the remaining query parameters — they may be meaningful (pagination, article ids), so keep
   them, but sort so their order can't produce two ids for one page.
7. Remove a trailing `/` from the path **unless** the path is just `/`.

The original origin-page `url` (pre-normalization) is preserved for browser captures.
`canonical_url` stores the page's own `<link rel="canonical">`/`og:url` when known, for reference —
it is not substituted with a CDN or direct media address. The URL-only app path normalizes the URL
before writing because no page metadata exists yet. Source-less local identities are already stable
internal URLs and do not go through web URL normalization. Two different normalized web origins for
the same content can still produce two readings — an accepted trade-off of origin-aware capture.

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
- All three components (`core`, `extension`, `macos`) must be updated together on a version bump.

---

## What lives in the library vs. outside it

| Belongs in library (synced) | Belongs outside library (per-device, never synced) |
|-----------------------------|----------------------------------------------------|
| `articles/<prefix>/<id>/article.md` | SQLite index (`~/Library/Application Support/Cuttings/`) |
| `articles/<prefix>/<id>/assets/*` | App preferences (theme, font, library path) |
| `articles/<prefix>/<id>/highlights.md` | Native messaging host manifest |
| `articles/<prefix>/<id>/note.md` (optional) | |
| `articles/<prefix>/<id>/original.html` (optional) | |
| `.cuttings-locks/<prefix>/<sha256-id>.lock` (operational, empty) | |
