// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Persists and resolves a security-scoped bookmark for the library folder.
///
/// macOS sandboxed apps lose access to user-chosen folders after reboot unless
/// the URL is stored as a security-scoped bookmark. This type handles the
/// full bookmark lifecycle: save, resolve, and start/stop accessing.
enum LibraryBookmark {
    private static let key = "libraryBookmark"

    // ── Save ──────────────────────────────────────────────────────────────

    static func save(url: URL) throws {
        let data = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(data, forKey: key)
    }

    // ── Resolve ───────────────────────────────────────────────────────────

    /// Returns a started security-scoped URL, or nil if no bookmark is stored.
    /// Caller must call `url.stopAccessingSecurityScopedResource()` when done.
    static func resolve() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        if isStale, let refreshed = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(refreshed, forKey: key)
        }

        guard url.startAccessingSecurityScopedResource() else { return nil }
        return url
    }

    // ── Clear ─────────────────────────────────────────────────────────────

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
