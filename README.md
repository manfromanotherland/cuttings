# read-later-macos

The macOS client (Swift / SwiftUI) for **read-later**, a local-first read-it-later system.
Browse, read, search, and tag your saved readings, organized by smart views
(All / Unread / Archive / Favorites). It embeds the Rust engine (`read-later-core`) via UniFFI
and watches the library folder for changes that arrive via the user's own sync.

**License:** GPL-3.0-or-later — see [LICENSE](./LICENSE). This is the copyleft application of the
project; the engine and plugin are MIT. Redistributing a modified build requires sharing your
source under the GPL.

Part of the read-later project. Architecture (`AGENTS.md`), UI design (`DESIGN.md`), the
library-format contract, and the backlog (`TICKETS.md`) live in the project's meta/spec repo.
