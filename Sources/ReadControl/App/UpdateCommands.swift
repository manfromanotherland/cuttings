// SPDX-License-Identifier: GPL-3.0-or-later

import Combine
import Sparkle
import SwiftUI

/// The "Check for Updates…" item, placed in the app menu just below "About
/// ReadControl". Sparkle enables it only while a check can actually start — not
/// while one is already running, and not before the updater has finished
/// launching — which is exactly what `canCheckForUpdates` tracks.
struct UpdateCommands: Commands {
    let updater: SPUUpdater

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            CheckForUpdatesButton(updater: updater)
        }
    }
}

/// Republishes the updater's `canCheckForUpdates` (a KVO-observable property on
/// Sparkle's `SPUUpdater`) as an `@Published` value SwiftUI can bind to, so the
/// menu item greys out while a check is in flight.
private final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

private struct CheckForUpdatesButton: View {
    @StateObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        _viewModel = StateObject(wrappedValue: CheckForUpdatesViewModel(updater: updater))
    }

    var body: some View {
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!viewModel.canCheckForUpdates)
    }
}
