// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Focused raw-Markdown editor for one reading's personal note.
struct NoteEditorSheet: View {
    @Binding var markdown: String
    @Binding var showsExternalChangeConfirmation: Bool
    let hasExistingNote: Bool
    let isCheckingSave: Bool
    let externalChangeActionLabel: String
    let onCancel: () -> Void
    let onSave: () -> Void
    let onDelete: () -> Void
    let onLoadLatest: () -> Void
    let onOverwrite: () -> Void

    @FocusState private var editorFocused: Bool
    @State private var showsDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Note")
                    .font(.title2.weight(.semibold))
                Text("Write in Markdown. The note is saved with this item in your library.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Markdown")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextEditor(text: $markdown)
                    .font(.system(.body, design: .monospaced))
                    .focused($editorFocused)
                    .disabled(isCheckingSave)
                    .accessibilityLabel("Markdown note")
                    .accessibilityIdentifier(A11y.Note.editor)
            }
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            HStack(spacing: 10) {
                if hasExistingNote {
                    Button("Delete note", role: .destructive) {
                        showsDeleteConfirmation = true
                    }
                    .disabled(isCheckingSave)
                    .accessibilityIdentifier(A11y.Note.delete)
                }

                Spacer()

                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier(A11y.Note.cancel)

                if isCheckingSave {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Checking note")
                } else {
                    Button("Save note", action: onSave)
                        .keyboardShortcut(.defaultAction)
                        .disabled(markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            && !hasExistingNote)
                        .accessibilityIdentifier(A11y.Note.save)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
        }
        .frame(minWidth: 560, idealWidth: 640, minHeight: 440, idealHeight: 520)
        .onAppear { editorFocused = true }
        .onExitCommand {
            guard !showsDeleteConfirmation, !showsExternalChangeConfirmation else { return }
            onCancel()
        }
        .confirmationDialog(
            "Delete this note?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete note", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The note file will be removed from your library.")
        }
        .alert(
            "This note changed on disk",
            isPresented: $showsExternalChangeConfirmation
        ) {
            Button("Load latest version", action: onLoadLatest)
            Button(externalChangeActionLabel, role: .destructive, action: onOverwrite)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A newer version was saved outside Cuttings. Load it or replace it with the text in this editor.")
        }
    }
}
