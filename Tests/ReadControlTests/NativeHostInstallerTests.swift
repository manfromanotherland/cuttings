// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

/// `NativeHostInstaller` re-installs the browser native-messaging manifest only
/// when the bundled host's path changed since the last install (e.g. the app
/// moved). The manifest itself is generated and written by the Rust `native-host`
/// binary (`--install-manifest`), so the Swift-side unit is this reinstall
/// decision; the end-to-end install is covered by the first-run UI journey.
final class NativeHostInstallerTests: XCTestCase {
    func testNeedsReinstallWhenNeverInstalled() {
        XCTAssertTrue(NativeHostInstaller.needsReinstall(
            lastInstalledPath: nil, currentPath: "/Applications/ReadControl.app/native-host"))
    }

    func testNoReinstallWhenPathUnchanged() {
        let path = "/Applications/ReadControl.app/native-host"
        XCTAssertFalse(NativeHostInstaller.needsReinstall(lastInstalledPath: path, currentPath: path))
    }

    func testNeedsReinstallWhenPathChanged() {
        XCTAssertTrue(NativeHostInstaller.needsReinstall(
            lastInstalledPath: "/old/ReadControl.app/native-host",
            currentPath: "/Applications/ReadControl.app/native-host"))
    }
}
