// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct TypographyCommands: Commands {
    @AppStorage("readerFont", store: AppDefaults.store) private var readerFont: ReaderFont = .system
    @AppStorage("readerFontSize", store: AppDefaults.store) private var readerFontSize: ReaderFontSize = .medium

    var body: some Commands {
        CommandMenu("Typography") {
            Section("Font") {
                ForEach(ReaderFont.allCases) { font in
                    Button(font.label) { readerFont = font }
                        .disabled(readerFont == font)
                }
            }
            Section("Size") {
                Button("Increase Size") {
                    if let next = ReaderFontSize.allCases.first(where: { $0.rawValue > readerFontSize.rawValue }) {
                        readerFontSize = next
                    }
                }
                .keyboardShortcut(ShortcutCatalog.increaseFont)
                .disabled(readerFontSize == .xlarge)

                Button("Decrease Size") {
                    if let prev = ReaderFontSize.allCases.last(where: { $0.rawValue < readerFontSize.rawValue }) {
                        readerFontSize = prev
                    }
                }
                .keyboardShortcut(ShortcutCatalog.decreaseFont)
                .disabled(readerFontSize == .small)

                Divider()

                ForEach(ReaderFontSize.allCases) { size in
                    Button(size.label) { readerFontSize = size }
                        .disabled(readerFontSize == size)
                }
            }
        }
    }
}
