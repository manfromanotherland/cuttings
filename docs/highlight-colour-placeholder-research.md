# Image Highlight Colour for Placeholders

Checked **2026-08-26** against the current Cuttings source and Apple’s public documentation.

## Finding

Cuttings does not receive a separate image “highlight colour” from Vision, Core Spotlight, or
AppKit. The reusable colour signal behind a search for `blue` is Cuttings’ own colour-family
classifier, fed by the weighted exact-sRGB clusters returned by Core Image k-means. A placeholder
highlight can use the same classifier while excluding neutral black, gray, and white families.

Apple documents that [`CIKMeans`](https://developer.apple.com/documentation/coreimage/cifilter-swift.class/kmeans%28%29)
returns the most common colours as RGB cluster centres, with alpha holding each cluster’s weight.
That is exactly the data cached by Cuttings. No new image analysis is needed.

The similarly named Apple APIs are not substitutes:

- [`VNClassifyImageRequest`](https://developer.apple.com/documentation/vision/vnclassifyimagerequest)
  returns `VNClassificationObservation` values. Apple defines those as a technical string
  [`identifier`](https://developer.apple.com/documentation/vision/vnclassificationobservation/identifier)
  plus observation confidence, not an RGB colour. Cuttings uses this request for labels such as
  `chair`, separately from palette extraction in
  [`AppleVisualAnalyzer.swift`](../macos/Sources/Cuttings/Platform/VisualAnalysis/AppleVisualAnalyzer.swift).
- Vision [saliency](https://developer.apple.com/documentation/vision/cropping-images-using-saliency)
  returns a one-component heat map and optional salient regions. It could mask a future colour
  calculation, but it does not itself return a colour and using it would be a new extraction
  algorithm.
- [`NSColor.highlightColor`](https://developer.apple.com/documentation/AppKit/NSColor/highlightColor)
  is the system colour used as a virtual UI light source. It is unrelated to an image’s pixels.
- Core Spotlight can independently return a semantic match for `blue`, but `CSUserQuery` returns
  ranked searchable items, not the colour or reasoning behind a match. Cuttings deliberately
  reduces those results to reading IDs in
  [`SpotlightVisualIndex.swift`](../macos/Sources/Cuttings/Platform/Spotlight/SpotlightVisualIndex.swift).
  Apple documents this ranked lexical/semantic query role in
  [`CSUserQuery`](https://developer.apple.com/documentation/corespotlight/csuserquery).

## How `blue` currently works

There are two search paths, merged by the Rust core:

1. `AppleVisualAnalyzer` runs Vision classification and
   [`VisualPaletteExtractor`](../macos/Sources/Cuttings/Platform/VisualAnalysis/VisualPaletteExtractor.swift).
   [`VisualSearchCoordinator.swift`](../macos/Sources/Cuttings/State/VisualSearchCoordinator.swift)
   sends the exact RGB cluster centres and weights to core.
2. In [`visual_index.rs`](../core/core/src/visual_index.rs), `normalize_palette` validates,
   weight-normalises, and orders those clusters. `predominant_color` maps every cluster to one of
   Cuttings’ named families, sums weights by family, and chooses the family with the greatest
   total weight. `normalize_result` appends that name, for example `blue`, to `visual_terms`.
3. `visual_terms` is a column of the `readings_fts` FTS5 table. A typed `blue` query therefore
   matches it through the ordinary query path in [`search.rs`](../core/core/src/search.rs). The
   app may also supply Core Spotlight candidate IDs; [`list.rs`](../core/core/src/list.rs) unions
   those after lexical/FTS matches and keeps FTS matches first.

The important detail is that `predominant_color` is only a **named family**. It is searchable but
not paintable. The exact paintable RGB values remain in `visual_analysis.palette_json`.

## Smallest correct code change

Two small corrections are required; neither needs another analysis algorithm:

1. Keep the original fixed k-means seeds. When rendering CIKMeans’ weighted RGBA output into an
   unpremultiplied destination, multiply each rendered RGB component by its alpha weight before
   clamping. That reverses the render conversion and preserves the cluster centre Apple describes.
   Bump the analyzer version so the disposable white-biased cache is recalculated once.
2. Parse the current supported/version-matched `palette_json` when mapping a reading row. Aggregate
   only chromatic clusters through the existing `color_family` classifier, choose the family with
   the largest total weight, then return its greatest-weight exact cluster. If the image is fully
   neutral, fall back to its greatest-weight neutral cluster.
3. Expose that `WeightedColor` through the existing `ReadingRow.dominant_color` /
   `FfiWeightedColor` path and use its exact sRGB components in `LocalReadingImage`.

The palette projection and UI plumbing are already wired through
[`list.rs`](../core/core/src/list.rs), [`ffi.rs`](../core/core/src/ffi.rs),
[`ReadingRow.swift`](../macos/Sources/Cuttings/Bridge/Mappers/ReadingRow.swift),
[`CuttingsTheme.swift`](../macos/Sources/Cuttings/Features/Cuttings/CuttingsTheme.swift), and
[`LocalReadingImage.swift`](../macos/Sources/Cuttings/Features/Cuttings/LocalReadingImage.swift).
The remaining semantic correction is to make `representative_placeholder_color` select the
highest-weight cluster inside the winning **chromatic** family, rather than apply a separate
extreme-neutral threshold.

That distinction is observable. For a palette containing one 30% red cluster and three blue
clusters totalling 70%, `blue` search matches because Blue wins the family aggregation. The
earlier helper could still return the 30% red cluster because it was the largest individual,
non-neutral cluster. A family-constrained selector makes search and placeholder agree by
construction.

Add one core regression with a largest individual cluster from one family and a larger aggregate
weight in another family. Assert that plain `blue` search returns the row and that the row’s exact
placeholder colour belongs to Blue. Existing mapper and theme tests cover the rest of the bridge.
