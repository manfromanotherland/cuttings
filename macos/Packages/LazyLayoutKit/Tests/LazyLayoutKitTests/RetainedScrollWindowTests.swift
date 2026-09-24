#if os(macOS)
import AppKit
@_spi(Instrumentation) import LazyLayoutKit
import SwiftUI
import XCTest

final class RetainedScrollWindowTests: XCTestCase {
    private struct Item: Identifiable, Equatable {
        let id: Int
    }

    private struct EditableRow: Identifiable, Equatable {
        let id: Int
        var height: Double = 200
        var tag = ""
    }

    @MainActor
    private final class EditableModel: ObservableObject {
        @Published var rows = (0 ..< 100).map { EditableRow(id: $0) }
        var measurements = 0
    }

    private struct EditableBoard: View {
        @ObservedObject var model: EditableModel

        var body: some View {
            LazyLayoutView(
                model.rows,
                id: \.id,
                layout: MasonryLayout(columns: 4, spacing: 12),
                recomputeOn: 0,
                geometryKey: { AnyHashable($0.height) },
                item: { row, _ in
                    model.measurements += 1
                    return .fixedHeight(row.height)
                }
            ) { row in Text(row.tag) }
        }
    }

    @MainActor
    func testContentOnlyEditsDoNotRemeasureTheCollection() {
        let model = EditableModel()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: EditableBoard(model: model))
        window.orderFront(nil)
        window.layoutIfNeeded()
        defer { window.close() }
        pump(0.3)
        let initial = model.measurements
        XCTAssertGreaterThan(initial, 0)
        model.rows[0].tag = "new tag"
        pump(0.2)
        XCTAssertEqual(model.measurements, initial)
        model.rows[0].height = 300
        pump(0.2)
        XCTAssertEqual(model.measurements, initial + model.rows.count)
    }

    @MainActor
    private final class Recorder {
        var publications = 0
        var viewportUpdates = 0
        var built: Set<Int> = []

        func record(_ event: LazyLayoutInstrumentationEvent) {
            switch event {
            case .windowPublication: publications += 1
            case .viewport: viewportUpdates += 1
            default: break
            }
        }
    }

    @MainActor
    func testSmallScrollsRetainTheMaterializedWindow() throws {
        let recorder = Recorder()
        let view = LazyLayoutView(
            (0 ..< 10_000).map { Item(id: $0) },
            id: \.id,
            layout: MasonryLayout(columns: 4, spacing: 12),
            overscan: .items(80),
            item: { _ in .fixedHeight(200) },
            onInstrumentation: recorder.record
        ) { item in
            Color.gray.onAppear { recorder.built.insert(item.id) }
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.orderFront(nil)
        window.layoutIfNeeded()
        defer { window.close() }
        pump(0.5)
        let scroll = try XCTUnwrap(findScrollView(window.contentView))
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 4000))
        scroll.reflectScrolledClipView(scroll.contentView)
        pump(0.3)
        let baseline = recorder.publications
        let viewportBaseline = recorder.viewportUpdates
        XCTAssertGreaterThan(baseline, 0)

        for offset in stride(from: 4002, through: 4020, by: 2) {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: offset))
            scroll.reflectScrolledClipView(scroll.contentView)
            pump(0.04)
        }

        XCTAssertGreaterThan(recorder.viewportUpdates, viewportBaseline,
                             "the test must drive the real scroll geometry callback")
        XCTAssertEqual(recorder.publications, baseline,
                       "scrolling within retained overscan must not republish cells")
        XCTAssertLessThan(recorder.built.count, 200)
    }

    @MainActor
    private func findScrollView(_ root: NSView?) -> NSScrollView? {
        guard let root else { return nil }
        if let scroll = root as? NSScrollView { return scroll }
        return root.subviews.lazy.compactMap { self.findScrollView($0) }.first
    }

    @MainActor
    private func pump(_ seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
    }
}
#endif
