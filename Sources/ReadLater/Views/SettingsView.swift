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

            NativeHostSettingsTab()
                .tabItem { Label("Extensions", systemImage: "puzzlepiece.extension") }
        }
        .frame(width: 440)
        .padding(20)
    }
}

// ── Appearance ────────────────────────────────────────────────────────────────

private struct AppearanceSettingsTab: View {
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system

    var body: some View {
        Form {
            Picker("Theme", selection: $appearanceMode) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
        .formStyle(.grouped)
        .frame(minHeight: 120)
    }
}

// ── Typography ────────────────────────────────────────────────────────────────

private struct TypographySettingsTab: View {
    @AppStorage("readerFont") private var readerFont: ReaderFont = .system
    @AppStorage("readerFontSize") private var readerFontSize: ReaderFontSize = .medium

    var body: some View {
        Form {
            Picker("Font", selection: $readerFont) {
                ForEach(ReaderFont.allCases) { font in
                    Text(font.label).tag(font)
                }
            }
            .pickerStyle(.segmented)

            Picker("Size", selection: $readerFontSize) {
                ForEach(ReaderFontSize.allCases) { size in
                    Text(size.label).tag(size)
                }
            }
            .pickerStyle(.segmented)

            Text("The quick brown fox jumps over the lazy dog.")
                .font(.custom(previewFontName, size: CGFloat(readerFontSize.rawValue)))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        }
        .formStyle(.grouped)
        .frame(minHeight: 160)
    }

    private var previewFontName: String {
        switch readerFont {
        case .system: return "-apple-system"
        case .serif: return "Georgia"
        case .mono: return "Menlo"
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
        }
        .formStyle(.grouped)
        .frame(minHeight: 120)
    }
}

// ── Native Host ───────────────────────────────────────────────────────────────

private struct NativeHostSettingsTab: View {
    @State private var hostPath: String? = HostInstaller.bundledHostURL()?.path
    @State private var installed: Bool = false
    @State private var reinstalling: Bool = false

    var body: some View {
        Form {
            LabeledContent("Binary") {
                Text(hostPath ?? "Not found in bundle")
                    .font(.caption)
                    .foregroundStyle(hostPath != nil ? Color.secondary : Color.red)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            LabeledContent("Manifest") {
                HStack {
                    Image(systemName: installed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(installed ? .green : .orange)
                    Text(installed ? "Installed" : "Not installed")
                        .foregroundStyle(.secondary)
                }
            }

            Button(reinstalling ? "Installing…" : "Reinstall Manifest") {
                reinstalling = true
                UserDefaults.standard.removeObject(forKey: "nativeHostInstalledPath")
                installed = HostInstaller.installIfNeeded()
                reinstalling = false
            }
            .disabled(hostPath == nil || reinstalling)
        }
        .formStyle(.grouped)
        .frame(minHeight: 140)
        .onAppear {
            let lastPath = UserDefaults.standard.string(forKey: "nativeHostInstalledPath")
            installed = lastPath != nil && lastPath == hostPath
        }
    }
}
