// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import os

/// Opt-in, app-scoped diagnostics. Nothing is collected during ordinary launches.
/// Scroll replay exercises the real NSScrollView but is explicitly synthetic:
/// event-delivery timing and screen capabilities are not presentation-frame evidence.
enum PerformanceTrace {
    static let isEnabled = TestHooks.isPerformanceTesting
    static let disableMaterials = isEnabled && environment("OIA_PERF_DISABLE_MATERIALS") == "1"
    private static let log = OSLog(subsystem: "is.edmundo.oia.performance", category: "PointsOfInterest")
    private static let counts = Counters()
    @MainActor private static var replayStarted = false

    static func begin(_ name: StaticString) -> OSSignpostID {
        guard isEnabled else { return .invalid }
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        return id
    }

    static func end(_ name: StaticString, _ id: OSSignpostID) {
        guard isEnabled else { return }
        os_signpost(.end, log: log, name: name, signpostID: id)
    }

    static func event(_ name: StaticString) {
        guard isEnabled else { return }
        os_signpost(.event, log: log, name: name)
    }

    static func increment(_ name: String, by amount: Int = 1) {
        guard isEnabled else { return }
        counts.increment(name, by: amount)
    }

    static func scrollPhaseChanged(_ isScrolling: Bool) {
        guard isEnabled else { return }
        increment(isScrolling ? "scroll_starts" : "scroll_stops")
        event(isScrolling ? "ScrollStart" : "ScrollStop")
    }

    @MainActor
    static func recordStartupEvent(_ name: String) {
        guard isEnabled else { return }
        // Card appearance is intentionally not logged or written to disk.
        guard name == "reconcile-finished" || name == "startup-error" else { return }
        if name == "startup-error" {
            event("StartupError")
            return
        }
        guard !replayStarted else { return }
        replayStarted = true
        event("LibraryReady")
        if let path = environment("OIA_PERF_READY_PATH") {
            try? "ready".write(toFile: path, atomically: true, encoding: .utf8)
        }
        Task { await awaitReplayTrigger() }
    }

    private static func environment(_ key: String) -> String? {
        ProcessInfo.processInfo.environment[key].flatMap { $0.isEmpty ? nil : $0 }
    }

    @MainActor
    private static func awaitReplayTrigger() async {
        guard let trigger = environment("OIA_PERF_TRIGGER_PATH") else { return }
        for _ in 0 ..< 1200 {
            if FileManager.default.fileExists(atPath: trigger) {
                await runReplay()
                return
            }
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
        }
        writeResult(status: "trigger_timeout", offsets: [])
    }

    @MainActor
    private static func runReplay() async {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
              let content = window.contentView,
              let scrollView = scrollViews(in: content).max(by: {
                  ($0.documentView?.bounds.height ?? 0) < ($1.documentView?.bounds.height ?? 0)
              }),
              (scrollView.documentView?.bounds.height ?? 0) > scrollView.contentView.bounds.height
        else {
            writeResult(status: "scroll_view_unavailable", offsets: [])
            return
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Allow the settled display previews to load before the critical first start.
        try? await Task.sleep(for: .seconds(2))
        var offsets = [scrollView.contentView.bounds.origin.y]
        let interval = begin("ScrollReplay")
        for direction in [-1, -1, 1] {
            let burst = begin("ScrollBurst")
            for tick in 0 ..< 240 {
                guard !Task.isCancelled else { break }
                sendScroll(to: scrollView, pixels: direction * 24, phase: tick == 0 ? 1 : 2)
                try? await Task.sleep(for: .milliseconds(8))
            }
            sendScroll(to: scrollView, pixels: 0, phase: 4)
            end("ScrollBurst", burst)
            offsets.append(scrollView.contentView.bounds.origin.y)
            try? await Task.sleep(for: .seconds(1))
        }
        end("ScrollReplay", interval)
        writeResult(status: offsets.dropFirst().contains(where: { $0 != offsets.first })
            ? "completed" : "no_scroll_movement", offsets: offsets)
    }

    @MainActor
    private static func sendScroll(to scrollView: NSScrollView, pixels: Int, phase: Int64) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
            wheel1: Int32(pixels), wheel2: 0, wheel3: 0
        ) else { return }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        if let nativeEvent = NSEvent(cgEvent: event) {
            scrollView.scrollWheel(with: nativeEvent)
        }
    }

    @MainActor
    private static func scrollViews(in view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
    }

    @MainActor
    private static func writeResult(status: String, offsets: [CGFloat]) {
        guard let path = environment("OIA_PERF_RESULT_PATH") else { return }
        let screen = NSApp.keyWindow?.screen ?? NSScreen.main
        let result: [String: Any] = [
            "schema_version": 1,
            "status": status,
            "driver": "synthetic_appkit_scroll_wheel_with_phases",
            "scroll_offsets": offsets.map(Double.init),
            "counters": counts.snapshot(),
            "target_hz": 120,
            "screen_maximum_frames_per_second": screen?.maximumFramesPerSecond ?? 0,
            "backing_scale": screen?.backingScaleFactor ?? 0,
            "frame_pacing_status": "unverified",
            "frame_pacing_reason": "No presentation-frame timestamps were measured. Replay timing is not FPS.",
            "real_gesture_validation": "required",
            "materials_disabled": disableMaterials
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        else { return }
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
        event("ReplayFinished")
    }

    private final class Counters: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String: Int] = [:]

        func increment(_ name: String, by amount: Int) {
            lock.lock()
            defer { lock.unlock() }
            values[name, default: 0] += amount
        }

        func snapshot() -> [String: Int] {
            lock.lock()
            defer { lock.unlock() }
            return values
        }
    }
}
