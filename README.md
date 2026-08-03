<p align="center">
  <img src="https://raw.githubusercontent.com/readcontrol/root/main/assets/icon.png" alt="ReadControl" width="128">
</p>
<h1 align="center">ReadControl</h1>
<p align="center">
  The native macOS reading manager
  <br />
  <a href="https://github.com/readcontrol/macos">macOS</a>
  ·
  <a href="https://github.com/readcontrol/core">core</a>
  ·
  <a href="https://github.com/readcontrol/extension">extension</a>
  ·
  <a href="https://github.com/readcontrol/root">root</a>
</p>

---

The native macOS reading manager. Save any webpage on your computer, read it anytime. No account needed. It's totally free.

## Principles

- **Local-first & offline** — everything works with no network and no backend.
- **Files are the source of truth** — each reading is a Markdown file with YAML frontmatter;
  content, tags, read state, and source URL all live in the file.
- **You bring your own sync** — point the app at one *library folder* and sync it however you
  like (Dropbox, iCloud Drive, Google Drive, git…). The app never syncs for you.
- **The database is a disposable cache** — a local index makes search fast but is rebuildable
  from the files and is never synced.
- **One shared core** — the domain logic lives in the Rust engine and is reused across clients.

## Components

Each component is its **own repository** (polyrepo). Clone the ones you need:

| Repo | Component | Stack |
|------|-----------|-------|
| [`root`](https://github.com/readcontrol/root) | meta/spec (this repo): docs, library-format contract, design, backlog | Markdown |
| [`core`](https://github.com/readcontrol/core) | engine + native messaging host (Cargo workspace) | Rust (SQLite + FTS5, UniFFI) |
| [`extension`](https://github.com/readcontrol/extension) | browser plugin | TypeScript, Manifest V3 |
| [`macos`](https://github.com/readcontrol/macos) | macOS client | Swift / SwiftUI |

The three app repos sit as folders **inside** this `readcontrol` folder for convenience
(git-ignored by the meta repo); each is still an independent repo with its own history.
See each repo's README for setup and run instructions.

## Development

Each repo has its own toolchain — see its README for setup. From the root, the `Makefile` drives
them all at once (no `cd`-ing between folders):

```bash
make lint          # lint every repo
make test          # test every repo
make build         # build every repo
make check         # lint + test (a quick pre-push gate)
make push          # git push each repo's current branch
make status        # git status across all repos
```

Run `make help` for the full list, or `make REPO=core test` to target one repo. Each maps to the
repo's native tools:

**Engine + native host (Rust) — `core`**
```bash
cargo build
cargo test
cargo clippy --all-targets --all-features -- -D warnings
cargo fmt --check
```

**Browser plugin (TypeScript) — `extension`**
```bash
npm install
npm run build        # bundle the MV3 extension
npm test             # Vitest unit tests
npm run lint         # ESLint + Prettier + tsc --noEmit
```

**macOS client (Swift) — `macos`**
```bash
xcodebuild build
xcodebuild test      # XCTest / XCUITest
swiftlint            # + swiftformat
```

### Docker sandbox

A reusable **Docker sandbox** pre-installs every toolchain (Node, Rust, Swift + linters), so you
can run a coding agent — e.g. [Claude Code](https://claude.com/claude-code) — across all the repos
in an isolated container with no per-session setup:

```bash
./scripts/sandbox-build.sh   # build + load the image (run on your host)
sbx run --template readcontrol/sandbox:1 claude -- "$(cat initial_sandbox_prompt.txt)" --dangerously-skip-permissions
```

The macOS app can't be built in the Linux sandbox (no Xcode) — it covers the Rust engine, the
extension, and lint/format for every repo. See [SANDBOX.md](./SANDBOX.md) for details.

## Documentation

- [ARCHITECTURE.md](./ARCHITECTURE.md) — components, data flow, and the library data model.
- [AGENTS.md](./AGENTS.md) — goals, principles, decisions, and conventions for contributors.
- [DESIGN.md](./DESIGN.md) — the macOS UI/UX design.
- [UBIQUITOUS_LANGUAGE.md](./UBIQUITOUS_LANGUAGE.md) — the shared product vocabulary (glossary).
- [docs/library-format.md](./docs/library-format.md) — **versioned library-format spec** (the cross-repo contract).
- [docs/native-messaging.md](./docs/native-messaging.md) — native messaging protocol (extension ↔ host).
- [docs/fixtures/](./docs/fixtures/) — sample article file, save request/response JSON.
