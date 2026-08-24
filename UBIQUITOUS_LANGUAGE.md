# UBIQUITOUS_LANGUAGE.md - cuttings

This glossary defines the shared product language for `cuttings`. Use these
terms in docs, code discussions, issue titles, UI architecture, and commit
messages so the project stays consistent across the extension, core, native
host, and macOS app.

## Naming Rules

- Use **save** for the user action that adds a page, image, video, or selected-text
  quote to the library. Saving is time-neutral: people save things to revisit
  *and* things they already consumed and want to keep. Do not use download or
  bookmark for this action.
- Use **capture** for the extension's technical extraction step (live DOM or
  right-click context → Markdown, origin metadata, image bytes). The user saves;
  the extension captures.
- Use **reading** for the saved domain object the user browses, searches, reads,
  tags, rates, archives, or deletes.
- Use **article file** only when talking about the on-disk `article.md` inside a
  reading's folder.
- Use **reading folder** for the per-reading folder `articles/<prefix>/<id>/`
  that holds a reading's article file, its assets, and its highlights.
- Use **library** or **library folder** for the user-selected folder that holds
  readings and assets.
- Use **index** for the local SQLite database. Do not call it the source of
  truth.
- Use **tag**, not list, collection, folder, or category.
- Use **smart view** for All, Unread, Read, Archive, and Favorites.
- Use lowercase **read**/**unread** for the boolean state and capitalized
  **Read**/**Unread** for the smart views derived from it.
- Use **extension** or **browser extension**, not plugin.
- Use **archive** as the noun for the smart view and **archived** for the stored
  state.
- Use **favorite** for the boolean state and **rating** for the 0-to-5 star
  judgement.

## Core Domain Terms

| Term | Definition |
|------|------------|
| App | The user-facing product as a whole. In implementation, this currently means the browser extension, native messaging host, Rust core, and macOS client. |
| Cuttings | The product name shown to users. |
| cuttings | The internal project slug used for the monorepo, packages, and file paths. Not shown to users. |
| Library | The folder chosen by the user that stores their synced, durable reading data. |
| Library folder | Same as Library, used when emphasizing the on-disk directory. |
| Library root | The absolute folder path selected on one device. Data stored inside the index must still use paths relative to this root. |
| Save | The user action that adds the current page, clicked media, or selected text to the library as a new reading/card. |
| Capture | The extension step that turns a page or right-click context into Markdown, universal origin metadata, and optional local image bytes before the save is written. Internal/technical term; users just "save". |
| Reading | One saved item in the user's library. A reading is backed by an article file, optional assets, and optional highlights — all inside its reading folder. |
| Card | User-facing visual representation of a reading on the macOS masonry board. Do not rename the internal `Reading` domain type merely to match presentation. |
| Card kind | The reading's capture/rendering kind: `article`, `image`, `video`, or `quote`. A missing kind on an older file means `article`. |
| Origin | The source page for every card kind: `url`, `canonical_url`, page title/site, and save date. For image/video cards this is deliberately distinct from `media_url`. |
| Media URL | Optional media identity for an image/video card. Normally it is a durable direct URL. A session-local video instead uses an opaque stable capture reference. It supplements the origin and never replaces the page URL. |
| Preview asset | Optional safe local `assets/<file>` reference used by the masonry card. The host derives it only after captured image/poster bytes have been written. |
| Quote | A selected-text card whose full selection is stored as Markdown and whose origin is the page on which the text was selected. |
| Reading folder | The per-reading folder `articles/<prefix>/<id>/` (named by the reading id, under a two-character fan-out bucket) that holds the reading's `article.md`, its `assets/`, and its `highlights.md`. Moving or deleting a reading operates on this one folder. |
| Article file | The `article.md` file inside a reading folder (`articles/<prefix>/<id>/article.md`) that stores one reading's frontmatter and body. |
| Frontmatter | YAML metadata at the top of an article file. It is the source of truth for reading metadata and state. |
| Body | The cleaned Markdown content after frontmatter in an article file. |
| Asset | A local file, usually an image, stored in the reading's own `assets/` folder (`articles/<prefix>/<id>/assets/`) and linked from the body with a relative `assets/<file>` path. |
| Original HTML | Optional raw HTML snapshot stored as `original.html` inside the reading folder for future reprocessing. |
| Highlight | A saved selected text passage for one reading. Highlights are stored in the reading folder, separate from the article file. |
| Highlight file | The `highlights.md` file inside a reading folder (`articles/<prefix>/<id>/highlights.md`) that stores that reading's saved highlights. |
| Reading id | Deterministic lowercase-hex SHA-256 content address. Articles hash the normalized origin URL; image/video cards hash kind + normalized origin + media identity; quote cards hash normalized origin + normalized selected Markdown. It names the reading folder and frontmatter `id`. |
| Content-addressed id | An id derived from stable card identity rather than assigned, so identical input yields an identical id without a coordinator. |
| ULID | Sortable id scheme (Crockford Base32). Used for highlight ids; reading ids are content-addressed (see Reading id), not ULIDs. |
| Source URL | The originating page URL stored as `url` for every card kind. For articles its normalized form is the whole identity; for media/quote it is one component of identity. |
| Canonical URL | The page's own canonical URL when known, stored as `canonical_url` for reference. Dedup keys on the reading id (from the normalized *visited* URL), not this field. |
| Source hash | Hash of cleaned content used to detect stale index rows and content changes. |
| Format version | Integer frontmatter version for the library file contract. |

## State And Organization

| Term | Definition |
|------|------------|
| Read | Boolean state meaning the user has read the reading. Stored in frontmatter. |
| Unread | Boolean state where `read == false`. |
| Archived | Boolean state meaning the reading is moved out of the active library list. Stored in frontmatter. |
| Favorite | Boolean state meaning the user marked the reading as important or worth returning to. Stored in frontmatter. |
| Rating | Integer star rating from 0 to 5, where 0 means unrated. Stored in frontmatter. |
| Tag | User-defined label stored in a reading's frontmatter. Tags organize readings and power tag filters. |
| Kind filter | Optional card-kind axis (`article`, `image`, `video`, `quote`) composed with smart view, rating, tag, and search in the core query. |
| Smart view | Built-in navigation-rail filter derived from frontmatter fields. One is always active (`All` is the base); it composes with optional kind, tag, and rating filters. |
| Composed filter | The active view, kind, tag, and rating (plus search) applied as an intersection to scope the board and counts. At most one value from each axis. |
| All | Smart view for non-archived readings. |
| Unread | Smart view for non-archived readings where `read == false`. |
| Read (smart view) | Smart view for non-archived readings where `read == true`. |
| Archive | Smart view for archived readings. |
| Favorites | Smart view for favorite readings, regardless of archive state. |
| Sidebar count | Derived presentation count for a smart view, tag, or rating. It is never persisted as source data. Scoped by the active search and selected facet (see Faceted count). |
| Faceted count | The rule that each sidebar section (Library, Ratings, Tags) counts against the active search plus the *other* sections' selection, never its own axis — so a selected facet still shows the alternatives you could switch to. |
| Selection | The currently open reading in the macOS app. It may remain open even when it no longer appears in the active filtered list. |

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
| Core | Rust engine that owns the library format, file parsing/writing, indexing, search, tags, states, ratings, highlights, and UniFFI surface. |
| macOS client | SwiftUI app that lets the user browse, read, search, tag, rate, highlight, archive, favorite, and configure the library. |
| UniFFI bindings | Generated Swift bridge that lets the macOS client call the Rust core. |
| Thin client | A client that delegates domain logic to the Rust core and keeps only presentation, navigation, and local UI state. |
| Folder watcher | macOS file-system watcher that notices library changes and triggers reconcile. |
| Native host manifest | Browser registration file that tells the browser where the native messaging host binary lives. |

## UI And Interaction

| Term | Definition |
|------|------------|
| Reader | Main article reading surface in the macOS app. It renders Markdown natively and supports local assets, text selection, highlights, and typography settings. |
| Card board | Mixed masonry presentation of reading rows for the active smart view, kind, tag, rating, search query, and sort. |
| Reading list | Legacy name for the old row-based macOS presentation and for the core listing API; the current user-facing home is the card board. |
| Sidebar | Navigation area containing smart views, ratings, tags, and settings. |
| Search | Full-text query over indexed reading title, content, and tags. |
| Sort | User-selected order for the reading list: relevance, date saved, date read, rating, or time to read. |
| Optimistic UI | UI pattern where local state changes immediately, then the core write and refresh reconcile against persisted truth. |
| Refresh | UI reload from the core/index after a mutation, sync, filter change, search change, or sort change. |
| One-motion removal | Interaction rule where a row that leaves the active filter is removed and selection advances in the same render tick. |
| Settings | macOS surface for appearance, typography, library folder, and native host status. |
| Appearance preference | Per-device Light, Dark, or System setting. |
| Typography preference | Per-device reader font and size setting. |

## Positioning And Marketing

Terms for user-facing copy: the landing page, app store text, READMEs' first
paragraphs, and the welcome article.

| Term | Definition |
|------|------------|
| Read-later app | The product category, used so people recognize what Cuttings is (the Pocket/Instapaper category). Category label only — never imply the library holds only unread things. |
| Reading library | Preferred description of what the user builds: a permanent, file-based library of the articles they save and own. Use it to balance "read-later" positioning ("a read-later app that builds a reading library you own"). |
| Local-first | Marketing shorthand for the no-accounts, no-servers, files-on-your-disk principles. |
| Save | The only user-facing verb for adding a page, in marketing as elsewhere (matches Pocket "Save to Pocket", Instapaper "Save Anything. Read Anywhere.", GoodLinks "Save. Read. Anywhere."). |

## Terms To Avoid Or Use Carefully

| Avoid | Use Instead | Reason |
|-------|-------------|--------|
| List | Tag, smart view, or reading list | Manual Lists are not a product model. |
| Database source | Index | The database is disposable and derived from files. |
| Sync engine | External sync | The app does not sync for the user. |
| Article as domain object | Reading | Article is useful for file names and reader UI, but reading is the product entity. |
| "Reading"/"readings" as a user-facing noun | Article, post, or page | In copy (welcome article, landing page, store text) naming the saved item a "reading" reads awkwardly. Prefer article/post/page for the item; keep **reading** for the activity and the "reading manager"/read-later positioning. In code and this glossary, reading stays the domain entity. |
| Starred | Favorite or rating | Favorite is boolean; rating is 0 to 5 stars. |
| Clip | Save | "Clip" is note-clipper vocabulary (Evernote, Notion, Obsidian Web Clipper) and suggests snipping fragments into a notes app. Read-later products say save. |
| Download (user action) | Save | Download implies fetching raw files over the network. The extension captures from the live DOM and the host never downloads — keep "download" for its technical meaning only. |
| Bookmark (user action) | Save | A bookmark is a link, not content. Cuttings stores the cleaned article itself. The bookmark glyph as brand iconography is fine; the verb is not. |
| Plugin | Extension | Browsers and their stores call them extensions. |
| Read-it-later system | Read-later app | One category phrase everywhere; "system" is architecture-speak. |
| Preferences | Settings | macOS renamed Preferences to Settings; the app's UI says Settings. |
| Star Ratings (section name) | Ratings | The sidebar section is "Ratings". "Star rating" is fine when describing the 0–5 value itself. |
| Web reader | Reader | The macOS reader is native, not WebView-based. |
| Add Link | Browser save or deferred in-app capture | In-app URL capture is not part of the current scope. |

## Flagged Ambiguities

- **"Read" is both a state and a smart view.** Lowercase `read` is the boolean
  frontmatter state; capitalized **Read** is the smart view scoped to
  non-archived readings where `read == true`.
- **"Save" vs "capture".** The *user saves* a page; the *extension captures*
  it (extraction, cleaning, image bytes) as the technical step inside that
  save.
- **"Read later" as identity.** Saving is time-neutral — users also save pages
  they already read to keep and reread. "Read-later app" stays as the category
  label, but copy should not describe saving as only for later reading.
- **"Bookmark" is overloaded.** It is the brand glyph, an Apple API term in the
  macOS client (security-scoped bookmarks), and a rejected user-facing verb.
  Only the first two uses are legitimate.
- **"Reading" is the domain entity but a weak user-facing noun.** In code, docs,
  and architecture a saved item is a **reading** (see Reading, Reading id,
  Reading folder). In user-facing copy the noun reads awkwardly, so name the
  saved item an **article**, **post**, or **page**, and reserve "reading" for the
  activity ("read anytime", "Happy reading") and the **reading manager** /
  **read-later** positioning. The visible tagline "the native macOS reading
  manager" stays.

## Example Dialogue

> **Dev:** "When the user **saves** a page, does the **extension** write the
> **article file**?"
>
> **Domain expert:** "No — the extension only **captures**: it extracts and
> cleans the live DOM and gathers image bytes. The **native messaging host**
> writes the **reading** into the **library** through the **core**."
>
> **Dev:** "And once they finish it, does the reading leave the **library**?"
>
> **Domain expert:** "It just flips the `read` state, so it moves from the
> **Unread** smart view to **Read**. It only leaves the active list when they
> **archive** it — and even then, an archived **favorite** still shows under
> **Favorites**."
>
> **Dev:** "So the **index** knows all of this?"
>
> **Domain expert:** "The index only mirrors it. The frontmatter in the article
> file is the source of truth; the index is disposable and rebuilt from files."
