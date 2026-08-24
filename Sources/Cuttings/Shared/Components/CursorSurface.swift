// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// A transparent AppKit layer that owns the pointer cursor over its area and can
/// handle a click and the Escape key. Used for the reader's clickable figures and
/// the image-zoom overlay.
///
/// It exists because the reader renders body text into real `NSTextView`s
/// (`SelectableTextView`), which set their own I-beam cursor. A SwiftUI
/// `.onHover` + `NSCursor.push/pop` (or a hit-test-transparent overlay) loses to
/// those text views: whichever view *wins hit-testing* under the pointer owns the
/// cursor. So this view deliberately **is** the hit-test winner — it participates
/// in hit-testing (occluding the text views beneath) and registers a cursor rect,
/// which is the reliable way to pin the cursor on macOS 14.
///
/// Because it swallows the mouse-down it sits over, it also carries the click:
/// `onClick` fires on mouse-down (open the zoom / dismiss the overlay), and, when
/// `onEscape` is set, it takes first responder so Escape reaches it. Scroll-wheel
/// events fall through to the enclosing scroll view (the default responder
/// behavior), so a figure overlay doesn't block scrolling the article.
struct CursorSurface: NSViewRepresentable {
    var cursor: NSCursor = .pointingHand
    var onClick: (() -> Void)?
    var onEscape: (() -> Void)?

    func makeNSView(context _: Context) -> SurfaceView {
        let view = SurfaceView()
        view.configure(cursor: cursor, onClick: onClick, onEscape: onEscape)
        if onEscape != nil {
            DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        }
        return view
    }

    func updateNSView(_ view: SurfaceView, context _: Context) {
        view.configure(cursor: cursor, onClick: onClick, onEscape: onEscape)
    }

    final class SurfaceView: NSView {
        private var cursor: NSCursor = .pointingHand
        private var onClick: (() -> Void)?
        private var onEscape: (() -> Void)?

        func configure(cursor: NSCursor, onClick: (() -> Void)?, onEscape: (() -> Void)?) {
            self.cursor = cursor
            self.onClick = onClick
            self.onEscape = onEscape
            window?.invalidateCursorRects(for: self)
        }

        /// The surface wins *hit-testing* on purpose (to own the cursor and click),
        /// but it carries no content, so it must stay out of the accessibility tree:
        /// otherwise it occludes the figure/image beneath it in the accessibility
        /// hit test, leaving them "not hittable" for VoiceOver and XCUITest. Kept at
        /// the AppKit level too so it holds however SwiftUI bridges the representable.
        override func isAccessibilityElement() -> Bool {
            false
        }

        // ── Cursor ────────────────────────────────────────────────────────────
        // Both a cursor rect and a `.cursorUpdate` tracking area, so the cursor is
        // re-asserted whether AppKit consults the rects or sends a cursor update.

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: cursor)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas {
                removeTrackingArea(area)
            }
            addTrackingArea(NSTrackingArea(
                rect: bounds,
                options: [.activeInActiveApp, .inVisibleRect, .cursorUpdate],
                owner: self,
                userInfo: nil
            ))
        }

        override func cursorUpdate(with _: NSEvent) {
            cursor.set()
        }

        // ── Interaction ─────────────────────────────────────────────────────────

        /// Click even when the window isn't key, so one click both activates the
        /// window and triggers the action.
        override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
            true
        }

        override var acceptsFirstResponder: Bool {
            onEscape != nil
        }

        override func mouseDown(with event: NSEvent) {
            if let onClick {
                onClick()
            } else {
                super.mouseDown(with: event)
            }
        }

        /// Escape (and ⌘.) arrive as `cancelOperation`.
        override func cancelOperation(_: Any?) {
            onEscape?()
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53, let onEscape { // Escape
                onEscape()
            } else {
                super.keyDown(with: event)
            }
        }
    }
}
