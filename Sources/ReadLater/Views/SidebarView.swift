// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List(selection: $appState.activeView) {
            Section("Library") {
                ForEach(SidebarItem.allCases) { item in
                    viewRow(item)
                        .tag(item)
                }
            }

            if !appState.allTags.isEmpty {
                Section("Tags") {
                    ForEach(appState.allTags, id: \.tag) { tc in
                        tagRow(tc)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Read Later")
        .onChange(of: appState.activeView) { _, _ in
            appState.selectedId = nil
            Task {
                appState.selectedTag = nil
                await appState.loadReadings()
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await appState.sync() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Sync library")
            }
        }
    }

    // ── Smart view row ────────────────────────────────────────────────────

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

    // ── Tag row ───────────────────────────────────────────────────────────

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
        .onTapGesture {
            Task { await appState.selectTag(tc.tag) }
        }
        .foregroundStyle(
            appState.selectedTag == tc.tag ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
        )
    }
}
