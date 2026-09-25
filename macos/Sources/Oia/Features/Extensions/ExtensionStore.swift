// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

// Public Óia store listings do not exist yet. Settings shows availability
// until official URLs are available.

/// Browser availability rows. These are deliberately non-interactive until the
/// Óia extension has official store listings.
struct ExtensionStoreLinks: View {
    var body: some View {
        ExtensionStoreAvailability(
            name: "Chrome",
            detail: "Also Edge, Brave, and other Chromium browsers",
            accessibilityID: A11y.Extensions.chromeLink
        )
        ExtensionStoreAvailability(
            name: "Firefox",
            detail: "Firefox 115 or newer",
            accessibilityID: A11y.Extensions.firefoxLink
        )
    }
}

private struct ExtensionStoreAvailability: View {
    let name: String
    let detail: String
    let accessibilityID: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("Coming soon")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier(accessibilityID)
    }
}
