// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import AppKit

extension NSAttributedString.Key {
    /// Value: `[CGFloat]` — the x-offsets (in text-container coordinates) of the
    /// quote bars enclosing this paragraph. Read by `ReaderLayoutManager`.
    static let quoteBar = NSAttributedString.Key("ReaderQuoteBar")

    /// Marks a range as a saved highlight. `ReaderLayoutManager` fills a tinted
    /// rounded rect behind it. A dedicated key (rather than `.backgroundColor`)
    /// keeps highlights from clobbering inline-code backgrounds.
    static let readerHighlight = NSAttributedString.Key("ReaderHighlight")
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
    /// Verbatim text of every highlight for this reading. Each exact occurrence
    /// found in this run is tinted.
    var highlights: [String] = []
    /// Called with the selected text when the user picks "Highlight" from the
    /// context menu.
    var onHighlight: (String) -> Void = { _ in }

    func makeNSView(context: Context) -> ReaderTextView {
        let textView = ReaderTextView.make()
        textView.onHighlight = onHighlight
        textView.highlights = highlights
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
        // Only re-set the storage when the *base* content actually changed (e.g.
        // the user changed the reader font/size). Re-setting on every SwiftUI
        // pass would clear the user's in-progress selection. We compare against
        // the stored base (not the live storage, which carries highlight
        // attributes added below) so applying a tint never looks like a content
        // change. Invalidating the intrinsic size makes SwiftUI re-read the
        // height *after* the text is in place — without this, a run measured
        // before its text was set (which happens on the first layout pass)
        // collapses to zero height and renders blank.
        guard let storage = textView.textStorage else { return }
        textView.onHighlight = onHighlight
        textView.highlights = highlights
        if textView.baseAttributed?.isEqual(attributed) != true {
            storage.setAttributedString(attributed)
            textView.baseAttributed = attributed.copy() as? NSAttributedString
            textView.invalidateIntrinsicContentSize()
        }
        applyHighlightTints(to: storage, in: textView)
    }

    /// Tag every exact occurrence of each highlight string with
    /// `.readerHighlight` so the layout manager draws a tint behind it. Cheap
    /// for article-sized text; runs each pass so added/removed highlights show
    /// immediately without rebuilding the attributed string.
    private func applyHighlightTints(to storage: NSTextStorage, in textView: ReaderTextView) {
        let whole = NSRange(location: 0, length: storage.length)
        storage.removeAttribute(.readerHighlight, range: whole)
        let haystack = storage.string as NSString
        for needle in highlights where !needle.isEmpty {
            var searchStart = 0
            while searchStart < haystack.length {
                let scope = NSRange(location: searchStart, length: haystack.length - searchStart)
                let found = haystack.range(of: needle, options: [], range: scope)
                if found.location == NSNotFound { break }
                storage.addAttribute(.readerHighlight, value: true, range: found)
                searchStart = found.location + max(found.length, 1)
            }
        }
        textView.needsDisplay = true
    }
}

/// An `NSTextView` that owns its TextKit-1 stack. Building the stack manually
/// (so our custom layout manager is used) means nothing else retains the
/// `NSTextStorage` — the cluster's back-references to it are weak — so the view
/// holds it strongly here to keep the whole stack alive.
final class ReaderTextView: NSTextView {
    private var retainedStorage: NSTextStorage?

    /// The last attributed string set as content, *without* the highlight
    /// attributes layered on top — the baseline `updateNSView` diffs against.
    var baseAttributed: NSAttributedString?

    /// Invoked with the selected text when the user chooses "Highlight".
    var onHighlight: ((String) -> Void)?

    /// Verbatim text of the reading's current highlights, so the context menu
    /// can offer "Remove Highlight" when the selection matches one.
    var highlights: [String] = []

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

    /// Starting an interaction here makes this run the active selection, so clear
    /// any selection held by the other runs first. Each `NSTextView` keeps its own
    /// selection independently, so without this a previous block's selection stays
    /// drawn (grayed, inactive) alongside the new one.
    override func mouseDown(with event: NSEvent) {
        if let content = window?.contentView {
            ReaderTextView.collapseSelections(in: content, except: self)
        }
        super.mouseDown(with: event)
    }

    /// All selection changes funnel through here (including live drag extension
    /// and programmatic clearing). Force a full repaint after each so incremental
    /// selection drawing can't leave stale highlight pixels behind — the ghost
    /// "blue line" that lingered between line fragments during a drag and survived
    /// clearing the selection, because a partial invalidation never covered it.
    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity,
                                    stillSelecting stillSelectingFlag: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
        needsDisplay = true
    }

    /// Collapse the selection of every reader text view in `root`'s subtree,
    /// skipping `keep` (the run taking over the selection, if any). Shared with
    /// the margin click-catcher, which clears them all.
    static func collapseSelections(in root: NSView, except keep: ReaderTextView? = nil) {
        for subview in root.subviews {
            if let textView = subview as? ReaderTextView,
               textView !== keep, textView.selectedRange().length > 0 {
                textView.setSelectedRange(NSRange(location: 0, length: 0))
            }
            collapseSelections(in: subview, except: keep)
        }
    }

    /// Replace the default rich text-editing context menu with just the commands
    /// the reader offers: a highlight toggle, and a "Look Up" that opens the
    /// system dictionary panel for the selection. With no selection there is
    /// nothing to act on, so no menu is shown. When the selection exactly matches
    /// an existing highlight the highlight command removes it; otherwise it adds
    /// one.
    override func menu(for event: NSEvent) -> NSMenu? {
        let range = selectedRange()
        guard range.length > 0, let storage = textStorage else { return nil }
        let selected = (storage.string as NSString)
            .substring(with: range)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let menu = NSMenu()

        let highlightTitle = highlights.contains(selected) ? "Remove Highlight" : "Highlight"
        let highlightItem = NSMenuItem(title: highlightTitle,
                                       action: #selector(highlightSelection(_:)),
                                       keyEquivalent: "")
        highlightItem.target = self
        menu.addItem(highlightItem)

        // "Look Up" opens the native define/thesaurus/Wikipedia popover. Only
        // offered when the trimmed selection has content to define; grouped in
        // its own section, matching how macOS separates Look Up from edit
        // actions.
        if !selected.isEmpty {
            menu.addItem(.separator())
            let lookUpItem = NSMenuItem(title: "Look Up \(Self.lookUpLabel(for: selected))",
                                        action: #selector(lookUpSelection(_:)),
                                        keyEquivalent: "")
            lookUpItem.target = self
            menu.addItem(lookUpItem)
        }
        return menu
    }

    @objc private func highlightSelection(_ sender: Any?) {
        let range = selectedRange()
        guard range.length > 0, let storage = textStorage else { return }
        let text = (storage.string as NSString).substring(with: range)
        onHighlight?(text)
    }

    /// Show the system Look Up panel (Dictionary, Thesaurus, and Apple's
    /// knowledge sources) for the current selection, anchored at its baseline.
    @objc private func lookUpSelection(_ sender: Any?) {
        let range = selectedRange()
        guard range.length > 0,
              let storage = textStorage,
              let layoutManager,
              let container = textContainer else { return }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range,
                                                  actualCharacterRange: nil)
        let bounds = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
        // The panel wants the baseline origin of the first character; the bottom
        // of the flipped line rect approximates it well enough to anchor there.
        let origin = NSPoint(x: bounds.minX + textContainerOrigin.x,
                             y: bounds.maxY + textContainerOrigin.y)
        showDefinition(for: storage.attributedSubstring(from: range), at: origin)
    }

    /// A quoted, length-capped rendering of the selection for the "Look Up" menu
    /// title, mirroring the system item's `Look Up “word”` styling.
    private static func lookUpLabel(for text: String) -> String {
        let maxLength = 24
        let condensed = text.replacingOccurrences(of: "\n", with: " ")
        guard condensed.count > maxLength else { return "“\(condensed)”" }
        return "“\(condensed.prefix(maxLength))…”"
    }
}

/// Draws block-quote bars in the text margin. TextKit gives no way to express a
/// per-paragraph leading rule, so we read the `.quoteBar` attribute (a list of
/// x-offsets, one per nesting level) and stroke a rounded bar down each line
/// fragment of a quoted paragraph.
final class ReaderLayoutManager: NSLayoutManager {
    /// Matches `MarkdownTheme.quoteBarWidth`.
    private let barWidth: CGFloat = 3

    /// Translucent fill behind highlighted passages. Yellow reads as a marker
    /// in both light and dark mode at this alpha.
    private let highlightColor = NSColor.systemYellow.withAlphaComponent(0.32)

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let textStorage else { return }

        drawHighlights(forGlyphRange: glyphsToShow, at: origin, textStorage: textStorage)

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

    /// Fill a rounded tint behind every range carrying `.readerHighlight`. Drawn
    /// in `drawBackground` (before the glyphs) so text stays on top.
    private func drawHighlights(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint,
                                textStorage: NSTextStorage) {
        guard let container = textContainers.first else { return }
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        highlightColor.setFill()
        textStorage.enumerateAttribute(.readerHighlight, in: charRange) { value, range, _ in
            guard value != nil else { return }
            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            self.enumerateEnclosingRects(
                forGlyphRange: glyphRange,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: container
            ) { rect, _ in
                let r = NSRect(x: origin.x + rect.minX, y: origin.y + rect.minY,
                               width: rect.width, height: rect.height)
                NSBezierPath(roundedRect: r, xRadius: 2, yRadius: 2).fill()
            }
        }
    }
}
