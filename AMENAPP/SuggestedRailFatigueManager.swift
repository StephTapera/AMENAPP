import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - Suggestion Fatigue Manager

/// Singleton tracking per-user fatigue signals for the suggested accounts rail.
///
/// **Per-target tracking** (keyed by suggested userId):
/// - impression count, ignore count, dismiss date, follow date
///
/// **Per-surface tracking** (keyed by `SuggestionSurface`):
/// - rail hide date
///
/// **Rules applied during scoring:**
/// - dismissed → 24h cooldown (target hidden for 24 hours)
/// - ignored 3+ → score penalty of -0.15 per ignore past 2
/// - followed → permanent removal from suggestions
/// - rail hidden → 12h surface cooldown (entire rail hidden)
///
/// Local state is backed by UserDefaults for instant access and synced to
/// Firestore at `users/{uid}/suggestionFeedback/{targetId}` for cross-device
/// persistence.
final class SuggestedRailFatigueManager {

    static let shared = SuggestedRailFatigueManager()

    // MARK: - Constants

    private static let dismissCooldownSeconds: TimeInterval = 24 * 60 * 60  // 24 hours
    private static let railHideCooldownSeconds: TimeInterval = 12 * 60 * 60 // 12 hours
    private static let ignoreThreshold = 3
    private static let ignorePenaltyPerCount: Double = 0.15

    // UserDefaults keys
    private static let impressionsKey    = "amen.suggestions.fatigue.impressions"
    private static let ignoresKey        = "amen.suggestions.fatigue.ignores"
    private static let dismissDatesKey   = "amen.suggestions.fatigue.dismissDates"
    private static let followedIdsKey    = "amen.suggestions.fatigue.followedIds"
    private static let railHideDatesKey  = "amen.suggestions.fatigue.railHideDates"

    private let defaults = UserDefaults.standard
    private lazy var db = Firestore.firestore()

    private init() {}

    // MARK: - Impression Tracking

    /// Record that a suggestion card was shown on screen.
    func recordImpression(targetUserId: String) {
        var impressions = loadImpressions()
        impressions[targetUserId, default: 0] += 1
        defaults.set(impressions, forKey: Self.impressionsKey)
    }

    /// Number of times a given suggestion has been shown.
    func impressionCount(for targetUserId: String) -> Int {
        loadImpressions()[targetUserId, default: 0]
    }

    // MARK: - Ignore Tracking

    /// Record that the user scrolled past a suggestion without acting.
    func recordIgnore(targetUserId: String) {
        var ignores = loadIgnores()
        ignores[targetUserId, default: 0] += 1
        defaults.set(ignores, forKey: Self.ignoresKey)
    }

    /// Number of times a given suggestion was ignored.
    func ignoreCount(for targetUserId: String) -> Int {
        loadIgnores()[targetUserId, default: 0]
    }

    // MARK: - Dismiss Tracking

    /// Record that the user explicitly dismissed a suggestion card.
    func recordDismiss(targetUserId: String, surface: SuggestionSurface) {
        var dates = loadDismissDates()
        dates[targetUserId] = Date().timeIntervalSince1970
        defaults.set(dates, forKey: Self.dismissDatesKey)

        // Sync to Firestore
        syncFeedbackToFirestore(targetUserId: targetUserId, action: "dismiss", surface: surface)
    }

    /// Whether a dismissed suggestion is still within its 24h cooldown.
    func isDismissCooldownActive(for targetUserId: String) -> Bool {
        guard let dismissTime = loadDismissDates()[targetUserId] else { return false }
        return Date().timeIntervalSince1970 - dismissTime < Self.dismissCooldownSeconds
    }

    // MARK: - Follow Tracking

    /// Record that the user followed a suggested account (permanent removal).
    func recordFollow(targetUserId: String, surface: SuggestionSurface) {
        var ids = loadFollowedIds()
        ids.insert(targetUserId)
        defaults.set(Array(ids), forKey: Self.followedIdsKey)

        // Sync to Firestore
        syncFeedbackToFirestore(targetUserId: targetUserId, action: "follow", surface: surface)
    }

    /// Whether the user has followed this suggestion (permanent exclusion).
    func hasFollowed(_ targetUserId: String) -> Bool {
        loadFollowedIds().contains(targetUserId)
    }

    // MARK: - Rail Hide Tracking

    /// Record that the user hid the entire rail for a given surface.
    func recordRailHide(surface: SuggestionSurface) {
        var dates = loadRailHideDates()
        dates[surface.rawValue] = Date().timeIntervalSince1970
        defaults.set(dates, forKey: Self.railHideDatesKey)
    }

    /// Whether the rail for the given surface is still within its 12h cooldown.
    func isRailHideCooldownActive(for surface: SuggestionSurface) -> Bool {
        guard let hideTime = loadRailHideDates()[surface.rawValue] else { return false }
        return Date().timeIntervalSince1970 - hideTime < Self.railHideCooldownSeconds
    }

    /// Clear the rail hide cooldown (user restores rail).
    func clearRailHide(surface: SuggestionSurface) {
        var dates = loadRailHideDates()
        dates.removeValue(forKey: surface.rawValue)
        defaults.set(dates, forKey: Self.railHideDatesKey)
    }

    // MARK: - Scoring Adjustments

    /// Returns the fatigue penalty to subtract from a candidate's suggestion score.
    /// - Dismissed within cooldown: returns 0.25 (effectively removes)
    /// - Followed: returns 1.0 (permanent removal)
    /// - Ignored 3+: returns 0.15 per ignore past the threshold of 2
    func fatiguePenalty(for targetUserId: String) -> Double {
        // Followed = permanent exclusion
        if hasFollowed(targetUserId) { return 1.0 }

        // Dismissed within cooldown
        if isDismissCooldownActive(for: targetUserId) { return 0.25 }

        // Ignore-based decay
        let ignores = ignoreCount(for: targetUserId)
        if ignores >= Self.ignoreThreshold {
            return Double(ignores - 2) * Self.ignorePenaltyPerCount
        }

        return 0.0
    }

    /// Whether a suggestion should be completely excluded from the rail.
    func shouldExclude(targetUserId: String) -> Bool {
        hasFollowed(targetUserId) || isDismissCooldownActive(for: targetUserId)
    }

    // MARK: - Firestore Sync

    private func syncFeedbackToFirestore(targetUserId: String, action: String, surface: SuggestionSurface) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Task {
            try? await db.collection("users").document(uid)
                .collection("suggestionFeedback").document(targetUserId)
                .setData([
                    "action": action,
                    "surface": surface.rawValue,
                    "timestamp": FieldValue.serverTimestamp(),
                    "impressions": impressionCount(for: targetUserId),
                    "ignores": ignoreCount(for: targetUserId)
                ], merge: true)
        }
    }

    // MARK: - UserDefaults Helpers

    private func loadImpressions() -> [String: Int] {
        (defaults.dictionary(forKey: Self.impressionsKey) as? [String: Int]) ?? [:]
    }

    private func loadIgnores() -> [String: Int] {
        (defaults.dictionary(forKey: Self.ignoresKey) as? [String: Int]) ?? [:]
    }

    private func loadDismissDates() -> [String: Double] {
        (defaults.dictionary(forKey: Self.dismissDatesKey) as? [String: Double]) ?? [:]
    }

    private func loadFollowedIds() -> Set<String> {
        Set(defaults.stringArray(forKey: Self.followedIdsKey) ?? [])
    }

    private func loadRailHideDates() -> [String: Double] {
        (defaults.dictionary(forKey: Self.railHideDatesKey) as? [String: Double]) ?? [:]
    }
}
