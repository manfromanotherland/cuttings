// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Supplies a compact resting width to SwiftUI's native
/// `NSSearchToolbarItem`. AppKit still owns the field, focus, animation,
/// cancel behavior, and expanded width.
struct CompactSearchToolbarConfiguration: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        SearchToolbarConfigurationView()
    }

    func updateNSView(_ view: NSView, context _: Context) {
        (view as? SearchToolbarConfigurationView)?.configureCurrentToolbar()
    }

    @MainActor
    private final class SearchToolbarConfigurationView: NSView {
        private static let compactConstraintIdentifier =
            "is.edmundo.oia.search.compact-resting-width"

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(toolbarWillAddItem(_:)),
                name: NSToolbar.willAddItemNotification,
                object: nil
            )
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            nil
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureCurrentToolbar()

            // SwiftUI can install its default search item after attaching the
            // content view. Recheck on the next main-loop turn as well as via
            // the toolbar-item notification above.
            DispatchQueue.main.async { [weak self] in
                self?.configureCurrentToolbar()
            }
        }

        override func hitTest(_: NSPoint) -> NSView? {
            nil
        }

        func configureCurrentToolbar() {
            window?.toolbar?.items
                .compactMap { $0 as? NSSearchToolbarItem }
                .forEach(Self.configure)
        }

        @objc private func toolbarWillAddItem(_ notification: Notification) {
            guard let toolbar = notification.object as? NSToolbar,
                  toolbar === window?.toolbar,
                  let item = notification.userInfo?[NSToolbarUserInfoKey.itemKey]
                  as? NSSearchToolbarItem
            else {
                return
            }

            Self.configure(item)
        }

        private static func configure(_ item: NSSearchToolbarItem) {
            let field = item.searchField
            guard !field.constraints.contains(where: {
                $0.identifier == compactConstraintIdentifier
            }) else {
                return
            }

            let compactWidth = field.widthAnchor.constraint(equalTo: field.heightAnchor)
            compactWidth.identifier = compactConstraintIdentifier
            // AppKit's resting autoresizing width uses `.defaultHigh`. Prefer
            // the compressed native representation by one point; an active
            // NSSearchToolbarItem still expands itself to its preferred width.
            compactWidth.priority = .init(rawValue: NSLayoutConstraint.Priority.defaultHigh.rawValue + 1)
            compactWidth.isActive = true
        }
    }
}
