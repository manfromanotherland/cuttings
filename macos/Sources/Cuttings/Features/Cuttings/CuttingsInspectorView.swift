// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct CuttingsInspectorView: View {
    @Environment(AppState.self) private var appState

    @Binding var row: ReadingRow
    var onEditTags: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                heading
                sourceSection
                noteSection
                tagsSection
                actionsSection
            }
            .padding(.horizontal, 26)
            .padding(.top, 72)
            .padding(.bottom, 30)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(row.kind.singularLabel, systemImage: row.kind.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(row.displayTitle)
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .lineLimit(5)
                .textSelection(.enabled)

            HStack(spacing: 6) {
                if let site = row.displaySite {
                    Text(site)
                }
                if !savedDate.isEmpty {
                    if row.displaySite != nil {
                        Text("·")
                    }
                    Text(savedDate)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var sourceSection: some View {
        inspectorSection("Source") {
            if let url = row.sourceURL {
                Button {
                    ReadingLink.open(url)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(row.title.isEmpty ? (row.displaySite ?? "Originating page") : row.title)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text(row.url)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Saved locally", systemImage: "internaldrive")
                        .font(.callout.weight(.medium))
                    Text("Added from the clipboard or a local file.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
            }

            if !row.canonicalUrl.isEmpty, row.canonicalUrl != row.url {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Canonical URL")
                        .font(.caption.weight(.medium))
                    Text(row.canonicalUrl)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
                .padding(.top, 6)
            }

            if row.sourceURL != nil,
               let mediaURL = row.mediaUrl,
               row.kind == .image || row.kind == .video
            {
                VStack(alignment: .leading, spacing: 3) {
                    Text(mediaURL.hasPrefix("cuttings-video:") ? "Playback" : "Direct media")
                        .font(.caption.weight(.medium))
                    if mediaURL.hasPrefix("cuttings-video:") {
                        Text("This video uses a temporary browser stream. Open its source page to play it.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(mediaURL)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    private var noteSection: some View {
        inspectorSection("Note") {
            ReadingNoteControl(readingID: row.id)
                .id(row.id)
        }
    }

    private var tagsSection: some View {
        inspectorSection("Tags") {
            if row.tags.isEmpty {
                Text("No tags")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(row.tags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                    }
                }
            }
            Button("Edit tags…", action: onEditTags)
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .foregroundStyle(.tint)
                .padding(.top, 4)
        }
    }

    private var actionsSection: some View {
        inspectorSection("Actions") {
            VStack(spacing: 3) {
                actionButton(
                    row.favorite ? "Remove from favorites" : "Add to favorites",
                    symbol: row.favorite ? "heart.slash" : "heart"
                ) { toggleFavorite() }
                actionButton("Delete", symbol: "trash", role: .destructive) {
                    appState.pendingDelete = row
                }
            }
        }
    }

    private func inspectorSection(
        _ title: String, @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
                .tracking(0.8)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionButton(
        _ title: String, symbol: String, role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 7)
    }

    private func toggleFavorite() {
        let old = row
        row.favorite.toggle()
        Task {
            await appState.toggleFavorite(old)
            row = await appState.reloadRow(id: old.id) ?? row
        }
    }

    private var savedDate: String {
        guard let date = ISO8601DateFormatter().date(from: row.savedAt) else { return row.savedAt }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
