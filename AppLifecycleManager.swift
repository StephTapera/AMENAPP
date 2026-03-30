// AppLifecycleManager.swift
// AMENAPP
//
// Centralized teardown coordinator for all sign-out and session-expiry paths.
//
// USAGE: Both AuthenticationViewModel.signOut() and SessionTimeoutManager.forceLogout()
// must call performFullSignOutCleanup() so both paths stop the exact same set of
// listeners and clear the exact same caches. Adding this prevents the common bug
// where a new service is added but only wired into one of the two sign-out paths.

import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class AppLifecycleManager {
    static let shared = AppLifecycleManager()
    private init() {}

    // BUG-12 FIX: Track whether a Firestore cache clear is still in flight.
    // AuthenticationViewModel.signIn() guards on this flag so a second user
    // cannot be authenticated until the previous user's on-disk cache is gone.
    private(set) var isClearingCache = false

    // MARK: - Sign-Out Cleanup

    /// Stops all active Firebase listeners and clears all per-user caches.
    /// Call this BEFORE calling Auth.auth().signOut() so all Firestore/RTDB
    /// listeners are detached while the user's credentials are still valid.
    /// Calling with stale credentials causes permission_denied floods.
    func performFullSignOutCleanup() {
        // ── Realtime Database listeners ──────────────────────────────────────
        RealtimePostService.shared.stopAllObserving()
        PostInteractionsService.shared.stopAllObservers()
        RealtimeRepostsService.shared.stopAllObservers()
        RealtimeSavedPostsService.shared.removeSavedPostsListener()
        RealtimeDatabaseService.shared.cleanup()
        RealtimeCommentsService.shared.removeAllListeners()
        ActivityFeedService.shared.stopAllObservers()

        // ── Firestore listeners ──────────────────────────────────────────────
        FollowService.shared.stopListening()
        NotificationService.shared.stopListening()
        BlockService.shared.stopListening()

        // ── Jobs & Opportunities platform ────────────────────────────────────
        JobService.shared.stopListening()

        // ── Spiritual Check-In system ────────────────────────────────────────
        SpiritualCheckInService.shared.stopListening()

        // ── Global listener registry (Firestore registrations + boolean gates) ──
        ListenerRegistry.shared.reset()

        // ── AI service caches ────────────────────────────────────────────────
        OpenAIService.shared.reset()
        ClaudeService.shared.reset()

        // ── Safety service caches (privacy: prevent data leaking to next session) ──
        if let uid = Auth.auth().currentUser?.uid {
            MessageSafetyGateway.shared.invalidateFreezeCache(for: uid)
            MinorSafetyService.shared.invalidateCache(for: uid)
        }
        MinorSafetyService.shared.clearCache()

        // ── Behavioral safety state ──────────────────────────────────────────
        // clearSupportState() resets supportState to .normal and clears pendingSupportSurface.
        // beginSession() resets all behavioral signals so they don't carry over to the next user.
        SafetyOrchestrator.shared.clearSupportState()
        BehavioralAwarenessEngine.shared.beginSession()

        // ── Session timeout timers ───────────────────────────────────────────
        // Stop monitoring AFTER service teardown so the warning UI is dismissed cleanly.
        SessionTimeoutManager.shared.stopMonitoring()

        // ── Firestore disk cache ─────────────────────────────────────────────
        // Clear persisted Firestore cache on sign-out so one user's data does not
        // remain on disk for the next user of the device.
        // BUG-12 FIX: Set isClearingCache = true before the async clear starts so
        // AuthenticationViewModel.signIn() can gate on it and prevent a second
        // user from loading stale data before the clear completes.
        isClearingCache = true
        Task {
            defer { Task { @MainActor in self.isClearingCache = false } }
            try? await Firestore.firestore().clearPersistence()
            dlog("✅ Firestore persistence cache cleared for new session")
        }
    }
}
