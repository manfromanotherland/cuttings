# Óia performance plan

September 24, 2026. Source audit at `8034ce3`.

The primary acceptance criterion is smooth 120 Hz board scrolling. The immediate
reproduction is specific: starting a scroll turns every visible image blurry and
frame drops begin. This plan prioritizes that transition, then sustained scrolling,
then other interactions. No app implementation or runtime profiling was performed
for this audit; the costs below are confirmed code paths, not measured frame costs.

## What the previous work established

The referenced **Improve image scroll performance** task landed `77ac55d`. Its
160px initial previews, 120ms idle refinement, 1024px board cap, visibility gating,
separate decode lanes, request coalescing, and exact-size cache are still present.
That task reported 184 passing tests and a Debug build, but explicitly did not
verify 120 Hz frame pacing. Preserve the useful bounds and cancellation behavior.

The current policy has a concrete problem: `LocalReadingImage.swift:59` selects
the lightweight bitmap whenever scrolling starts, including for cards that already
have a display-quality bitmap. Line 30 also changes interpolation. Refinement task
identity changes at line 108. All these depend on the same observable scroll flag.
`AssetPreviewPresentation` retains both variants, so selecting the smaller bitmap
does not release the retained display bitmap. The old test at
`AssetPreviewLoadPlanTests.swift:125` explicitly expects lightweight selection.

This explains the observed blur. A trace must establish how much of the frame loss
comes from those image swaps, view updates, task changes, or rendering work.

## 1. Establish a repeatable frame-time gate

Add a dedicated performance launch mode using an isolated library, index and
preferences, building on `TestHooks`. Avoid the existing UI-test accessibility
probes and synchronous startup-event file writes in timed sections. Exercise real
card views, real media decoding and the real scroll path.

- Record the Mac, OS, app revision, Swift/Rust build configurations, display,
  actual refresh rate, backing scale, window size, card size and library size.
  The target display must be capable of and operating at 120 Hz during motion.
- Profile the optimized app with symbols, and reproduce the symptom in the normal
  Debug app separately. Keep builds and all other conditions identical for A/B runs.
- Start with a warm, fully refined image viewport: idle, begin scrolling, stop,
  reverse, repeat. Separately test an empty preview cache, newly entering images,
  long screenshots/SVGs, video-heavy sections and mixed text cards.
- Use a deterministic 10,000-card mixed fixture plus the user's actual library.
  Cover the densest and sparsest card sizes and scrolling while reconciliation or
  visual analysis is active. Record scroll velocity/distance and phase boundaries.
- Capture SwiftUI updates and their causes, Time Profiler, and presentation/hitch
  evidence. Add signposts/counters for scroll phase, image publication, decode,
  cache hits, cell creation, window publication, layout solves, and core queue wait.
  LazyLayoutKit already supplies `solve` and `visibility` signposts and an
  instrumentation SPI. Use it instead of adding per-frame text logs.

Proposed command to implement: `macos/scripts/check-scroll-performance.sh`.
It must save the trace, run metadata and a machine-readable comparison. If frame
presentation data or a 120 Hz target is unavailable, report **unverified**; do not
substitute a display-link callback counter or synthetic geometry test for a pass.

Acceptance: during active motion, meet every 8.33ms presentation deadline with
zero app-attributable missed refreshes across three 60-second runs of each primary
scenario. Report all misses, including separately attributed system misses, plus
p50/p95/p99/worst frame intervals and hitch duration. A high average FPS cannot
hide a bad scroll-start frame. Aim for p99 main-thread update/commit work below
4ms to leave headroom; presentation deadlines remain the actual gate. Record CPU,
GPU/render cost and retained memory, and check memory plateaus across repeated
down/up sweeps. The user's own visual acceptance remains a separate requirement.

## 2. Remove the scroll-start image downgrade

This is the first implementation checkpoint and A/B experiment.

- Keep the best already-presented board image stable for the same asset and size.
  Scroll phase must not change its bitmap, interpolation or geometry.
- Use a 160px preview or existing color placeholder for newly entering uncached
  cards. Defer their display-quality work until scrolling settles.
- Stop reading the scroll flag in the render path. When a display variant already
  satisfies the request, exit refinement planning before reading that flag too.
  Scrolling then changes pending work rather than every resolved image.
- On warm re-entry, use a suitable cached board display variant immediately.
  Do not force another lightweight-to-display cycle. Preserve board/detail size
  separation: a large detail decode must not become a board preview.
- Prevent identical display variants from being republished after every idle
  transition. Preserve cancellation of stale queued requests and asset identity
  checks. Already-running synchronous decodes may finish into cache; they must
  not publish an obsolete result into a recycled card.

Replace the downgrade assertion with regressions for stable image identity across
scroll start/stop, low-cost loading of new cards, a single idle upgrade, warm re-entry,
asset replacement, offscreen release and rapid reversals. Use the real load-plan
and presentation boundary; these tests complement the frame trace.

Pass gate: zero image replacements or new decode requests caused solely by starting
to scroll a fully refined viewport. Compare the same scroll-start trace before and
after. If hitches remain, keep their measured attribution and continue below.

## 3. Make scrolling update only the cards that change

LazyLayoutKit 0.3.0 currently writes viewport state and creates/assigns a new
`placed` array on every geometry callback, even if membership is unchanged:
`SwiftUI/LazyLayoutView.swift:423` and `:659`. This is confirmed allocation/state
work; Instruments must show its downstream view cost.

- Keep continuously changing raw scroll geometry outside broad observable view
  state. Publish the materialized window only when its membership, content
  revision or geometry revision changes.
- Retain a bounded overscan region and recompute membership when its boundary is
  crossed. Preserve anchoring, accessibility, selection and programmatic scrolling.
- Use the board's existing frames to drive one visibility/prefetch coordinator.
  Today each media card also installs `CardViewportVisibilityModifier`
  (`AssetPreviewPipeline.swift:31`). Send per-card visibility transitions only;
  retain stricter actual-viewport gating for playback.
- Measure window-query time, cell creation rate and retained cells separately.
  `.items(80)` targets roughly 80 total materialized cells, not 80 extra cells.
  Blindly reducing that number can increase construction churn.

Pass gate: zero placed-array publications while scrolling within an unchanged
materialization window; work scales with entering/leaving cards, not total library
size. Compare update counts and presentation deadlines on the same corpus.
Any dependency change must be a reproducible pinned patch/fork or local package,
never an edit left inside `build/SourcePackages/checkouts`.

## 4. Make cold media cheap without causing idle bursts

The board currently uses an in-memory cache (`AssetPreviewPipeline.swift:172`)
configured for 256 entries and a 128MiB cost target. That is not a total-process
memory limit. A miss still opens the original: raster downsampling, SVG parsing and
rasterization, or AVFoundation frame extraction for posterless video.

- Add disposable per-device derived thumbnails and video posters, outside the
  synced library. Key by validated source identity/fingerprint, a small set of
  pixel tiers and renderer version. Handle missing, corrupt and changed sources.
- Generate them in bounded background jobs; the board must not wait for a complete
  library backfill. While a preview is missing, keep the existing placeholder and
  queue only work relevant to the viewport or a small directional prefetch region.
- Separate board and detail cache budgets. Bound disk space, retained decoded
  bytes and pending jobs. Prefer measured size tiers over nearly identical entries
  for every pixel width during resizing.
- Centralize priority: visible initial previews, near-viewport previews, idle
  refinement, then unrelated maintenance. Cancel obsolete prefetch after reversals.
  Pace image publication as well as decoding; serial decode lanes alone do not
  prevent many cached images from being published in the same frame.

Spotlight's thumbnail cache is a useful existing implementation reference; board
rendering must remain independent of Spotlight availability or indexing progress.
Core retains ownership of source identity and invalidation rules; platform image
rendering remains a disposable presentation concern.

Pass gate: no original-media reads on the warm scroll path, bounded cold work,
no burst of replacements at idle, and stable memory under repeated reversals.
Prioritize this phase when traces implicate cold decoding or cache churn.

## 5. Remove layout, video and background interference where measured

These are additional concrete costs, ordered by their relevance to the trace.

| Area | Current implementation | Planned correction and gate |
| --- | --- | --- |
| Video phase transitions | `AutoplayVideoCard.swift:39` removes the player view at scroll start; visible players start/resume immediately at idle. | Pause with stable view/layer identity; budget and stagger playback startup after settling. Measure image-only and video-heavy traces separately; preserve playback position and release offscreen players. |
| Duplicate geometry | `LazyMasonryBoard.swift:219` computes all frames for navigation from the view body, then LazyLayoutKit solves them again. | Share one immutable geometry snapshot between rendering, visibility and navigation. One solve per geometry revision; none for scroll offsets, selection, or content edits that do not change geometry/membership. |
| Text/resize work | `OiaCardTextMetrics.swift:17` clears all heights on width changes; measurement is main-actor isolated at line 34. | Prepare immutable metrics with safe font/thread ownership, cancel stale resize requests, and publish one current snapshot. Keep measured and rendered typography identical; do not move existing AppKit work blindly to a detached task. |
| Card compositing | `OiaCardView.swift:72` layers material, clipping and overlays; hover menus remain constructed at zero opacity. | Use diagnostic material/overlay toggles with identical geometry to isolate GPU/render cost. Optimize the responsible layer only if measured; preserve the intended appearance for the user's review. |
| Board refresh | `Readings.swift:151` publishes the entire result; `ReadingQuery.swift:39` requests all rows. | Separate stable ordered IDs, per-row content revisions and geometry revisions. Apply changed-row updates without repeated all-library work. Mapping is already off-main; naive pagination is not the first fix. |
| Filesystem/indexing | `FolderWatcher.swift:60` discards changed paths; routine `CoreBridge.sync()` shares an actor with interactive reads. Full scanning reads Markdown and hashes preview assets. | Reconcile changed readings with full-scan recovery for startup/overflow. Keep filesystem authority, external-writer safety and short database critical sections. Measure queue wait, scanned bytes and lock duration. |
| Optional analysis | Visual analysis requests all pending staging work before batching; some filesystem staging occurs under the database lock. | Bound issuance and move staging/revalidation outside long-held locks; delay optional work during interaction without starving reconciliation. Compare otherwise identical scrolls with maintenance active/idle. |

After board acceptance, reuse the instrumentation for search, filters, card-size
changes, opening/closing Gallery and reader images. Search currently waits for
semantic lookup before querying the core; detail image loaders also have separate
decode scheduling. Address measured delays without expanding the first scroll fix.

## Delivery and fallback

Deliver measurement support, stable image presentation, and scroll-window changes
as separate coherent checkpoints. Run the relevant correctness tests, compare the
same frame trace after each checkpoint, and build the normal runnable Debug app.
Commit narrowly in the repository's existing style; do not push as part of this plan.
Continue into the conditional phases until the acceptance matrix passes.

If the simplified board still misses deadlines and traces locate the remaining
cost in SwiftUI cell lifecycle or layout overhead, benchmark a bounded
`NSCollectionView` prototype against the same data, geometry, media cache and
interactions. Adopt it only if it wins that comparison while preserving behavior.
There is no current evidence requiring a wholesale app rewrite.

Apple's [SwiftUI Instruments guidance](https://developer.apple.com/videos/play/wwdc2025/306/)
supports measuring expensive updates and their causes in an optimized build.
Its [render-loop explanation](https://developer.apple.com/videos/play/tech-talks/10855/)
is the basis for separating application work from missed presentation deadlines.
