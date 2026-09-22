// SPDX-License-Identifier: MIT
// Run from the repository root with Icon Composer installed:
// swift extension/scripts/generate-icons.swift
import AppKit

let source = CommandLine.arguments.dropFirst().first
    ?? "macos/Sources/Oia/Oia.icon"
let sourceURL = URL(fileURLWithPath: source)
let temporaryExport = FileManager.default.temporaryDirectory
    .appendingPathComponent("oia-watch-icon-\(UUID().uuidString).png")
defer { try? FileManager.default.removeItem(at: temporaryExport) }

let imageURL: URL
if sourceURL.pathExtension == "icon" {
    let exporter = Process()
    exporter.executableURL = URL(fileURLWithPath:
        "/Applications/Icon Composer.app/Contents/Executables/ictool")
    exporter.arguments = [
        sourceURL.path, "--export-image", "--output-file", temporaryExport.path,
        "--platform", "watchOS", "--rendition", "Default",
        "--width", "1024", "--height", "1024", "--scale", "1",
    ]
    try exporter.run()
    exporter.waitUntilExit()
    guard exporter.terminationStatus == 0 else {
        fatalError("Icon Composer could not export the watchOS icon")
    }
    imageURL = temporaryExport
} else {
    imageURL = sourceURL
}
guard let image = NSImage(contentsOf: imageURL) else {
    fatalError("Cannot load \(imageURL.path)")
}

for size in [16, 32, 48, 128] {
    for saved in [false, true] {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            fatalError("Cannot create icon bitmap")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        let side = CGFloat(size)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side),
                   from: .zero, operation: .copy, fraction: 1)
        if saved {
            let diameter = side * 0.48
            let badge = NSRect(x: side - diameter, y: 0, width: diameter, height: diameter)
            NSColor(srgbRed: 0.12, green: 0.65, blue: 0.30, alpha: 1).setFill()
            NSBezierPath(ovalIn: badge).fill()
            let check = NSBezierPath()
            check.move(to: NSPoint(x: badge.minX + diameter * 0.24, y: diameter * 0.49))
            check.line(to: NSPoint(x: badge.minX + diameter * 0.43, y: diameter * 0.30))
            check.line(to: NSPoint(x: badge.minX + diameter * 0.77, y: diameter * 0.70))
            check.lineWidth = max(1, diameter * 0.12)
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            NSColor.white.setStroke()
            check.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            fatalError("Cannot encode icon")
        }
        let name = saved ? "icon-saved" : "icon"
        try png.write(to: URL(fileURLWithPath: "extension/icons/\(name)-\(size).png"))
    }
}
