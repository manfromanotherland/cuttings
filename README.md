<p align="center">
  <img src="./assets/icon.png" alt="Cuttings" width="128">
</p>
<h1 align="center">Cuttings</h1>
<p align="center">
  Keep what you find, with where it came from
  <br />
  <a href="./macos">macOS</a>
  ·
  <a href="./core">core</a>
  ·
  <a href="./extension">extension</a>
  ·
  <a href=".">root</a>
</p>

---

Cuttings is a native, local-first home for articles, images, videos, and quotes you find on the
web. Everything is stored as ordinary files in a folder you choose. No account or server needed.

## What Cuttings does

Cuttings turns things you find into a local, visual inspiration library. The browser extension can
save a full article, a right-clicked image or video, or selected text. The macOS client presents
those saves as a mixed masonry board of article, image, video, and quote cards. You can also drop
or paste a web link, text, image, or MP4/MOV video anywhere on the board. Local text, images, and
videos are copied into the library; a pasted link starts as a lightweight card that a later browser
save can enrich with the cleaned article.

Web cards retain their origin page URL, canonical URL, page title/site, and save date. Image and
video cards additionally retain a durable media URL when the browser exposes one; session-local
video streams receive a compact stable capture reference instead. Captured and locally pasted
images, video posters, and locally imported video files are stored inside the card's own folder.
Remote browser video files themselves are not downloaded. The library remains plain files in a
user-selected iCloud Drive, Dropbox, or other folder.

Every card can also carry a personal Markdown note. Notes live as optional `note.md` files inside
the same reading folder, so they remain editable without Cuttings and travel with the saved item.

## Principles

- **Local-first & offline** — everything works with no network and no backend.
- **Files are the source of truth** — each saved item is a Markdown file with YAML frontmatter;
  content, tags, favorite state, and source URL live in that file, with an optional personal `note.md`
  beside it.
- **You bring your own sync** — point the app at one *library folder* and sync it however you
  like (Dropbox, iCloud Drive, Google Drive, git…). The app never syncs for you.
- **The database is a disposable cache** — a local index makes search fast but is rebuildable
  from the files and is never synced.
- **One shared core** — the domain logic lives in the Rust engine and is reused across clients.

## Components

Cuttings is a **monorepo**. Clone it once to get the product contracts and all three components:

| Path | Component | Stack |
|------|-----------|-------|
| [repository root](.) | product docs, library-format contract, design, backlog | Markdown |
| [`core`](./core) | engine + native messaging host (Cargo workspace) | Rust (SQLite + FTS5, UniFFI) |
| [`extension`](./extension) | browser extension for page, media, and quote capture | TypeScript, Manifest V3 |
| [`macos`](./macos) | native visual inspiration library and article viewer | Swift / SwiftUI |

All paths share one Git history, so a library-format or native-messaging change can update every
affected component in one atomic commit. See each component's README for setup and run instructions.

## Development

Each component keeps its native toolchain — see its README for setup. From the repository root,
the `Makefile` drives them all at once (no `cd`-ing between folders):

```bash
make lint          # lint every component
make test          # test every component
make build         # build every component
make check         # lint + test (a quick pre-push gate)
make push          # git push the monorepo's current branch once
make status        # git status for the monorepo
```

Run `make help` for the full list, or `make COMPONENT=core test` to target one component. Component
selection applies to quality commands; Git commands always operate on the whole monorepo. Each
quality command maps to the component's native tools:

**Engine + native host (Rust) — `core`**
```bash
cd core
cargo build
cargo test
cargo clippy --all-targets --all-features -- -D warnings
cargo fmt --check
```

**Browser extension (TypeScript) — `extension`**
```bash
cd extension
npm install
npm run build        # bundle the MV3 extension
npm test             # Vitest unit tests
npm run lint         # ESLint + Prettier + tsc --noEmit
```

**macOS client (Swift) — `macos`**
```bash
cd macos
xcodebuild build
xcodebuild test      # XCTest / XCUITest
swiftlint            # + swiftformat
```

### Docker sandbox

A reusable **Docker sandbox** pre-installs every toolchain (Node, Rust, Swift + linters), so you
can run a coding agent — e.g. [Claude Code](https://claude.com/claude-code) — across the monorepo
in an isolated container with no per-session setup:

```bash
./scripts/sandbox-build.sh   # build + load the image (run on your host)
sbx run --template cuttings/sandbox:1 claude -- "$(cat initial_sandbox_prompt.txt)" --dangerously-skip-permissions
```

The macOS app can't be built in the Linux sandbox (no Xcode) — it covers the Rust engine, the
extension, and macOS lint/format. See [SANDBOX.md](./SANDBOX.md) for details.

## Documentation

- [ARCHITECTURE.md](./ARCHITECTURE.md) — components, data flow, and the library data model.
- [AGENTS.md](./AGENTS.md) — goals, principles, decisions, and conventions for contributors.
- [DESIGN.md](./DESIGN.md) — the macOS UI/UX design.
- [UBIQUITOUS_LANGUAGE.md](./UBIQUITOUS_LANGUAGE.md) — the shared product vocabulary (glossary).
- [docs/library-format.md](./docs/library-format.md) — **versioned library-format spec** (the cross-component contract).
- [docs/native-messaging.md](./docs/native-messaging.md) — native messaging protocol (extension ↔ host).
- [docs/fixtures/](./docs/fixtures/) — sample article file, save request/response JSON.

## Releases

What users download is the macOS app — a signed `.dmg` published on GitHub with a
Sparkle appcast entry for in-app updates.

- [RELEASE.md](./RELEASE.md) — the step-by-step release runbook.
- [CHANGELOG.md](./CHANGELOG.md) — notable changes per version.
