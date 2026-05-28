// BannerRouter.swift
// AMEN — Selah Banner Rail
//
// Routes a validated AmenSpaceBannerRoute into the app's existing flows.
//
// Contract (mirrors the spec):
//   "Open" routes (openSpace, pray, watchSermon) complete immediately — they
//   fire a notification and call completion(true) right away.
//   "Action" routes (joinGroup, rsvpEvent, applyJob) store the completion
//   callback; the receiving flow calls BannerRouter.shared.complete(bannerId:success:)
//   ONLY on confirmed success so that banner_cta_complete fires correctly.
//
// Decoupling strategy — NotificationCenter, not direct imports:
//   BannerRouter posts typed Notification.Name values. Views that own the
//   join/RSVP/apply flows observe those notifications and call complete(_:_:).
//   This avoids import cycles and keeps the banner rail independent of
//   any particular screen.
//
// Adding a new CTA route:
//   1. Add the case to AmenSpaceBannerRoute (in AmenSpaceBannerRail.swift).
//   2. Add a Notification.Name below.
//   3. Add a case in navigate(to:item:completion:).
//   4. Observe in the target view and call BannerRouter.shared.complete.

import Foundation

// MARK: - Notification Names

extension Notification.Name {
    // Action routes — completion fires only on confirmed success
    static let bannerRouteJoinGroup   = Notification.Name("bannerRouteJoinGroup")
    static let bannerRouteRSVPEvent   = Notification.Name("bannerRouteRSVPEvent")
    static let bannerRouteApplyJob    = Notification.Name("bannerRouteApplyJob")

    // Open routes — fire-and-forget; completion fires immediately
    static let bannerRouteOpenSpace   = Notification.Name("bannerRouteOpenSpace")
    static let bannerRoutePray        = Notification.Name("bannerRoutePray")
    static let bannerRouteWatchSermon = Notification.Name("bannerRouteWatchSermon")
}

// Notification userInfo keys
enum BannerRouteKey {
    static let entityId  = "id"
    static let bannerId  = "bannerId"
}

// MARK: - BannerRouter

@MainActor
final class BannerRouter {

    static let shared = BannerRouter()
    private init() {}

    // Pending completions for action routes; keyed by bannerId.
    // Cleared after 30 s to prevent unbounded growth.
    private var pendingCompletions: [String: (Bool) -> Void] = [:]
    private var expiryTasks: [String: Task<Void, Never>] = [:]

    // MARK: - Navigate

    /// Route a validated banner tap into the app's existing join/RSVP/apply/open/pray/watch flows.
    ///
    /// - Parameters:
    ///   - route:      The typed route (pre-validated by AmenSpaceBannerRailViewModel).
    ///   - item:       The banner item (used as the key for the pending completion).
    ///   - completion: Called with `true` on confirmed success, `false` on cancellation or failure.
    func navigate(
        to route: AmenSpaceBannerRoute,
        item: AmenSpaceBannerItem,
        completion: @escaping (Bool) -> Void
    ) {
        // Dispatch navigation into the app's existing flows first.
        // AmenSpaceBannerRouteOpener calls NotificationDeepLinkRouter for every route,
        // ensuring the correct screen opens regardless of whether the target view
        // also observes the per-route NotificationCenter names below.
        AmenSpaceBannerRouteOpener.open(route)

        switch route {

        // ── Action routes ─────────────────────────────────────────────────────
        // Completion fires ONLY when the target flow confirms success.

        case .joinGroup(let id):
            store(completion, for: item.id)
            NotificationCenter.default.post(
                name: .bannerRouteJoinGroup,
                object: nil,
                userInfo: [BannerRouteKey.entityId: id, BannerRouteKey.bannerId: item.id]
            )

        case .rsvpEvent(let id):
            store(completion, for: item.id)
            NotificationCenter.default.post(
                name: .bannerRouteRSVPEvent,
                object: nil,
                userInfo: [BannerRouteKey.entityId: id, BannerRouteKey.bannerId: item.id]
            )

        case .applyJob(let id):
            store(completion, for: item.id)
            NotificationCenter.default.post(
                name: .bannerRouteApplyJob,
                object: nil,
                userInfo: [BannerRouteKey.entityId: id, BannerRouteKey.bannerId: item.id]
            )

        // ── Open routes ───────────────────────────────────────────────────────
        // No waiting required; navigation is fire-and-forget.

        case .openSpace(let id):
            NotificationCenter.default.post(
                name: .bannerRouteOpenSpace,
                object: nil,
                userInfo: [BannerRouteKey.entityId: id]
            )
            completion(true)

        case .pray(let id):
            NotificationCenter.default.post(
                name: .bannerRoutePray,
                object: nil,
                userInfo: [BannerRouteKey.entityId: id]
            )
            completion(true)

        case .watchSermon(let id):
            NotificationCenter.default.post(
                name: .bannerRouteWatchSermon,
                object: nil,
                userInfo: [BannerRouteKey.entityId: id]
            )
            completion(true)
        }
    }

    // MARK: - Completion callback (called by the target flow)

    /// Call this from the join/RSVP/apply flow when it confirms success or cancellation.
    /// - Parameters:
    ///   - bannerId: The bannerId that was passed in the notification userInfo.
    ///   - success:  `true` if the user completed the action, `false` if they cancelled.
    func complete(bannerId: String, success: Bool) {
        cancelExpiry(for: bannerId)
        guard let callback = pendingCompletions.removeValue(forKey: bannerId) else { return }
        callback(success)
    }

    // MARK: - Private helpers

    private func store(_ completion: @escaping (Bool) -> Void, for bannerId: String) {
        pendingCompletions[bannerId] = completion
        // Auto-expire after 30 s to prevent leaks if the flow never calls back.
        expiryTasks[bannerId] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.pendingCompletions.removeValue(forKey: bannerId)
                self?.expiryTasks.removeValue(forKey: bannerId)
            }
        }
    }

    private func cancelExpiry(for bannerId: String) {
        expiryTasks.removeValue(forKey: bannerId)?.cancel()
    }
}
