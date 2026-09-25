// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Supplies a compact resting width to SwiftUI's native
/// `NSSearchToolbarItem`. AppKit still owns the field, focus, animation,
/// cancel behavior, and expanded width.
struct CompactSearchToolbarConfiguration: NSViewRepresentable {
    let isSearchFocused: Bool

    func makeNSView(context _: Context) -> NSView {
        SearchToolbarConfigurationView(isSearchFocused: isSearchFocused)
    }

    func updateNSView(_ view: NSView, context _: Context) {
        (view as? SearchToolbarConfigurationView)?.setSearchFocused(isSearchFocused)
    }

    @MainActor
    private final class SearchToolbarConfigurationView: NSView {
        private static let compactConstraintIdentifier =
            "is.edmundo.oia.search.compact-resting-width"
        private var isSearchFocused: Bool

        init(isSearchFocused: Bool) {
            self.isSearchFocused = isSearchFocused
            super.init(frame: .zero)

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

        func setSearchFocused(_ isSearchFocused: Bool) {
            self.isSearchFocused = isSearchFocused
            configureCurrentToolbar()
        }

        func configureCurrentToolbar() {
            window?.toolbar?.items
                .compactMap { $0 as? NSSearchToolbarItem }
                .forEach { configure($0) }
        }

        @objc private func toolbarWillAddItem(_ notification: Notification) {
            guard let toolbar = notification.object as? NSToolbar,
                  toolbar === window?.toolbar,
                  let item = notification.userInfo?[NSToolbarUserInfoKey.itemKey]
                  as? NSSearchToolbarItem
            else {
                return
            }

            configure(item)
        }

        private func configure(_ item: NSSearchToolbarItem) {
            let field = item.searchField
            if let compactWidth = field.constraints.first(where: {
                $0.identifier == Self.compactConstraintIdentifier
            }) {
                updatePriority(of: compactWidth)
                return
            }

            let compactWidth = field.widthAnchor.constraint(equalTo: field.heightAnchor)
            compactWidth.identifier = Self.compactConstraintIdentifier
            // AppKit's resting autoresizing width uses `.defaultHigh`. Prefer
            // the compressed native representation by one point only while
            // search is inactive. While focused, dropping this below AppKit's
            // width lets the trailing item expand leftward without clipping.
            updatePriority(of: compactWidth)
            compactWidth.isActive = true
        }

        private func updatePriority(of compactWidth: NSLayoutConstraint) {
            compactWidth.priority = isSearchFocused
                ? .defaultLow
                : .init(rawValue: NSLayoutConstraint.Priority.defaultHigh.rawValue + 1)
        }
    }
}
