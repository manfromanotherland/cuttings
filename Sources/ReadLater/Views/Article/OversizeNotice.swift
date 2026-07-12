// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import AppKit

/// Shown instead of the reader when a reading's body is too large to parse (see
/// `ArticleDetailView.maxParseBytes` / `maxParseWords`). The full text is still
/// available in the browser.
struct OversizeNotice: View {
    let url: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("This article is too large to display in the reader")
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Open it in your browser to read the full text.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            if let link = URL(string: url) {
                Button("Open in Browser") {
                    NSWorkspace.shared.open(link)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
                .accessibilityIdentifier(A11y.Detail.oversizeOpenInBrowser)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .accessibilityIdentifier(A11y.Detail.oversize)
    }
}
