// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Inspector control for loading, previewing, and editing one reading's note.
struct ReadingNoteControl: View {
    @Environment(AppState.self) private var appState

    let readingID: String

    @State private var note: String?
    @State private var draft = ""
    @State private var isLoading = true
    @State private var loadedReadingID: String?
    @State private var showsEditor = false
    @State private var editorBaseline: String?
    @State private var pendingDiskNote: String?
    @State private var pendingSaveMarkdown: String?
    @State private var showsExternalChangeConfirmation = false
    @State private var isCheckingSave = false
    @State private var saveCheckTask: Task<Void, Never>?

    var body: some View {
        Group {
            if isLoading || loadedReadingID != readingID {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Loading note")
            } else {
                if let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(note)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(6)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier(A11y.Note.preview)
                }

                Button(hasNote ? "Edit note…" : "Add note…", action: openEditor)
                    .buttonStyle(.plain)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tint)
                    .accessibilityIdentifier(hasNote ? A11y.Note.edit : A11y.Note.add)
            }
        }
        .task(id: NoteLoadKey(readingID: readingID, revision: appState.noteRevision)) {
            let id = readingID
            if loadedReadingID != id {
                note = nil
                isLoading = true
            }
            let loaded = await appState.getNote(id: id)
            guard !Task.isCancelled else { return }
            if showsEditor, loaded != editorBaseline {
                pendingDiskNote = loaded
                pendingSaveMarkdown = nil
                showsExternalChangeConfirmation = true
            }
            note = loaded
            loadedReadingID = id
            isLoading = false
        }
        .sheet(isPresented: $showsEditor, onDismiss: cancelSaveCheck) {
            NoteEditorSheet(
                markdown: $draft,
                showsExternalChangeConfirmation: $showsExternalChangeConfirmation,
                hasExistingNote: hasNote,
                isCheckingSave: isCheckingSave,
                externalChangeActionLabel: pendingSaveMarkdown?
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true
                    ? "Delete latest note" : "Replace with my note",
                onCancel: cancelEditor,
                onSave: { checkAndSave(draft) },
                onDelete: { checkAndSave("") },
                onLoadLatest: loadLatestVersion,
                onOverwrite: { commitSave(pendingSaveMarkdown ?? draft) }
            )
        }
    }

    private var hasNote: Bool {
        note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func openEditor() {
        draft = note ?? ""
        editorBaseline = note
        pendingDiskNote = nil
        pendingSaveMarkdown = nil
        showsExternalChangeConfirmation = false
        showsEditor = true
    }

    /// Re-read immediately before saving so a synced edit that arrived before
    /// its coalesced FSEvent cannot be replaced without the user's knowledge.
    private func checkAndSave(_ markdown: String) {
        guard !isCheckingSave else { return }
        let id = readingID
        let baseline = editorBaseline
        isCheckingSave = true
        saveCheckTask = Task {
            let diskNote = await appState.getNote(id: id)
            guard !Task.isCancelled, showsEditor, readingID == id else { return }
            isCheckingSave = false
            saveCheckTask = nil
            if diskNote != baseline {
                note = diskNote
                pendingDiskNote = diskNote
                pendingSaveMarkdown = markdown
                showsExternalChangeConfirmation = true
            } else {
                commitSave(markdown)
            }
        }
    }

    private func loadLatestVersion() {
        draft = pendingDiskNote ?? ""
        editorBaseline = pendingDiskNote
        note = pendingDiskNote
        pendingDiskNote = nil
        pendingSaveMarkdown = nil
    }

    private func cancelEditor() {
        cancelSaveCheck()
        showsEditor = false
    }

    private func cancelSaveCheck() {
        saveCheckTask?.cancel()
        saveCheckTask = nil
        isCheckingSave = false
    }

    /// Update the inspector immediately, then reconcile with the note re-read by
    /// the core after its atomic write. A failed write restores the disk value.
    private func commitSave(_ markdown: String) {
        let id = readingID
        cancelSaveCheck()
        note = markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : markdown
        editorBaseline = nil
        pendingDiskNote = nil
        pendingSaveMarkdown = nil
        showsEditor = false
        Task {
            let persisted = await appState.setNote(id: id, markdown: markdown)
            guard appState.selectedId == id, loadedReadingID == id else { return }
            note = persisted
        }
    }
}

private struct NoteLoadKey: Equatable {
    let readingID: String
    let revision: UInt64
}
