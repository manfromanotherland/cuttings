// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import ImageIO
import UniformTypeIdentifiers

/// One item decoded from a paste or drop operation.
///
/// Image bytes retain their original raster encoding and carry the MIME type
/// detected from those bytes. Text-file cases have already been validated as
/// UTF-8, but remain distinct so ingestion can preserve the source filename as
/// a title while saving their contents as a quote.
enum IngestionPayload: Equatable, Sendable {
    case image(data: Data, contentType: String, suggestedFilename: String?)
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
