// SPDX-License-Identifier: MIT
// Run from the repository root after building the macOS app:
// swift extension/scripts/generate-icons.swift
import AppKit

let source = CommandLine.arguments.dropFirst().first
    ?? "macos/build/Build/Products/Debug/Óia.app/Contents/Resources/Oia.icns"
guard let image = NSImage(contentsOfFile: source) else {
    fatalError("Cannot load \(source). Build the macOS app first.")
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
