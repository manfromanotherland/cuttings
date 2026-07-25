// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

// Query and wait helpers used by the page objects, so first-run element-type
// surprises (Table vs Outline, sheet vs dialog) are absorbed in one place
// rather than scattered across journeys.

extension XCUIApplication {
    /// The first element anywhere in the app carrying `identifier`, regardless of
    /// element type. Prefer a type-specific page-object accessor where the type
    /// is known; this is the catch-all the page objects build on.
    func byId(_ identifier: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Clicks a button by title in the frontmost confirmation dialog. A SwiftUI
    /// `confirmationDialog` surfaces on macOS as a sheet on the key window; fall
    /// back to a top-level dialog or plain button if the sheet query misses.
    func tapDialogButton(_ title: String, timeout: TimeInterval = 8) {
        let candidates = [sheets.buttons[title], dialogs.buttons[title], buttons[title]]
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let hit = candidates.first(where: { $0.exists }) {
                hit.click()
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        XCTFail("Dialog button '\(title)' not found within \(timeout)s.")
    }

    /// Drives a menu-bar path, e.g. `selectMenu("File", "Close")`: clicks the
    /// top-level menu, then each subsequent item.
    func selectMenu(_ path: String..., timeout: TimeInterval = 8) {
        guard let first = path.first else { return }
        let top = menuBars.firstMatch.menuBarItems[first]
        XCTAssertTrue(top.waitForExistence(timeout: timeout), "Menu '\(first)' not found.")
        top.click()
        for title in path.dropFirst() {
            let item = menuItems[title]
            XCTAssertTrue(item.waitForExistence(timeout: timeout), "Menu item '\(title)' not found.")
            item.click()
        }
    }
}

extension XCUIElement {
    /// Waits up to `timeout` for the element to exist; returns whether it did.
    @discardableResult
    func waitExists(_ timeout: TimeInterval = 8) -> Bool {
        waitForExistence(timeout: timeout)
    }

    /// Waits up to `timeout` for the element to stop existing; returns whether it
    /// disappeared in time.
    @discardableResult
    func waitDisappears(_ timeout: TimeInterval = 8) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while exists {
            if Date() >= deadline {
                return false
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return true
    }

    /// Waits for existence (then a beat for hittability) before clicking — avoids
    /// clicking an element that exists but isn't yet laid out on screen.
    func clickWhenReady(_ timeout: TimeInterval = 8) {
        XCTAssertTrue(waitForExistence(timeout: timeout), "Element '\(identifier)' never appeared to click.")
        let deadline = Date().addingTimeInterval(timeout)
        while !isHittable, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        click()
    }
}
