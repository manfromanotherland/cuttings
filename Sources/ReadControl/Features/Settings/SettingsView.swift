// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            AppearanceSettingsTab()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }

            TypographySettingsTab()
                .tabItem { Label("Typography", systemImage: "textformat") }

            LibrarySettingsTab()
                .tabItem { Label("Library", systemImage: "folder") }

            ExtensionsSettingsTab()
                .tabItem { Label("Extensions", systemImage: "puzzlepiece.extension") }
        }
        .frame(width: 440)
        .padding(20)
    }
}

// ── Appearance ────────────────────────────────────────────────────────────────

private struct AppearanceSettingsTab: View {
    @AppStorage("appearanceMode", store: AppDefaults.store) private var appearanceMode: AppearanceMode = .system

    var body: some View {
        Form {
            Picker("Theme", selection: $appearanceMode) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier(A11y.Settings.themePicker)
        }
        .formStyle(.grouped)
        .frame(minHeight: 120)
        .accessibilityIdentifier(A11y.Settings.appearanceTab)
    }
}

// ── Typography ────────────────────────────────────────────────────────────────

private struct TypographySettingsTab: View {
    @AppStorage("readerFont", store: AppDefaults.store) private var readerFont: ReaderFont = .system
    @AppStorage("readerFontSize", store: AppDefaults.store) private var readerFontSize: ReaderFontSize = .medium

    var body: some View {
        Form {
            Picker("Font", selection: $readerFont) {
                ForEach(ReaderFont.allCases) { font in
                    Text(font.label).tag(font)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier(A11y.Settings.fontPicker)

            Picker("Size", selection: $readerFontSize) {
                ForEach(ReaderFontSize.allCases) { size in
                    Text(size.label).tag(size)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier(A11y.Settings.sizePicker)

            Text("The quick brown fox jumps over the lazy dog.")
                .font(.custom(previewFontName, size: CGFloat(readerFontSize.rawValue)))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        }
        .formStyle(.grouped)
        .frame(minHeight: 160)
        .accessibilityIdentifier(A11y.Settings.typographyTab)
    }

    private var previewFontName: String {
        switch readerFont {
        case .system: "-apple-system"
        case .serif: "Georgia"
        case .mono: "Menlo"
        }
    }
}

// ── Library ───────────────────────────────────────────────────────────────────

private struct LibrarySettingsTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            LabeledContent("Location") {
                if let url = appState.libraryURL {
                    Text(url.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                } else {
                    Text("Not configured")
                        .foregroundStyle(.secondary)
                }
            }

            Button("Change Library…") {
                appState.chooseLibrary()
            }
            .accessibilityIdentifier(A11y.Settings.changeLibrary)
        }
        .formStyle(.grouped)
        .frame(minHeight: 120)
        .accessibilityIdentifier(A11y.Settings.libraryTab)
    }
}

// ── Extensions ────────────────────────────────────────────────────────────────

// Public store listings for the browser extension. Commented out while the
// extension is under Chrome Web Store / Firefox Add-ons review — until it's
// approved the app hands out the packaged download below instead. Restore these
// (and the `ExtensionLink` rows) once the listings go live.
//
// private enum ExtensionStore {
//     static let chrome = URL(string: "https://chromewebstore.google.com/")!
//     static let firefox = URL(string: "https://addons.mozilla.org/firefox/")!
// }

/// Offers the browser extension as a sideload-able download while it awaits store
/// review, with load-unpacked instructions. The native-messaging manifest is
/// installed automatically when the library boots (see `AppState.boot`), so once
/// the extension is loaded it connects to the app on its own.
private struct ExtensionsSettingsTab: View {
    var body: some View {
        Form {
            // Store listings — restore when the extension is approved:
            //
            // Section {
            //     ExtensionLink(
            //         name: "Chrome",
            //         detail: "Also Edge, Brave, and other Chromium browsers",
            //         url: ExtensionStore.chrome,
            //         accessibilityID: A11y.Settings.chromeExtensionLink
            //     )
            //     ExtensionLink(
            //         name: "Firefox",
            //         detail: "Firefox 115 or newer",
            //         url: ExtensionStore.firefox,
            //         accessibilityID: A11y.Settings.firefoxExtensionLink
            //     )
            // } header: {
            //     Text("Get the browser extension")
            // } footer: {
            //     Text("Install the extension in your browser to save pages to your library.")
            // }

            Section {
                ExtensionApprovalNote()
                ExtensionDownloadButton()
            } header: {
                Text("Get the browser extension")
            }

            Section {
                ExtensionInstallSteps()
            } header: {
                Text("Install it as a developer build")
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 320)
        // Let users copy the URLs and steps rather than retype them (matches the
        // onboarding step). Applied via the environment, so it reaches the Text in
        // the child components too.
        .textSelection(.enabled)
        .accessibilityIdentifier(A11y.Settings.extensionsTab)
    }
}

// One store row: browser name, a short note, and an open-in-browser hint.
// Restore alongside the store-listing section above once the extension is
// approved and the `ExtensionStore` URLs go live.
//
// private struct ExtensionLink: View {
//     let name: String
//     let detail: String
//     let url: URL
//     let accessibilityID: String
//
//     @Environment(\.openURL) private var openURL
//
//     var body: some View {
//         Button {
//             openURL(url)
//         } label: {
//             HStack(spacing: 12) {
//                 VStack(alignment: .leading, spacing: 2) {
//                     Text(name)
//                         .foregroundStyle(.primary)
//                     Text(detail)
//                         .font(.caption)
//                         .foregroundStyle(.secondary)
//                 }
//
//                 Spacer()
//
//                 Image(systemName: "arrow.up.forward.square")
//                     .foregroundStyle(.secondary)
//             }
//             .contentShape(Rectangle())
//         }
//         .buttonStyle(.plain)
//         .accessibilityIdentifier(accessibilityID)
//     }
// }
