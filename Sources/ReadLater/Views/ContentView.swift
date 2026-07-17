// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    /// Which of the two navigable columns currently holds keyboard focus. Shared
    /// with both column views so the ←/→ arrows can hand focus back and forth.
    @FocusState private var focusedColumn: FocusColumn?

    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    /// The reading-list column width the user last dragged to, persisted. Focus
    /// mode collapses the column to hide it, which drops SwiftUI's remembered
    /// width — so we store the measured width here and force the column back to it
    /// on exit (see `restoringListWidth`). Persisting also carries the width across
    /// relaunches.
    @AppStorage("readingListColumnWidth", store: AppDefaults.store)
    private var listColumnWidth: Double = 320

    /// True briefly while exiting focus mode: pins the list column to
    /// `listColumnWidth` (min == max) so it reopens at exactly that width, since
    /// the collapse wipes SwiftUI's remembered width and `ideal` alone isn't
    /// honored on reopen. Relaxed a beat later so the divider is draggable again.
    @State private var restoringListWidth = false

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
            if isFocus {
                appState.searchQuery = ""
            } else {
                // Exiting: pin the list column to its saved width so it reopens
                // exactly there (see `restoringListWidth`).
                restoringListWidth = true
            }
            withAnimation(.easeInOut(duration: 0.25)) {
                // `.doubleColumn` hides the sidebar; the reading-list column is
                // hidden by collapsing its width (below). `.detailOnly` is ignored
                // for this column on macOS, so visibility can't hide the list.
                columnVisibility = isFocus ? .doubleColumn : .all
            }
        }
        .onChange(of: restoringListWidth) { _, restoring in
            guard restoring else { return }
            // Release the pin once the reopen has settled, restoring a draggable
            // column. The delay clears the 0.25s reopen animation.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                restoringListWidth = false
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
                // Persist the width the user drags to, so it survives relaunches and
                // can be forced back on reopen from focus mode. Guarded to ignore the
                // transient zero width while the column is collapsed.
                .background {
                    GeometryReader { geo in
                        Color.clear
                            .onChange(of: geo.size.width) { _, width in
                                if !appState.isFocusMode, width > 1 {
                                    listColumnWidth = width
                                }
                            }
                    }
                }
                // Focus mode collapses the column to zero to hide it (the only
                // mechanism that works on macOS). While `restoringListWidth` is set
                // (just after exiting focus), min == max pins it to the saved width,
                // forcing the exact reopen width; then it relaxes to a normal
                // draggable range with `ideal` as a fallback.
                .navigationSplitViewColumnWidth(
                    min: appState.isFocusMode ? 0 : (restoringListWidth ? CGFloat(listColumnWidth) : 260),
                    ideal: appState.isFocusMode ? 0 : CGFloat(listColumnWidth),
                    max: appState.isFocusMode ? 0 : (restoringListWidth ? CGFloat(listColumnWidth) : .infinity)
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
