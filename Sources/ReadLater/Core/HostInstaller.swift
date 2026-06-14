// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Installs the bundled `native-host` binary's native-messaging manifest
/// into all supported browsers on first launch (and whenever the app moves).
enum HostInstaller {
    private static let installedPathKey = "nativeHostInstalledPath"

    // ── Public API ────────────────────────────────────────────────────────

    /// Returns true if the manifest was installed (or was already up to date).
    @discardableResult
    static func installIfNeeded() -> Bool {
        guard let hostURL = bundledHostURL() else {
            print("HostInstaller: native-host binary not found in bundle")
            return false
        }
        let path = hostURL.path

        // Re-install whenever the binary path changes (e.g. app moved).
        let lastPath = UserDefaults.standard.string(forKey: installedPathKey)
        guard lastPath != path else { return true }

        do {
            try run(hostURL: hostURL)
            UserDefaults.standard.set(path, forKey: installedPathKey)
            print("HostInstaller: manifest installed from \(path)")
            return true
        } catch {
            print("HostInstaller: \(error.localizedDescription)")
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
            throw HostInstallerError.nonZeroExit(
                code: process.terminationStatus,
                output: output
            )
        }
    }
}

// ── Error ─────────────────────────────────────────────────────────────────────

enum HostInstallerError: LocalizedError {
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
