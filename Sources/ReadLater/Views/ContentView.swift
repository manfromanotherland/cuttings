// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    /// Which of the two navigable columns currently holds keyboard focus. Shared
    /// with both column views so the ←/→ arrows can hand focus back and forth.
    @FocusState private var focusedColumn: FocusColumn?

    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var appState = appState
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
        // Attached at the root so ⌘/ works from any screen.
        .sheet(isPresented: $appState.showShortcuts) {
            ShortcutsView()
        }
        .onChange(of: appState.isFocusMode) { _, isFocus in
            if isFocus { appState.searchQuery = "" }
            withAnimation(.easeInOut(duration: 0.25)) {
                columnVisibility = isFocus ? .doubleColumn : .all
            }
        }
        .onChange(of: columnVisibility) { _, newValue in
            if appState.isFocusMode && newValue != .doubleColumn {
                appState.isFocusMode = false
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        @Bindable var appState = appState
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(focusedColumn: $focusedColumn)
                .navigationSplitViewColumnWidth(min: 160, ideal: 200)
        } content: {
            ReadingListView(focusedColumn: $focusedColumn)
                .navigationSplitViewColumnWidth(
                    min: appState.isFocusMode ? 0 : 260,
                    ideal: appState.isFocusMode ? 0 : 320,
                    max: appState.isFocusMode ? 0 : .infinity
                )
        } detail: {
            ArticleDetailView()
        }
        .searchable(text: $appState.searchQuery, placement: .toolbar, prompt: "Search")
        .onChange(of: appState.searchQuery) { _, _ in
            appState.searchDidChange()
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

// ── Column focus ──────────────────────────────────────────────────────────────
// Identifies the two columns that participate in ←/→ arrow navigation. The
// detail (reader) column isn't part of this cycle — it's reached by selecting a
// reading, not by arrowing across.

enum FocusColumn: Hashable {
    case sidebar
    case list
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

// ── Onboarding placeholder ────────────────────────────────────────────────────

private struct OnboardingView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("Welcome to Read Later")
                .font(.title)
                .accessibilityIdentifier(A11y.Onboarding.title)
            Text("Choose an existing library folder or create a new one.")
                .foregroundStyle(.secondary)
            Button("Choose Library…") {
                appState.chooseLibrary()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier(A11y.Onboarding.chooseLibrary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
