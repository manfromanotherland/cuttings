# UBIQUITOUS_LANGUAGE.md - cuttings

This glossary defines the shared product language for `cuttings`. Use these
terms in docs, code discussions, issue titles, UI architecture, and commit
messages so the project stays consistent across the extension, core, native
host, and macOS app.

## Naming Rules

- Use **save** for the user action that adds a page, image, video, or text quote
  to the library, whether from the extension or by pasting/dropping in the app. Saving is
  time-neutral: people save things to revisit
  *and* things they already consumed and want to keep. Do not use download or
  bookmark for this action.
- Use **capture** for the extension's technical extraction step (live DOM or
  right-click context → Markdown, origin metadata, image bytes). The user saves;
  the extension captures.
- Use **reading** for the established internal saved-domain object. In user-facing copy, prefer
  **card** or **saved item**: people browse, search, revisit, annotate, tag, favorite, or delete it.
- Use **article file** only when talking about the on-disk `article.md` inside a
  reading's folder.
- Use **reading folder** for the per-reading folder `articles/<prefix>/<id>/`
  that holds a reading's article file, its assets, and its highlights.
- Use **library** or **library folder** for the user-selected folder that holds
  readings and assets.
- Use **index** for the local SQLite database. Do not call it the source of
  truth.
- Use **tag**, not list, collection, folder, or category.
- Use **extension** or **browser extension**, not plugin.
- Use **favorite** for the one visible boolean curation state. `read_at`, `archived`, and `rating`
  are legacy format-v1 field names, not current product vocabulary.

## Core Domain Terms

| Term | Definition |
|------|------------|
| App | The user-facing product as a whole. In implementation, this currently means the browser extension, native messaging host, Rust core, and macOS client. |
| Cuttings | The product name shown to users. |
| cuttings | The internal project slug used for the monorepo, packages, and file paths. Not shown to users. |
| Library | The folder chosen by the user that stores their synced, durable reading data. |
| Library folder | Same as Library, used when emphasizing the on-disk directory. |
| Library root | The absolute folder path selected on one device. Data stored inside the index must still use paths relative to this root. |
| Save | The user action that adds a page, media item, or text to the library as a new reading/card, from either the extension or the app's paste/drop path. |
| Capture | The extension step that turns a page or right-click context into Markdown, universal origin metadata, and optional local image bytes before the save is written. Internal/technical term; users just "save". |
| Reading | One saved item in the user's library. A reading is backed by an article file plus optional assets, highlights, and a personal note — all inside its reading folder. |
| Card | User-facing visual representation of a reading on the macOS masonry board. Do not rename the internal `Reading` domain type merely to match presentation. |
| Card kind | The reading's capture/rendering kind: `article`, `image`, `video`, or `quote`. A missing kind on an older file means `article`. |
| Origin | The source page for a web card: `url`, `canonical_url`, page title/site, and save date. For image/video cards this is deliberately distinct from `media_url`. Source-less app saves instead carry a private local identity. |
| Media URL | Optional media identity for an image/video card. Normally it is a durable direct URL. A session-local video instead uses an opaque stable capture reference. It supplements the origin and never replaces the page URL. |
| Preview asset | Optional safe local `assets/<file>` reference used by the masonry card. The host derives it only after captured image/poster bytes have been written. |
| Quote | A text card whose full text is stored as Markdown. Browser selections retain their page origin; source-less paste/drop text uses a private local identity. |
| Lightweight link | An article card created by pasting or dropping only an HTTP(S) URL. It is explicitly marked `lightweight: true`; a later full browser capture upgrades the same reading in place. |
| Local identity | A deterministic, non-web `cuttings://local/...` URL used for source-less text or image saves. It prevents machine-local paths leaking into synced files and is never shown as an openable source. |
| Reading folder | The per-reading folder `articles/<prefix>/<id>/` (named by the reading id, under a two-character fan-out bucket) that holds the reading's `article.md`, its `assets/`, `highlights.md`, and `note.md`. Moving or deleting a reading operates on this one folder. |
| Article file | The `article.md` file inside a reading folder (`articles/<prefix>/<id>/article.md`) that stores one reading's frontmatter and body. |
| Frontmatter | YAML metadata at the top of an article file. It is the source of truth for reading metadata and state. |
| Body | The cleaned Markdown content after frontmatter in an article file. |
| Asset | A local file, usually an image, stored in the reading's own `assets/` folder (`articles/<prefix>/<id>/assets/`) and linked from the body with a relative `assets/<file>` path. |
| Original HTML | Optional raw HTML snapshot stored as `original.html` inside the reading folder for future reprocessing. |
| Highlight | A saved selected text passage for one reading. Highlights are stored in the reading folder, separate from the article file. |
| Highlight file | The `highlights.md` file inside a reading folder (`articles/<prefix>/<id>/highlights.md`) that stores that reading's saved highlights. |
| Personal note | The user's optional Markdown annotation attached to one reading. It is distinct from both the captured body and highlights; Cuttings does not create standalone note cards. |
| Note file | The optional `note.md` file inside a reading folder (`articles/<prefix>/<id>/note.md`) that stores one personal note as plain Markdown. |
| Reading id | Deterministic lowercase-hex SHA-256 content address. Web articles hash the normalized origin URL; web image/video cards hash kind + normalized origin + media identity; web quotes hash normalized origin + normalized selected Markdown; source-less app saves derive identity from their content. It names the reading folder and frontmatter `id`. |
| Content-addressed id | An id derived from stable card identity rather than assigned, so identical input yields an identical id without a coordinator. |
| ULID | Sortable id scheme (Crockford Base32). Used for highlight ids; reading ids are content-addressed (see Reading id), not ULIDs. |
| Source URL | The originating page URL stored as `url` for a web card. For articles its normalized form is the whole identity; for media/quote it is one component of identity. A source-less app save stores a local identity in the same required field. |
| Canonical URL | The page's own canonical URL when known, stored as `canonical_url` for reference. Dedup keys on the reading id (from the normalized *visited* URL), not this field. |
| Source hash | Hash of cleaned content used to detect stale index rows and content changes. |
| Format version | Integer frontmatter version for the library file contract. |

## Curation And Organization

| Term | Definition |
|------|------------|
| Favorite | Boolean state meaning the user marked the reading as important or worth returning to. Stored in frontmatter. |
| Tag | User-defined label stored in a reading's frontmatter. Tags organize readings and are indexed by search. |
| Board scope | Exactly one toolbar selection: All, Favourites, Media, Articles, Notes, Links, or Quotes. Media combines image and video readings; Articles excludes lightweight links; Notes selects readings with a personal note sidecar; Links selects lightweight article placeholders. |
| Board filter | The selected board scope and optional search query, applied as an intersection to the board. |
| All | The unfiltered board scope. It includes every saved item, including files carrying a legacy `archived: true` value. |
| Favourites | Board scope for readings where `favorite == true`. |
| Legacy state field | `read_at`, `archived`, or `rating` in a format-v1 file. The core preserves these for compatibility; the current macOS app does not display or mutate them. |
| Selection | The currently open reading in the macOS app. When an optimistic edit removes it from the active board scope, selection advances to an adjacent matching reading in the same render tick. |

## Storage And Sync

| Term | Definition |
|------|------------|
| Files are the source of truth | The rule that durable reading data lives in Markdown files, not only in a database. |
| File-first mutation | A state change that writes frontmatter first, then updates the derived index from the re-read file. |
| Index | Per-device SQLite database used for fast listing and search. It is disposable and rebuildable. |
| Reconcile | Process that scans files and brings the index back in line with the library. |
| Rebuild | Full index recreation from the library files. |
| Sync | User-managed movement of library files between devices through tools outside this app, such as iCloud Drive, Dropbox, Google Drive, git, or a USB drive. |
| External writer | Any process other than the current app instance that can add, remove, or edit files in the library. |
| Conflict | A duplicate or conflicted file created by an external sync tool. Conflict detection and UX are still future work. |
| Per-device data | Data that belongs outside the library and should not sync, such as the index, UI preferences, and local app configuration. |
| Relative path | A path stored relative to the library root. The index should store relative paths because absolute paths differ per device. |

## Components

| Term | Definition |
|------|------------|
| Extension | Browser extension that captures a cleaned page, clicked image/video, or selected-text quote and sends Markdown, universal origin metadata, and optional image bytes to the native host. |
| Site adapter | Extension pre-processor for a specific host (e.g. X/Twitter) that reshapes single-page-app markup before generic extraction, so content Readability would otherwise discard is preserved. |
| Native messaging host | Native binary called by the extension. It writes readings and assets to the library through `core`. |
| Core | Rust engine that owns save/import behavior, the library format, file parsing/writing, indexing, search, tags, favorites, compatibility fields, highlights, personal notes, and the UniFFI surface. |
| macOS client | SwiftUI app that lets the user save by paste/drop, browse, search, revisit, annotate, tag, highlight, favorite, delete, and configure the library. |
| UniFFI bindings | Generated Swift bridge that lets the macOS client call the Rust core. |
| Thin client | A client that delegates domain logic to the Rust core and keeps only presentation, navigation, and local UI state. |
| Folder watcher | macOS file-system watcher that notices library changes and triggers reconcile. |
| Native host manifest | Browser registration file that tells the browser where the native messaging host binary lives. |

## UI And Interaction

| Term | Definition |
|------|------------|
| Reader | Main article reading surface in the macOS app. It renders Markdown natively and supports local assets, text selection, highlights, and typography settings. |
| Card board | Full-width mixed masonry presentation of reading rows for the active board scope and search query. |
| Note editor | The raw-Markdown sheet opened from a card's inspector to add, replace, or delete that reading's personal note. |
| Reading list | Legacy name for the old row-based macOS presentation and for the core listing API; the current user-facing home is the card board. |
| Search | Full-text query over indexed reading title, content, and tags. |
| Board order | Fixed card-board ordering: newest saved first while browsing and relevance while searching. |
| Optimistic UI | UI pattern where local state changes immediately, then the core write and refresh reconcile against persisted truth. |
| Refresh | UI reload from the core/index after a mutation, sync, filter change, or search change. |
| One-motion removal | Interaction rule where a row that leaves the active filter is removed and selection advances in the same render tick. |
| Settings | macOS surface for appearance, typography, library folder, and native host status. |
| Appearance preference | Per-device Light, Dark, or System setting. |
| Typography preference | Per-device reader font and size setting. |

## Positioning And Marketing

Terms for user-facing copy: the landing page, app store text, READMEs' first
paragraphs, and the welcome article.

| Term | Definition |
|------|------------|
| Inspiration library | Preferred product category: a visual, permanent place for articles, images, videos, and quotes that spark ideas. |
| Visual library | Shorter supporting description when "inspiration library" has already established the product. |
| Local-first | Marketing shorthand for the no-accounts, no-servers, files-on-your-disk principles. |
| Save | The user-facing verb for adding a page, media item, or quote to Cuttings. |

## Terms To Avoid Or Use Carefully

| Avoid | Use Instead | Reason |
|-------|-------------|--------|
| List | Tag, filter, or board | Manual Lists are not a product model. |
| Database source | Index | The database is disposable and derived from files. |
| Sync engine | External sync | The app does not sync for the user. |
| Article as domain object | Reading | Article is useful for file names and reader UI, but reading is the product entity. |
| "Reading"/"readings" as a user-facing noun | Card, saved item, article, image, video, or quote | The internal domain term should not make the product sound like a reading queue. |
| Starred | Favorite | Favorite is the product's one visible boolean curation state. |
| Clip | Save | One verb covers pages, media, quotes, and in-app paste/drop without implying that only a fragment is kept. |
| Standalone note | Personal note | A note in Cuttings annotates a saved reading; it is not a fifth card kind or a general-purpose notes-app document. |
| Download (user action) | Save | Download implies fetching raw files over the network. The extension captures from the live DOM and the host never downloads — keep "download" for its technical meaning only. |
| Bookmark (user action) | Save | A full browser capture stores cleaned content; a URL-only app save is explicitly lightweight and can later be upgraded. The bookmark glyph as brand iconography is fine; the verb is not. |
| Plugin | Extension | Browsers and their stores call them extensions. |
| Read-later app | Inspiration library | The product is organized around collecting and revisiting inspiration, not clearing an unread queue. |
| Preferences | Settings | macOS renamed Preferences to Settings; the app's UI says Settings. |
| Web reader | Reader | The macOS reader is native, not WebView-based. |
| Add Link | Paste or drop a link; Save | The app uses the standard paste/drop gestures rather than a bespoke form, and the user-facing action is still Save. |

## Flagged Ambiguities

- **"Save" vs "capture".** The *user saves* a page; the *extension captures*
  it (extraction, cleaning, image bytes) as the technical step inside that
  save.
- **"Inspiration" as identity.** It describes why mixed pages, images, videos,
  and quotes belong together. It does not imply that every card must be visually
  decorative or that articles stop being readable.
- **"Bookmark" is overloaded.** It is the brand glyph, an Apple API term in the
  macOS client (security-scoped bookmarks), and a rejected user-facing verb.
  Only the first two uses are legitimate.
- **"Reading" remains the internal domain entity.** Renaming the storage model is
  a separate format/API migration. User-facing copy says card, saved item, or the
  concrete kind so the product identity stays broader than articles.

## Example Dialogue

> **Dev:** "When the user **saves** a page, does the **extension** write the
> **article file**?"
>
> **Domain expert:** "No — the extension only **captures**: it extracts and
> cleans the live DOM and gathers image bytes. The **native messaging host**
> writes the **reading** into the **library** through the **core**."
>
> **Dev:** "How does someone organize what they saved?"
>
> **Domain expert:** "Everything stays together on the board. They can add
> **tags**, mark a card as a **favorite**, search for it later, or permanently
> **delete** it when it no longer belongs."
>
> **Dev:** "So the **index** knows all of this?"
>
> **Domain expert:** "The index only mirrors it. The frontmatter in the article
> file is the source of truth; the index is disposable and rebuilt from files."
