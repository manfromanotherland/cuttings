// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// A wrapping layout — like an `HStack` that flows onto new lines when it runs
/// out of width. Used for tag chips in the article header and the tag tiles in
/// the sidebar.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(subviews: subviews, in: proposal.replacingUnspecifiedDimensions()).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(subviews: subviews, in: bounds.size)
        for (view, origin) in zip(subviews, result.origins) {
            view.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func layout(subviews: Subviews, in size: CGSize) -> (size: CGSize, origins: [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        var origins: [CGPoint] = []
        for view in subviews {
            let s = view.sizeThatFits(.unspecified)
            if x + s.width > size.width, x > 0 {
                x = 0; y += rowH + spacing; rowH = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return (CGSize(width: size.width, height: y + rowH), origins)
    }
}
