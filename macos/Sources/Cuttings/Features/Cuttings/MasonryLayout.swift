// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Small, deterministic geometry helpers shared by the layout and its unit
/// tests. Cards are always assigned to the currently shortest column, preserving
/// source order while producing a true masonry silhouette.
enum MasonryGeometry {
    static func resolvedWidth(
        proposedWidth: CGFloat?, minimumColumnWidth: CGFloat
    ) -> CGFloat {
        let fallback = minimumColumnWidth.isFinite && minimumColumnWidth > 0
            ? minimumColumnWidth : 1
        guard let proposedWidth, proposedWidth.isFinite else { return fallback }
        return max(fallback, proposedWidth)
    }

    static func columnCount(
        width: CGFloat, minimumColumnWidth: CGFloat, spacing: CGFloat, maximum: Int
    ) -> Int {
        guard width.isFinite, width > 0 else { return 1 }
        let divisor = minimumColumnWidth + spacing
        guard divisor.isFinite, divisor > 0 else { return 1 }
        let rawCount = (width + spacing) / divisor
        guard rawCount.isFinite else { return 1 }
        let count = Int(rawCount)
        return min(max(1, maximum), max(1, count))
    }

    static func columnWidth(width: CGFloat, columns: Int, spacing: CGFloat) -> CGFloat {
        let gaps = CGFloat(max(0, columns - 1)) * spacing
        return max(0, (width - gaps) / CGFloat(max(1, columns)))
    }

    static func shortestColumn(in heights: [CGFloat]) -> Int {
        heights.enumerated().min { lhs, rhs in
            lhs.element == rhs.element ? lhs.offset < rhs.offset : lhs.element < rhs.element
        }?.offset ?? 0
    }
}

struct MasonryLayout: Layout {
    var minimumColumnWidth: CGFloat = 220
    var spacing: CGFloat = 18
    /// Let the selected card width determine density on wide boards. A global
    /// ceiling collapses several zoom stops into identical rendered widths.
    var maximumColumns = Int.max

    func sizeThatFits(
        proposal: ProposedViewSize, subviews: Subviews, cache _: inout Void
    ) -> CGSize {
        let width = MasonryGeometry.resolvedWidth(
            proposedWidth: proposal.width, minimumColumnWidth: minimumColumnWidth
        )
        let result = measure(subviews: subviews, width: width)
        return CGSize(width: width, height: result.height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal _: ProposedViewSize,
        subviews: Subviews, cache _: inout Void
    ) {
        let measurement = measure(subviews: subviews, width: bounds.width)
        for (index, subview) in subviews.enumerated() {
            let placement = measurement.placements[index]
            subview.place(
                at: CGPoint(x: bounds.minX + placement.origin.x,
                            y: bounds.minY + placement.origin.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: placement.width, height: placement.height)
            )
        }
    }

    private func measure(subviews: Subviews, width: CGFloat) -> Measurement {
        let columns = MasonryGeometry.columnCount(
            width: width, minimumColumnWidth: minimumColumnWidth,
            spacing: spacing, maximum: maximumColumns
        )
        let itemWidth = MasonryGeometry.columnWidth(
            width: width, columns: columns, spacing: spacing
        )
        var heights = Array(repeating: CGFloat.zero, count: columns)
        var placements: [CGRect] = []

        for subview in subviews {
            let size = subview.sizeThatFits(
                ProposedViewSize(width: itemWidth, height: nil)
            )
            let column = MasonryGeometry.shortestColumn(in: heights)
            let horizontalOffset = CGFloat(column) * (itemWidth + spacing)
            placements.append(
                CGRect(
                    x: horizontalOffset, y: heights[column],
                    width: itemWidth, height: size.height
                )
            )
            heights[column] += size.height + spacing
        }

        let height = max(0, (heights.max() ?? 0) - (subviews.isEmpty ? 0 : spacing))
        return Measurement(height: height, placements: placements)
    }

    private struct Measurement {
        var height: CGFloat
        var placements: [CGRect]
    }
}
