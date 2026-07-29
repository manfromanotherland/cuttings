// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Native `NSSearchField` for the reading-list column's toolbar.
///
/// `.searchable` can't be used: on macOS it always renders at the trailing edge of
/// the unified title bar (the reader's side), whichever column attaches it. A
/// `ToolbarItem` wrapping a real field keeps it over the list column.
///
/// It stays an `NSSearchField` (not a SwiftUI `TextField`) so that ⌘K
/// (`focusSearchField()`) finds it, `TextEditingMonitor` sees its field-editor
/// notifications, and the UI tests match it via `searchFields`.
struct ListSearchField: NSViewRepresentable {
    @Binding var text: String
    var prompt: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = prompt
        field.delegate = context.coordinator
        field.sendsWholeSearchString = false
        field.sendsSearchStringImmediately = true
        // Stretch to the frame's width instead of hugging the placeholder text.
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSSearchField, context _: Context) {
        // Write back only when they differ, so we don't reset the caret mid-typing.
        if field.stringValue != text {
            field.stringValue = text
        }
        field.placeholderString = prompt
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        private let text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
