// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showAppearancePopover = false

    var body: some View {
        List(selection: $appState.sidebarSelection) {
            Section("Library") {
                ForEach(SidebarItem.allCases) { item in
                    viewRow(item)
                        .tag(SidebarSelection.view(item))
                }
            }

            if !appState.allTags.isEmpty {
                Section("Tags") {
                    ForEach(appState.allTags, id: \.tag) { tc in
                        tagRow(tc)
                            .tag(SidebarSelection.tag(tc.tag))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                settingsButton
            }
            .background(.background)
        }
        .navigationTitle("Read Later")
        .onChange(of: appState.sidebarSelection) { _, _ in
            appState.selectedId = nil
            Task { await appState.loadReadings() }
        }
    }

    // ── Settings button ───────────────────────────────────────────────────────

    private var settingsButton: some View {
        Button {
            showAppearancePopover.toggle()
        } label: {
            Label("Settings", systemImage: "gear")
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

    // ── Tag row ───────────────────────────────────────────────────────────────

    private func tagRow(_ tc: FfiTagCount) -> some View {
        HStack {
            Label(tc.tag, systemImage: "tag")
                .lineLimit(1)
            Spacer()
            Text("\(tc.count)")
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
