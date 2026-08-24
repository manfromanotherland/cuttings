// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Watches `articles/` inside the library root with FSEvents and invokes
/// `onChange` whenever files are created, modified, or deleted — including
/// files arriving via iCloud or other sync services.
///
/// The FSEvents latency (0.5 s) coalesces rapid bursts into a single callback,
/// so the caller doesn't need its own debounce.
final class FolderWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "is.edmundo.cuttings.fsevents", qos: .utility)
    private let onChange: @Sendable () -> Void

    init(libraryPath: String, onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        let watchPath = (libraryPath as NSString).appendingPathComponent("articles")
        start(path: watchPath)
    }

    deinit { stop() }

    /// Tear down the stream and release the retain that keeps `self` alive.
    ///
    /// Callers **must** invoke this before dropping their reference (e.g. when
    /// switching libraries). `start` stores a `passRetained(self)` in the
    /// FSEvents context; that +1 is only balanced by the stream's `release`
    /// callback, which only runs when the stream is torn down here. Relying on
    /// `deinit` alone is a deadlock: the retain keeps the refcount above zero,
    /// so `deinit` never runs, so the stream never tears down, so the retain is
    /// never released. Calling `invalidate()` explicitly breaks that cycle.
    /// `deinit { stop() }` remains as a backstop; `stop()` is idempotent.
    func invalidate() {
        stop()
    }

    // ── Private ───────────────────────────────────────────────────────────

    private func start(path: String) {
        // `passRetained` keeps self alive for the duration of the stream; the
        // `release` callback balances it when the stream is torn down in stop().
        // Hold the token so the create-failure path below can balance it by hand
        // (that path never creates a stream, so `release` would never fire).
        let retained = Unmanaged.passRetained(self)
        var ctx = FSEventStreamContext(
            version: 0,
            info: retained.toOpaque(),
            retain: nil,
            release: { Unmanaged<FolderWatcher>.fromOpaque($0!).release() },
            copyDescription: nil
        )

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue().fire()
        }

        stream = FSEventStreamCreate(
            nil, callback, &ctx,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5, // seconds of latency / coalescing
            flags
        )
        guard let stream else {
            // No stream means the `release` callback will never run, so balance
            // the retain above by hand instead of leaking `self`.
            retained.release()
            return
        }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    private func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func fire() {
        onChange()
    }
}
