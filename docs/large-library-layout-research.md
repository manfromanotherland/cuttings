# Large-Library Board Layout Research

Checked **2026-08-25** against Apple's public AppKit, SwiftUI, PhotoKit, Image I/O,
Quick Look, and AVFoundation documentation, plus the source repositories of the relevant
open-source packages. Cuttings currently targets macOS 15 in
[`macos/project.yml`](../macos/project.yml).

> **Status:** The option analysis below predates the adopted implementation.
> Cuttings now uses LazyLayoutKit 0.3.0 for one complete, stable-ID masonry
> snapshot whose card views are materialized only around the viewport. The board
> has no user-visible pagination or loading row, and its layout metrics never wait
> for asset decoding or rendered-view measurement.

## Earlier decision analysis

Use one native **`NSCollectionView`** with a diffable data source, recycled items, prefetching, and
a derived thumbnail store. Do not paginate the view and do not block presenting item identifiers
on image decoding or card-height preparation. A collection view creates and recycles only the
items it is displaying, so thousands of records are not, by themselves, a reason to show a next-page
loader ([`NSCollectionView`](https://developer.apple.com/documentation/appkit/nscollectionview)).

Make the board layout a user-testable choice over that common foundation:

1. **Photos grid — recommended default.** Uniform square or portrait cells, media cropped with
   `aspectFill`, and fixed overlays for kind/title. Implement with `NSCollectionViewFlowLayout`.
   It has the least layout work, the most stable filtering, and the simplest smooth zoom.
2. **Justified rows — recommended visual alternative.** Preserve media aspect ratios while each
   completed row fills the available width. Give article, link, and quote cards a small set of
   predetermined ratios. Implement as a custom `NSCollectionViewLayout` with all geometry known
   before display.
3. **Compact mixed feed — recommended content alternative.** A regular media grid plus fixed-height
   rows or sections for quotes and articles. Implement with `NSCollectionViewCompositionalLayout`.
   It gives text more room but no longer preserves one strictly interleaved chronological board.
4. **Masonry — optional comparison, not the default.** It preserves full card proportions and packs
   space efficiently, but an insertion, filter, resize, or changed height can alter the column of
   every later item. That visible reflow is inherent to shortest-column masonry, not merely an
   implementation bug; even LazyLayoutKit documents this explicitly
   ([source](https://github.com/Dave861/LazyLayoutKit#what-is-not-in-030)).

The first prototype should expose **Photos / Justified / Masonry** as three modes using the same
item views, thumbnail cache, data snapshot, and test library. That isolates the layout choice from
image-loading and filtering performance. The compact mixed feed is worth testing only if the first
three show that text readability matters more than preserving a single mixed board.

## The Native Options

| Option | Large-library behaviour | Fit for Cuttings | Verdict |
| --- | --- | --- | --- |
| `NSCollectionViewFlowLayout` | Collection-view reuse with regular rows; fixed or delegate-provided item sizes | Ideal for a Photos-style cropped grid; item-size changes can use AppKit's layout animation | **Best default** |
| `NSCollectionViewCompositionalLayout` | Apple describes it as “fast by default”; combines regular, nested, or custom groups without a layout subclass | Best for a hybrid board with different sections; a custom group can express special geometry, but it still needs explicit frames | **Best hybrid option** |
| Custom `NSCollectionViewLayout` | Full control over precomputed frames, visible-rectangle queries, invalidation, and transitions | Appropriate for justified rows or masonry when sizes are known before display | **Use only for layouts AppKit does not ship** |
| `NSCollectionViewGridLayout` | Basic regular grid | Offers no useful advantage over flow layout for this board | Skip |
| `IKImageBrowserView` | Was specifically designed for many images and movies | Apple has deprecated it and says to use `NSCollectionView` | **Do not adopt** |
| SwiftUI `LazyVGrid` | Lazily creates regular-grid items as needed | Plausible for a simple grid, but gives less explicit control over AppKit cell reuse, prefetching, diffable updates, and layout transitions | Prototype only if the AppKit wrapper itself becomes a maintenance problem |
| SwiftUI custom `Layout` | Arbitrary geometry and animation | Apple's SwiftUI team states that custom `Layout` is eager and there is currently no public custom lazy-layout protocol | **Not suitable for thousands of cards** |

Sources:

- [`NSCollectionViewFlowLayout`](https://developer.apple.com/documentation/appkit/nscollectionviewflowlayout)
  supports equal or differing item sizes, dynamic delegate sizing, and custom update animations.
- Apple's [Advances in Collection View Layout](https://developer.apple.com/videos/play/wwdc2019/215/)
  introduces compositional layout on macOS as fast by default and documents custom groups for
  absolute item frames; AppKit exposes the corresponding
  [`NSCollectionLayoutGroup.custom`](https://developer.apple.com/documentation/appkit/nscollectionlayoutgroup/custom(layoutsize:itemprovider:)).
- Apple's [`NSCollectionViewLayout`](https://developer.apple.com/documentation/appkit/nscollectionviewlayout)
  documentation defines the required prepared attributes, visible-rectangle lookup, invalidation,
  animated bounds changes, and layout transitions for a custom layout.
- [`IKImageBrowserView`](https://developer.apple.com/documentation/quartz/ikimagebrowserview) is
  deprecated with the explicit replacement “Please use NSCollectionView instead.”
- [`LazyVGrid`](https://developer.apple.com/documentation/swiftui/lazyvgrid) creates children only as
  needed, but Apple's [2026 SwiftUI Group Lab](https://developer.apple.com/videos/play/wwdc2026/8006/?time=2621)
  says the public custom `Layout` protocol remains eager and cannot define a custom lazy layout.

## What the Public Photos Pattern Actually Is

Apple does not publish the macOS Photos app's internal view hierarchy, so claims about its exact
private implementation would be speculation. The public pattern Apple teaches for a Photos-like
browser is nevertheless clear:

- Present assets in a **collection-view thumbnail grid**.
- Request thumbnails at the display size rather than decoding original assets into cells.
- Maintain a **preheat rectangle** beyond the viewport, starting cache requests for items entering
  it and stopping requests for items leaving it.
- Because recycled cells may receive an earlier asynchronous result, apply a thumbnail only when
  the result's asset identifier still matches the cell.

Apple's PhotoKit sample implements all four points and uses `aspectFill` cells
([Browsing and Modifying Photo Albums](https://developer.apple.com/documentation/photokit/browsing-and-modifying-photo-albums)).
Its large-library guide says to preload thumbnails in batches with `PHCachingImageManager`
([Loading and Caching Assets and Thumbnails](https://developer.apple.com/documentation/photokit/loading-and-caching-assets-and-thumbnails)).

`PHCachingImageManager` itself is **not** Cuttings' solution. `PHAsset` represents an image or video
managed by the user's Photos library, whereas Cuttings owns an arbitrary local Markdown-and-assets
library ([`PHAsset`](https://developer.apple.com/documentation/photos/phasset),
[`PhotoKit`](https://developer.apple.com/documentation/photokit)). Importing Cuttings assets into
Photos would violate the product's storage model. Reproduce the preheat-and-cache pattern over
Cuttings' own disposable thumbnail index instead.

## The Shared Pipeline Every Layout Needs

The layout should never wait for an image, video frame, text measurement, or next page.

1. **Put all matching reading IDs in one snapshot.** Use
   [`NSCollectionViewDiffableDataSource`](https://developer.apple.com/documentation/appkit/nscollectionviewdiffabledatasource-axww)
   and apply a new identifier snapshot when the type/tag/search filter changes. Apple's diffable
   data-source session describes snapshot updates as heavily stress-tested, automatically diffed,
   and available on macOS
   ([Advances in UI Data Sources](https://developer.apple.com/videos/play/wwdc2019/220/)).
   Pagination may still exist between the Rust index and storage internally, but it must not be a
   user-visible gate between already indexed cards and the collection view.
2. **Generate derived thumbnails before scrolling needs them.** At import/index time, write a few
   pixel-size buckets to per-device Application Support, keyed by the source content hash and
   thumbnail recipe. These files remain disposable cache data, not library truth.
3. **Use the platform decoders.** Quick Look can asynchronously thumbnail local images, text, PDFs,
   and videos ([Quick Look Thumbnailing](https://developer.apple.com/documentation/quicklookthumbnailing),
   [`QLThumbnailGenerator`](https://developer.apple.com/documentation/quicklookthumbnailing/qlthumbnailgenerator)).
   Image I/O exposes orientation-aware, maximum-pixel-size thumbnail decoding
   ([Image I/O thumbnail options](https://developer.apple.com/documentation/imageio/kcgimagesourceshouldcache)),
   while AVFoundation requires video frame generation to run asynchronously because synchronous
   decoding can block the UI
   ([Creating images from a video asset](https://developer.apple.com/documentation/avfoundation/creating-images-from-a-video-asset)).
4. **Preheat ahead of the viewport.** Implement `NSCollectionViewPrefetching` for roughly one to two
   screens beyond the visible rectangle and cancel work that leaves the window
   ([`NSCollectionViewPrefetching`](https://developer.apple.com/documentation/appkit/nscollectionviewprefetching)).
5. **Use a costed memory cache over the disk thumbnails.** `NSCache` is thread-safe and evicts
   transient values under memory pressure; its cost can be the decoded byte size
   ([`NSCache`](https://developer.apple.com/documentation/foundation/nscache),
   [`totalCostLimit`](https://developer.apple.com/documentation/foundation/nscache/totalcostlimit)).
6. **Never show a spinner in a card or between batches.** Show the closest cached thumbnail
   immediately. During first-time cache construction, show a stable neutral card background or a
   smaller cached representation and replace only its pixels—not its frame—when the requested
   thumbnail arrives.
7. **Recycle one stable view hierarchy.** Apple explicitly recommends that an AppKit collection
   cell containing SwiftUI keep one `NSHostingView` and update its root view instead of adding and
   removing subviews during scrolling
   ([Use SwiftUI with AppKit](https://developer.apple.com/videos/play/wwdc2022/10075/?time=235)).
   If that still cannot meet the frame budget, make the board item itself a small AppKit view and
   keep the richer SwiftUI card for detail presentation.

For zoom, a uniform flow grid has the safest path: change one item-size parameter and let AppKit
animate the layout, keeping the item under the pointer anchored. AppKit supports animated layout
replacement and interactive collection-view transition layouts
([`collectionViewLayout`](https://developer.apple.com/documentation/appkit/nscollectionview/collectionviewlayout),
[`NSCollectionViewTransitionLayout`](https://developer.apple.com/documentation/appkit/nscollectionviewtransitionlayout)).
`NSScrollView` also provides native magnification and a centered magnification API, which is worth
testing as the live gesture layer before settling to a discrete grid size
([`NSScrollView`](https://developer.apple.com/documentation/appkit/nsscrollview)).

## Open-Source Audit

No mature package found is a drop-in improvement over AppKit for Cuttings' macOS 14 target.

| Package | Source finding | Decision |
| --- | --- | --- |
| [CHTCollectionViewWaterfallLayout](https://github.com/chiahsien/CHTCollectionViewWaterfallLayout) | Mature and collection-view based, but its manifest supports only iOS and tvOS and subclasses `UICollectionViewLayout`, not AppKit | Cannot use on macOS |
| [WaterfallGrid](https://github.com/paololeonardi/WaterfallGrid) | Supports macOS, but its source creates a `ForEach` for the complete collection inside a `ZStack`, measures every child through preferences, and then corrects alignment | Wrong architecture for thousands of cards |
| [LazyLayoutKit](https://github.com/Dave861/LazyLayoutKit) | The most relevant design: precomputed geometry, viewport indexing, masonry and justified modes, and only visible SwiftUI views. Its package requires macOS 15; version 0.3 has a small history, states its API may change before 1.0, and does not animate insertion/removal | Useful experimental benchmark if Cuttings raises its baseline; not the production dependency now |
| [SwiftUILazyContainer](https://github.com/ciaranrobrien/SwiftUILazyContainer) | Supports macOS 10.15 and precomputes masonry frames while creating views only for its computed visible range, but it has no justified layout, published performance benchmark, or test target; its source still notes a visibility edge case | Lower-confidence masonry prototype that retains macOS 14; not a production recommendation |

The manifests and implementation support those conclusions directly:

- [CHT's `Package.swift`](https://raw.githubusercontent.com/chiahsien/CHTCollectionViewWaterfallLayout/master/Package.swift)
  lists only iOS 13 and tvOS 13.
- [WaterfallGrid's implementation](https://github.com/paololeonardi/WaterfallGrid/blob/master/Sources/WaterfallGrid/WaterfallGrid.swift)
  contains the eager `ZStack`/`ForEach` and preference-based measure-and-correct pass.
- [LazyLayoutKit's manifest](https://github.com/Dave861/LazyLayoutKit/blob/main/Package.swift)
  requires macOS 15, and its [documented limits](https://github.com/Dave861/LazyLayoutKit#what-is-not-in-030)
  include no animated insertions/removals and an API still below 1.0.
- [SwiftUILazyContainer's masonry implementation](https://github.com/ciaranrobrien/SwiftUILazyContainer/tree/main/Sources/SwiftUILazyContainer/Internal/Masonry)
  separates precomputed frames from the visible-item `ForEach`, but does not supply the evidence or
  feature breadth needed to replace AppKit as the shared collection foundation.

## Prototype and Selection Criteria

Build the three selectable modes over one **10,000-item** fixture library with thumbnails already
generated. Test a Release build on the same Mac and scroll trace. A mode is viable only if it meets
all of these:

- no loading indicator, batch boundary, or empty pause while scrolling;
- the number of live item views remains proportional to the viewport, not the library;
- kind filters replace the visible snapshot immediately and never show the wrong kind;
- repeated zoom in/out keeps the item under the pointer stable and does not re-decode thumbnails on
  every intermediate size;
- no geometry changes after a card becomes visible;
- decoded-image memory reaches a stable ceiling rather than growing with scroll distance.

The recommended order is **Photos grid first**, **justified rows second**, and **existing masonry as
the comparison**. The winning visual mode should not change the underlying collection-view,
snapshot, thumbnail, or prefetch architecture.
