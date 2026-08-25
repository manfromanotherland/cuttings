// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftUI

/// Optional metadata inspector for the Finder-style gallery detail. The gallery
/// remains the primary interface; this pane uses the platform's compact form
/// hierarchy when someone asks for more information.
struct CuttingsInspectorView: View {
    let row: ReadingRow
    var onEditTags: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            heading
            Divider()
            detailsForm
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(row.displayTitle)
                .font(.title2.weight(.semibold))
                .lineLimit(4)
                .textSelection(.enabled)

            HStack(spacing: 6) {
                Label(row.kind.singularLabel, systemImage: row.kind.symbol)
                Text("·")
                Text(savedDate)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    private var detailsForm: some View {
        Form {
            LabeledContent("Source") {
                sourceValue
            }

            LabeledContent("Tags") {
                tagsValue
            }

            if !row.canonicalUrl.isEmpty, row.canonicalUrl != row.url {
                LabeledContent("Canonical URL") {
                    selectableValue(row.canonicalUrl)
                }
            }

            if row.sourceURL != nil,
               let mediaURL = row.mediaUrl,
               row.kind == .image || row.kind == .video
            {
                LabeledContent(mediaURL.hasPrefix("cuttings-video:") ? "Playback" : "Media") {
                    if mediaURL.hasPrefix("cuttings-video:") {
                        Text("Open the source page to play this browser stream.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        selectableValue(mediaURL)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var sourceValue: some View {
        if let url = row.sourceURL {
            VStack(alignment: .leading, spacing: 5) {
                Button {
                    ReadingLink.open(url)
                } label: {
                    Label(row.displaySite ?? "Open Source", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.link)

                Text(row.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Label("Saved locally", systemImage: "internaldrive")
                Text("Clipboard or local file")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var tagsValue: some View {
        VStack(alignment: .leading, spacing: 8) {
            if row.tags.isEmpty {
                Text("None")
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(row.tags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }

            Button(action: onEditTags) {
                Label("Edit tags…", systemImage: "tag")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func selectableValue(_ value: String) -> some View {
        Text(value)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(3)
            .truncationMode(.middle)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var savedDate: String {
        guard let date = Self.parseISO8601(row.savedAt) else { return row.savedAt }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }
}
