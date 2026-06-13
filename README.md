# read-later-extension

The browser plugin (Manifest V3, TypeScript) for **read-later**, a local-first read-it-later
system. It extracts and cleans the current page (Readability-style extraction + HTML→Markdown)
and hands the result to the native messaging host, which saves it into your library folder.

**License:** MIT — see [LICENSE](./LICENSE).

Part of the read-later project. Architecture (`AGENTS.md`), the library-format contract, and the
backlog (`TICKETS.md`) live in the project's meta/spec repo. The native messaging host lives in
the `read-later-core` repo.
