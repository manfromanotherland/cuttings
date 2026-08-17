# AGENTS.md — ReadControl

> Guidance for humans and AI agents working in this repository.
> This file is the project's north star: it explains **what we are building, why, and the
> principles that constrain how.** When in doubt, optimize for the principles below over any
> single feature.

## What this is

**ReadControl** is a local-first, single-user "save it now, read it later" system.

You save a web page from your browser; it is stripped of clutter and stored as a **Markdown
file on your own disk**. A native app lets you browse, read, search, and tag your saved
readings. There are no accounts, no servers, no logins, no telemetry. Your readings are plain
files that you own and can read with any text editor forever.

## Core principles

These are load-bearing. Most architectural questions resolve by appealing to one of them.

1. **Local-first & offline.** Everything works with no network and no backend. There is no
   server to run and nothing to log into.

2. **Files are the source of truth.** Each reading is a Markdown file with YAML frontmatter.
   Everything that matters — content, source URL, tags, read/unread state, save date — lives
   *in the file*. If every other part of this project vanished, the user's library would still
   be complete and usable in any text editor.

3. **Sync is the user's choice, and external to us.** We never sync for the user. The user
   points the app at one **library folder** and syncs that folder however they like — Dropbox,
   iCloud Drive, Google Drive, git, a USB stick. The system must therefore behave correctly
   when an external process adds, removes, or modifies files at any time, possibly from another
   device. **We are never the only writer.**

4. **The database is a disposable cache.** A local index makes listing and search fast, but it
   is *derived* from the files and can be rebuilt from scratch by re-scanning the library.
   - Never store anything in the DB that cannot be recovered from the files.
   - **Never put the DB inside the synced library folder, and never sync it.** It lives
     per-device (e.g. `~/Library/Application Support/ReadControl/`).
   - Store **relative** paths (from the library root), never absolute paths — they differ per
     device.

5. **Thin clients, one shared core.** All real logic lives in the Rust engine. Native UIs are
   thin layers over it. This keeps behavior identical everywhere and makes new platforms cheap.
   Logic is **not** duplicated in Swift or JavaScript.

## Features (the product)

- **Save to read later** — browser plugin. Capture and clean the current page, save it locally.
- **List of readings** — native app. Browse the library, organized by smart views:
  **All**, **Unread**, **Archive**, **Favorites**.
- **Search** — native app. Full-text search over readings (title, content, tags) via SQLite
  FTS5. Word-occurrence lookup and word meanings are noted as future ideas, not v1 scope.
- **Tags** — native app. Organize readings with labels stored in each file's frontmatter. (The
  macOS mockup's "Lists" section is implemented as **Tags** — manual Lists are not planned.)
- **Item states** — native app. Mark readings **read/unread**, **favorite**, and **archive**
  (stored in frontmatter).
- **Appearance** — native app. Light/Dark/System theme and adjustable reader typography
  (font, size, width, line height), stored as per-device preferences (not synced).

> The macOS UI is specified in [DESIGN.md](./DESIGN.md). An in-app **"Add Link"** (paste a URL)
> appears in the mockup but is **deferred** — page capture stays in the browser plugin for now.

## Decisions already made

- Markdown + YAML frontmatter as the storage format; files are the source of truth.
- HTML cleanup runs in the plugin (it has the live DOM).
- All logic in a Rust core crate; native UIs are thin and share it.
- The index is SQLite + FTS5, rebuildable, per-device, never synced.
- Use a **content-addressed id** — `SHA256(normalize(url))` — as the reading-folder name and
  frontmatter id; it doubles as the O(1) dedup key (hash the URL, stat the folder). Normalize URLs
  (strip `utm_*`, `fbclid`, etc.); `canonical_url` is stored as metadata, not the identity key.
- Start native clients with macOS / Swift (SwiftUI) via UniFFI.
- **Search (v1) is full-text over readings** (title, content, tags) using SQLite FTS5. Design
  the schema so word-occurrence lookup and a vector column can be added later without migration
  pain — but they are not v1 scope.
- **The plugin saves via a native messaging host** (thin wrapper over `core`), not
  the Downloads API.
- **Images are captured by the extension and written into the library** in each reading's own
  `assets/` folder (`articles/<prefix>/<id>/assets/`) with relative `assets/<file>` links, so saved
  readings stay readable offline and survive the source going away. The
  extension fetches each image (reusing the browser's cache) and sends the bytes; the host writes
  them and never makes network requests of its own.
- **The organizing model is Tags** (labels in frontmatter), not manual Lists. Smart views
  **All / Unread / Archive / Favorites** are backed by the frontmatter fields `read`,
  `archived`, and `favorite`.
- **UI preferences** (theme, reader font/size/width/line height) are per-device app
  preferences — not stored in the library and not synced.
- **In-app "Add Link" is deferred.** Page capture stays in the browser plugin; there is no
  engine-side fetch/extraction for now. See [DESIGN.md](./DESIGN.md).
- **Name:** the product is **ReadControl** (readcontrol.app); shown to end users as "ReadControl".
- **License / openness:** the project is **open source, multi-licensed by component**. The
  **browser plugin, engine (`core`), and native
  host are MIT** — as permissive as possible to drive adoption and let anyone embed them. The
  **macOS client is GPL-3.0-or-later** — public, but anyone distributing a modified client must
  share their changes. MIT is GPL-compatible, so the GPL client can embed the MIT engine while
  the engine stays independently MIT. Add matching `SPDX-License-Identifier` headers per
  component.

## Git commit message standards

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
type(scope): short description

Optional body explaining why, not what.
```

**Types:** `feat`, `fix`, `chore`, `docs`, `test`, `refactor`, `style`, `ci`, `build`, `perf`, `revert`.

**Scopes** are optional and must be **semantic** (lowercase, human-readable): `core`, `list`, `search`, `reader`, `shortcuts`, `sidebar`, `sort`, `selection`, `macos`, `clippy`, etc. — whatever describes the area of the code.

**Never put ticket or issue numbers in a commit message** — not in the subject, not in the body. No `feat(EXT-7):`, no `CORE-14: ...` section headers in the body, nothing. If a commit covers multiple areas, name the areas in the subject or body as plain prose.

**Never add `Co-Authored-By` trailers** referencing AI assistants (Claude, GitHub Copilot, etc.). Commit messages should read as first-person author voice.

Good examples:
```
feat: add tag picker sheet to the article header
fix(search): include archived items in search results
feat(core): add per-reading text highlights
test: isolate native-host library resolution from the host machine
```

Bad examples:
```
feat(EXT-7): options page with host status          ← ticket ref in scope
feat(CORE-14): tests covering the full core stack ← ticket ref in scope
CORE-6: scan_library() walks articles/...           ← ticket ref as body header
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>  ← AI co-author trailer
```

## Conventions for agents working here

- **Use the project's ubiquitous language.** Match the terms in
  [UBIQUITOUS_LANGUAGE.md](./UBIQUITOUS_LANGUAGE.md) in docs, code, UI, and commit messages.
- **Reference docs:** [ARCHITECTURE.md](./ARCHITECTURE.md) for the components, data flow, and data
  model; [DESIGN.md](./DESIGN.md) for the macOS UI/UX design.
- **Releasing:** a public release is the signed macOS `.dmg` on GitHub plus a Sparkle appcast
  entry. Follow [RELEASE.md](./RELEASE.md) for the runbook and record changes in
  [CHANGELOG.md](./CHANGELOG.md).
- Treat the **library format as a public contract** — version it; don't break readers/writers
  silently.
- Never write logic into Swift/JS that belongs in `core`.
- **The macOS reader is native SwiftUI — never use a WebView** (`WKWebView`/`WebKit`).
- Never assume single-writer access to the library; always reconcile against the files.
- Never persist anything important only in the DB, and never sync the DB.
- **Native UIs update optimistically; persistence happens in the background.** A mutation already
  runs off the main thread (the core call writes the file → syncs the index), but the UI must not
  *wait* on it. Pattern: patch the in-memory published state immediately so the change shows on the
  next frame, then `await` the core call and a refresh that reconciles against the index. The
  refresh is the self-heal — a failed write re-reads as the prior truth, so optimistic guesses can
  never get stuck wrong. Don't add manual rollback paths; let the refresh be authoritative.
- **When an action removes the selected row from the current view, advance in one motion.** If an
  optimistic status change pushes a row out of the active filter (e.g. Archive in *All*, Mark Read
  in *Unread*), remove it **and** move selection to an adjacent row in the *same* render tick —
  mirror the core's view/tag/rating filter client-side to decide. Flipping the icon in place and
  *then* letting the row jump on the later refresh reads as a two-stage stutter; one motion (the
  Mail model) does not. Membership *ordering* still settles on the refresh.
- Keep everything offline-capable; no network calls are required for core features.
- This is a **polyrepo**: plugin, engine+host, and client are separate repos. The library format
  and the native-messaging message contract are the cross-repo contracts — change them in
  lockstep across repos.
- Each sub-project (`core/`, `extension/`, `macos/`) is an
  **independent git repository with its own commit history**. They live inside this working
  directory for local convenience but are git-ignored by this meta repo. Always `cd` into the
  relevant sub-project directory before running `git` commands — running git from the root will
  only see the meta repo and will miss all changes made in the sub-projects.
