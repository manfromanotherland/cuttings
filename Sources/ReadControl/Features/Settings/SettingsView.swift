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

/// The public store listings for the browser extension. The native-messaging
/// manifest is installed automatically when the library boots (see
/// `AppState.boot`), so once the extension is installed it connects to the app on
/// its own. The store links themselves live in `ExtensionStore.swift`, shared with
/// the onboarding step.
private struct ExtensionsSettingsTab: View {
    var body: some View {
        Form {
            Section {
                ExtensionStoreLinks()
            } header: {
                Text("Get the browser extension")
            } footer: {
                Text("Install the extension in your browser to save pages to your library.")
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 200)
        // Let users copy the links rather than retype them.
        .textSelection(.enabled)
        .accessibilityIdentifier(A11y.Settings.extensionsTab)
    }
}
