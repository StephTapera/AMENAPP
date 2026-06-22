//
//  FollowSafetyFilter.swift
//  AMENAPP
//
//  System 13: Suggested Follows — Safety Engine
//
//  Two responsibilities:
//    1. FollowSafetyFilter  — excludes unsafe candidates from suggestion lists
//    2. FollowBurstCoordinator — detects abnormal follow velocity and applies
//       a friction → cooldown state machine before any follow action executes.
//
//  Internal risk signals are intentionally neutral:
//    - demographicConcentrationScore  (not surfaced to users)
//    - relationshipSeekingBurstScore  (not surfaced to users)
//    - lowContextBurstScore           (not surfaced to users)
//
//  All thresholds are configurable via FollowSafetyThresholds, which can be
//  overwritten from a remote config fetch without a code change.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - Configurable Thresholds

/// All safety thresholds are stored here so they can be overwritten at runtime
/// from a remote-config or Firestore document without a code change.
struct FollowSafetyThresholds: Sendable {
    // Soft warning levels
    var softWarningFollowsIn15Min: Int   = 8
    var softWarningFollowsIn60Min: Int   = 15

    // Cooldown trigger levels
    var cooldownFollowsIn60Min: Int      = 20
    var cooldownPrivateFollowsIn30Min: Int = 5

    // Friction confirmation delay (seconds) before the follow registers
    var frictionDelaySeconds: Double     = 3.0

    // Cooldown duration (minutes) once triggered
    var cooldownDurationMinutes: Double  = 10.0

    // Extended cooldown after repeated bursts in a 24-hour window
    var extendedCooldownDurationMinutes: Double = 30.0
    var burstRepeatThresholdIn24h: Int   = 2  // how many burst events trigger extended cooldown

    // Demographic concentration: ratio of similar-profile follows in a window
    var demographicConcentrationThreshold: Double = 0.70

    // Minimum trust score for a candidate to appear in suggestions
    var minimumSuggestionTrustScore: Double = 0.35

    /// Shared default. Overwrite this property to apply remote config values app-wide.
    static var shared = FollowSafetyThresholds()
}

// MARK: - Follow Event Record

/// Lightweight, append-only record of every follow action taken by the current user.
/// Persisted in memory for the session; we write a lightweight Firestore entry
/// so the backend can verify independently.
struct FollowEventRecord: Sendable {
    let targetUserId: String
    let targetIsPrivate: Bool
    let timestamp: Date
    /// Neutral internal cluster tag — never shown to user, never logged in analytics exports.
    let internalProfileCluster: String?
}

// MARK: - Friction State

/// The current friction level for follow actions.
/// Moves forward (escalating) and resets only after a cooldown window clears.
enum FollowFrictionState: Int, Comparable, Sendable {
    case clear      = 0  // No friction — follow proceeds immediately
    case nudge      = 1  // Gentle mindful banner shown
    case confirm    = 2  // Confirmation dialog shown + short delay
    case cooldown   = 3  // All new follows disabled temporarily

    static func < (lhs: FollowFrictionState, rhs: FollowFrictionState) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// User-facing copy. Never accusatory, never gender-specific, never shaming.
    var userMessage: String? {
        switch self {
        case .clear:   return nil
        case .nudge:
            return "You're connecting with people quickly right now. Please make sure your follows are intentional and respectful."
        case .confirm:
            return "Thoughtful connections help keep AMEN a safe community. Follow this account?"
        case .cooldown:
            return "Follow activity is temporarily paused to keep connections healthy and safe. Try again in a few minutes."
        }
    }

    var requiresConfirmation: Bool { self == .confirm }
    var blocksAction: Bool         { self == .cooldown }
}

// MARK: - Follow Burst Coordinator

/// Evaluates follow velocity and manages the friction/cooldown state machine.
/// Call `recordFollow(_:)` before or after each follow action.
/// Call `frictionStateForNextFollow()` before performing a follow to know
/// whether to show a warning, ask for confirmation, or block the action.
@MainActor
final class FollowBurstCoordinator: ObservableObject {

    static let shared = FollowBurstCoordinator()

    // Published so views can react to state changes
    @Published private(set) var frictionState: FollowFrictionState = .clear
    @Published private(set) var cooldownEndsAt: Date?

    // Internal event log (session only — lightweight)
    private var events: [FollowEventRecord] = []

    // Tracks how many burst events happened in the last 24h for escalation
    private var burstEventTimestamps: [Date] = []

    private lazy var db = Firestore.firestore()
    private var thresholds: FollowSafetyThresholds { FollowSafetyThresholds.shared }

    private init() {}

    // MARK: - Public API

    /// Record that a follow action was executed.
    /// Call this after a confirmed follow (optimistically, or on success).
    func recordFollow(
        targetUserId: String,
        targetIsPrivate: Bool = false,
        internalProfileCluster: String? = nil
    ) {
        let event = FollowEventRecord(
            targetUserId: targetUserId,
            targetIsPrivate: targetIsPrivate,
            timestamp: Date(),
            internalProfileCluster: internalProfileCluster
        )
        events.append(event)
        evaluateState()
        writeEventToFirestore(event)
    }

    /// Returns the current friction state to apply to the next follow attempt.
    /// Call this before executing a follow to determine UX behavior.
    func frictionStateForNextFollow() -> FollowFrictionState {
        // If in cooldown, check whether it has expired
        if frictionState == .cooldown, let endsAt = cooldownEndsAt {
            if Date() >= endsAt {
                frictionState = .clear
                cooldownEndsAt = nil
            }
        }
        return frictionState
    }

    /// Resets all friction state. Used after cooldown timer expires or for testing.
    func resetFriction() {
        frictionState = .clear
        cooldownEndsAt = nil
    }

    // MARK: - State Evaluation

    private func evaluateState() {
        let now = Date()

        // --- Compute windowed follow counts ---
        let last15Min  = events.filter { now.timeIntervalSince($0.timestamp) <= 15 * 60 }.count
        let last60Min  = events.filter { now.timeIntervalSince($0.timestamp) <= 60 * 60 }.count
        let last30Min  = events.filter { now.timeIntervalSince($0.timestamp) <= 30 * 60 }

        // Private-account burst
        let privateIn30Min = last30Min.filter { $0.targetIsPrivate }.count

        // Demographic concentration score (neutral signal, never exposed to user)
        let demographicConcentrationScore = computeDemographicConcentration(window: last60Min)

        // Low-context burst (private + no mutual context)
        let lowContextBurstScore: Double = privateIn30Min >= thresholds.cooldownPrivateFollowsIn30Min ? 1.0 :
            Double(privateIn30Min) / Double(max(thresholds.cooldownPrivateFollowsIn30Min, 1))

        // Relationship-seeking burst score (high velocity + demographic concentration)
        let relationshipSeekingBurstScore: Double = demographicConcentrationScore > thresholds.demographicConcentrationThreshold
            && last60Min >= thresholds.softWarningFollowsIn60Min ? 1.0 : 0.0

        // --- Determine target state ---
        var targetState: FollowFrictionState = .clear

        // Nudge threshold
        if last15Min >= thresholds.softWarningFollowsIn15Min
           || last60Min >= thresholds.softWarningFollowsIn60Min {
            targetState = max(targetState, .nudge)
        }

        // Confirm threshold (more serious patterns)
        if last60Min >= thresholds.softWarningFollowsIn60Min
           && (lowContextBurstScore > 0.5 || relationshipSeekingBurstScore > 0) {
            targetState = max(targetState, .confirm)
        }

        // Cooldown threshold
        if last60Min >= thresholds.cooldownFollowsIn60Min
           || (privateIn30Min >= thresholds.cooldownPrivateFollowsIn30Min)
           || (relationshipSeekingBurstScore >= 1.0 && last60Min >= thresholds.softWarningFollowsIn60Min) {
            targetState = .cooldown
        }

        // --- Apply state ---
        if targetState > frictionState || targetState == .cooldown {
            frictionState = targetState

            if frictionState == .cooldown && cooldownEndsAt == nil {
                // Check whether this is a repeated burst (escalate cooldown)
                burstEventTimestamps.append(now)
                burstEventTimestamps = burstEventTimestamps.filter {
                    now.timeIntervalSince($0) <= 24 * 3600
                }

                let cooldownMinutes = burstEventTimestamps.count >= thresholds.burstRepeatThresholdIn24h
                    ? thresholds.extendedCooldownDurationMinutes
                    : thresholds.cooldownDurationMinutes

                cooldownEndsAt = now.addingTimeInterval(cooldownMinutes * 60)
                dlog("⚠️ FollowBurstCoordinator: Cooldown triggered for \(cooldownMinutes) min. Repeated bursts in 24h: \(burstEventTimestamps.count)")
            }
        }
    }

    /// Computes the ratio of follows in the last 60-min window that share the same
    /// internal profile cluster (neutral demographic tag). Never exposed to users.
    private func computeDemographicConcentration(window followCount: Int) -> Double {
        guard followCount > 0 else { return 0 }
        let last60Events = events.filter { Date().timeIntervalSince($0.timestamp) <= 60 * 60 }
        let clusterCounts = last60Events.compactMap { $0.internalProfileCluster }
            .reduce(into: [:] as [String: Int]) { $0[$1, default: 0] += 1 }
        let maxCluster = clusterCounts.values.max() ?? 0
        return Double(maxCluster) / Double(followCount)
    }

    // MARK: - Firestore Event Write

    private func writeEventToFirestore(_ event: FollowEventRecord) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        // Write a lightweight event document for backend safety review.
        // Internal cluster tags are stored only on the backend; never returned to the client.
        let doc: [String: Any] = [
            "actorUserId": uid,
            "targetUserId": event.targetUserId,
            "targetIsPrivate": event.targetIsPrivate,
            "timestamp": Timestamp(date: event.timestamp),
            "frictionStateAtTime": frictionState.rawValue
        ]
        db.collection("users").document(uid)
            .collection("followEvents")
            .addDocument(data: doc) { error in
                if let error = error {
                    dlog("FollowBurstCoordinator write error: \(error.localizedDescription)")
                }
            }
    }
}

// MARK: - Follow Safety Filter

/// Filters a candidate list of user recommendations, removing anyone who should
/// not be shown in the Suggested Follows surface.
@MainActor
final class FollowSafetyFilter {

    static let shared = FollowSafetyFilter()
    private init() {}

    /// Filter recommendation candidates for the Suggested Follows surface.
    /// Runs entirely on the main actor — call from a Task or async context.
    func filter(
        _ candidates: [RecommendedUsersAIService.UserRecommendation],
        limit: Int = 8
    ) -> [RecommendedUsersAIService.UserRecommendation] {
        guard let uid = Auth.auth().currentUser?.uid else { return [] }

        let blocked    = BlockService.shared.blockedUsers
        let following  = FollowService.shared.following
        let restricted = RestrictService.shared.restrictedUserIds

        return candidates
            .filter { candidate in
                // Never suggest yourself
                guard candidate.id != uid else { return false }

                // Exclude blocked (either direction)
                guard !blocked.contains(candidate.id) else { return false }

                // Exclude already-following
                guard !following.contains(candidate.id) else { return false }

                // Exclude users the current user has restricted
                guard !restricted.contains(candidate.id) else { return false }

                // Exclude candidates below minimum trust score
                // matchScore is 0-100 in RecommendedUsersAIService; normalize to 0-1
                let normalizedTrust = Double(candidate.matchScore) / 100.0
                guard normalizedTrust >= FollowSafetyThresholds.shared.minimumSuggestionTrustScore else {
                    return false
                }

                return true
            }
            .prefix(limit)
            .map { $0 }
    }
}
