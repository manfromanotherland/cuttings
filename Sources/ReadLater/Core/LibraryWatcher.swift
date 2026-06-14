// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Watches `articles/` inside the library root with FSEvents and invokes
/// `onChange` whenever files are created, modified, or deleted — including
/// files arriving via iCloud or other sync services.
///
/// The FSEvents latency (0.5 s) coalesces rapid bursts into a single callback,
/// so the caller doesn't need its own debounce.
final class LibraryWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.readlater.fsevents", qos: .utility)
    private let onChange: @Sendable () -> Void

    init(libraryPath: String, onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        let watchPath = (libraryPath as NSString).appendingPathComponent("articles")
        start(path: watchPath)
    }

    deinit { stop() }

    // ── Private ───────────────────────────────────────────────────────────

    private func start(path: String) {
        // `passRetained` keeps self alive for the duration of the stream.
        // The `release` callback balances the retain when the stream is torn down.
        var ctx = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passRetained(self).toOpaque(),
            retain: nil,
            release: { Unmanaged<LibraryWatcher>.fromOpaque($0!).release() },
            copyDescription: nil
        )

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<LibraryWatcher>.fromOpaque(info).takeUnretainedValue().fire()
        }

        stream = FSEventStreamCreate(
            nil, callback, &ctx,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,   // seconds of latency / coalescing
            flags
        )
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    private func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }

    private func fire() {
        onChange()
    }
}
