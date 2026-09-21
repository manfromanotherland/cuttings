// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Search-first tag selection for the board filter. A native toolbar menu is a
/// poor fit for libraries with thousands of tags because AppKit materializes
/// every menu item at once. This sheet keeps the complete local tag vocabulary
/// searchable while rendering at most a small, useful result window.
struct TagFilterSheet: View {
    private static let resultLimit = 100

    let selectedTag: String?
    let onSelect: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var searchIndex: SearchIndex
    @FocusState private var searchFocused: Bool

    init(tags: [String], selectedTag: String?, onSelect: @escaping (String?) -> Void) {
        self.selectedTag = selectedTag
        self.onSelect = onSelect
        _searchIndex = State(initialValue: SearchIndex(tags: tags))
    }

    var body: some View {
        let result = searchIndex.matches(
            query: query, selectedTag: selectedTag, limit: Self.resultLimit
        )

        VStack(spacing: 0) {
            searchField
            Divider()
            List {
                if selectedTag != nil, query.isEmpty {
                    Button {
                        choose(nil)
                    } label: {
                        Label("Any Tag", systemImage: "line.3.horizontal.decrease.circle")
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                ForEach(result.tags, id: \.self) { tag in
                    Button {
                        choose(tag)
                    } label: {
                        HStack {
                            Text("#\(tag)")
                            Spacer()
                            if tag == selectedTag {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(A11y.Filter.tag(tag))
                }

                if result.tags.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else if result.hasMore {
                    Text("Showing the first \(Self.resultLimit) matches — keep typing to narrow them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.inset)

            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 420, height: 520)
        .accessibilityIdentifier(A11y.Filter.tagSheet)
        .onExitCommand { dismiss() }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search tags…", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .accessibilityIdentifier(A11y.Filter.tagSearch)
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

    private func choose(_ tag: String?) {
        onSelect(tag)
        dismiss()
    }
}

private struct SearchIndex {
    struct Result {
        var tags: [String]
        var hasMore: Bool
    }

    private struct Entry {
        var tag: String
        var folded: String
    }

    private let entries: [Entry]

    init(tags: [String]) {
        entries = tags.map { Entry(tag: $0, folded: $0.localizedLowercase) }
    }

    func matches(query: String, selectedTag: String?, limit: Int) -> Result {
        let needle = query.trimmingCharacters(in: .whitespaces).localizedLowercase
        var matches: [String] = []
        matches.reserveCapacity(limit)

        if needle.isEmpty, let selectedTag, entries.contains(where: { $0.tag == selectedTag }) {
            matches.append(selectedTag)
        }

        for entry in entries where entry.tag != selectedTag {
            guard needle.isEmpty || entry.folded.contains(needle) else { continue }
            if matches.count == limit {
                return Result(tags: matches, hasMore: true)
            }
            matches.append(entry.tag)
        }
        return Result(tags: matches, hasMore: false)
    }
}
