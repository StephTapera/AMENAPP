// AmenLiveActivityManager.swift
// AMENAPP
//
// iOS service for managing Amen Live Activities in the main app target.
// Uses ActivityKit to start, update, and end Live Activities that correspond
// to IntelligenceCards with active backing entities.
//
// TARGET MEMBERSHIP: AMENAPP main target only.
//
// Eligibility rules:
//   - Only SPIRITUAL or LOCAL tier cards may generate a Live Activity.
//   - Cards must have a verified BackingEntity (backingEntity.verified == true).
//   - Card must not be expired (expiresAt > now) at time of creation.
//   - Device must support Live Activities (iOS 16.2+, user permission granted).
//   - staleDate is always set to card.expiresAt — all activities are finite.
//
// Loop-closing:
//   - When a user acts on a card, call updateActivity with phase = .followUp.
//   - If the card has formation.loopParentId, the follow-up message closes that prior loop.

import Foundation
import os
import OSLog

#if canImport(ActivityKit)
import ActivityKit

// MARK: - AmenLiveActivityManager

/// Singleton iOS service for the Amen Live Activity lifecycle.
/// All methods run on the MainActor to satisfy ActivityKit's threading requirements.
@MainActor
final class AmenLiveActivityManager: ObservableObject {

    // MARK: Shared Instance

    static let shared = AmenLiveActivityManager()

    // MARK: Private State

    /// In-memory map: intelligenceCardId → Activity ID string.
    /// Populated when an activity is started; cleared when ended.
    private var activeActivities: [String: String] = [:]

    private let logger = os.Logger(subsystem: "com.amenapp", category: "LiveActivity")

    private init() { }

    // MARK: - Support Check

    /// Returns `true` if this device and OS version support Live Activities
    /// AND the user has authorized them.
    /// Always call this before `startActivity` — never assume support.
    var isSupported: Bool {
        if #available(iOS 16.2, *) {
            return ActivityAuthorizationInfo().areActivitiesEnabled
        }
        return false
    }

    // MARK: - Start

    /// Start a Live Activity for the given `IntelligenceCard`.
    ///
    /// Eligibility gates (all must pass):
    ///   1. `isSupported` — device + OS + user permission
    ///   2. Tier is `.spiritual` or `.local` (not community, family, or global)
    ///   3. `backingEntity.verified == true`
    ///   4. `card.expiresAt > Date.now` — card has not already expired
    ///   5. No existing Live Activity for this card (idempotent)
    ///
    /// Returns the Activity if created, or nil when ineligible / unsupported.
    /// Never throws to callers — failures are logged and swallowed gracefully.
    @discardableResult
    func startActivity(for card: IntelligenceCard) -> ActivityKit.Activity<AmenLiveActivityAttributes>? {
        guard #available(iOS 16.2, *) else {
            logger.info("LiveActivity: iOS 16.2+ required — skipped for card \(card.id)")
            return nil
        }

        guard isSupported else {
            logger.info("LiveActivity: activities disabled or not authorized — skipped for card \(card.id)")
            return nil
        }

        // Tier eligibility: only SPIRITUAL and LOCAL
        guard card.tier == .spiritual || card.tier == .local else {
            logger.debug("LiveActivity: tier \(card.tier.rawValue) not eligible for card \(card.id)")
            return nil
        }

        // Must have a verified backing entity
        guard card.backingEntity.verified else {
            logger.info("LiveActivity: unverified backing entity — skipped for card \(card.id)")
            return nil
        }

        // Must not be expired
        guard card.expiresAt > Date.now.timeIntervalSince1970 else {
            logger.info("LiveActivity: card \(card.id) already expired at \(card.expiresAt) — skipped")
            return nil
        }

        // Idempotency: don't create a duplicate
        if hasActiveActivity(for: card.id) {
            logger.debug("LiveActivity: already active for card \(card.id) — skipped")
            return nil
        }

        let tierForActivity = liveActivityTier(from: card.tier)

        let attributes = AmenLiveActivityAttributes(
            intelligenceCardId: card.id,
            backingKind: card.backingEntity.kind.rawValue,
            backingId: card.backingEntity.id,
            tier: tierForActivity,
            loopParentId: card.formation.loopParentId
        )

        let initialState = AmenLiveActivityAttributes.ContentState(
            title: card.title,
            subtitle: initialSubtitle(for: card),
            actionLabel: primaryActionLabel(for: card),
            phase: .active,
            updatedAt: Date.now
        )

        let content = ActivityContent(
            state: initialState,
            staleDate: Date(timeIntervalSince1970: card.expiresAt)   // REQUIRED: all Live Activities are finite
        )

        do {
            let activity = try ActivityKit.Activity.request(
                attributes: attributes,
                content: content,
                pushType: .token            // enable remote APNs updates
            )
            activeActivities[card.id] = activity.id
            logger.info("LiveActivity: started \(activity.id) for card \(card.id) — expires \(card.expiresAt)")

            // Begin observing the push token so the backend can update this activity
            Task {
                await observePushToken(for: activity, cardId: card.id)
            }

            return activity

        } catch {
            logger.error("LiveActivity: failed to start for card \(card.id): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Update

    /// Update the dynamic ContentState of an existing Live Activity.
    ///
    /// - Parameters:
    ///   - activityId: The `Activity.id` string (NOT the intelligenceCardId).
    ///   - newState: The new ContentState to push to the Live Activity.
    ///
    /// If the activity no longer exists (ended by OS or user), the call is a no-op.
    func updateActivity(
        id activityId: String,
        newState: AmenLiveActivityAttributes.ContentState
    ) async {
        guard #available(iOS 16.2, *) else { return }

        let matching = ActivityKit.Activity<AmenLiveActivityAttributes>
            .activities
            .first { $0.id == activityId }

        guard let activity = matching else {
            logger.info("LiveActivity: update skipped — activity \(activityId) not found (may have ended)")
            return
        }

        let content = ActivityContent(
            state: newState,
            staleDate: activity.content.staleDate  // preserve original staleDate
        )

        await activity.update(content)
        logger.info("LiveActivity: updated \(activityId) — phase=\(newState.phase.rawValue)")
    }

    /// Convenience: update an activity by its intelligenceCardId.
    /// Resolves the activityId from the in-memory map first.
    func updateActivity(
        forCardId cardId: String,
        newState: AmenLiveActivityAttributes.ContentState
    ) async {
        guard let activityId = activeActivities[cardId] else {
            logger.debug("LiveActivity: no tracked activity for card \(cardId)")
            return
        }
        await updateActivity(id: activityId, newState: newState)
    }

    // MARK: - End

    /// End a Live Activity, optionally showing a final state for up to 4 hours.
    ///
    /// Call this when:
    ///   - The backing event has concluded
    ///   - The prayer request has been answered
    ///   - `card.expiresAt` passes (ActivityKit will stale it, but calling end
    ///     explicitly allows a clean final ContentState with `.closing` phase)
    ///   - The user dismisses the card in-app
    ///
    /// - Parameters:
    ///   - activityId: The `Activity.id` string.
    ///   - finalState: The last ContentState shown before the pill dismisses.
    ///     Set phase to `.closing` or `.followUp` as appropriate.
    func endActivity(
        id activityId: String,
        finalState: AmenLiveActivityAttributes.ContentState
    ) async {
        guard #available(iOS 16.2, *) else { return }

        let matching = ActivityKit.Activity<AmenLiveActivityAttributes>
            .activities
            .first { $0.id == activityId }

        guard let activity = matching else {
            logger.info("LiveActivity: end skipped — activity \(activityId) not found")
            return
        }

        // Dismiss after ~4 seconds so the user sees the final state
        let dismissPolicy = ActivityUIDismissalPolicy.after(Date.now.addingTimeInterval(4))
        let content = ActivityContent(
            state: finalState,
            staleDate: Date.now
        )

        await activity.end(content, dismissalPolicy: dismissPolicy)

        // Remove from in-memory tracking
        activeActivities = activeActivities.filter { $0.value != activityId }

        logger.info("LiveActivity: ended \(activityId) — phase=\(finalState.phase.rawValue)")
    }

    /// Convenience: end an activity by intelligenceCardId.
    func endActivity(
        forCardId cardId: String,
        finalState: AmenLiveActivityAttributes.ContentState
    ) async {
        guard let activityId = activeActivities[cardId] else {
            logger.debug("LiveActivity: no tracked activity for card \(cardId)")
            return
        }
        await endActivity(id: activityId, finalState: finalState)
        activeActivities.removeValue(forKey: cardId)
    }

    // MARK: - Loop Closing

    /// Called when the user acts on a card (e.g., RSVPs, prays, gives).
    /// Transitions the Live Activity to `.followUp` phase to close the loop.
    ///
    /// If `card.formation.loopParentId` is present, the followUp title reflects
    /// that this action completed a prior commitment.
    func markUserActed(on card: IntelligenceCard, actionLabel: String) async {
        guard hasActiveActivity(for: card.id) else { return }

        let followUpTitle: String
        if let parentId = card.formation.loopParentId, !parentId.isEmpty {
            followUpTitle = "You followed through"
        } else {
            followUpTitle = card.title
        }

        let followUpState = AmenLiveActivityAttributes.ContentState(
            title: followUpTitle,
            subtitle: "You \(actionLabel.lowercased()). Loop closed.",
            actionLabel: "See What Happened",
            phase: .followUp,
            updatedAt: Date.now
        )

        await updateActivity(forCardId: card.id, newState: followUpState)
        logger.info("LiveActivity: loop-closed for card \(card.id) via action '\(actionLabel)'")
    }

    // MARK: - Query

    /// Returns `true` if a Live Activity is currently active for the given cardId.
    func hasActiveActivity(for cardId: String) -> Bool {
        guard #available(iOS 16.2, *) else { return false }

        // Check in-memory map first (fast path)
        guard let trackedId = activeActivities[cardId] else { return false }

        // Verify the OS still considers it active
        let isStillLive = ActivityKit.Activity<AmenLiveActivityAttributes>
            .activities
            .contains { $0.id == trackedId }

        if !isStillLive {
            // OS ended it (expired, user dismissed) — clean up stale entry
            activeActivities.removeValue(forKey: cardId)
            return false
        }

        return true
    }

    /// All currently tracked intelligenceCardIds with active Live Activities.
    var activeCardIds: [String] {
        guard #available(iOS 16.2, *) else { return [] }
        let liveIds = Set(ActivityKit.Activity<AmenLiveActivityAttributes>.activities.map { $0.id })
        // Remove any stale entries and return remaining
        let stale = activeActivities.filter { !liveIds.contains($0.value) }.keys
        stale.forEach { activeActivities.removeValue(forKey: $0) }
        return Array(activeActivities.keys)
    }

    // MARK: - Cleanup

    /// End ALL active Amen Live Activities. Call on sign-out or account deletion.
    func endAllActivities() async {
        guard #available(iOS 16.2, *) else { return }

        for activity in ActivityKit.Activity<AmenLiveActivityAttributes>.activities {
            let dismissState = AmenLiveActivityAttributes.ContentState(
                title: "Session ended",
                subtitle: "Sign out — all updates paused",
                actionLabel: "Open AMEN",
                phase: .closing,
                updatedAt: Date.now
            )
            let content = ActivityContent(
                state: dismissState,
                staleDate: Date.now
            )
            await activity.end(content, dismissalPolicy: .immediate)
        }

        activeActivities.removeAll()
        logger.info("LiveActivity: all activities ended (sign-out / cleanup)")
    }

    // MARK: - Private Helpers

    /// Maps `IntelligenceTier` → `LiveActivityTier`.
    /// Family and global tiers are not eligible (guarded upstream), but we provide
    /// a `.community` fallback so the compiler can reason exhaustively.
    private func liveActivityTier(from tier: IntelligenceTier) -> LiveActivityTier {
        switch tier {
        case .spiritual:  return .spiritual
        case .local:      return .local
        case .community:  return .community
        case .global:     return .global
        case .family:     return .community  // not expected — eligibility gate above
        }
    }

    /// Derive an initial subtitle from the card's first rank reason or summary.
    private func initialSubtitle(for card: IntelligenceCard) -> String {
        if let reason = card.rankReasons.first, !reason.isEmpty {
            return reason
        }
        if let bullet = card.summary.first, !bullet.isEmpty {
            let truncated = String(bullet.prefix(80))
            return truncated.count < bullet.count ? "\(truncated)…" : truncated
        }
        return card.backingEntity.kind.rawValue.capitalized
    }

    /// Choose a CTA label from the card's highest-priority action,
    /// preferring SHOW_UP > PRAY > GIVE > LEARN > DISCUSS > NOTICE.
    private func primaryActionLabel(for card: IntelligenceCard) -> String {
        let preferred: [ActionRung] = [.showUp, .pray, .give, .learn, .discuss, .notice]
        for rung in preferred {
            if let action = card.actions.first(where: { $0.rung == rung }) {
                return action.label
            }
        }
        return card.actions.first?.label ?? "Open"
    }

    /// Observe the push token for a Live Activity and log it so the
    /// backend can register it for remote updates via APNs.
    ///
    /// In production this token should be sent to a Cloud Function
    /// (e.g., `registerLiveActivityToken`) so the backend can push updates.
    @available(iOS 16.2, *)
    private func observePushToken(
        for activity: ActivityKit.Activity<AmenLiveActivityAttributes>,
        cardId: String
    ) async {
        for await tokenData in activity.pushTokenUpdates {
            let tokenHex = tokenData.map { String(format: "%02x", $0) }.joined()
            logger.info("LiveActivity: push token for card \(cardId): \(tokenHex)")

            // TODO: Send tokenHex to backend via Cloud Function
            // CloudFunctions.functions().httpsCallable("registerLiveActivityToken").call([
            //     "cardId": cardId,
            //     "activityId": activity.id,
            //     "pushToken": tokenHex
            // ])
        }
    }
}

#endif // canImport(ActivityKit)
