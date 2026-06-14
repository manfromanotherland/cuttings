// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List(SidebarItem.allCases, selection: $appState.activeView) { item in
            Label(item.label, systemImage: item.icon)
                .tag(item)
        }
        .listStyle(.sidebar)
        .navigationTitle("Read Later")
        .onChange(of: appState.activeView) { _, _ in
            appState.selectedId = nil
            Task { await appState.loadReadings() }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await appState.loadReadings() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh list")
            }
        }
    }
}
