// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Observation
import SwiftUI

extension EnvironmentValues {
    @Entry var masonryCardIsVisible: Bool?
}

@MainActor
@Observable
private final class MasonryHostingModel {
    var identity: AnyHashable?
    var width: CGFloat = 220
    var height: CGFloat = 180
    var content = AnyView(EmptyView())
    var isVisible = false

    func reset() {
        identity = nil
        content = AnyView(EmptyView())
        isVisible = false
    }
}

private struct MasonryHostedCard: View {
    @Bindable var model: MasonryHostingModel

    var body: some View {
        model.content
            .id(model.identity)
            .environment(\.masonryCardIsVisible, model.isVisible)
            .frame(width: model.width, height: model.height, alignment: .top)
            .clipped()
    }
}

@MainActor
final class MasonryHostingItem: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("MasonryHostingItem")
    #if DEBUG
        private(set) static var allocationCount = 0
        private(set) static var visibilityMutationCount = 0

        static func resetAllocationCount() {
            allocationCount = 0
        }

        static func resetVisibilityMutationCount() {
            visibilityMutationCount = 0
        }
    #endif

    private let model = MasonryHostingModel()
    private lazy var hostingController = NSHostingController(
        rootView: MasonryHostedCard(model: model)
    )

    override func loadView() {
        #if DEBUG
            Self.allocationCount += 1
        #endif
        addChild(hostingController)
        hostingController.sizingOptions = []
        view = hostingController.view
    }

    func configure(
        identity: AnyHashable,
        width: CGFloat,
        height: CGFloat,
        content: AnyView
    ) {
        _ = view
        model.identity = identity
        model.width = width
        model.height = height
        model.content = content
    }

    func setVisible(_ visible: Bool) {
        guard model.isVisible != visible else { return }
        #if DEBUG
            Self.visibilityMutationCount += 1
        #endif
        model.isVisible = visible
    }

    func endDisplaying() {
        model.reset()
    }

    override func apply(_ layoutAttributes: NSCollectionViewLayoutAttributes) {
        super.apply(layoutAttributes)
        if abs(model.width - layoutAttributes.size.width) >= 0.5 {
            model.width = layoutAttributes.size.width
        }
        if abs(model.height - layoutAttributes.size.height) >= 0.5 {
            model.height = layoutAttributes.size.height
        }
    }

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: NSCollectionViewLayoutAttributes
    ) -> NSCollectionViewLayoutAttributes {
        layoutAttributes
    }

    override func prepareForReuse() {
        model.reset()
        super.prepareForReuse()
    }
}
