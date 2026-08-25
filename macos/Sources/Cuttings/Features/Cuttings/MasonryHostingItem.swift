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
    var content = AnyView(EmptyView())
    var isVisible = false

    @ObservationIgnored var reportHeight: ((CGFloat, CGFloat) -> Void)?

    func reset() {
        identity = nil
        content = AnyView(EmptyView())
        isVisible = false
        reportHeight = nil
    }
}

private struct MasonryHostedCard: View {
    @Bindable var model: MasonryHostingModel

    var body: some View {
        model.content
            .id(model.identity)
            .environment(\.masonryCardIsVisible, model.isVisible)
            .frame(width: model.width)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                model.reportHeight?(model.width, height)
            }
    }
}

@MainActor
final class MasonryHostingItem: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("MasonryHostingItem")
    #if DEBUG
        private(set) static var allocationCount = 0

        static func resetAllocationCount() {
            allocationCount = 0
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
        content: AnyView,
        reportHeight: @escaping (CGFloat, CGFloat) -> Void
    ) {
        _ = view
        model.identity = identity
        model.width = width
        model.content = content
        model.reportHeight = reportHeight
        measure()
    }

    func setVisible(_ visible: Bool) {
        model.isVisible = visible
    }

    func endDisplaying() {
        model.reset()
    }

    override func apply(_ layoutAttributes: NSCollectionViewLayoutAttributes) {
        super.apply(layoutAttributes)
        guard abs(model.width - layoutAttributes.size.width) >= 0.5 else { return }
        model.width = layoutAttributes.size.width
        measure()
    }

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: NSCollectionViewLayoutAttributes
    ) -> NSCollectionViewLayoutAttributes {
        measure(width: layoutAttributes.size.width)
        return layoutAttributes
    }

    override func prepareForReuse() {
        model.reset()
        super.prepareForReuse()
    }

    private func measure(width: CGFloat? = nil) {
        let width = width ?? model.width
        guard width.isFinite, width > 0 else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, model.identity != nil else { return }
            let size = hostingController.sizeThatFits(
                in: CGSize(width: width, height: .greatestFiniteMagnitude)
            )
            model.reportHeight?(width, size.height)
        }
    }
}
