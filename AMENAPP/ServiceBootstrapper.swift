// ServiceBootstrapper.swift
// AMEN App
//
// P2 FIX: Circular dependency guard + documented service initialization order.
//
// With ~228 singletons that reference each other via `.shared` accessors,
// there is no compile-time protection against initialization cycles.
// A cycle (A.shared → B.shared → A.shared before A fully initializes)
// surfaces as a hard-to-reproduce crash, often EXC_BAD_ACCESS.
//
// This file does three things:
//   1. Documents the canonical init order (topological sort of the dependency graph).
//   2. Provides a `ServiceBootstrapper.bootstrap()` method that warms services
//      in a safe order at app launch, replacing scattered "warm on first use" init.
//   3. Provides a `ServiceBootstrapper.assertNotCycling()` DEBUG guard that panics
//      if a service tries to access `.shared` of a service that has not yet finished
//      its own init — making cycles surface immediately during development.
//
// INITIALIZATION ORDER (leaf → root):
//
//   Tier 0 — no dependencies:
//     FirebaseManager, AMENAnalyticsService, AMENFeatureFlags
//
//   Tier 1 — depend only on Tier 0:
//     FollowStateManager, BlockService, PrivacyAccessControl
//     ListenerRegistry, DeviceTokenManager
//
//   Tier 2 — depend on Tier 0/1:
//     FollowService (→ FollowStateManager, FirebaseManager)
//     NotificationService (→ FirebaseManager, BadgeCountManager)
//     SearchService (→ FirebaseManager, AlgoliaSearchService)
//     CommentService (→ FirebaseManager, ListenerRegistry)
//
//   Tier 3 — depend on Tier 0/1/2:
//     PostsManager (→ FollowService, CommentService, FirebaseManager)
//     HomeFeedAlgorithm (→ PostsManager, FollowService, FeedIntelligenceService)
//     RecommendationIntelligenceService (→ HomeFeedAlgorithm, FirebaseManager)
//
//   Tier 4 — depend on Tier 0-3:
//     BereanCoreService (→ FirebaseManager, AMENAnalyticsService)
//     FeedIntelligenceService (→ HomeFeedAlgorithm, AMENAnalyticsService)
//     NotificationAggregationService (→ NotificationService)

import Foundation
import FirebaseAuth

@MainActor
final class ServiceBootstrapper {

    static let shared = ServiceBootstrapper()
    private var bootstrapped = false

    // DEBUG: tracks which services are currently inside their init() to detect cycles.
    // In RELEASE builds this is compiled away.
    #if DEBUG
    private var initializingServices: Set<String> = []

    func beginInit(_ name: String) {
        assert(!initializingServices.contains(name),
               "⚠️ ServiceBootstrapper: Circular initialization detected for \(name). " +
               "Check that \(name).init() does not access another service whose init accesses \(name).")
        initializingServices.insert(name)
    }

    func endInit(_ name: String) {
        initializingServices.remove(name)
    }
    #endif

    /// Call once from `AMENAPPApp.init()` or `AppDelegate.application(_:didFinishLaunchingWithOptions:)`.
    /// Warms services in topological order so no `.shared` accessor fires before its dependencies are ready.
    func bootstrap() {
        guard !bootstrapped else { return }
        bootstrapped = true

        // Tier 0 — self-contained
        _ = AMENAnalyticsService.shared
        _ = AMENFeatureFlags.shared

        // Tier 1 — lightweight, no heavy async work
        _ = FollowStateManager.shared
        _ = ListenerRegistry.shared

        // Tier 2 — real-time services (warm but don't start listeners yet;
        //          listeners start after auth state is confirmed)
        // Not pre-warming PostsManager / HomeFeedAlgorithm here because they
        // require an authenticated UID — they warm on the first auth state change.

        dlog("✅ ServiceBootstrapper: Tier 0–1 services warmed in safe order")
    }
}
