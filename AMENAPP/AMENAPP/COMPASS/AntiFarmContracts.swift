//  AntiFarmContracts.swift
//  AMEN — COMPASS · Anti-Farming + Steering + Activity-Discovery · Swift mirror of
//  Backend/functions/src/compass/antiFarmContracts.ts.
//  FROZEN. Source of truth is TypeScript; this mirrors it field-for-field. Any change
//  requires a contract-change note + re-freeze.
//
//  INVARIANTS (server-enforced; client re-asserts for UX only):
//    - Coordinated-behavior signals set `integrityPenalty` BEFORE ranking; bot detection is
//      device/burst heuristics, NEVER a public person score.
//    - `OriginalityScore` and `integrityPenalty` are INTERNAL-only — never displayed.
//    - Steering weight is clamped to [-1, 1]; faith is one optional vertical, never privileged.
//    - Fail-closed when the relevant flag is OFF: integrityPenalty == 0 (no demotion),
//      ranking is unweighted, activity-discovery surface is empty.
//
//  This file REUSES `ProvenanceStatus` (provenance basis) from TrueSourceModels.swift rather
//  than minting a parallel enum. It deliberately mints NO public person score.
//
//  NEW FILE — auto-included via the AMENAPP PBXFileSystemSynchronizedRootGroup (no pbxproj edit).

import Foundation

// MARK: - Anti-farming signals

/// Deterministic coordinated-behavior signal kinds — evidence categories, not scores.
/// Raw values match the TS `AntiFarmSignal` union members exactly.
enum AntiFarmSignal: String, Codable, CaseIterable, Sendable {
    case sybilCluster             = "sybilCluster"
    case followFarm               = "followFarm"
    case coordinatedAmplification = "coordinatedAmplification"
}

/// Per-user amplification budget. Reach is bounded, never bought.
struct AmplificationBudget: Codable, Equatable, Sendable {
    let uid: String
    /// Total amplification units available this window (base allotment, never purchasable).
    let totalUnits: Int
    /// Units already consumed this window.
    let consumedUnits: Int
    /// UTC epoch ms when the budget window resets.
    let windowResetAtUTC: Double
    /// True once consumed >= total; further amplification is held, never extended for pay.
    let depleted: Bool
}

/// INTERNAL-ONLY. Composite originality assessment. MUST NEVER be rendered as a number or
/// surfaced to a user. `internalOnly` is a structural reminder of that contract.
struct OriginalityScore: Codable, Equatable, Sendable {
    /// 0...1, higher = more likely original to this author. INTERNAL.
    let value: Double
    /// Coarse provenance basis (reuses ProvenanceStatus). INTERNAL.
    let provenanceBasis: ProvenanceStatus
    /// Repost-chain depth observed; longer chains lower originality. INTERNAL.
    let repostLineageDepth: Int
    /// Always true — this type is never client-facing.
    let internalOnly: Bool

    enum CodingKeys: String, CodingKey {
        case value
        case provenanceBasis
        case repostLineageDepth
        case internalOnly
    }

    init(value: Double, provenanceBasis: ProvenanceStatus, repostLineageDepth: Int) {
        self.value = value
        self.provenanceBasis = provenanceBasis
        self.repostLineageDepth = repostLineageDepth
        self.internalOnly = true
    }
}

/// Subject of an integrity evaluation. Raw values match the TS `subjectKind` union.
enum IntegritySubjectKind: String, Codable, CaseIterable, Sendable {
    case post    = "post"
    case account = "account"
}

/// Deterministic integrity evaluation applied BEFORE ranking. When the anti-farming flag is
/// OFF, `integrityPenalty` is fixed at 0 (fail-closed = no demotion) and `originality` is nil.
struct IntegrityEvaluation: Codable, Equatable, Sendable {
    let subjectId: String
    let subjectKind: IntegritySubjectKind
    /// Detected coordinated-behavior signals (may be empty).
    let signals: [AntiFarmSignal]
    /// 0...1 demotion magnitude applied to ranking. INTERNAL — never displayed.
    /// MUST be exactly 0 when `flagEnabled` is false.
    let integrityPenalty: Double
    /// INTERNAL originality assessment; nil when flag is OFF.
    let originality: OriginalityScore?
    /// Reflects compass_anti_farming_enabled at evaluation time.
    let flagEnabled: Bool
    let evaluatedAtUTC: Double

    /// Fail-closed evaluation: no signals, zero penalty, no originality leakage.
    static func unweighted(
        subjectId: String,
        subjectKind: IntegritySubjectKind,
        evaluatedAtUTC: Double
    ) -> IntegrityEvaluation {
        IntegrityEvaluation(
            subjectId: subjectId,
            subjectKind: subjectKind,
            signals: [],
            integrityPenalty: 0,
            originality: nil,
            flagEnabled: false,
            evaluatedAtUTC: evaluatedAtUTC
        )
    }
}

// MARK: - Steering

/// A single user-owned, additive steering edit on an interest tag. Weight clamped to [-1, 1].
/// Never a person score; never keyed on time-on-app. Faith is one optional vertical.
struct SteeringPreference: Codable, Equatable, Sendable {
    let interestTagId: String
    /// -1...1, clamped via SteeringBounds.clamp. Negative = less of, positive = more of.
    let weight: Double
    /// Optional vertical context (e.g. "faith"); additive only, never privileged.
    let vertical: String?

    init(interestTagId: String, weight: Double, vertical: String? = nil) {
        self.interestTagId = interestTagId
        self.weight = weight
        self.vertical = vertical
    }
}

/// User-owned, inspectable, deletable steering set (PRIVACY-CORE preference zone).
struct SteeringPreferenceSet: Codable, Equatable, Sendable {
    let uid: String
    let preferences: [SteeringPreference]
    /// Reflects compass_steering_enabled; when false, ranking is unweighted.
    let flagEnabled: Bool
    let updatedAtUTC: Double
}

/// Steering clamp bounds — mirror of STEERING_WEIGHT_MIN/MAX.
enum SteeringBounds {
    static let min: Double = -1
    static let max: Double = 1

    /// Clamp a steering weight to [-1, 1].
    static func clamp(_ weight: Double) -> Double {
        Swift.max(min, Swift.min(max, weight))
    }
}

// MARK: - Activity discovery

/// Coarse, private activity signals that drive discovery. Never GPS, never follower counts.
enum SharedActivitySignal: String, Codable, CaseIterable, Sendable {
    case joined    = "joined"
    case rsvped    = "rsvped"
    case completed = "completed"
}

/// Kinds of shared activity OBJECTS that anchor discovery.
enum ActivityObjectKind: String, Codable, CaseIterable, Sendable {
    case event        = "event"
    case prayerCircle = "prayerCircle"
    case localGroup   = "localGroup"
    case volunteer    = "volunteer"
}

/// Truthful "why shown" rationale. No reason => no surface.
struct ActivityDiscoveryRationale: Codable, Equatable, Sendable {
    let sharedActivity: SharedActivitySignal
    let detail: String
}

/// Eligibility gate for an activity-discovery candidate; fail-closed.
struct ActivityDiscoveryEligibility: Codable, Equatable, Sendable {
    /// False => candidate is dropped (never surfaced).
    let eligible: Bool
    /// Reflects compass_activity_discovery_enabled.
    let flagEnabled: Bool

    /// Fail-closed default: ineligible, flag off.
    static let failClosed = ActivityDiscoveryEligibility(eligible: false, flagEnabled: false)
}

/// A discovery candidate anchored to a shared activity object.
struct ActivityDiscoveryCandidate: Codable, Equatable, Identifiable, Sendable {
    let candidateId: String
    let objectId: String
    let objectKind: ActivityObjectKind
    /// The coarse private signal that surfaced this candidate.
    let sharedActivity: SharedActivitySignal
    let rationale: ActivityDiscoveryRationale
    let eligibility: ActivityDiscoveryEligibility

    var id: String { candidateId }

    /// Fail-closed (empty) activity-discovery surface.
    static var emptySurface: [ActivityDiscoveryCandidate] { [] }
}
