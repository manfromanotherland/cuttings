// SPDX-License-Identifier: GPL-3.0-or-later

import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A file-backed movie source. Finder URLs remain at their original location and
/// are accessed under a security scope; `NSItemProvider` file representations
/// instead carry an app-owned temporary directory because the provider URL is
/// only guaranteed to exist inside its completion handler. Explicit cleanup
/// after import keeps disk use predictable, while `deinit` covers cancellation.
final class IngestionVideoFile: @unchecked Sendable, Equatable {
    let url: URL

    private let cleanupDirectoryURL: URL?
    private let lock = NSLock()
    private var removed = false

    init(url: URL, cleanupDirectoryURL: URL? = nil) {
        self.url = url
        self.cleanupDirectoryURL = cleanupDirectoryURL
    }

    static func == (lhs: IngestionVideoFile, rhs: IngestionVideoFile) -> Bool {
        lhs === rhs
    }

    func remove() {
        lock.lock()
        guard !removed else {
            lock.unlock()
            return
        }
        removed = true
        lock.unlock()
        if let cleanupDirectoryURL {
            try? FileManager.default.removeItem(at: cleanupDirectoryURL)
        }
    }

    deinit {
        remove()
    }
}

struct StagedVideoFile: Sendable {
    let file: IngestionVideoFile
    let contentType: String
    let suggestedFilename: String?
}

/// One item decoded from a paste or drop operation.
///
/// Image bytes retain their original raster encoding and carry the MIME type
/// detected from those bytes. Text-file cases have already been validated as
/// UTF-8, but remain distinct so ingestion can preserve the source filename as
/// a title while saving their contents as a quote.
enum IngestionPayload: Equatable, Sendable {
    case image(data: Data, contentType: String, suggestedFilename: String?)
    case video(file: IngestionVideoFile, contentType: String, suggestedFilename: String?)
    case link(URL)
    case text(String)
    case markdownFile(data: Data, suggestedFilename: String?)
    case textFile(data: Data, suggestedFilename: String?)
}

/// Pure decoding and classification shared by the item-provider adapter and
/// its hostless unit tests.
enum IngestionPayloadDecoder {
    static let maximumByteCount = 40 * 1024 * 1024

    static func payload(
        forPlainTextData data: Data,
        maximumByteCount: Int = maximumByteCount
    ) -> IngestionPayload? {
        guard !data.isEmpty,
              data.count <= maximumByteCount,
              let string = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return payload(forPlainText: string, maximumByteCount: maximumByteCount)
    }

    static func payload(
        forPlainText string: String,
        maximumByteCount: Int = maximumByteCount
    ) -> IngestionPayload? {
        guard string.utf8.count <= maximumByteCount else { return nil }

        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = httpURL(from: trimmed) {
            return .link(url)
        }

        return .text(string)
    }

    static func httpURL(from string: String) -> URL? {
        guard !string.contains(where: \Character.isWhitespace),
              let components = URLComponents(string: string),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host != nil
        else {
            return nil
        }

        return components.url
    }

    static func payload(
        forLocalFile url: URL,
        maximumByteCount: Int = maximumByteCount
    ) -> IngestionPayload? {
        guard url.isFileURL else { return nil }

        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let type = contentType(for: url) else { return nil }
        let filename = nonempty(url.lastPathComponent)

        if isImage(type) {
            guard let data = try? readData(at: url, maximumByteCount: maximumByteCount) else {
                return nil
            }
            return payload(
                forImageData: data,
                suggestedFilename: filename,
                maximumByteCount: maximumByteCount
            )
        }

        let markdown = isMarkdown(type: type, pathExtension: url.pathExtension)
        let plainText = isPlainText(type: type, pathExtension: url.pathExtension)
        guard markdown || plainText,
              let data = try? readData(at: url, maximumByteCount: maximumByteCount),
              !data.isEmpty,
              String(data: data, encoding: .utf8) != nil
        else { return nil }

        if markdown {
            return .markdownFile(data: data, suggestedFilename: filename)
        }
        return .textFile(data: data, suggestedFilename: filename)
    }

    static func payload(
        forImageData data: Data,
        suggestedFilename: String?,
        maximumByteCount: Int = maximumByteCount
    ) -> IngestionPayload? {
        guard !data.isEmpty,
              data.count <= maximumByteCount,
              let contentType = rasterContentType(for: data)
        else {
            return nil
        }

        return .image(
            data: data,
            contentType: contentType,
            suggestedFilename: suggestedFilename
        )
    }

    static func isImage(_ type: UTType) -> Bool {
        type.identifier == UTType.image.identifier
            || supportedRasterTypeIdentifiers.contains(type.identifier)
            || type.conforms(to: .image)
    }

    static func isSupportedVideo(_ type: UTType) -> Bool {
        type.conforms(to: .mpeg4Movie) || type.conforms(to: .quickTimeMovie)
    }

    /// Copy an MP4/M4V/MOV into an app-owned temporary directory. This function
    /// is deliberately synchronous so an item-provider callback can complete the
    /// copy before returning and invalidating its source URL. It copies the file
    /// on disk and never materializes the movie as `Data`.
    static func stageVideoFile(
        at url: URL,
        declaredTypeIdentifier: String? = nil,
        suggestedFilename: String? = nil
    ) -> StagedVideoFile? {
        guard let source = videoFile(
            at: url,
            declaredTypeIdentifier: declaredTypeIdentifier,
            suggestedFilename: suggestedFilename
        ) else { return nil }

        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("Cuttings-Ingestion", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destination = parent.appendingPathComponent("video.\(source.fileExtension)")

        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            try FileManager.default.createDirectory(
                at: parent, withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: url, to: destination)
            return StagedVideoFile(
                file: IngestionVideoFile(url: destination, cleanupDirectoryURL: parent),
                contentType: source.contentType,
                suggestedFilename: source.suggestedFilename
            )
        } catch {
            try? FileManager.default.removeItem(at: parent)
            return nil
        }
    }

    /// Classify a durable Finder file URL without copying it. Callers retain the
    /// URL and open a security-scoped access window while validating and while
    /// core streams it into the library.
    static func videoFile(
        at url: URL,
        declaredTypeIdentifier: String? = nil,
        suggestedFilename: String? = nil
    ) -> (file: IngestionVideoFile, contentType: String, fileExtension: String, suggestedFilename: String?)? {
        guard url.isFileURL else { return nil }

        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let values = try? url.resourceValues(forKeys: [
            .contentTypeKey, .fileSizeKey, .isRegularFileKey
        ]),
            values.isRegularFile == true,
            values.fileSize.map({ $0 > 0 }) ?? true,
            let videoType = videoType(
                resourceType: values.contentType,
                sourceURL: url,
                declaredTypeIdentifier: declaredTypeIdentifier,
                suggestedFilename: suggestedFilename
            )
        else {
            return nil
        }

        return (
            IngestionVideoFile(url: url),
            videoType.contentType,
            videoType.extension,
            nonempty(suggestedFilename ?? "") ?? nonempty(url.lastPathComponent)
        )
    }

    /// AVFoundation verifies the staged bytes are playable and contain a video
    /// track. Extension/UTType checks alone would accept renamed or corrupt files.
    static func payload(forStagedVideo staged: StagedVideoFile) async -> IngestionPayload? {
        let didAccess = staged.file.url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                staged.file.url.stopAccessingSecurityScopedResource()
            }
        }
        let asset = AVURLAsset(url: staged.file.url)
        do {
            guard try await asset.load(.isPlayable),
                  try await !(asset.loadTracks(withMediaType: .video)).isEmpty
            else {
                staged.file.remove()
                return nil
            }
        } catch {
            staged.file.remove()
            return nil
        }

        return .video(
            file: staged.file,
            contentType: staged.contentType,
            suggestedFilename: staged.suggestedFilename
        )
    }

    private static let supportedRasterTypeIdentifiers = Set(
        (CGImageSourceCopyTypeIdentifiers() as NSArray).compactMap { $0 as? String }
    )

    /// Some macOS builds omit MIME tags from the Uniform Type registry even
    /// though ImageIO can decode the declared raster type. Keep the common
    /// standards explicit so valid clipboard images do not depend on that
    /// ambient registry state.
    private static let fallbackRasterContentTypes = [
        "public.jpeg": "image/jpeg",
        "public.png": "image/png",
        "com.compuserve.gif": "image/gif",
        "public.tiff": "image/tiff",
        "public.jpeg-2000": "image/jp2",
        "public.jpeg-xl": "image/jxl",
        "public.avif": "image/avif",
        "public.heic": "image/heic",
        "public.heif": "image/heif",
        "org.webmproject.webp": "image/webp",
        "com.microsoft.bmp": "image/bmp",
        "com.microsoft.ico": "image/vnd.microsoft.icon"
    ]

    private static func rasterContentType(for data: Data) -> String? {
        let options = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false
        ] as CFDictionary

        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              CGImageSourceGetCount(source) > 0,
              CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
              CGImageSourceCopyPropertiesAtIndex(source, 0, options) != nil,
              let identifier = CGImageSourceGetType(source) as String?,
              supportedRasterTypeIdentifiers.contains(identifier),
              let contentType = UTType(identifier)?.preferredMIMEType
              ?? fallbackRasterContentTypes[identifier],
              contentType.hasPrefix("image/")
        else {
            return nil
        }

        return contentType
    }

    private static func contentType(for url: URL) -> UTType? {
        if let resourceType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return resourceType
        }
        return UTType(filenameExtension: url.pathExtension)
    }

    private static func videoType(
        resourceType: UTType?,
        sourceURL: URL,
        declaredTypeIdentifier: String?,
        suggestedFilename: String?
    ) -> (contentType: String, extension: String)? {
        let filenameExtension = suggestedFilename
            .map { URL(fileURLWithPath: $0).pathExtension }
            .flatMap { $0.isEmpty ? nil : $0 }
        let candidates = [
            resourceType,
            UTType(filenameExtension: sourceURL.pathExtension),
            filenameExtension.flatMap { UTType(filenameExtension: $0) },
            declaredTypeIdentifier.flatMap(UTType.init)
        ].compactMap(\.self)

        for type in candidates where isSupportedVideo(type) {
            if type.conforms(to: .quickTimeMovie) {
                return ("video/quicktime", "mov")
            }
            return ("video/mp4", "mp4")
        }
        return nil
    }

    private static func isMarkdown(type: UTType, pathExtension: String) -> Bool {
        let markdownExtensions = Set(["md", "markdown", "mdown", "mkd", "mkdn"])
        return type.identifier == "net.daringfireball.markdown"
            || markdownExtensions.contains(pathExtension.lowercased())
    }

    private static func isPlainText(type: UTType, pathExtension: String) -> Bool {
        let plainTextExtensions = Set(["txt", "text"])
        return type.conforms(to: .plainText) || plainTextExtensions.contains(pathExtension.lowercased())
    }

    private static func readData(at url: URL, maximumByteCount: Int) throws -> Data {
        if let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           fileSize > maximumByteCount
        {
            throw CocoaError(.fileReadTooLarge)
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var result = Data()
        let chunkSize = min(1_048_576, maximumByteCount + 1)

        while result.count <= maximumByteCount {
            let remaining = maximumByteCount + 1 - result.count
            guard let chunk = try handle.read(upToCount: min(chunkSize, remaining)),
                  !chunk.isEmpty
            else {
                return result
            }
            result.append(chunk)
        }

        throw CocoaError(.fileReadTooLarge)
    }

    private static func nonempty(_ string: String) -> String? {
        string.isEmpty ? nil : string
    }
}
