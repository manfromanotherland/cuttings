// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.libraryPath == nil {
                OnboardingView()
            } else {
                mainContent
            }
        }
    }

    private var mainContent: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 160, ideal: 200)
        } content: {
            ReadingListView()
                .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        } detail: {
            ArticleDetailView()
        }
        .searchable(text: $appState.searchQuery, placement: .toolbar, prompt: "Search")
        .onChange(of: appState.searchQuery) { _, _ in
            Task { await appState.loadReadings() }
        }
        .overlay {
            if let err = appState.error {
                VStack {
                    Spacer()
                    Text(err)
                        .foregroundStyle(.white)
                        .padding()
                        .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                        .padding()
                }
            }
        }
    }
}

// ── Onboarding placeholder (fleshed out in MAC-2) ─────────────────────────────

private struct OnboardingView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("Welcome to Read Later")
                .font(.title)
            Text("Choose a library folder to get started.")
                .foregroundStyle(.secondary)
            Button("Choose Library…") {
                // MAC-2 will wire this up.
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
