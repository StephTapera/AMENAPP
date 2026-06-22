//
//  PrayerSessionManager.swift
//  AMENAPP
//
//  Manages the local-only Prayer Session Live Activity.
//  Call start(title:) when a user enters a focused prayer moment;
//  call end() when the session concludes.
//
//  Note: uses ActivityKit.Activity<> (fully qualified) because the AMENAPP
//  module defines its own plain `struct Activity` in ActivityFeedService.swift
//  which would otherwise shadow ActivityKit.Activity.
//
//  Phase 1 call sites (confirm with user before wiring):
//    Option A — PrayerRoomView.onAppear / .onDisappear (shared prayer rooms)
//    Option B — a "Start Prayer Session" button added to PrayerView (personal)
//

import Foundation
import ActivityKit

@MainActor
final class PrayerSessionManager {
    static let shared = PrayerSessionManager()
    private init() {}

    private var activity: ActivityKit.Activity<PrayerSessionAttributes>?
    private var stateObserver: Task<Void, Never>?

    var isActive: Bool { activity != nil }

    // MARK: - Start

    /// Start a focused prayer session, replacing any already-running session.
    func start(title: String) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        await end()
        let attrs = PrayerSessionAttributes(title: title, startedAt: .now)
        let state = PrayerSessionAttributes.ContentState(topic: nil)
        activity = try? ActivityKit.Activity.request(
            attributes: attrs,
            content: .init(state: state, staleDate: nil)
        )
        observeStateChanges()
    }

    // MARK: - Update

    /// Optionally push a focus topic beneath the timer (no APNs round-trip needed).
    func updateTopic(_ topic: String?) async {
        guard let activity else { return }
        let newState = PrayerSessionAttributes.ContentState(topic: topic)
        await activity.update(.init(state: newState, staleDate: nil))
    }

    // MARK: - End

    /// End the session and dismiss the Live Activity immediately.
    func end() async {
        await activity?.end(nil, dismissalPolicy: .immediate)
        activity = nil
        stateObserver?.cancel()
        stateObserver = nil
    }

    // MARK: - Private

    // Watch for external dismissals (e.g., user ended via Dynamic Island button).
    private func observeStateChanges() {
        guard let activity else { return }
        stateObserver = Task { [weak self] in
            for await state in activity.activityStateUpdates {
                if state == .dismissed || state == .ended {
                    self?.activity = nil
                    self?.stateObserver?.cancel()
                    break
                }
            }
        }
    }
}
