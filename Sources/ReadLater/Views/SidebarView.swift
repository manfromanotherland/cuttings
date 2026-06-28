// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showAppearancePopover = false

    /// Shared with the reading list so → can hand focus across to it.
    @FocusState.Binding var focusedColumn: FocusColumn?

    // Per-section collapse state, persisted across launches so the sidebar
    // reopens the way the user left it. Default to expanded.
    @AppStorage("sidebarLibraryExpanded") private var libraryExpanded = true
    @AppStorage("sidebarRatingsExpanded") private var ratingsExpanded = true
    @AppStorage("sidebarTagsExpanded") private var tagsExpanded = true

    var body: some View {
        List(selection: $appState.sidebarSelection) {
            Section(isExpanded: $libraryExpanded) {
                ForEach(SidebarItem.allCases) { item in
                    viewRow(item)
                        .tag(SidebarSelection.view(item))
                }
            } header: {
                Text("Library")
                    .padding(.top, 12)
            }

            if !appState.allRatings.isEmpty {
                Section("Ratings", isExpanded: $ratingsExpanded) {
                    ForEach(appState.allRatings, id: \.rating) { rc in
                        ratingRow(rc)
                            .tag(SidebarSelection.rating(rc.rating))
                    }
                }
            }

            if !appState.allTags.isEmpty {
                Section("Tags", isExpanded: $tagsExpanded) {
                    // Apple Notes-style: tags as small pills that wrap, rather than
                    // a vertical list of identical rows. The flow is a single,
                    // non-selectable List row; each tile manages its own selection.
                    FlowLayout(spacing: 6) {
                        ForEach(appState.allTags, id: \.tag) { tc in
                            tagTile(tc)
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
        .listStyle(.sidebar)
        .focused($focusedColumn, equals: .sidebar)
        // → crosses into the reading list; ↑/↓ keep navigating the sidebar's own
        // rows. The list's ← arrow brings focus back here.
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
        .navigationTitle("Read Later")
        .onChange(of: appState.sidebarSelection) { _, _ in
            // Don't clear the selection here: loadReadings() re-selects the
            // first item (or keeps a still-valid one), so clearing first only
            // makes the selection-dependent toolbar (sort + actions) blink off
            // and back on while the new list loads.
            Task { await appState.loadReadings() }
        }
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
        .popover(isPresented: $showAppearancePopover, arrowEdge: .trailing) {
            AppearancePopoverView()
        }
    }

    // ── Smart view row ────────────────────────────────────────────────────────

    private func viewRow(_ item: SidebarItem) -> some View {
        HStack {
            Label(item.label, systemImage: item.icon)
                .labelStyle(.tightIcon)
            Spacer()
            if let count = appState.viewCounts[item], count > 0 {
                Text("\(count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.15), in: Capsule())
            }
        }
    }

    // ── Tag tile ──────────────────────────────────────────────────────────────

    /// A small pill showing `#tag` with its reading count in a trailing badge —
    /// the badge matching the smart-view rows. No icon; the name uses the same
    /// (default) font as those rows, and the selected tag fills with the accent.
    private func tagTile(_ tc: FfiTagCount) -> some View {
        let isSelected = appState.selectedTag == tc.tag
        return Button {
            appState.sidebarSelection = .tag(tc.tag)
        } label: {
            HStack(spacing: 5) {
                Text("#\(tc.tag)")
                    // 2pt smaller than the sidebar's default (~13pt) row font.
                    .font(.system(size: 11))
                    .lineLimit(1)
                Text("\(tc.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(isSelected ? Color.white : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        isSelected
                            ? AnyShapeStyle(.white.opacity(0.25))
                            : AnyShapeStyle(.secondary.opacity(0.18)),
                        in: Capsule()
                    )
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
    }

    // ── Rating row ──────────────────────────────────────────────────────────────

    private func ratingRow(_ rc: FfiRatingCount) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<5) { i in
                Image(systemName: i < Int(rc.rating) ? "star.fill" : "star")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(rc.count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.secondary.opacity(0.15), in: Capsule())
        }
        .contentShape(Rectangle())
    }
}

// ── Appearance popover ────────────────────────────────────────────────────────

private struct AppearancePopoverView: View {
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @AppStorage("readerFont") private var readerFont: ReaderFont = .system
    @AppStorage("readerFontSize") private var readerFontSize: ReaderFontSize = .medium

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Appearance")
                .font(.headline)

            // Theme mode picker
            HStack(spacing: 4) {
                ForEach(AppearanceMode.allCases) { mode in
                    Button {
                        appearanceMode = mode
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 14))
                            Text(mode.label)
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            appearanceMode == mode ?
                                AnyShapeStyle(.secondary.opacity(0.25)) :
                                AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

            // Font picker
            HStack {
                Text("Font")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Font", selection: $readerFont) {
                    ForEach(ReaderFont.allCases) { font in
                        Text(font.label).tag(font)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.regular)
            }

            // Font size slider
            HStack(spacing: 8) {
                Text("Aa")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Slider(value: fontSizeBinding, in: 0...Double(ReaderFontSize.allCases.count - 1), step: 1)
                Text("Aa")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 240)
    }

    private var fontSizeBinding: Binding<Double> {
        Binding {
            Double(ReaderFontSize.allCases.firstIndex(of: readerFontSize) ?? 1)
        } set: { val in
            let idx = min(max(Int(val.rounded()), 0), ReaderFontSize.allCases.count - 1)
            readerFontSize = ReaderFontSize.allCases[idx]
        }
    }
}
