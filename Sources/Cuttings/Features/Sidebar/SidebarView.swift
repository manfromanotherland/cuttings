// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct SidebarView: View {
    // Shared insets for the smart-view and rating rows (both custom toggle
    // buttons) so they line up and stand at the same, comfortably tall height.
    // Horizontal padding sets the flush-left label offset; vertical sets the row
    // height (taller than a default compact list row).
    private static let rowHPadding: CGFloat = 10
    private static let rowVPadding: CGFloat = 7

    /// Count-badge vertical padding, also applied to the content beside it (tag
    /// name, rating stars) so a row keeps one height with or without a badge.
    private static let badgeVPadding: CGFloat = 2

    @Environment(AppState.self) private var appState
    @State private var showAppearancePopover = false

    /// Shared with the reading list so → can hand focus across to it.
    @FocusState.Binding var focusedColumn: FocusColumn?

    // Per-section collapse state, persisted across launches so the sidebar
    // reopens the way the user left it. Default to expanded.
    @AppStorage("sidebarLibraryExpanded", store: AppDefaults.store) private var libraryExpanded = true
    @AppStorage("sidebarRatingsExpanded", store: AppDefaults.store) private var ratingsExpanded = true
    @AppStorage("sidebarTagsExpanded", store: AppDefaults.store) private var tagsExpanded = true

    var body: some View {
        List {
            Section("Library", isExpanded: $libraryExpanded) {
                ForEach(SidebarItem.allCases) { item in
                    viewRow(item)
                }
            }

            if !appState.sidebar.ratings.isEmpty {
                Section("Ratings", isExpanded: $ratingsExpanded) {
                    ForEach(appState.sidebar.ratings, id: \.rating) { ratingCount in
                        ratingRow(ratingCount)
                    }
                }
            }

            if !appState.sidebar.tags.isEmpty {
                Section("Tags", isExpanded: $tagsExpanded) {
                    // Apple Notes-style: tags as small pills that wrap, rather than
                    // a vertical list of identical rows. The flow is a single,
                    // non-selectable List row; each tile manages its own selection.
                    FlowLayout(spacing: 6) {
                        ForEach(appState.sidebar.tags, id: \.tag) { tagCount in
                            tagTile(tagCount)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // No padding around the section — only FlowLayout's spacing
                    // between tiles.
                    .listRowInsets(EdgeInsets())
                    .selectionDisabled()
                }
            }
        }
        .padding(.top, 1) // Remove the white background color at the traffic lights
        .listStyle(.sidebar)
        .focused($focusedColumn, equals: .sidebar)
        // → crosses into the reading list; the list's ← arrow brings focus back
        // here. (The rows are toggle buttons, not a native List selection, so the
        // filters can compose and deselect — see `viewRow`/`ratingRow`/`tagTile`.)
        .onKeyPress(.rightArrow) {
            focusedColumn = .list
            return .handled
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                settingsButton
            }
            .background(.background)
        }
        .navigationTitle("Cuttings")
    }

    // ── Settings button ───────────────────────────────────────────────────────

    private var settingsButton: some View {
        Button {
            showAppearancePopover.toggle()
        } label: {
            Label("Settings", systemImage: "gear")
                .labelStyle(.tightIcon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(A11y.Sidebar.settingsButton)
        .popover(isPresented: $showAppearancePopover, arrowEdge: .trailing) {
            AppearancePopoverView()
        }
    }

    // ── Smart view row ────────────────────────────────────────────────────────

    /// A smart-view row. It's a toggle like the tag/rating filters (custom button,
    /// not a native `List` selection) so clicking the active view can fall back to
    /// `All` — `List` single-selection never fires on a re-click of the selected
    /// row, so it can't express deselect. The selected row fills with the accent,
    /// matching the ratings and tags.
    private func viewRow(_ item: SidebarItem) -> some View {
        let count = appState.sidebar.viewCounts[item] ?? 0
        let isSelected = appState.activeView == item
        return Button {
            appState.selectView(item)
        } label: {
            HStack {
                Label(item.label, systemImage: item.icon)
                    .labelStyle(.tightIcon)
                Spacer()
                if count > 0 {
                    countBadge(count, isSelected: isSelected)
                        .accessibilityIdentifier(A11y.Sidebar.viewCount(item.id))
                }
            }
            // No height-matching padding needed: the icon+label out-heights the badge.
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .modifier(RowChrome(isSelected: isSelected))
        }
        .buttonStyle(.plain)
        // Zero row insets (like the Tags section) so the row is flush-left with no
        // extra margin; the padding above sets the label offset and row height.
        .listRowInsets(EdgeInsets())
        // Expose the count as the row's accessibility value so the UI-test suite
        // reads a definite number (the button flattens its children, so the inner
        // badge isn't separately queryable). Always set, even at 0.
        .accessibilityValue("\(count)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier(A11y.Sidebar.viewRow(item.id))
    }

    // ── Tag tile ──────────────────────────────────────────────────────────────

    /// A small pill showing `#tag` with its reading count in a trailing badge —
    /// the badge matching the smart-view rows. No icon; the name uses the same
    /// (default) font as those rows, and the selected tag fills with the accent.
    private func tagTile(_ tagCount: TagCount) -> some View {
        let isSelected = appState.selectedTag == tagCount.tag
        return Button {
            appState.toggleTag(tagCount.tag)
        } label: {
            HStack(spacing: 5) {
                Text("#\(tagCount.tag)")
                    // 2pt smaller than the sidebar's default (~13pt) row font.
                    .font(.system(size: 11))
                    .lineLimit(1)
                    // Height-match the badge so tiles stay one height (the name,
                    // slightly larger than the badge, sets it). See badgeVPadding.
                    .padding(.vertical, Self.badgeVPadding)
                // A tag with no results under the current search/facet stays pinned
                // (so you can still see and switch to it) but drops its badge, like
                // the smart-view rows hide a 0.
                if tagCount.count > 0 {
                    countBadge(tagCount.count, isSelected: isSelected)
                        .accessibilityIdentifier(A11y.Sidebar.tagCount(tagCount.tag))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                isSelected
                    ? AnyShapeStyle(Color.accentColor)
                    : AnyShapeStyle(.secondary.opacity(0.12)),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        // Count exposed as the tile's accessibility value (same reason as the
        // smart-view rows).
        .accessibilityValue("\(tagCount.count)")
        .accessibilityIdentifier(A11y.Sidebar.tagTile(tagCount.tag))
    }

    /// The trailing count badge shared by every sidebar section, tinted to read
    /// against both the resting and the accent-filled (selected) background.
    private func countBadge(_ count: some BinaryInteger, isSelected: Bool) -> some View {
        Text(String(count))
            .font(.caption2.monospacedDigit())
            .foregroundStyle(isSelected ? Color.white : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, Self.badgeVPadding)
            .background(
                isSelected
                    ? AnyShapeStyle(.white.opacity(0.25))
                    : AnyShapeStyle(.secondary.opacity(0.15)),
                in: Capsule()
            )
    }

    /// Shared chrome for the full-width selectable rows (smart views + ratings;
    /// tags are pills, apart): consistent height/inset, accent fill, hit target.
    private struct RowChrome: ViewModifier {
        let isSelected: Bool
        func body(content: Content) -> some View {
            content
                .padding(.horizontal, SidebarView.rowHPadding)
                .padding(.vertical, SidebarView.rowVPadding)
                .frame(maxWidth: .infinity)
                .background(
                    isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .contentShape(Rectangle())
        }
    }

    // ── Rating row ──────────────────────────────────────────────────────────────

    /// A rating filter row. Like the tags, it's an independent toggle: click to
    /// filter by that star value, click again to clear it. The selected row fills
    /// with the accent, matching the tag tiles.
    private func ratingRow(_ ratingCount: RatingCount) -> some View {
        let isSelected = appState.selectedRating == ratingCount.rating
        return Button {
            appState.toggleRating(ratingCount.rating)
        } label: {
            HStack(spacing: 2) {
                // Height-match the badge so rows stay one height — the always-present
                // stars (same `.caption2` size) set it, not the badge. See badgeVPadding.
                HStack(spacing: 2) {
                    ForEach(0 ..< 5) { star in
                        Image(systemName: star < Int(ratingCount.rating) ? "star.fill" : "star")
                            .font(.caption2)
                            .foregroundStyle(isSelected ? Color.white : .secondary)
                    }
                }
                .padding(.vertical, Self.badgeVPadding)
                Spacer()
                // Pinned like the tag tiles: a bucket with no results under the
                // current search/facet keeps its row but hides the count badge.
                if ratingCount.count > 0 {
                    countBadge(ratingCount.count, isSelected: isSelected)
                }
            }
            .modifier(RowChrome(isSelected: isSelected))
        }
        .buttonStyle(.plain)
        // Match the smart-view rows: flush-left, no extra margin, same height.
        .listRowInsets(EdgeInsets())
        .selectionDisabled()
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(A11y.Sidebar.ratingRow(ratingCount.rating))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityLabel(
            "\(ratingCount.rating) star\(ratingCount.rating == 1 ? "" : "s"), "
                + "\(ratingCount.count) reading\(ratingCount.count == 1 ? "" : "s")"
        )
    }
}
