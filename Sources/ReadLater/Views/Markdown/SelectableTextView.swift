// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import AppKit

extension NSAttributedString.Key {
    /// Value: `[CGFloat]` — the x-offsets (in text-container coordinates) of the
    /// quote bars enclosing this paragraph. Read by `ReaderLayoutManager`.
    static let quoteBar = NSAttributedString.Key("ReaderQuoteBar")
}

/// A read-only `NSTextView` bridged into SwiftUI. SwiftUI's `Text` +
/// `.textSelection(.enabled)` can only select *within* a single `Text`, so the
/// reader (which renders one `Text` per block) cannot drag-select across
/// paragraphs. Rendering a contiguous run of text blocks as one
/// `NSAttributedString` in an `NSTextView` restores native, continuous
/// selection (and copy) across the whole run.
///
/// The view draws no background and no insets so it lines up with the
/// surrounding SwiftUI blocks; height is computed from the laid-out text via
/// `sizeThatFits`. A custom `ReaderLayoutManager` draws block-quote bars, which
/// plain attributed text cannot express.
struct SelectableTextView: NSViewRepresentable {
    let attributed: NSAttributedString

    func makeNSView(context: Context) -> ReaderTextView {
        let textView = ReaderTextView.make()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = []
        // Links are opened by NSTextView's default handling (NSWorkspace), which
        // matches the rest of the reader: links open in the system browser.
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.controlAccentColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand,
        ]
        // Fill the width SwiftUI proposes; height comes from intrinsicContentSize.
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.defaultHigh, for: .vertical)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        return textView
    }

    func updateNSView(_ textView: ReaderTextView, context: Context) {
        // Only re-set the storage when the content actually changed (e.g. the
        // user changed the reader font/size). Re-setting on every SwiftUI pass
        // would clear the user's in-progress selection. Invalidating the
        // intrinsic size makes SwiftUI re-read the height *after* the text is in
        // place — without this, a run measured before its text was set (which
        // happens on the first layout pass) collapses to zero height and renders
        // blank.
        guard let storage = textView.textStorage else { return }
        if !storage.isEqual(attributed) {
            storage.setAttributedString(attributed)
            textView.invalidateIntrinsicContentSize()
        }
    }
}

/// An `NSTextView` that owns its TextKit-1 stack. Building the stack manually
/// (so our custom layout manager is used) means nothing else retains the
/// `NSTextStorage` — the cluster's back-references to it are weak — so the view
/// holds it strongly here to keep the whole stack alive.
final class ReaderTextView: NSTextView {
    private var retainedStorage: NSTextStorage?

    static func make() -> ReaderTextView {
        let storage = NSTextStorage()
        let layoutManager = ReaderLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)

        let textView = ReaderTextView(frame: .zero, textContainer: container)
        textView.retainedStorage = storage
        return textView
    }

    /// Height is driven by the laid-out text; width is left flexible so SwiftUI
    /// stretches the view to the proposed width. Because the text container
    /// tracks the view width, `usedRect` reflects wrapping at the current width.
    override var intrinsicContentSize: NSSize {
        guard let layoutManager, let textContainer else { return super.intrinsicContentSize }
        layoutManager.ensureLayout(for: textContainer)
        return NSSize(width: NSView.noIntrinsicMetric,
                      height: ceil(layoutManager.usedRect(for: textContainer).height))
    }

    /// A width change rewraps the text, changing its height — re-measure.
    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        if widthChanged { invalidateIntrinsicContentSize() }
    }
}

/// Draws block-quote bars in the text margin. TextKit gives no way to express a
/// per-paragraph leading rule, so we read the `.quoteBar` attribute (a list of
/// x-offsets, one per nesting level) and stroke a rounded bar down each line
/// fragment of a quoted paragraph.
final class ReaderLayoutManager: NSLayoutManager {
    /// Matches `MarkdownTheme.quoteBarWidth`.
    private let barWidth: CGFloat = 3

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let textStorage else { return }
        let color = NSColor.secondaryLabelColor.withAlphaComponent(0.4)

        enumerateLineFragments(forGlyphRange: glyphsToShow) { rect, _, _, glyphRange, _ in
            let charIndex = self.characterIndexForGlyph(at: glyphRange.location)
            guard charIndex < textStorage.length,
                  let bars = textStorage.attribute(.quoteBar, at: charIndex,
                                                   effectiveRange: nil) as? [CGFloat],
                  !bars.isEmpty else { return }
            color.setFill()
            for x in bars {
                let barRect = NSRect(x: origin.x + x, y: origin.y + rect.minY,
                                     width: self.barWidth, height: rect.height)
                NSBezierPath(roundedRect: barRect,
                             xRadius: self.barWidth / 2, yRadius: self.barWidth / 2).fill()
            }
        }
    }
}
