// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

extension CuttingsLibraryView {
    func toggleQuickLook() {
        if quickLookURL != nil {
            quickLookURL = nil
            return
        }

        guard presentedReading == nil,
              let row = singleSelectedRow,
              let url = ReadingQuickLookURLResolver.previewURL(
                  for: row,
                  libraryURL: appState.libraryURL
              )
        else { return }

        quickLookURL = url
    }
}
