// Modified for Óia; distributed under the upstream Apache-2.0 license.

/// Safe item preparation for main-actor-owned text/font measurers. Layout and
/// indexing can then consume the immutable output on a background task.
enum CooperativeLayoutPreparation {
    @MainActor
    static func items<Element, Item>(
        _ elements: [Element],
        make: (Element) -> Item,
        onBatch: ((Duration, Int) -> Void)? = nil
    ) async throws -> (items: [Item], duration: Duration) {
        var values: [Item] = []
        values.reserveCapacity(elements.count)
        var total = Duration.zero
        var batchStart = ContinuousClock.now
        var batchCount = 0
        for element in elements {
            try Task.checkCancellation()
            values.append(make(element))
            batchCount += 1
            let duration = batchStart.duration(to: .now)
            if batchCount >= 32 || duration >= .milliseconds(2) {
                total += duration
                onBatch?(duration, batchCount)
                await Task.yield()
                batchStart = .now
                batchCount = 0
            }
        }
        try Task.checkCancellation()
        if batchCount > 0 {
            let duration = batchStart.duration(to: .now)
            total += duration
            onBatch?(duration, batchCount)
        }
        return (values, total)
    }
}
