// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

// The public store listings for the Cuttings browser extension, now that it's
// live on the Chrome Web Store and Firefox Add-ons. Shared by the onboarding step
// (`ExtensionStep`) and the Settings › Extensions tab.

/// The official store listings for the browser extension.
enum ExtensionStore {
    static let chrome = URL(
        string: "https://chromewebstore.google.com/detail/cuttings/cegehgdbbjjeondepcaejickdmkacbck"
    )!
    static let firefox = URL(
        string: "https://addons.mozilla.org/en-US/firefox/addon/cuttings"
    )!
}

/// The Chrome and Firefox store rows. A `@ViewBuilder` body of two sibling rows
/// (rather than a wrapping container) so it flattens into separate rows inside the
/// Settings `Form` while still stacking naturally in the onboarding step's `VStack`.
struct ExtensionStoreLinks: View {
    var body: some View {
        ExtensionStoreLink(
            name: "Chrome",
            detail: "Also Edge, Brave, and other Chromium browsers",
            url: ExtensionStore.chrome,
            accessibilityID: A11y.Extensions.chromeLink
        )
        ExtensionStoreLink(
            name: "Firefox",
            detail: "Firefox 115 or newer",
            url: ExtensionStore.firefox,
            accessibilityID: A11y.Extensions.firefoxLink
        )
    }
}

/// One store row: browser name, a short note, and an open-in-browser hint. Opens
/// the public listing in the user's default browser.
private struct ExtensionStoreLink: View {
    let name: String
    let detail: String
    let url: URL
    let accessibilityID: String

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(url)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.up.forward.square")
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityID)
    }
}
