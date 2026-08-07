// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import UniformTypeIdentifiers

/// The browser extension shipped inside the app bundle.
///
/// While the extension awaits review on the Chrome Web Store and Firefox
/// Add-ons, the app hands users the packaged `.zip` directly so they can load it
/// unpacked as a developer build. The archive is bundled as a resource
/// (`Resources/extension.zip`); `save()` copies it wherever the user chooses.
enum ExtensionPackage {
    /// The public source, offered alongside the download so users can inspect
    /// what they're installing.
    static let sourceURL = URL(string: "https://github.com/readcontrol/extension")!

    /// The file name proposed in the save panel.
    static let suggestedFileName = "readcontrol-extension.zip"

    /// The bundled archive, if present. `nil` only if the resource somehow didn't
    /// ship — call sites hide the download affordance in that case.
    static var bundledZipURL: URL? {
        Bundle.main.url(forResource: "extension", withExtension: "zip")
    }

    /// Prompt for a destination with an `NSSavePanel` and copy the bundled archive
    /// there, then reveal it in Finder. A no-op if the resource is missing; copy
    /// failures surface as a modal alert rather than failing silently, since this
    /// is an explicit user action.
    @MainActor
    static func save() {
        guard let zipURL = bundledZipURL else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedFileName
        panel.allowedContentTypes = [.zip]
        panel.prompt = "Download"
        panel.message = "Choose where to save the ReadControl browser extension."
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        do {
            // The panel already confirmed any overwrite; clear a stale file first
            // so the copy can't fail on an existing destination.
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: zipURL, to: destination)
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't save the extension"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}
