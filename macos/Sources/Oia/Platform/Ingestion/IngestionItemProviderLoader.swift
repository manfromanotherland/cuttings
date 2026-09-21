// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import UniformTypeIdentifiers

/// Decodes the `NSItemProvider` values supplied by both SwiftUI drop and paste
/// handlers. Each provider contributes at most one payload, and providers are
/// awaited sequentially so their input order is retained.
@MainActor
enum IngestionItemProviderLoader {
    static func load(from providers: [NSItemProvider]) async -> [IngestionPayload] {
        var payloads: [IngestionPayload] = []
        payloads.reserveCapacity(providers.count)

        for provider in providers {
            if let payload = await load(from: provider) {
                payloads.append(payload)
            }
        }

        return payloads
    }

    static func load(from provider: NSItemProvider) async -> IngestionPayload? {
        if let payload = await loadLocalFile(from: provider) {
            return payload
        }
        if let payload = await loadImage(from: provider) {
            return payload
        }
        if let payload = await loadWebURL(from: provider) {
            return payload
        }
        return await loadPlainText(from: provider)
    }

    private static func loadLocalFile(from provider: NSItemProvider) async -> IngestionPayload? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let url = await loadURLItem(from: provider, typeIdentifier: UTType.fileURL.identifier),
           let payload = await decodeLocalFile(at: url)
        {
            return payload
        }

        // Some pasteboards and non-Finder drag sources vend the movie itself
        // instead of a public.file-url. `loadFileRepresentation` owns its URL only
        // for the callback, so the helper stages it before resuming this task.
        for identifier in movieTypeIdentifiers(from: provider) {
            guard let staged = await loadStagedVideoRepresentation(
                from: provider, typeIdentifier: identifier
            ),
                let payload = await IngestionPayloadDecoder.payload(forStagedVideo: staged)
            else {
                continue
            }
            return payload
        }
        return nil
    }

    private static func loadImage(from provider: NSItemProvider) async -> IngestionPayload? {
        for identifier in imageTypeIdentifiers(from: provider) {
            guard let data = await loadData(from: provider, typeIdentifier: identifier),
                  let payload = await decodeImage(data, suggestedFilename: provider.suggestedName)
            else {
                continue
            }
            return payload
        }
        return nil
    }

    private static func loadWebURL(from provider: NSItemProvider) async -> IngestionPayload? {
        for identifier in webURLTypeIdentifiers(from: provider) {
            if let url = await loadURLItem(from: provider, typeIdentifier: identifier),
               let httpURL = IngestionPayloadDecoder.httpURL(from: url.absoluteString)
            {
                return .link(httpURL)
            }

            if let string = await loadString(from: provider, typeIdentifier: identifier),
               let httpURL = IngestionPayloadDecoder.httpURL(
                   from: string.trimmingCharacters(in: .whitespacesAndNewlines)
               )
            {
                return .link(httpURL)
            }
        }
        return nil
    }

    private static func loadPlainText(from provider: NSItemProvider) async -> IngestionPayload? {
        for identifier in plainTextTypeIdentifiers(from: provider) {
            if let data = await loadData(from: provider, typeIdentifier: identifier),
               let payload = IngestionPayloadDecoder.payload(forPlainTextData: data)
            {
                return payload
            }

            if let string = await loadString(from: provider, typeIdentifier: identifier),
               let payload = IngestionPayloadDecoder.payload(forPlainText: string)
            {
                return payload
            }
        }

        return nil
    }

    private static func imageTypeIdentifiers(from provider: NSItemProvider) -> [String] {
        provider.registeredTypeIdentifiers.filter { identifier in
            guard let type = UTType(identifier) else { return false }
            return IngestionPayloadDecoder.isImage(type) && !type.conforms(to: .fileURL)
        }
    }

    private static func webURLTypeIdentifiers(from provider: NSItemProvider) -> [String] {
        provider.registeredTypeIdentifiers.filter { identifier in
            guard let type = UTType(identifier) else { return false }
            return type.conforms(to: .url) && !type.conforms(to: .fileURL)
        }
    }

    private static func plainTextTypeIdentifiers(from provider: NSItemProvider) -> [String] {
        provider.registeredTypeIdentifiers.filter { identifier in
            UTType(identifier)?.conforms(to: .plainText) == true
        }
    }

    private static func movieTypeIdentifiers(from provider: NSItemProvider) -> [String] {
        provider.registeredTypeIdentifiers.filter { identifier in
            guard let type = UTType(identifier) else { return false }
            return type.conforms(to: .movie) && !type.conforms(to: .fileURL)
        }
    }

    private static func loadData(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private static func loadURLItem(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                continuation.resume(returning: decodedURL(from: item))
            }
        }
    }

    private static func loadString(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                continuation.resume(returning: decodedString(from: item))
            }
        }
    }

    private static func loadStagedVideoRepresentation(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async -> StagedVideoFile? {
        let suggestedFilename = provider.suggestedName
        return await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _ in
                // The provider may remove `url` as soon as this closure returns.
                // Finish the on-disk copy synchronously inside the closure.
                let staged = url.flatMap {
                    IngestionPayloadDecoder.stageVideoFile(
                        at: $0,
                        declaredTypeIdentifier: typeIdentifier,
                        suggestedFilename: suggestedFilename
                    )
                }
                continuation.resume(returning: staged)
            }
        }
    }

    private nonisolated static func decodedURL(from item: NSSecureCoding?) -> URL? {
        switch item {
        case let url as URL:
            url
        case let url as NSURL:
            url as URL
        case let data as Data:
            URL(dataRepresentation: data, relativeTo: nil)
                ?? String(data: data, encoding: .utf8).flatMap(URL.init(string:))
        case let string as String:
            URL(string: string)
        case let string as NSString:
            URL(string: string as String)
        default:
            nil
        }
    }

    private nonisolated static func decodedString(from item: NSSecureCoding?) -> String? {
        switch item {
        case let string as String:
            string
        case let string as NSString:
            string as String
        case let data as Data:
            String(data: data, encoding: .utf8)
        default:
            nil
        }
    }

    private static func decodeLocalFile(at url: URL) async -> IngestionPayload? {
        if let source = await Task.detached(operation: {
            IngestionPayloadDecoder.videoFile(at: url)
        }).value,
            let payload = await IngestionPayloadDecoder.payload(
                forStagedVideo: StagedVideoFile(
                    file: source.file,
                    contentType: source.contentType,
                    suggestedFilename: source.suggestedFilename
                )
            )
        {
            return payload
        }

        return await Task.detached {
            IngestionPayloadDecoder.payload(forLocalFile: url)
        }.value
    }

    private static func decodeImage(
        _ data: Data,
        suggestedFilename: String?
    ) async -> IngestionPayload? {
        await Task.detached {
            IngestionPayloadDecoder.payload(
                forImageData: data,
                suggestedFilename: suggestedFilename
            )
        }.value
    }
}
