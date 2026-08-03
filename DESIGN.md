# DESIGN.md — ReadControl

> UI/UX design for the macOS client. This captures the visual language, layout, navigation, and
> screen states the app should implement. Architecture and data principles live in
> [AGENTS.md](./AGENTS.md).

## Source

- [`assets/icon.png`](./assets/icon.png) — the app logo / icon.

## Product name

The product name is **ReadControl** ([readcontrol.app](https://readcontrol.app)). It is displayed
to end users as "ReadControl." (An early mockup branded the app "Later" — that placeholder is
superseded.)

## Logo / app icon

<img src="./assets/icon.png" alt="ReadControl app icon" width="96" />

The app icon is a rounded-square ("squircle") in the same near-black charcoal as the UI, with a
centered cream/off-white **bookmark** glyph (notched bottom). It ties directly into the design
language — dark, minimal, content-first — and reuses the **bookmark motif** that also appears in
the app's empty state ("Your reading list is empty").

- **Source:** [`assets/icon.png`](./assets/icon.png).
- **Usage:** the macOS app icon, and the basis for the browser-extension toolbar icon and any
  favicon — ideally a monochrome glyph (cream-on-dark / dark-on-light) at small sizes.
- **To finalize:** export the full macOS icon set (`.icns` / `AppIcon.appiconset`, 16–1024 px)
  and the extension icon sizes (16 / 32 / 48 / 128 px); confirm the glyph stays legible at 16 px.

## Design language

- **Theme:** dark by default, with **Light / Dark / System** options (the mockup shows Dark).
- **Tone:** minimal, calm, content-first. Generous negative space; the reading list and reader
  are the focus and the chrome stays quiet.
- **Shape & depth:** rounded corners and soft elevation — panels (sidebar, popovers) sit
  slightly above the main surface. Subtle, low-contrast dividers and borders.
- **Typography:** **Inter** as the default UI font; the reader's font family and size are
  user-adjustable (see Settings).
- **Native feel:** a standard macOS window with traffic-light controls; behaves like a Mac app.

### Design tokens (approximate — finalize before implementation)

> Values are approximate and should be confirmed/replaced with exact tokens
> (ideally a shared token file) before implementation.

| Token | Role | Approx. (dark) |
|-------|------|----------------|
| `bg/base` | window background / main surface | near-black charcoal (~`#1B1B1D`) |
| `bg/elevated` | sidebar, popovers | slightly lighter (~`#242427`) |
| `bg/selected` | selected row / control | subtle highlight (~`#2E2E32`) |
| `text/primary` | headings, body | near-white (~`#ECECEC`) |
| `text/secondary` | metadata, hints, empty-state subtext | muted gray (~`#8A8A8E`) |
| `border/subtle` | dividers, control outlines | low-contrast gray |
| `accent` | primary actions, selection accent | **TBD** — define a brand accent |
| `radius/panel`, `radius/control` | corner radii | medium / small |

### Icon–label spacing

Any icon paired with text (sidebar items, tag rows, the article header metadata
row, etc.) uses a **4 pt** gap between the icon and its label — tighter than
SwiftUI's default `Label`, which reads as too loose for our compact rows. This
is the single source of truth: use the same value everywhere an icon sits next
to a label.

- Implemented as `TightIconLabelStyle` (constant `iconLabelSpacing = 4`); apply
  with `.labelStyle(.tightIcon)`.
- The spacing *between* separate metadata items (e.g. site · author · reading
  time) is a distinct, larger value and is not governed by this token.

## App layout

A classic three-region macOS layout:

```
┌───────────┬──────────────────────────────────────────────┐
│  Sidebar  │  Toolbar: [ Search ]            [+ Add Link] ⚙│
│  (nav)    ├──────────────────────────────────────────────┤
│           │                                                │
│           │           Content: list / reader               │
│           │                 / empty state                  │
│ ⚙ Settings│                                                │
└───────────┴──────────────────────────────────────────────┘
```

### Sidebar (left)

- **App title** at the top ("ReadControl").
- **Smart views**, each with an icon and a count badge:
  - **All** — the reading list.
  - **Unread** — not yet read.
  - **Archive** — items moved out of the active list.
  - **Favorites** — starred items.
- **Tags** section with a `+` to create/manage tags and an empty state
  (*"No tags yet…"*). Selecting a tag filters the list.
  > **Note:** the mockup labels this section **"Lists,"** but per design review we are using
  > **Tags** (not manual Lists). The section is **Tags**.
- **Settings** (gear) pinned to the bottom-left, opening the settings/appearance surface.
- **Collapsible sections** — the **Library**, **Ratings**, and **Tags** groups each have a
  disclosure triangle and can be collapsed independently. The expanded/collapsed state of each
  section is **persisted** (per-section `@AppStorage` flags, default expanded), so the sidebar
  reopens exactly as the user left it.

### Toolbar (top of content)

- **Search field** — placeholder *"Search or paste a link…"*. For now this is **search-only**;
  the paste-a-link affordance is deferred together with Add Link (below).
- **+ Add Link** button — **deferred / out of scope for now** (see Deferred). Hidden or disabled
  until in-app capture exists.
- **Filter / sort** control at the far right.

### Content states

- **Empty state:** centered bookmark icon, heading (*"Your reading list is empty"*), subtext
  (*"Save articles and pages to read later"*), and a call to action. (The mockup's CTA is Add
  Link, which is deferred — fall back to guidance about installing/using the browser plugin.)
- **List view:** rows of saved readings (title, site, excerpt, estimated reading time,
  read/favorite indicators, tags), filtered by the selected smart view / tag. Reading time
  is derived from word count at 200 wpm (see "Article header chrome").
- **Reader view:** the cleaned Markdown rendered with local assets and the user's chosen
  typography; actions to mark read/unread, favorite, archive, and edit tags.

### Settings / appearance (popover from the gear)

- **Appearance:** segmented **Light / Dark / System**.
- **Font:** family picker (default **Inter**) and a size **slider** (small → large "Aa").
- These are **per-device UI preferences** — stored in app preferences (e.g. `UserDefaults`),
  **not** in the library folder and **not synced**, consistent with the "the DB/cache is
  per-device" principle in [AGENTS.md](./AGENTS.md).
- This surface is also the natural home for the **library-folder path** and **native-host
  status**.

## Apple platform style guide — the reader

> This section is **exclusive to the Apple (macOS) client** and is the source of truth for how a
> saved article is rendered in the reader. It follows the
> [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/typography):
> a clear typographic hierarchy, a comfortable reading measure, asymmetric "section" spacing, and
> native controls (text selection, Dynamic-Type-like sizing, semantic Light/Dark colors).
>
> It is implemented natively with SwiftUI + [`swift-markdown`](https://github.com/apple/swift-markdown)
> (no WebView). Every value below is expressed **relative to the reader's body size** so the whole
> document rescales when the user changes the text size.

### Where it lives

| Concern | File |
|---------|------|
| All fonts / sizes / weights / spacing tokens | `Sources/ReadControl/Views/Markdown/MarkdownTheme.swift` |
| Inline runs → styled `AttributedString` (bold, italic, code, links…) | `…/Markdown/InlineRenderer.swift` |
| Block rendering (headings, lists, quotes, tables, code…) | `…/Markdown/MarkdownBlockView.swift` |
| Images / figures + captions | `…/Markdown/AssetImageView.swift` |
| Scroll container, reading measure, link handling | `…/Markdown/MarkdownDocumentView.swift` |
| Article header chrome (title, metadata, tags) | `Sources/ReadControl/Views/ArticleDetailView.swift` |

### Reader typography

The body font is user-selectable (**System** = San Francisco, **Serif** = New York, **Monospace** =
SF Mono) at four sizes — these are the per-device preferences described under *Settings / appearance*.

| Size option | Body point size |
|-------------|-----------------|
| Small | 15 pt |
| **Medium (default)** | **17 pt** |
| Large | 19 pt |
| Extra Large | 21 pt |

Everything else is a multiple of this body size, so the document keeps its proportions at any size:

| Token | Value (× body) | At 17 pt | Role |
|-------|----------------|----------|------|
| Line spacing | `0.55em` | ~9.4 pt | added leading → effective line-height ≈ **1.75** |
| Block spacing | `1.0em` | 17 pt | vertical gap between top-level blocks |
| Content measure | `680 pt` (fixed) | — | optimal line length (~60–75 chars); content is centered |

### Heading hierarchy

The old reader left headings looking like body text — every inline run carried the body font, which
overrode the heading font. The renderer now injects a per-heading **font context** so all six levels
are visually distinct. Headings get more space **above** than below, so a heading visually *binds to
the section it introduces* (a core HIG/typography principle) and major sections get a clear break.

| Level | Size (× body) | At 17 pt | Weight | Tracking | Space above (× body) | Treatment |
|-------|---------------|----------|--------|----------|----------------------|-----------|
| **H1** | 1.80 | ~30.6 pt | Bold | −0.5 | 1.7em | page/section title |
| **H2** | 1.45 | ~24.7 pt | Bold | −0.3 | 1.3em | major section |
| **H3** | 1.20 | ~20.4 pt | Semibold | 0 | 1.0em | sub-section |
| **H4** | 1.05 | ~17.9 pt | Semibold | 0 | 0.8em | minor heading |
| **H5** | 0.95 | ~16.2 pt | Semibold | 0 | 0.6em | small heading |
| **H6** | 0.85 | ~14.5 pt | Semibold | +0.6 | 0.6em | **uppercase eyebrow**, secondary color |

- **Tracking:** large display headings are tightened (Apple tightens large titles); the small H6
  eyebrow is opened up and uppercased for legibility.
- `Space above` is **added on top of** the 1em block spacing, so the gap above a heading is always
  larger than the gap below it.
- **The article title is the sole H1.** The header draws the title from the frontmatter `title` at
  the H1 size; the extension demotes any body `#` to `##` (see library-format), so body headings
  start at H2 and never duplicate the title.

### Lists

| Aspect | Spec |
|--------|------|
| Gap between items | `0.5em` (tighter than the 1em block gap) |
| Marker → text gap | `0.5em` |
| Marker column | fixed hanging indent — `1.5em` (ordered) / `1.1em` (unordered/task), right-aligned |
| Unordered bullets | cycle by nesting depth: **`•` → `◦` → `▪`**, in secondary color |
| Ordered markers | `1.`, `2.`, … with **monospaced digits**, secondary color |
| Task lists (GFM) | `☑` (`checkmark.square.fill`, **accent**) / `☐` (`square`, secondary) |
| Nesting | nested lists indent one marker column and step the bullet/number down a level |
| Rich item content | a list item may contain multiple paragraphs, code, quotes, or nested lists |

### Block quotes

- A **3 pt rounded vertical bar** (secondary, 40% opacity) with a `0.85em` gap to the quoted content.
- Quoted text is rendered in the **secondary** color; inner blocks use `0.6em` spacing.
- Quotes may nest and may contain any block (paragraphs, lists, code, even other quotes).

### Code

| Kind | Spec |
|------|------|
| Inline code | monospaced at `0.9em`, subtle `secondary @ 15%` background |
| Code block | monospaced at `0.9em` on a `secondary @ 10%` surface, **corner radius 8**, padding 14, **horizontal scroll** (no wrapping) |
| Language label | when a fence declares a language it's shown lowercased above the block in the caption style |

> **Not yet:** syntax highlighting — code is rendered as uniform monospaced text.

### Tables (GFM)

- Rendered with a SwiftUI `Grid`; **header row is semibold** with a divider beneath it.
- **Column alignment is honored** — left / center / right per the table's `:---`, `:--:`, `---:`.
- Horizontal spacing 16 pt, vertical 8 pt; cells support full inline styling and text selection.

### Images & figures

- Scaled to fit the content width, **corner radius 6**; centered.
- **Alt text becomes a caption** rendered below the image (centered, `0.85em`, secondary) — i.e. a
  proper *figure*. Images with empty alt show no caption.
- Local library assets load from `…/assets/<id>/<file>`. An image the extension couldn't capture at
  save time stays a remote `http(s)` URL; the reader shows a labelled placeholder for it and never
  fetches it over the network.
- The common `[![alt](img)](url)` pattern (a link wrapping a single image) is unwrapped and rendered
  as the image.

### Inline text styles

| Element | Rendering |
|---------|-----------|
| **Bold** (`**`/`__`) | semibold/bold run |
| *Italic* (`*`/`_`) | italic run |
| ~~Strikethrough~~ (GFM) | strikethrough line |
| `Inline code` | monospaced + tinted background (see Code) |
| [Links](#) | **accent** color + underline; open in the **system browser** |
| Nested emphasis | composes correctly (e.g. bold-inside-italic-inside-a-link) |
| Hard / soft line breaks | preserved / collapsed to a space |

### Other blocks

- **Thematic break** (`---`): a full-width divider with `0.5em` vertical breathing room.
- **Raw HTML** (block or inline): **tags are stripped**; only the visible text is shown (secondary
  color). Raw markup is never rendered or executed.

### Article header chrome

Above the scrolling reader (in `ArticleDetailView`), each article shows:

- **Title** at the **H1 type token** (bold) — the reading's sole h1. Like the metadata and rating,
  it is sized from the reader's body size, so the whole header rescales when the reader changes the
  font size instead of staying fixed while the copy grows.
- **Metadata row** — site (`globe`), author (`person`), and estimated reading time (`clock`) as
  secondary labels sized from the body, shown only when present. Reading time is derived from
  word count at an average **200 wpm**, rounded up to a 1-minute minimum (e.g. "5 min read"); the
  raw word count is kept as the label's hover tooltip. Icon–label gaps use the 4 pt
  icon–label spacing token.
- **Tags** as rounded **capsule chips** in the header, each removable with an inline ×. New
  tags are added from a **`#` button** in the article toolbar that opens a searchable modal
  sheet — it lists the 10 most-used tags by default, toggles a tag's membership with a
  checkmark, and offers to create-and-apply a new tag as you type. (Adding lives in the sheet,
  not inline, so revealing matches never reflows the article below.)
- A divider separates the header from the scrollable body.

The **rating is deliberately *not* in the header.** A rating is a judgment formed *after* reading,
so a 5-star control would prompt for a verdict before the reader has read a word. Instead it lives
at the **end of the reading** (see below).

### End-of-article rating

A 5-star control sits at the **foot of the article body**, rendered as a `footer` inside the
reader's own scroll (`MarkdownDocumentView`) — so it surfaces only when the reader reaches the end
of the piece, matching the moment a rating is actually formed. A short "Rate this article" label
and a divider set it off from the body. Clicking the current rating again clears it back to
unrated. The same footer is appended to the excerpt-only fallback path so unfetched readings can
still be rated.

### Text selection

The reader supports **continuous, native selection** (drag, double/triple-click, ⌘C copy) across the
article body. SwiftUI's `Text` + `.textSelection` can only select *within* a single `Text`, so
contiguous **headings and paragraphs are coalesced into one `NSAttributedString` rendered by a
read-only `NSTextView`** (`SelectableTextView`), with the theme's spacing re-expressed as
`NSParagraphStyle` attributes. This stays within the no-WebView rule (it's AppKit/TextKit, not WebKit).

- A run breaks — forming a **selection seam** — at any block that isn't a heading or text-only
  paragraph: **images/figures, code blocks, tables, lists, and block quotes** each keep their richer
  SwiftUI renderer.
- Run height is driven by the text view's `intrinsicContentSize` (invalidated whenever the text or
  width changes), **not** `sizeThatFits` — the latter can run before the text is installed on the
  first layout pass, measuring an empty view and collapsing the run to zero height (a blank reader).
- Lists and block quotes are deliberately *not* folded into the text run for now. Their attributed
  layout (marker tab stops, hanging indents, quote bars via `ReaderLayoutManager`) is implemented in
  `MarkdownTextRun` but unvalidated on-device, so they stay on the proven SwiftUI path and form a
  seam. Re-enabling is a matter of flipping `isFoldable`.
- ⌘F find-bar isn't offered per run (a standalone `NSTextView` needs an enclosing scroll view for
  it); selection and copy are unaffected.

### Element coverage & known limitations

The renderer covers the full CommonMark + GFM surface that the extension's HTML→Markdown step can
produce. Anything unrecognized recurses into its children so **no content is silently dropped**.

| Element | Supported | Notes |
|---------|-----------|-------|
| Headings H1–H6 | ✅ | full six-level hierarchy (above) |
| Paragraphs, emphasis, strong, strikethrough, inline code | ✅ | |
| Links, line/soft breaks | ✅ | links open in the system browser |
| Images / figures with captions | ✅ | local assets; missing images show a placeholder |
| Ordered / unordered / nested lists | ✅ | depth-aware bullets & indent |
| Task lists (checkboxes) | ✅ | GFM |
| Block quotes (incl. nested) | ✅ | |
| Code blocks (with language label) | ✅ | no syntax highlighting yet |
| Tables with column alignment | ✅ | GFM |
| Thematic break / horizontal rule | ✅ | |
| Raw HTML (block & inline) | ⚠️ | text extracted, tags stripped |
| Footnotes (`[^1]`) | ❌ | swift-markdown doesn't model them; render as literal text |
| Math / LaTeX | ❌ | not rendered |
| Definition lists, sub/superscript | ❌ | not in CommonMark; would arrive as HTML and be stripped |

> When the upstream extension produces these unsupported constructs, prefer normalizing them during
> HTML→Markdown (e.g. flatten footnotes, drop math) so the reader stays clean. Revisit footnotes and
> syntax highlighting as future enhancements.

## Item states & data-model impact

The mockup introduces item states beyond read/unread. These are **reading data**, so they live
in each file's frontmatter (the source of truth) and are mirrored in the index:

| State | Frontmatter field | Notes |
|-------|-------------------|-------|
| Read / unread | `read: bool` | already planned |
| Archived | `archived: bool` | moved out of the active list |
| Favorite | `favorite: bool` | starred |
| Rating | `rating: u8` | 0–5 stars (0 = unrated); powers the sidebar **Ratings** filter |
| Tags | `tags: [..]` | labels; power the sidebar **Tags** section |

**Smart-view semantics (assumption — please confirm):**
- **All** — readings that are **not archived** (the active list).
- **Unread** — not archived **and** `read == false`.
- **Archive** — `archived == true`.
- **Favorites** — `favorite == true` (regardless of archive state).

## Interaction model — optimistic & self-healing

Status changes (read, favorite, archive, rating, tags) **apply to the UI instantly**; persistence
happens in the background. The user clicks, the star/heart/dot flips on the next frame, and the
core write + index refresh run behind it. Because the markdown file is the source of truth and the
refresh re-reads from it, a failed write simply reconciles back — no spinners, no manual undo.

**One motion, not two.** When an action moves a reading out of the view you're looking at —
Archive in *All*, Mark Read in *Unread*, removing the tag you're filtered by — the row slides out
**and** selection advances to the neighbouring reading in the same beat, like archiving in Mail.
The reader follows to the next item. (Flipping the icon in place and letting the row jump a moment
later, on the async refresh, reads as a stutter; this avoids it.) Row *re-ordering* after an edit
still settles on the background refresh — only removal/advance is immediate.

**The sidebar counts move with the row.** The view counts (All / Unread / Read / Archive /
Favorites) and the **Tags** and **Ratings** sections are optimistic too: an edit folds its
before/after into the counts in memory on the same frame, so archiving a tagged 5-star reading
instantly does `All −1`, `Archive +1`, and drops it from both its tag count and the 5-star count.
The deltas mirror the engine's own count rules — tag and rating counts include only non-archived
readings; Favorites counts regardless of archived — and `loadSidebar()` reconciles to the true
numbers on the background refresh. Counts are pure presentation, never persisted, so this stays a
UI concern and never touches the file-first persistence model.

**Selection can sit off-list.** A reading stays selected and shown in the reader even after an edit
drops it from the visible list — e.g. re-rating the open article while in a Ratings filter. The
list simply shows no highlight, and the toolbar reads from the open reading rather than the (now
absent) list row. This keeps the reader and the list from disagreeing, and a post-edit refresh
never re-homes the selection out from under you (only direct reloads — filter switch, sort, search,
first load — pick a default row).

## Deferred / out of scope (for now)

- **In-app "Add Link" / paste-a-URL.** Adding a reading by URL inside the app would require the
  engine to fetch and clean the page **without a browser DOM** (a Rust-side readability +
  HTML→Markdown path). Per design review this is **deferred** — capture stays in the browser
  plugin. The Add Link button and the search field's paste-a-link behavior appear in the mockup
  but are not built yet.
- **Lists.** The mockup's "Lists" section is replaced by **Tags**; manual Lists are not planned.

## Open questions / to finalize

- Exact color tokens and the brand **accent** color (the mockup palette is near-monochrome).
- **Archive vs All** semantics (does "All" include archived?) — the assumption above pending
  confirmation.
- List-row density and exactly which indicators/metadata appear inline.
