// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

@main
struct ReadLaterApp: App {
    @StateObject private var appState = AppState()
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
                .preferredColorScheme(appearanceMode.colorScheme)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            ArticleCommands(appState: appState)
            AppearanceCommands(appearanceMode: $appearanceMode)
            TypographyCommands()
        }
    }
}
