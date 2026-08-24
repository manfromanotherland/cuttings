// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct AppearanceCommands: Commands {
    @Binding var appearanceMode: AppearanceMode

    var body: some Commands {
        CommandMenu("Appearance") {
            ForEach(AppearanceMode.allCases) { mode in
                Button(mode.label) {
                    appearanceMode = mode
                }
                .disabled(appearanceMode == mode)
            }
        }
    }
}
