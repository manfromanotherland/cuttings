// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// A wrapping layout — like an `HStack` that flows onto new lines when it runs
/// out of width. Used for tag chips in the card inspector.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        layout(subviews: subviews, in: proposal.replacingUnspecifiedDimensions()).size
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let result = layout(subviews: subviews, in: bounds.size)
        for (view, origin) in zip(subviews, result.origins) {
            view.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func layout(subviews: Subviews, in size: CGSize) -> (size: CGSize, origins: [CGPoint]) {
        var cursorX: CGFloat = 0, cursorY: CGFloat = 0, rowHeight: CGFloat = 0
        var origins: [CGPoint] = []
        for view in subviews {
            let viewSize = view.sizeThatFits(.unspecified)
            if cursorX + viewSize.width > size.width, cursorX > 0 {
                cursorX = 0; cursorY += rowHeight + spacing; rowHeight = 0
            }
            origins.append(CGPoint(x: cursorX, y: cursorY))
            cursorX += viewSize.width + spacing
            rowHeight = max(rowHeight, viewSize.height)
        }
        return (CGSize(width: size.width, height: cursorY + rowHeight), origins)
    }
}
