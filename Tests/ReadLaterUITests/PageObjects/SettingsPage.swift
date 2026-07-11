// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// The Settings window (⌘,). Most personalization journeys use the sidebar
/// appearance popover (`SidebarPage`); this covers the full window when needed.
struct SettingsPage {
    let app: XCUIApplication

    /// Open the Settings window with ⌘,.
    func open() { app.typeKey(",", modifierFlags: .command) }

    /// Select a tab by its toolbar title ("Appearance", "Typography", "Library",
    /// "Extensions").
    func selectTab(_ name: String) {
        let toolbarButton = app.toolbars.buttons[name]
        if toolbarButton.exists {
            toolbarButton.click()
        } else {
            app.buttons[name].clickWhenReady()
        }
    }

    var appearanceTab: XCUIElement { app.byId(A11y.Settings.appearanceTab) }
    var typographyTab: XCUIElement { app.byId(A11y.Settings.typographyTab) }
    var libraryTab: XCUIElement { app.byId(A11y.Settings.libraryTab) }
    var extensionsTab: XCUIElement { app.byId(A11y.Settings.extensionsTab) }

    // Segmented pickers expose each option as a button labelled with the option.
    func setTheme(_ label: String) { app.byId(A11y.Settings.themePicker).buttons[label].clickWhenReady() }
    func setFont(_ label: String) { app.byId(A11y.Settings.fontPicker).buttons[label].clickWhenReady() }
    func setSize(_ label: String) { app.byId(A11y.Settings.sizePicker).buttons[label].clickWhenReady() }

    func changeLibrary() { app.byId(A11y.Settings.changeLibrary).clickWhenReady() }
    func reinstallManifest() { app.byId(A11y.Settings.reinstallManifest).clickWhenReady() }
}
