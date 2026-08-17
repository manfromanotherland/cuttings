// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// The Settings window (⌘,). Most personalization journeys use the sidebar
/// appearance popover (`SidebarPage`); this covers the full window when needed.
struct SettingsPage {
    let app: XCUIApplication

    /// Open the Settings window with ⌘,.
    func open() {
        app.typeKey(",", modifierFlags: .command)
    }

    /// Close the Settings window with ⌘W, returning focus to the main window.
    func close() {
        app.typeKey("w", modifierFlags: .command)
    }

    /// Open Settings and land on the Typography tab, waiting for it to render.
    @discardableResult
    func openTypography() -> Bool {
        open()
        selectTab("Typography")
        return typographyTab.waitExists()
    }

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

    var appearanceTab: XCUIElement {
        app.byId(A11y.Settings.appearanceTab)
    }

    var typographyTab: XCUIElement {
        app.byId(A11y.Settings.typographyTab)
    }

    var libraryTab: XCUIElement {
        app.byId(A11y.Settings.libraryTab)
    }

    var extensionsTab: XCUIElement {
        app.byId(A11y.Settings.extensionsTab)
    }

    /// One option of a segmented picker, resolved by the option's label.
    ///
    /// SwiftUI's `.pickerStyle(.segmented)` becomes an `NSSegmentedControl` on
    /// macOS, which surfaces as a **RadioGroup of RadioButtons** — not buttons.
    /// The query stays scoped to the picker: several option labels ("Extra
    /// Large", "Medium") are also titles in the app's Typography *menu bar*, so
    /// an app-wide lookup can match the menu instead of the setting.
    private func segment(_ pickerID: String, _ label: String) -> XCUIElement {
        let picker = app.byId(pickerID)
        let radio = picker.radioButtons[label]
        return radio.exists ? radio : picker.buttons[label]
    }

    /// Whether a segment is the picker's current value.
    ///
    /// A segmented option does **not** carry the `.isSelected` trait on macOS —
    /// `isSelected` reads false even for the active segment. Selection comes
    /// through as the element's `value`: 1 for the chosen segment, 0 for the
    /// rest. The type it arrives as isn't guaranteed, so accept the numeric and
    /// string spellings, and keep `isSelected` as a last resort.
    private func segmentIsOn(_ pickerID: String, _ label: String) -> Bool {
        let element = segment(pickerID, label)
        guard element.exists else { return false }
        switch element.value {
        case let number as Int: return number == 1
        case let string as String: return string == "1"
        case let bool as Bool: return bool
        default: return element.isSelected
        }
    }

    func setTheme(_ label: String) {
        segment(A11y.Settings.themePicker, label).clickWhenReady()
    }

    func setFont(_ label: String) {
        segment(A11y.Settings.fontPicker, label).clickWhenReady()
    }

    func setSize(_ label: String) {
        segment(A11y.Settings.sizePicker, label).clickWhenReady()
    }

    func setWidth(_ label: String) {
        segment(A11y.Settings.widthPicker, label).clickWhenReady()
    }

    func setLineHeight(_ label: String) {
        segment(A11y.Settings.lineHeightPicker, label).clickWhenReady()
    }

    func widthSelected(_ label: String) -> Bool {
        segmentIsOn(A11y.Settings.widthPicker, label)
    }

    func lineHeightSelected(_ label: String) -> Bool {
        segmentIsOn(A11y.Settings.lineHeightPicker, label)
    }

    /// The live sample under the Typography pickers. Its frame reflects the
    /// chosen measure and leading, so a test can assert the settings took effect.
    var typographyPreview: XCUIElement {
        app.byId(A11y.Settings.typographyPreview)
    }

    func changeLibrary() {
        app.byId(A11y.Settings.changeLibrary).clickWhenReady()
    }

    var chromeExtensionLink: XCUIElement {
        app.byId(A11y.Extensions.chromeLink)
    }

    var firefoxExtensionLink: XCUIElement {
        app.byId(A11y.Extensions.firefoxLink)
    }
}
