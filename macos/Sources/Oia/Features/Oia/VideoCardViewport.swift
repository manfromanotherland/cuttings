// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics

enum VideoCardViewport {
    static func containsVisibleArea(of cardFrame: CGRect, in viewportFrame: CGRect) -> Bool {
        guard cardFrame.width > 0, cardFrame.height > 0,
              viewportFrame.width > 0, viewportFrame.height > 0,
              cardFrame.isFinite, viewportFrame.isFinite
        else {
            return false
        }

        let intersection = cardFrame.intersection(viewportFrame)
        return !intersection.isNull && intersection.width > 0 && intersection.height > 0
    }
}

private extension CGRect {
    var isFinite: Bool {
        [minX, minY, maxX, maxY].allSatisfy(\.isFinite)
    }
}
