// BereanFallbackCoordinator.swift
// AMENAPP
//
// Coordinator for the Berean AI fallback sheet (shown when Live Activities are
// disabled or fail). Replaces the raw @Published Bool pattern with a proper state
// machine that any feed surface can opt into via .bereanFallbackSheet().
//
// Contract:
//  - First visible surface to observe .queued state claims the presentation slot.
//  - Claim is @MainActor-atomic — prevents multi-sheet storms across tabs.
//  - Sign-out clears queued/presenting context so no stale state leaks.
//  - Context (sourceSurface, sourcePostId, triggerReason) enables analytics.

import SwiftUI
import Combine

// MARK: - BereanFallbackContext

struct BereanFallbackContext {
    let sourceSurface: String
    let sourcePostId: String?
    let triggerReason: String    // "live_activity_disabled" | "live_activity_failed"
    let queuedAt: Date
}

// MARK: - BereanFallbackCoordinator

@MainActor
final class BereanFallbackCoordinator: ObservableObject {
    static let shared = BereanFallbackCoordinator()

    enum PresentationState: Equatable {
        case idle
        case queued
        case presenting
        case dismissed
    }

    @Published private(set) var presentationState: PresentationState = .idle
    private(set) var context: BereanFallbackContext?

    private init() {}

    var isReadyToPresent: Bool { presentationState == .queued }

    // MARK: - State Transitions

    /// BereanLiveActivityService calls this when the fallback must be shown.
    func enqueue(sourceSurface: String = "feed", sourcePostId: String? = nil, triggerReason: String) {
        guard presentationState == .idle || presentationState == .dismissed else { return }
        context = BereanFallbackContext(
            sourceSurface: sourceSurface,
            sourcePostId: sourcePostId,
            triggerReason: triggerReason,
            queuedAt: Date()
        )
        presentationState = .queued
    }

    /// Called by BereanFallbackSheetModifier — returns true if this surface wins the slot.
    /// Atomic on @MainActor: only the first caller moves state from queued → presenting.
    func claim() -> Bool {
        guard presentationState == .queued else { return false }
        presentationState = .presenting
        return true
    }

    /// Called by the sheet's onDismiss. 0.3 s cool-down prevents immediate re-trigger.
    func markDismissed() {
        presentationState = .dismissed
        context = nil
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if presentationState == .dismissed { presentationState = .idle }
        }
    }

    /// Sign-out cleanup — no stale routing context leaks to the next account.
    func clearForSignOut() {
        presentationState = .idle
        context = nil
    }
}

// MARK: - BereanFallbackSheetModifier

/// Attaches Berean AI fallback sheet presentation to any surface.
/// The first visible surface to receive .queued claims the slot — guarantees exactly one sheet.
struct BereanFallbackSheetModifier: ViewModifier {
    @ObservedObject private var coordinator = BereanFallbackCoordinator.shared
    @State private var isVisible = false
    @State private var showSheet = false

    func body(content: Content) -> some View {
        content
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
            .sheet(isPresented: $showSheet, onDismiss: {
                BereanFallbackCoordinator.shared.markDismissed()
            }) {
                BereanFallbackSheet()
            }
            .onReceive(coordinator.$presentationState) { state in
                switch state {
                case .queued where isVisible:
                    if coordinator.claim() { showSheet = true }
                case .idle:
                    showSheet = false
                default:
                    break
                }
            }
    }
}

extension View {
    /// Opt this surface into Berean AI fallback sheet presentation.
    /// Apply to the top-level view of HomeView, UserProfileView, PrayerView, OpenTableView.
    func bereanFallbackSheet() -> some View {
        modifier(BereanFallbackSheetModifier())
    }
}
