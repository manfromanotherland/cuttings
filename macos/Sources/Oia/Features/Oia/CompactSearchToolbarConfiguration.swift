// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Supplies a compact resting width to SwiftUI's native
/// `NSSearchToolbarItem`. AppKit still owns the field, focus, cancel behavior,
/// and expanded width.
struct CompactSearchToolbarConfiguration: NSViewRepresentable {
    let isSearchExpanded: Bool

    func makeNSView(context _: Context) -> NSView {
        SearchToolbarConfigurationView(isSearchExpanded: isSearchExpanded)
    }

    func updateNSView(_ view: NSView, context _: Context) {
        (view as? SearchToolbarConfigurationView)?.setSearchExpanded(isSearchExpanded)
    }

    @MainActor
    private final class SearchToolbarConfigurationView: NSView {
        private static let compactConstraintIdentifier =
            "is.edmundo.oia.search.compact-resting-width"
        private var isSearchExpanded: Bool

        init(isSearchExpanded: Bool) {
            self.isSearchExpanded = isSearchExpanded
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

        func setSearchExpanded(_ isSearchExpanded: Bool) {
            self.isSearchExpanded = isSearchExpanded
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
                updatePriority(of: compactWidth, in: field)
                return
            }

            let compactWidth = field.widthAnchor.constraint(equalTo: field.heightAnchor)
            compactWidth.identifier = Self.compactConstraintIdentifier
            // AppKit's resting autoresizing width uses `.defaultHigh`. Prefer
            // the compressed native representation by one point only while
            // search is collapsed. While focused or retaining search input,
            // dropping this below AppKit's width lets the trailing item expand
            // leftward without clipping.
            compactWidth.priority = desiredPriority
            compactWidth.isActive = true
        }

        private var desiredPriority: NSLayoutConstraint.Priority {
            isSearchExpanded
                ? .defaultLow
                : .init(rawValue: NSLayoutConstraint.Priority.defaultHigh.rawValue + 1)
        }

        private func updatePriority(
            of compactWidth: NSLayoutConstraint,
            in field: NSSearchField
        ) {
            let priority = desiredPriority
            guard compactWidth.priority != priority else { return }

            // SwiftUI updates this representable inside the search field's own
            // focus transaction. Letting the priority change inherit that
            // transaction makes two width animations fight: the field first
            // draws beyond its toolbar allocation, then the toolbar catches
            // up. Resolve the public constraint change synchronously so focus
            // is immediate and no intermediate frame can be clipped.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                context.allowsImplicitAnimation = false
                compactWidth.priority = priority
                field.superview?.layoutSubtreeIfNeeded()
                window?.contentView?.layoutSubtreeIfNeeded()
            }
        }
    }
}
