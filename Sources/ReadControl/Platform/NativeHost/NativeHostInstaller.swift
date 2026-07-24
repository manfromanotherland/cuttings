// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Installs the bundled `native-host` binary's native-messaging manifest into
/// every browser found on the machine.
///
/// Called on every launch (from `boot`). The Rust `native-host --install-manifest`
/// it runs is a cheap, idempotent scan — directory reads plus a few small writes,
/// no deletions — so re-running it each time costs almost nothing and is what lets
/// a browser installed *after* first launch get wired up without an app update.
enum NativeHostInstaller {
    private static let installedPathKey = "nativeHostInstalledPath"

    // ── Public API ────────────────────────────────────────────────────────

    /// Runs the manifest install and returns true on success. Idempotent, so
    /// safe to call on every launch.
    @discardableResult
    static func install() -> Bool {
        guard let hostURL = bundledHostURL() else {
            print("NativeHostInstaller: native-host binary not found in bundle")
            return false
        }

        do {
            try run(hostURL: hostURL)
            // Record the path so Settings can show the manifest as installed for
            // this bundle.
            UserDefaults.standard.set(hostURL.path, forKey: installedPathKey)
            print("NativeHostInstaller: manifest installed from \(hostURL.path)")
            return true
        } catch {
            print("NativeHostInstaller: \(error.localizedDescription)")
            return false
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    static func bundledHostURL() -> URL? {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/native-host")
            .resolvingSymlinksInPath()
            .existingFile()
    }

    private static func run(hostURL: URL) throws {
        let process = Process()
        process.executableURL = hostURL
        process.arguments = ["--install-manifest"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let output = String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        if process.terminationStatus != 0 {
            throw NativeHostInstallerError.nonZeroExit(
                code: process.terminationStatus,
                output: output
            )
        }
    }
}

// ── Error ─────────────────────────────────────────────────────────────────────

enum NativeHostInstallerError: LocalizedError {
    case nonZeroExit(code: Int32, output: String)

    var errorDescription: String? {
        switch self {
        case let .nonZeroExit(code, output):
            "native-host exited with code \(code): \(output)"
        }
    }
}

// ── URL helper ────────────────────────────────────────────────────────────────

private extension URL {
    func existingFile() -> URL? {
        FileManager.default.fileExists(atPath: path) ? self : nil
    }
}
