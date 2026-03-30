//
//  BereanIslandViewModel+LiveActivity.swift
//  AMENAPP
//
//  Wires BereanIslandViewModel state transitions into the Live Activity lifecycle.
//  Call sites in BereanIslandViewModel automatically drive the Dynamic Island.
//

import Foundation

extension BereanIslandViewModel {

    // MARK: - Session lifecycle

    /// Call when Berean becomes active (e.g. trigger() or triggerWithCachedResult()).
    @MainActor
    func startLiveActivityIfNeeded() {
        BereanLiveActivityBridge.shared.handleVoiceSessionStarted()
    }

    // MARK: - State transitions

    @MainActor
    func updateLiveActivityForThinking(progress: Double = 0.45) {
        Task { await BereanLiveActivityManager.shared.setThinking(progress: progress) }
    }

    @MainActor
    func updateLiveActivityForSpeaking(scripture: String? = nil) {
        BereanLiveActivityBridge.shared.handleModelBeganResponding(scripture: scripture)
    }

    @MainActor
    func updateLiveActivityForVerse(_ reference: String) {
        BereanLiveActivityBridge.shared.handleScriptureSurfaced(reference)
    }

    /// Call from dismiss() — ends the Live Activity.
    @MainActor
    func endLiveActivity() {
        BereanLiveActivityBridge.shared.handleSessionEnded()
    }
}
