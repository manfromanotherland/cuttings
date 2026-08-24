// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Sparkle
import SwiftUI

@main
struct CuttingsApp: App {
    @State private var appState = AppState()
    @AppStorage("appearanceMode", store: AppDefaults.store) private var appearanceMode: AppearanceMode = .system

    /// Sparkle's updater. It reads its feed URL and EdDSA public key from
    /// Info.plist (`SUFeedURL` / `SUPublicEDKey`), so there is nothing to wire up
    /// here beyond owning it and exposing the "Check for Updates…" command.
    private let updaterController: SPUStandardUpdaterController

    init() {
        // Single-window app: disable macOS automatic window tabbing so the
        // "New Tab", "Show Tab Bar", and "Move Tab to New Window" items never appear.
        NSWindow.allowsAutomaticWindowTabbing = false

        // Keep the updater dormant under UI testing: the XCUITest suite runs
        // against a throwaway library and must stay offline and non-interactive,
        // so we never start background checks that could fire a "new version
        // available" dialog and steal focus mid-test.
        updaterController = SPUStandardUpdaterController(
            startingUpdater: !TestHooks.isUITesting,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .frame(minWidth: 900, minHeight: 600)
                .onChange(of: appearanceMode, initial: true) { _, mode in
                    NSApplication.shared.appearance = mode.nsAppearance
                }
        }
        // Open roomy the first time (no saved frame yet); afterwards SwiftUI
        // restores the size the user left it at, so `.defaultSize` is ignored.
        .defaultSize(width: 1100, height: 720)
        .windowStyle(.titleBar)
        // `showsTitle: false` drops the title from the titlebar entirely, so the
        // reading list's toolbar section starts at the column's leading edge
        // instead of behind a reserved (and empty) title region. Setting
        // `NSWindow.titleVisibility` from AppKit doesn't hold: SwiftUI re-applies
        // it every time `.navigationTitle` changes, which the reader does on each
        // selection.
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {}
            UpdateCommands(updater: updaterController.updater)
            ArticleCommands(appState: appState)
            TypographyCommands()
            AppearanceCommands(appearanceMode: $appearanceMode)
            NavigationCommands(appState: appState)
            HelpCommands(appState: appState)
        }

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
