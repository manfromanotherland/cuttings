// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.libraryURL != nil {
                mainContent
            } else if appState.isRestoringLibrary {
                // A saved library is still being opened; stay neutral rather than
                // flashing onboarding for the few frames before boot settles.
                RestoringView()
            } else {
                OnboardingView()
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
                .transition(.move(edge: .bottom))
            }
        }
    }
}

// ── Restoring placeholder ─────────────────────────────────────────────────────
// Shown while a previously chosen library is being reopened on launch, so the
// onboarding button never flashes for users who've already picked a folder.

private struct RestoringView: View {
    var body: some View {
        ProgressView()
            .controlSize(.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// ── Onboarding placeholder (fleshed out in MAC-2) ─────────────────────────────

private struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("Welcome to Read Later")
                .font(.title)
            Text("Choose an existing library folder or create a new one.")
                .foregroundStyle(.secondary)
            Button("Choose Library…") {
                appState.chooseLibrary()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
