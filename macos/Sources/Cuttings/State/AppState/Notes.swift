// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// ── Personal notes ──────────────────────────────────────────────────────────

extension AppState {
    /// Load the optional personal Markdown note attached to a reading.
    func getNote(id: String) async -> String? {
        guard let core else { return nil }
        do {
            return try await core.getNote(readingId: id)
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    /// Persist a complete Markdown note, then re-read it as the authoritative
    /// value. Blank Markdown clears the note and therefore returns `nil`.
    @discardableResult
    func setNote(id: String, markdown: String) async -> String? {
        guard let core else { return nil }
        let hasNote = !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        applyOptimisticNotePresence(id: id, hasNote: hasNote)
        do {
            try await core.setNote(readingId: id, markdown: markdown)
            let persisted = try await core.getNote(readingId: id)
            await loadReadings(resetSelectionIfMissing: false)
            return persisted
        } catch {
            self.error = error.localizedDescription
            await loadReadings(resetSelectionIfMissing: false)
            return try? await core.getNote(readingId: id)
        }
    }
}
