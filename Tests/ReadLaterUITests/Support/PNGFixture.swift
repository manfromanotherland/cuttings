// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import CryptoKit

/// A tiny but valid 1×1 PNG for asset tests, plus the filename the library
/// contract mandates: `assets/<id>/<sha256>.<ext>`, where `<sha256>` is the
/// lowercase hex SHA-256 of the file's raw bytes.
enum PNGFixture {
    /// A valid 1×1 transparent RGBA PNG (the canonical smallest PNG): signature,
    /// IHDR, a single-pixel IDAT, and IEND, each chunk with its correct CRC.
    static let bytes: [UInt8] = [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // signature
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR length + type
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // width=1, height=1
        0x08, 0x06, 0x00, 0x00, 0x00,                   // 8-bit, RGBA, deflate, no filter/interlace
        0x1F, 0x15, 0xC4, 0x89,                         // IHDR CRC
        0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, // IDAT length=10 + type
        0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, // zlib: one transparent pixel
        0x0D, 0x0A, 0x2D, 0xB4,                         // IDAT CRC
        0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, // IEND length=0 + type
        0xAE, 0x42, 0x60, 0x82,                         // IEND CRC
    ]

    static var data: Data { Data(bytes) }

    /// `<sha256>.png` — the contract-mandated asset filename for `bytes`.
    static var fileName: String {
        let hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return "\(hex).png"
    }
}
