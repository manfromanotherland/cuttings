// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Modal tag picker for an article. A search field filters the library's tags;
/// with no query it lists the article's tags first, then others. Clicking a tag
/// toggles it on or off for the article (a checkmark marks applied tags). Typing
/// a name that doesn't exist yet offers an "Add" row — or press Return — to
/// create and apply it.
///
/// Changes apply live through `onToggle`, so the sheet stays open to manage
/// several tags in a row and closing needs no explicit save.
struct TagPickerSheet: View {
    /// Tags currently applied to the article. Re-supplied by the presenter on
    /// every render, so checkmarks stay in step as toggles take effect.
    var applied: [String]
    /// All library tag names, most-used first (the order of `AppState.allTags`).
    var allTags: [String]
    /// `(tag, shouldApply)` — apply the tag when `true`, remove it when `false`.
    var onToggle: (String, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    /// Display order, snapshotted when the sheet opens (applied tags first, then
    /// the rest) and held stable while open, so toggling a tag never reorders the
    /// list. Seeded in `init`, so it's correct on the first frame; re-derived each
    /// time the sheet reopens (fresh @State). Checkmarks track the live `applied`.
    @State private var order: [String]

    init(applied: [String], allTags: [String], onToggle: @escaping (String, Bool) -> Void) {
        self.applied = applied
        self.allTags = allTags
        self.onToggle = onToggle
        // Freeze the order at presentation: applied tags first, then the rest.
        let appliedSet = Set(applied)
        _order = State(initialValue: applied + allTags.filter { !appliedSet.contains($0) })
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }
    private var appliedSet: Set<String> { Set(applied) }

    /// The list contents, drawn from the frozen `order`: idle shows the first ten,
    /// searching shows every match. Applied tags already sit first in `order`.
    private var listed: [String] {
        let q = trimmedQuery.lowercased()
        if q.isEmpty { return Array(order.prefix(10)) }
        return order.filter { $0.lowercased().contains(q) }
    }

    /// The tag to offer creating — the typed name, when it doesn't already exist
    /// (case-insensitive). `nil` hides the "Add" row.
    private var creatable: String? {
        let q = trimmedQuery
        guard !q.isEmpty,
              !allTags.contains(where: { $0.caseInsensitiveCompare(q) == .orderedSame })
        else { return nil }
        return q
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            tagList
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 380, height: 460)
        // Esc closes the sheet even while the search field holds focus — a
        // focused TextField can swallow the Done button's cancel shortcut.
        .onExitCommand { dismiss() }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search or add tags…", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit(submit)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .onAppear { searchFocused = true }
    }

    private var tagList: some View {
        List {
            if let creatable {
                Button { apply(creatable) } label: {
                    Label("Add “\(creatable)”", systemImage: "plus.circle")
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            ForEach(listed, id: \.self) { tag in
                Button { toggle(tag) } label: {
                    HStack {
                        Text("#\(tag)")
                        Spacer()
                        if appliedSet.contains(tag) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if listed.isEmpty, creatable == nil {
                Text(allTags.isEmpty
                     ? "No tags yet — type to create one."
                     : "No matching tags.")
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.inset)
    }

    private func toggle(_ tag: String) {
        onToggle(tag, !appliedSet.contains(tag))
    }

    private func apply(_ tag: String) {
        // A freshly created tag isn't in the frozen order yet — surface it at the
        // top so it's visible (and within the idle first-ten).
        if !order.contains(tag) { order.insert(tag, at: 0) }
        onToggle(tag, true)
        query = ""
    }

    /// Return key: apply an existing exact match (case-insensitive) if there is
    /// one, otherwise create and apply the typed tag.
    private func submit() {
        let q = trimmedQuery
        guard !q.isEmpty else { return }
        if let existing = allTags.first(where: { $0.caseInsensitiveCompare(q) == .orderedSame }) {
            if !appliedSet.contains(existing) { onToggle(existing, true) }
        } else {
            if !order.contains(q) { order.insert(q, at: 0) }
            onToggle(q, true)
        }
        query = ""
    }
}
