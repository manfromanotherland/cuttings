/// Selects a cell's newest payload only when it still occupies the geometry's
/// identity. During cooperative preparation, the parent collection can already
/// be shorter or reordered while the previous snapshot remains scrollable.
enum LayoutWindowContent {
    static func element<Element, ID: Equatable>(
        at position: Int,
        matching id: ID,
        currentElements: [Element],
        currentIDs: [ID],
        fallback: @autoclosure () -> Element
    ) -> Element {
        guard currentElements.indices.contains(position),
              currentIDs.indices.contains(position),
              currentIDs[position] == id
        else { return fallback() }
        return currentElements[position]
    }
}
