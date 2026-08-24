// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        Group {
            if isOnboarding {
                // Both onboarding steps run in a sheet (below); keep a neutral
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
        // First-run onboarding as one non-dismissible sheet spanning both steps
        // (see `OnboardingFlow`): step 1 is left only by choosing a folder, and the
        // sheet stays up through the extension step until "Continue".
        .sheet(isPresented: onboardingSheet) {
            OnboardingFlow()
                .interactiveDismissDisabled()
        }
        // Attached at the root so ⌘/ works from any screen.
        .sheet(isPresented: $appState.showShortcuts) {
            ShortcutsView()
        }
        .onChange(of: appState.isFocusMode) { _, isFocus in
            if isFocus {
                appState.searchQuery = ""
            }
        }
    }

    /// Whether first-run onboarding should be showing: the folder pick (no library
    /// yet, and not mid-restore) or the extension step that follows it. Restoring a
    /// saved library on launch never trips this — those users go straight to boot.
    private var isOnboarding: Bool {
        appState.showExtensionSetup || (appState.libraryURL == nil && !appState.isRestoringLibrary)
    }

    /// Drives the onboarding sheet from `isOnboarding`. Read-only: the flow is
    /// advanced and dismissed through app state, never by the user, so the setter is
    /// a no-op that pairs with `interactiveDismissDisabled`.
    private var onboardingSheet: Binding<Bool> {
        Binding(get: { isOnboarding }, set: { _ in })
    }

    private var mainContent: some View {
        CuttingsLibraryView()
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

// ── Onboarding backdrop ───────────────────────────────────────────────────────
// Sits behind the onboarding sheet on first run, so the empty first-launch window
// reads as intentional rather than blank.

private struct OnboardingBackdrop: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.system(size: 56))
            Text("Cuttings")
                .font(.title2)
        }
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// ── Onboarding flow ───────────────────────────────────────────────────────────
// The two first-run steps in one fixed-size sheet: choosing a library folder, then
// the browser-extension pointer. Both steps share the same size so the sheet never
// resizes; the wizard-style push animates the hand-off when `showExtensionSetup`
// flips (raised by the folder pick, cleared by "Continue").

private struct OnboardingFlow: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            if appState.showExtensionSetup {
                ExtensionStep()
                    .transition(.push(from: .trailing))
            } else {
                ChooseLibraryStep()
                    .transition(.push(from: .trailing))
            }
        }
        .frame(width: 560, height: 380)
        .animation(.easeInOut(duration: 0.35), value: appState.showExtensionSetup)
    }
}

/// Step 1: pick the library folder. Has no dismiss affordance — the only way
/// forward is choosing a folder, which raises the extension step.
private struct ChooseLibraryStep: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("Welcome to Cuttings")
                .font(.title)
                .accessibilityIdentifier(A11y.Onboarding.title)
            Text("Choose an existing library folder or create a new one.")
                .foregroundStyle(.secondary)
            Text(
                "Your saved pages live here as plain files you own — pick a folder you can "
                    + "back up or sync, and Cuttings keeps your whole library in it."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 360)
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

/// Step 2: point the user at the browser extension on the Chrome Web Store and
/// Firefox Add-ons. "Continue" clears `showExtensionSetup`, dismissing the sheet.
private struct ExtensionStep: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("Add the browser extension")
                    .font(.title)
                    .accessibilityIdentifier(A11y.Onboarding.extensionTitle)
                Text("The extension saves pages straight into your library.")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                ExtensionStoreLinks()
            }

            Button("Continue") {
                appState.completeExtensionSetup()
            }
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier(A11y.Onboarding.extensionContinue)
            // Centered under the content, matching the folder-pick step's button.
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: 460, alignment: .leading)
        .padding(40)
        // Fill the sheet so the block sits centered — vertically like step 1.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Let users copy the links rather than retype them.
        .textSelection(.enabled)
    }
}
