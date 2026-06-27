// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import AppKit

@main
struct ReadLaterApp: App {
    @StateObject private var appState = AppState()
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system

    init() {
        // Single-window app: disable macOS automatic window tabbing so the
        // "New Tab", "Show Tab Bar", and "Move Tab to New Window" items never appear.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
                .onChange(of: appearanceMode, initial: true) { _, mode in
                    NSApplication.shared.appearance = mode.nsAppearance
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            ArticleCommands(appState: appState)
            TypographyCommands()
            AppearanceCommands(appearanceMode: $appearanceMode)
            NavigationCommands(appState: appState)
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
