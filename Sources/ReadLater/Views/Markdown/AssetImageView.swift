// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Renders a single Markdown image natively, with an optional caption drawn from
/// the image's alt text (a "figure"). Local library assets
/// (`../assets/<id>/<file>`) load from disk under `libraryURL/assets/`;
/// remote `http(s)` images use `AsyncImage`. Replaces the `readlater://`
/// custom-scheme handler the WebView relied on.
struct AssetImageView: View {
    let source: String
    let alt: String
    let libraryURL: URL?
    let theme: MarkdownTheme

    @State private var localImage: NSImage?
    @State private var failed = false

    var body: some View {
        VStack(spacing: theme.captionGap) {
            picture
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: theme.imageCornerRadius))
                .accessibilityLabel(alt)
            if !alt.isEmpty {
                Text(alt)
                    .font(theme.captionFont)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var picture: some View {
        if let url = remoteURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                case .failure:
                    placeholder
                default:
                    ProgressView().frame(maxWidth: .infinity, minHeight: 80)
                }
            }
        } else if let localImage {
            Image(nsImage: localImage)
                .resizable()
                .scaledToFit()
        } else if failed {
            placeholder
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 80)
                .task(id: source) { await loadLocal() }
        }
    }

    private var placeholder: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo")
            Text(alt.isEmpty ? "Image unavailable" : alt)
        }
        .foregroundStyle(.secondary)
        .font(.callout)
        .frame(maxWidth: .infinity, minHeight: 80)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: theme.imageCornerRadius))
    }

    // ── Resolution ──────────────────────────────────────────────────────────

    private var remoteURL: URL? {
        guard let scheme = URL(string: source)?.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return nil }
        return URL(string: source)
    }

    /// Resolve a relative library asset path to an on-disk URL. The stored
    /// Markdown references assets as `../assets/<id>/<file>`; strip the known
    /// prefixes and resolve under `libraryURL/assets/` (the path the old
    /// `AssetSchemeHandler` reconstructed).
    private var localURL: URL? {
        guard let libraryURL else { return nil }
        var path = source
        for prefix in ["../assets/", "./assets/", "assets/"] {
            if path.hasPrefix(prefix) {
                path = String(path.dropFirst(prefix.count))
                break
            }
        }
        return libraryURL
            .appendingPathComponent("assets")
            .appendingPathComponent(path)
    }

    private func loadLocal() async {
        guard let url = localURL else { failed = true; return }
        // Read bytes off the main actor (Data is Sendable; NSImage is not).
        let data = await Task.detached(priority: .userInitiated) {
            try? Data(contentsOf: url)
        }.value
        if let data, let image = NSImage(data: data) {
            localImage = image
        } else {
            failed = true
        }
    }
}
