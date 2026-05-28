// BereanOnboardingView.swift
// AMENAPP — Berean Onboarding
// Entry-point host and full onboarding shell using BereanOnboardingManager.

import SwiftUI

// MARK: - Host
// Standalone gate: resolves manager state, then shows onboarding or the home view.
// Used when Berean is navigated to as a full-screen destination.

struct BereanOnboardingHost: View {
    var onComplete: (() -> Void)? = nil

    @ObservedObject private var manager = BereanOnboardingManager.shared
    @State private var resolved = false

    var body: some View {
        Group {
            if !resolved {
                // Skeleton while Firestore resolves — matches Berean's own loading aesthetic
                ZStack {
                    BereanOnboardingBackground()
                    ProgressView()
                        .tint(BereanColor.textTertiary)
                }
                .ignoresSafeArea()
            } else {
                switch manager.presentation {
                case .fullOnboarding, .welcomeBack:
                    BereanFullOnboardingView {
                        onComplete?()
                    }
                case .none, .loading:
                    BereanHomeView()
                        .onAppear { manager.recordActivity() }
                }
            }
        }
        .task {
            await manager.resolve()
            resolved = true
        }
    }
}

// MARK: - Full Onboarding View
// Presented as a sheet from BereanAIAssistantView when onboarding is needed.
// Internally switches between the 3-page flow and Welcome Back.

struct BereanFullOnboardingView: View {
    let onDismiss: () -> Void

    var body: some View {
        _BereanOnboardingGate(onDismiss: onDismiss)
    }
}

private struct _BereanOnboardingGate: View {
    let onDismiss: () -> Void

    @ObservedObject var manager = BereanOnboardingManager.shared

    var body: some View {
        switch manager.presentation {
        case .fullOnboarding:
            BereanOnboardingFlowView(onDismiss: onDismiss)
        case .welcomeBack:
            BereanWelcomeBackView(onDismiss: onDismiss)
        case .none, .loading:
            // Decision resolved to "no onboarding" — dismiss immediately
            Color.clear
                .onAppear { onDismiss() }
        }
    }
}

// MARK: - Previews

#Preview("Full 3-Page Flow") {
    BereanOnboardingFlowView { }
}

#Preview("Welcome Back") {
    BereanWelcomeBackView { }
}

#Preview("Page 1 — Meet Berean") {
    ZStack {
        BereanOnboardingBackground()
        BereanPage1View()
    }
}

#Preview("Page 2 — Five Modes") {
    ZStack {
        BereanOnboardingBackground()
        BereanPage2View()
    }
}

#Preview("Page 3 — Grounded & Trustworthy") {
    ZStack {
        BereanOnboardingBackground()
        BereanPage3View()
    }
}

#Preview("Dark Mode — Full Flow") {
    BereanOnboardingFlowView { }
        .preferredColorScheme(.dark)
}

#Preview("Large Type — Full Flow") {
    BereanOnboardingFlowView { }
        .environment(\.dynamicTypeSize, .accessibility3)
}
