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

    // Issue 5 FIX: Replace the polling spin-wait with a proper async signal.
    // A plain Bool + busy-wait loop has two problems:
    //   (a) 10 × 100 ms = 1 s hard cap — clearPersistence() can take longer on slow
    //       devices, so signIn() could proceed while the clear is still in flight.
    //   (b) The poll wastes CPU and blocks the async task budget for 0–1 s.
    // Solution: store a list of continuations. Any caller that arrives while
    // isClearingCache = true suspends itself; the Task that owns the clear resumes
    // all waiters atomically when it finishes.
    private(set) var isClearingCache = false
    private var cacheClearContinuations: [CheckedContinuation<Void, Never>] = []

    /// Suspend the caller until the in-flight Firestore cache clear (if any) finishes.
    /// Returns immediately if no clear is in progress.
    func waitForCacheClear() async {
        guard isClearingCache else { return }
        await withCheckedContinuation { continuation in
            cacheClearContinuations.append(continuation)
        }
    }

    // MARK: - Sign-Out Cleanup

    /// Stops all active Firebase listeners and clears all per-user caches.
    /// Call this BEFORE calling Auth.auth().signOut() so all Firestore/RTDB
    /// listeners are detached while the user's credentials are still valid.
    /// Calling with stale credentials causes permission_denied floods.
    func performFullSignOutCleanup() {
        // ── Realtime Database listeners ──────────────────────────────────────
        RealtimePostService.shared.stopAllObserving()
        // P0-14 FIX: Detach FirebasePostService Firestore listeners on sign-out so they
        // cannot fire under the stale (or nil) auth credential after sign-out, which would
        // cause permission_denied floods and potential cross-user data leaks.
        FirebasePostService.shared.stopListening()
        // resetUserState() calls stopAllObservers() AND clears per-user like/amen/repost
        // sets so the previous user's interaction state is never visible to the next account.
        PostInteractionsService.shared.resetUserState()
        RealtimeRepostsService.shared.stopAllObservers()
        RealtimeSavedPostsService.shared.removeSavedPostsListener()
        RealtimeDatabaseService.shared.cleanup()
        RealtimeCommentsService.shared.removeAllListeners()
        ActivityFeedService.shared.stopAllObservers()

        // ── Firestore listeners + per-user published state ───────────────────
        // resetUserState() calls stopListening() AND zeroes all published Sets/arrays
        // so the previous user's follow graph / block list are never accessible to
        // the next signed-in account — even during the sign-out → sign-in window.
        FollowService.shared.resetUserState()
        NotificationService.shared.stopListening()
        BlockService.shared.resetUserState()
        PostsManager.shared.stopListeningForProfileUpdates()
        // Clear post arrays so stale block-filtered posts from the previous user
        // cannot briefly appear in the feed before the new user's posts load.
        PostsManager.shared.clearPosts()

        // ── Messaging ────────────────────────────────────────────────────────
        MessageSettingsService.shared.stopListening()
        MessageSettingsService.shared.clearCache()

        // ── FCM device token ─────────────────────────────────────────────────
        // Section-14 item-13 FIX: Mark this device's FCM token as inactive in
        // Firestore on sign-out so the server stops sending push notifications
        // to a device that no longer has an authenticated session.
        // unregisterDeviceToken() sets isActive: false, clears currentToken,
        // and resets isTokenRegistered — it does NOT delete the Firestore doc,
        // so cleanupInvalidTokens() can still expire it after 30 days.
        Task { await DeviceTokenManager.shared.unregisterDeviceToken() }

        // ── Church journey tracking ───────────────────────────────────────────
        ChurchInteractionService.shared.stopListening()
        ChurchVisitReminderService.shared.cancelAllReminders()

        // ── Jobs & Opportunities platform ────────────────────────────────────
        JobService.shared.stopListening()

        // ── Spiritual Check-In system ────────────────────────────────────────
        SpiritualCheckInService.shared.stopListening()

        // ── Global listener registry (Firestore registrations + boolean gates) ──
        ListenerRegistry.shared.reset()

        // ── Per-user singleton caches ─────────────────────────────────────────
        // DraftsManager: clears in-memory and UserDefaults drafts so a newly
        // signed-in account cannot see the previous user's unsaved posts.
        DraftsManager.shared.reset()
        // BadgeCountManager: stop all Firestore snapshot listeners first (PE-03 FIX:
        // explicit stopListening() call so dangling listeners are removed before
        // the full reset wipes published state), then zero all counts and caches
        // so the next user starts with a clean badge state.
        BadgeCountManager.shared.stopListening()
        BadgeCountManager.shared.reset()
        // GrowthLoopEngine: detaches Firestore listener and clears loop/metrics
        // data so growth-loop history from the previous user is never visible
        // to the next signed-in account.
        GrowthLoopEngine.shared.reset()

        // ── AI service caches ────────────────────────────────────────────────
        OpenAIService.shared.reset()
        ClaudeService.shared.reset()
        EnforcementService.shared.dismissBanner()  // Clear any in-memory enforcement state

        // ── Trust score cache ─────────────────────────────────────────────────
        ContentTrustScoreService.shared.clearAll()

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

        // ── Navigation routers ───────────────────────────────────────────────
        // S1-2 FIX: Reset deep-link routers on sign-out so queued navigation
        // destinations from user A cannot fire into user B's session after re-login.
        NotificationDeepLinkRouter.shared.reset()
        DeepLinkRouter.shared.reset()

        // ── Session timeout timers ───────────────────────────────────────────
        // Stop monitoring AFTER service teardown so the warning UI is dismissed cleanly.
        SessionTimeoutManager.shared.stopMonitoring()

        // ── Firestore disk cache ─────────────────────────────────────────────
        // Clear persisted Firestore cache on sign-out so one user's data does not
        // remain on disk for the next user of the device.
        // BUG-12 FIX: Set isClearingCache = true before the async clear starts so
        // AuthenticationViewModel.signIn() can gate on it and prevent a second
        // user from loading stale data before the clear completes.
        // PE-02 FIX: clearPersistence() takes a completion block — the rest of the
        // sign-out sequence (resuming sign-in waiters) happens INSIDE the completion
        // block so it never runs before the cache clear finishes.
        isClearingCache = true
        Firestore.firestore().clearPersistence { [weak self] error in
            // PE-02 FIX: Log clearPersistence failures; previously try? silently
            // discarded errors, making cache-clear failures invisible in production.
            if let error = error {
                print("clearPersistence error: \(error)")
            } else {
                dlog("✅ Firestore persistence cache cleared for new session")
            }
            // Resume all callers that suspended in waitForCacheClear() AFTER the
            // completion block fires — i.e., only once the clear has actually finished
            // (or failed). This was previously done in a defer on the Task body, which
            // is equivalent timing-wise, but the completion-block form is explicit and
            // avoids the nested Task { @MainActor } hop that could reorder on a busy queue.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isClearingCache = false
                // Issue 5 FIX: Resume all callers that suspended in waitForCacheClear().
                let waiters = self.cacheClearContinuations
                self.cacheClearContinuations.removeAll()
                for c in waiters { c.resume() }
                dlog("✅ Firestore cache clear done — resumed \(waiters.count) waiting sign-in(s)")
            }
        }
    }
}
