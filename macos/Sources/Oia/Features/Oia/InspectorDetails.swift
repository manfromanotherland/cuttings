// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct InspectorSource: View {
    let row: ReadingRow

    var body: some View {
        if let url = row.sourceURL {
            Button { ReadingLink.open(url) } label: {
                HStack(spacing: 4) {
                    Text(url.host() ?? row.displaySite ?? "Open source")
                        .lineLimit(1).truncationMode(.middle)
                    Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .medium))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.system(size: 12))
            .help(url.absoluteString)
            .contextMenu {
                Button("Copy source URL") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }
            }
        } else {
            Text("Saved locally").font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}

struct InspectorDetails: View {
    let row: ReadingRow
    let inspector: ReadingInspector?
    let failed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(row.kind == .article ? "Saved preview" : "File")
                .font(.system(size: 12, weight: .semibold))
            if let file = inspector?.file {
                fact("Format", file.format)
                if let width = file.width, let height = file.height {
                    fact("Dimensions", "\(width) × \(height) px")
                }
                fact("Size", ByteCountFormatter.string(
                    fromByteCount: Int64(clamping: file.byteCount), countStyle: .file
                ))
                fact("Storage", "Saved on this Mac")
            } else if let inspector {
                Text(inspector.hasLocalFile ? "Local file is unavailable." : "No local media file.")
                    .foregroundStyle(.secondary)
            } else if failed {
                Text("File details couldn’t be loaded.").foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small).accessibilityLabel("Loading file details")
            }
            Divider().opacity(0.5)
            fact("Saved", Self.savedDate(row.savedAt))
            if let author = row.author, !author.isEmpty { fact("Author", author) }
        }
        .font(.system(size: 12))
        .accessibilityIdentifier(A11y.Inspector.file)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
    }

    static func savedDate(_ value: String) -> String {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        return date?.formatted(date: .abbreviated, time: .omitted) ?? value
    }
}
