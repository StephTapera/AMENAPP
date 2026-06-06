// AmenLiveViewModel.swift
// AMENAPP — Amen Live banner view model
//
// Owns the banner visibility state for one active live session at a time.
// Observes AmenLiveService.activeSessions and drives AmenLiveBannerView.
//
// Dismiss behaviour: sets state to .dismissed(id:) so the dismissed session
// does NOT re-appear, even if the snapshot listener delivers it again.
// Dismissed IDs are cleared when the listener is restarted (e.g. new login).

import Foundation
import Combine

// MARK: - AmenLiveViewModel

@MainActor
final class AmenLiveViewModel: ObservableObject {

    // MARK: - BannerState

    enum BannerState: Equatable {
        /// No active session to surface.
        case hidden
        /// A session is active and the banner should be shown.
        case visible(AmenLiveSession)
        /// User dismissed the banner for this session ID.
        case dismissed(String)

        static func == (lhs: BannerState, rhs: BannerState) -> Bool {
            switch (lhs, rhs) {
            case (.hidden, .hidden):
                return true
            case (.visible(let a), .visible(let b)):
                return a.id == b.id
            case (.dismissed(let a), .dismissed(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    // MARK: - Published state

    @Published var bannerState: BannerState = .hidden

    // MARK: - Private

    private let service = AmenLiveService.shared
    private var cancellables = Set<AnyCancellable>()

    /// Session IDs the user has dismissed in the current app session.
    /// Not persisted — clearing on restart is intentional (avoids stale dismissals).
    private var dismissedIds = Set<String>()

    // MARK: - startObserving

    /// Begin observing live sessions for the given church/org IDs.
    /// Replaces any existing observation.
    ///
    /// - Parameter churchIds: IDs of the user's churches/orgs.
    func startObserving(churchIds: [String]) {
        cancellables.removeAll()
        dismissedIds.removeAll()

        service.startListening(for: churchIds)

        service.$activeSessions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                self?.updateBannerState(from: sessions)
            }
            .store(in: &cancellables)
    }

    // MARK: - stopObserving

    /// Detach all observations and hide the banner.
    func stopObserving() {
        cancellables.removeAll()
        service.stopListening()
        bannerState = .hidden
    }

    // MARK: - dismiss

    /// Dismiss the banner for the currently visible session.
    /// The session will not re-appear for the lifetime of this view model instance.
    func dismiss() {
        if case .visible(let session) = bannerState {
            dismissedIds.insert(session.id)
            bannerState = .dismissed(session.id)

            // After a short delay, check if another session should be shown.
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                try? await Task.sleep(nanoseconds: 400_000_000) // 0.4 s
                self.updateBannerState(from: self.service.activeSessions)
            }
        }
    }

    // MARK: - handleAction

    /// Called when the user taps the action button on the banner.
    /// Records the action via the CF callable and hides the banner.
    ///
    /// - Parameter session: The session whose action was tapped.
    func handleAction(_ session: AmenLiveSession) async {
        do {
            try await service.recordAction(
                sessionId: session.id,
                action:    session.actionHandler,
                targetId:  session.actionTarget
            )
        } catch {
            // Action recording is best-effort — don't block UI on failure.
            print("[AmenLiveViewModel] recordAction failed: \(error.localizedDescription)")
        }

        // Mark as dismissed after action so the banner doesn't stay visible.
        dismissedIds.insert(session.id)
        bannerState = .dismissed(session.id)
    }

    // MARK: - Private helpers

    private func updateBannerState(from sessions: [AmenLiveSession]) {
        // Pick the first session that has not been dismissed.
        let candidate = sessions.first { !dismissedIds.contains($0.id) }

        if let session = candidate {
            // Only transition to visible if we're currently hidden or dismissed
            // (not if the same session is already visible — avoids animation re-trigger).
            switch bannerState {
            case .visible(let current) where current.id == session.id:
                break // already showing the same session
            default:
                bannerState = .visible(session)
            }
        } else {
            // No undismissed session available
            switch bannerState {
            case .dismissed:
                break // keep dismissed state until next startObserving
            default:
                bannerState = .hidden
            }
        }
    }
}
