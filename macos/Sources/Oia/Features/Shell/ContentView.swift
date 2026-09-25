// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        Group {
            if isOnboarding {
                // Onboarding runs in a sheet (below); keep a neutral
                // backdrop under it so the main UI never peeks around the sheet.
                OnboardingBackdrop()
            } else if appState.libraryURL != nil {
                mainContent
            } else if appState.isRestoringLibrary {
                // A saved library is still being opened; stay neutral rather than
                // flashing onboarding for the few frames before boot settles.
                RestoringView()
            } else {
                OnboardingBackdrop()
            }
        }
        // Choosing a library dismisses this first-run sheet.
        .sheet(isPresented: onboardingSheet) {
            ChooseLibraryStep()
                .frame(width: 560, height: 340)
                .interactiveDismissDisabled()
        }
        // Attached at the root so ⌘/ works from any screen.
        .sheet(isPresented: $appState.showShortcuts) {
            ShortcutsView()
        }
        .onChange(of: appState.isFocusMode) { _, isFocus in
            if isFocus {
                appState.clearSearch()
            }
        }
    }

    /// Show the folder picker only when no library is configured or restoring.
    private var isOnboarding: Bool {
        appState.libraryURL == nil && !appState.isRestoringLibrary
    }

    /// Drives the onboarding sheet from `isOnboarding`. Read-only: the flow is
    /// advanced and dismissed through app state, never by the user, so the setter is
    /// a no-op that pairs with `interactiveDismissDisabled`.
    private var onboardingSheet: Binding<Bool> {
        Binding(get: { isOnboarding }, set: { _ in })
    }

    private var mainContent: some View {
        OiaLibraryView()
    }
}

// ── Restoring placeholder ─────────────────────────────────────────────────────
// Shown while a previously chosen library is being reopened on launch, so the
// onboarding button never flashes for users who've already picked a folder.

private struct RestoringView: View {
    var body: some View {
        OnboardingBackdrop()
    }
}

// ── Onboarding backdrop ───────────────────────────────────────────────────────
// Sits behind the onboarding sheet on first run, so the empty first-launch window
// reads as intentional rather than blank.

private struct OnboardingBackdrop: View {
    var body: some View {
        VStack(spacing: 12) {
            OiaEye()
            Text("Óia")
                .font(.title2)
        }
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Choose a library folder to open the board.
private struct ChooseLibraryStep: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 16) {
            OiaEye()
                .foregroundStyle(.secondary)
            Text("Welcome to Óia")
                .font(.title)
                .accessibilityIdentifier(A11y.Onboarding.title)
            Text("Choose a folder for your library.\nYour saves stay on your Mac.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Choose Library…") {
                appState.chooseLibrary()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier(A11y.Onboarding.chooseLibrary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Exact eye vector from Figma's “eye final” (10:248), shared with the app icon.
private struct OiaEye: View {
    var body: some View {
        Image("OiaEye")
            .resizable()
            .scaledToFit()
            .frame(width: 96, height: 96)
            .accessibilityHidden(true)
    }
}
