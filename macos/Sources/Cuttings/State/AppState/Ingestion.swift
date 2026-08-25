// SPDX-License-Identifier: GPL-3.0-or-later

import Accessibility
import Foundation

struct SaveNotice: Equatable, Sendable {
    let message: String
    let systemImage: String
}

private struct SaveSummary {
    var saved = 0
    var upgraded = 0
    var duplicates = 0
    var failures: Int
    var lastError: Error?

    var changed: Int {
        saved + upgraded
    }

    var completed: Int {
        changed + duplicates
    }
}

// MARK: - Paste and drop saves

extension AppState {
    /// Persist a decoded paste/drop batch through the shared Rust save path.
    /// One malformed item does not discard its valid siblings; the final notice
    /// reports new saves, duplicates, and partial failures together.
    func save(_ payloads: [IngestionPayload], rejectedCount: Int = 0) async {
        guard let core else { return }
        guard !payloads.isEmpty else {
            presentSaveNotice("Nothing here can be saved", systemImage: "exclamationmark.triangle")
            return
        }

        isSaving = true
        defer { isSaving = false }

        let summary = await save(payloads, rejectedCount: rejectedCount, with: core)

        if summary.changed > 0 {
            // Every core import synchronizes the disposable index before it
            // returns. Reload once after the batch so cards/counts move together.
            await refresh()
            scheduleVisualSearchReconciliation()
        }

        if summary.completed == 0, let lastError = summary.lastError {
            error = lastError.localizedDescription
            return
        }

        let notice = saveNotice(
            saved: summary.saved,
            upgraded: summary.upgraded,
            duplicates: summary.duplicates,
            failures: summary.failures
        )
        presentSaveNotice(notice.message, systemImage: notice.systemImage)
    }

    private func save(
        _ payloads: [IngestionPayload],
        rejectedCount: Int,
        with core: any CoreBridging
    ) async -> SaveSummary {
        var summary = SaveSummary(failures: rejectedCount)
        for payload in payloads {
            do {
                switch try await save(payload, with: core).disposition {
                case .saved: summary.saved += 1
                case .upgraded: summary.upgraded += 1
                case .duplicate: summary.duplicates += 1
                }
            } catch {
                summary.failures += 1
                summary.lastError = error
            }
        }
        return summary
    }

    private func save(
        _ payload: IngestionPayload,
        with core: any CoreBridging
    ) async throws -> FfiImportResult {
        switch payload {
        case let .link(url):
            return try await core.importLink(url: url.absoluteString)

        case let .text(text):
            return try await core.importText(text: text, title: nil)

        case let .markdownFile(data, suggestedFilename),
             let .textFile(data, suggestedFilename):
            guard let text = String(data: data, encoding: .utf8) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            return try await core.importText(
                text: text, title: title(from: suggestedFilename)
            )

        case let .image(data, contentType, suggestedFilename):
            return try await core.importImage(
                data: data,
                contentType: contentType,
                title: title(from: suggestedFilename) ?? "Pasted image"
            )

        case let .video(file, contentType, suggestedFilename):
            // Core copies the source file into the library before returning. A
            // provider-owned temporary directory is removed on every outcome;
            // `IngestionVideoFile.deinit` covers cancellation before here. A
            // Finder URL has no cleanup directory, but its security scope must
            // remain active until core has finished streaming it.
            defer { file.remove() }
            let didAccess = file.url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    file.url.stopAccessingSecurityScopedResource()
                }
            }
            return try await core.importVideoFile(
                filePath: file.url.path,
                contentType: contentType,
                title: title(from: suggestedFilename) ?? "Imported video"
            )
        }
    }

    private func saveNotice(
        saved: Int, upgraded: Int, duplicates: Int, failures: Int
    ) -> SaveNotice {
        let changed = saved + upgraded
        var parts: [String] = []

        if changed > 0 {
            parts.append(changed == 1 ? "Saved to Cuttings" : "Saved \(changed) items to Cuttings")
        }
        if duplicates > 0 {
            parts.append(duplicates == 1 ? "Already saved" : "\(duplicates) already saved")
        }
        if failures > 0 {
            parts.append(
                failures == 1 ? "1 item couldn’t be saved" : "\(failures) items couldn’t be saved"
            )
        }

        let symbol = failures > 0
            ? "exclamationmark.triangle"
            : (changed > 0 ? "checkmark.circle.fill" : "checkmark.circle")
        return SaveNotice(message: parts.joined(separator: " · "), systemImage: symbol)
    }

    private func presentSaveNotice(_ message: String, systemImage: String) {
        let notice = SaveNotice(message: message, systemImage: systemImage)
        saveNotice = notice
        AccessibilityNotification.Announcement(message).post()

        saveNoticeTask?.cancel()
        saveNoticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, self?.saveNotice == notice else { return }
            self?.saveNotice = nil
        }
    }

    private func title(from filename: String?) -> String? {
        guard let filename, !filename.isEmpty else { return nil }
        let title = URL(fileURLWithPath: filename)
            .deletingPathExtension()
            .lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }
}
