//
//  HeyFeedSteeringContracts.swift
//  AMENAPP
//
//  HeyFeed v2 — Steerable Feed · Swift mirror of Backend/functions/src/heyFeed/heyFeedSteering.ts
//  (the TypeScript file is the source of truth; this mirrors it field-for-field).
//
//  Wave 0 FROZEN: 2026-06-23. Spec authority: audit/BORROW_AND_SMARTEN_SPEC.md §8.2 Feature A.
//
//  EXTENDS the existing HeyFeed v1: HeyFeedAlgorithm stays the scorer. v2 adds (a) a user-owned,
//  transparent, additive + CLAMPED steering delta and (b) an immovable SafetyFloor that runs
//  BEFORE ranking and cannot be relaxed by any preference.
//
//  Invariants: SafetyFloor non-overridable · steering clamped to ±SteeringBounds.clamp ·
//  every steered item carries a truthful reason · PreferenceVocabulary is user-owned /
//  inspectable / deletable (preference zone) · SafetyFloor is NOT flag-gated (always-on).
//

import Foundation

// MARK: - Steering Verb (maps v1 HeyFeedNLAction)

enum SteeringVerb: String, Codable, CaseIterable, Sendable {
    case moreOf
    case lessOf
    case prioritize
    case mute
    case explore
    case reset

    /// Bridges to the existing v1 natural-language action vocabulary (HeyFeedNLModels.swift).
    /// `prioritize` maps to `.increase` (a strong "more of"); `reset` maps to `.balance`.
    var nlAction: HeyFeedNLAction {
        switch self {
        case .moreOf:      return .increase
        case .lessOf:      return .decrease
        case .prioritize:  return .increase
        case .mute:        return .mute
        case .explore:     return .explore
        case .reset:       return .balance
        }
    }
}

// MARK: - Steering Target

enum SteeringTargetType: String, Codable, CaseIterable, Sendable {
    case topic
    case tone
    case creatorType
    case relationship
    case locality
    case format
    case novelty
    case intensity

    /// Bridges to the existing v1 target taxonomy (HeyFeedNLTargetType in HeyFeedNLModels.swift).
    var nlTargetType: HeyFeedNLTargetType {
        switch self {
        case .topic:        return .topic
        case .tone:         return .tone
        case .creatorType:  return .creatorType
        case .relationship: return .relationship
        case .locality:     return .locality
        case .format:       return .format
        case .novelty:      return .novelty
        case .intensity:    return .intensity
        }
    }
}

struct SteeringTarget: Codable, Identifiable, Sendable {
    var id: String
    var type: SteeringTargetType
    var label: String
}

// MARK: - Steering Source

enum SteeringSource: String, Codable, Sendable {
    case nlInput        = "nl_input"
    case quickChip      = "quick_chip"
    case sessionMode    = "session_mode"
    case explicitControl = "explicit_control"
}

// MARK: - Preference Vocabulary

struct PreferenceVocabularyEntry: Codable, Identifiable, Sendable {
    var id: String
    var verb: SteeringVerb
    var target: SteeringTarget
    var strength: Double            // 0..1, clamped server-side
    var duration: HeyFeedDuration   // reuse v1 duration enum (HeyFeedNLModels.swift)
    var source: SteeringSource
    var active: Bool
    var paused: Bool
    var createdAt: Date
    var expiresAt: Date?
    /// User-inspectable + deletable preference zone (PRIVACY-CORE). NSPrivacyTracking=false.
    let zone: String = "preference"
}

struct PreferenceVocabulary: Codable, Sendable {
    var userId: String
    var entries: [PreferenceVocabularyEntry]
    var liturgicalSeasonKey: String?   // additive seasonal context only
    var updatedAt: Date
}

// MARK: - Ranking Signals

enum RankingSignalKind: String, Codable, CaseIterable, Sendable {
    case following
    case topicRelevance
    case recency
    case intentBoost
    case resonance
    case authorBoost
    case userSteering        // additive delta from PreferenceVocabulary (clamped)
    case liturgicalSeason    // additive seasonal context (clamped)
}

struct RankingSignal: Codable, Sendable {
    var kind: RankingSignalKind
    var contribution: Double
    var origin: String?
    var rationaleText: String?
}

struct SteeredRankingResult: Codable, Sendable {
    var postId: String
    var baseScore: Double       // HeyFeedAlgorithm.weightedTotal — unchanged scorer
    var steeringDelta: Double
    var liturgicalDelta: Double
    var signals: [RankingSignal]
    var finalScore: Double
}

// MARK: - SafetyFloor (immovable, runs BEFORE ranking)

enum SafetyFloorCategory: String, Codable, CaseIterable, Sendable {
    case childSafety
    case csam
    case harassment
    case hate
    case threats
    case selfHarm
    case sexualContent
    case violence
    case scam
    case spam
}

enum SafetyFloorAction: String, Codable, Sendable {
    case hardBlock
    case ceiling
    case alwaysShield
}

struct SafetyFloor: Codable, Sendable {
    var category: SafetyFloorCategory
    var action: SafetyFloorAction
    var ceilingRisk: Double   // max risk that may EVER clear, even at SensitivityFilter.off
    var alwaysOn: Bool        // ignores heyFeedSteering flag entirely
}

struct SafetyFloorVerdict: Codable, Sendable {
    var postId: String
    var allowed: Bool         // false => never surfaces; fail-closed when unevaluable
    var appliedFloor: SafetyFloorCategory?
    var appliedAction: SafetyFloorAction?
    var isMinorShielded: Bool
    var reasons: [String]     // INTERNAL ONLY — never displayed to users
}

// MARK: - Bounds + pure helpers (mirror STEER_CLAMP / clampSteering / effectiveRiskThreshold)

enum SteeringBounds {
    /// Mirrors STEER_CLAMP in heyFeedSteering.ts.
    static let clamp: Double = 0.35

    /// Mirrors clampSteering(v).
    static func clampSteering(_ v: Double) -> Double {
        return max(-clamp, min(clamp, v))
    }

    /// Mirrors effectiveRiskThreshold(userThreshold, ceilingRisk).
    /// A user preference may only make the feed STRICTER, never laxer.
    static func effectiveRiskThreshold(userThreshold: Double, ceilingRisk: Double) -> Double {
        return min(userThreshold, ceilingRisk)
    }

    /// Mirrors failClosedFloorVerdict(postId).
    static func failClosedFloorVerdict(postId: String) -> SafetyFloorVerdict {
        return SafetyFloorVerdict(
            postId: postId,
            allowed: false,
            appliedFloor: nil,
            appliedAction: nil,
            isMinorShielded: false,
            reasons: ["unevaluable"]
        )
    }

    /// Mirrors isFloorTargetForbidden(target): a steering target whose label/id corresponds to
    /// any SafetyFloor category can NEVER be boosted — fail-closed against laundering unsafe
    /// content through the steering surface.
    static func isFloorTargetForbidden(_ target: SteeringTarget) -> Bool {
        let needle = (target.id + " " + target.label).lowercased()
        let id = target.id.lowercased()
        return SafetyFloorCategory.allCases.contains { category in
            let token = category.rawValue.lowercased()
            return needle.contains(token) || id == token
        }
    }
}
