// SPDX-License-Identifier: GPL-3.0-or-later

import Sparkle
import SwiftUI

/// The "Check for Updates…" item, placed in the app menu just below "About
/// Cuttings" once an official Cuttings appcast is available.
///
/// It is always enabled. Sparkle's `SPUUpdater.canCheckForUpdates` — which would
/// let us grey the item out while a check is in flight — is `@MainActor`-isolated,
/// so it can't be observed through a Combine key-path publisher under Swift 6
/// (the `KeyPath` would escape the isolation). Sparkle already ignores a check
/// requested while one is running, so gating the button added no real protection.
struct UpdateCommands: Commands {
    let updater: SPUUpdater

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                updater.checkForUpdates()
            }
        }
    }
}
