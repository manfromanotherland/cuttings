// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

// Shared pieces for offering the browser extension as a sideload-able download
// while it awaits Chrome Web Store and Firefox Add-ons review. Used by both the
// onboarding step (`ExtensionSetupView`) and the Settings › Extensions tab.

/// The short note explaining why the extension is a manual download for now, with
/// a link to the public source.
struct ExtensionApprovalNote: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(
                "The ReadControl extension is awaiting review on the Chrome Web Store and "
                    + "Firefox Add-ons. Until it's approved you can install it yourself as an "
                    + "unpacked developer build — it takes a minute."
            )
            .foregroundStyle(.secondary)

            Button("View the source on GitHub") {
                openURL(ExtensionPackage.sourceURL)
            }
            .buttonStyle(.link)
            .accessibilityIdentifier(A11y.Extensions.sourceLink)
        }
    }
}

/// The "Download Extension…" button. Copies the bundled archive to a location the
/// user picks. Hidden entirely if the archive somehow didn't ship in the bundle.
struct ExtensionDownloadButton: View {
    var prominent: Bool = false

    var body: some View {
        if ExtensionPackage.bundledZipURL != nil {
            Button {
                ExtensionPackage.save()
            } label: {
                Label("Download Extension…", systemImage: "arrow.down.circle")
            }
            .modifier(ProminenceModifier(prominent: prominent))
            .accessibilityIdentifier(A11y.Extensions.download)
        }
    }

    /// `.borderedProminent` for the onboarding call-to-action, plain bordered for
    /// the settings row.
    private struct ProminenceModifier: ViewModifier {
        let prominent: Bool

        func body(content: Content) -> some View {
            if prominent {
                content.buttonStyle(.borderedProminent)
            } else {
                content
            }
        }
    }
}

/// Step-by-step "load unpacked" instructions for the Chromium browsers and
/// Firefox. Deliberately terse — the copy matches what each browser calls the
/// buttons so users can follow along.
struct ExtensionInstallSteps: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            browser(
                "Chrome, Edge & Brave",
                steps: [
                    "Unzip the downloaded file.",
                    "Open chrome://extensions",
                    "Turn on Developer mode (top-right).",
                    "Click Load unpacked and choose the unzipped folder."
                ]
            )

            browser(
                "Firefox",
                steps: [
                    "Unzip the downloaded file.",
                    "Open about:debugging#/runtime/this-firefox",
                    "Click Load Temporary Add-on… and pick the manifest.json inside the unzipped folder."
                ],
                footnote: "Firefox drops temporary add-ons when it restarts, so you'll re-add it "
                    + "each launch until the signed version ships."
            )
        }
    }

    @ViewBuilder
    private func browser(_ name: String, steps: [String], footnote: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .font(.headline)

            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(index + 1).")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text(step)
                }
            }

            if let footnote {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }
}
