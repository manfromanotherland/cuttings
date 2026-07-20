// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The sample image an asset test writes into a per-test library, and the
/// filename it's stored under. `Fixtures` references it from the article body and
/// `DeepReadJourney` writes the bytes to disk — both go through here so the name
/// they use always matches.
///
/// `SampleImage.png` is a real image file (the Markdown mark, fitting the
/// "The Complete Markdown Sample" fixture article) shipped in the UITest bundle.
/// The test copies it onto disk in the library's `assets/` and the app reads it
/// back on render — exactly how a normal article's image is stored and loaded.
enum PNGFixture {
    /// The asset filename inside `assets/<id>/`. The reader resolves the body's
    /// image path literally, so any stable name works; it just has to match on
    /// both sides.
    static let fileName = "SampleImage.png"

    /// The image's raw bytes, read from the bundled `SampleImage.png`.
    static var data: Data {
        guard let url = Bundle(for: BundleToken.self).url(forResource: "SampleImage", withExtension: "png"),
              let data = try? Data(contentsOf: url) else {
            fatalError("SampleImage.png is missing from the UITest bundle resources.")
        }
        return data
    }

    /// Anchors `Bundle(for:)` to the UITest bundle that carries `SampleImage.png`.
    private final class BundleToken {}
}
