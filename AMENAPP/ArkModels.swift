// ArkModels.swift
// AMENAPP — Ark Protocol models

import Foundation
import FirebaseFirestore

// MARK: - ArkCommunity

struct ArkCommunity: Identifiable, Codable {
    @DocumentID var id: String?
    var name: String
    var description: String
    var leaderId: String
    var covenantText: String
    var covenantPrinciples: [String]    // ["truth-telling", "no gossip", "grace-first conflict"]
    var memberCount: Int
    var isVerified: Bool
    var category: String               // "small_group" | "ministry" | "recovery" | "study" | "prayer"
    var createdAt: Timestamp
    var aiModerationLevel: String      // "light" | "standard" | "strict"

    init(
        id: String? = nil,
        name: String,
        description: String,
        leaderId: String,
        covenantText: String = "",
        covenantPrinciples: [String] = [],
        memberCount: Int = 0,
        isVerified: Bool = false,
        category: String = "small_group",
        createdAt: Timestamp = Timestamp(date: Date()),
        aiModerationLevel: String = "standard"
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.leaderId = leaderId
        self.covenantText = covenantText
        self.covenantPrinciples = covenantPrinciples
        self.memberCount = memberCount
        self.isVerified = isVerified
        self.category = category
        self.createdAt = createdAt
        self.aiModerationLevel = aiModerationLevel
    }
}

// MARK: - ArkMember (subcollection under arkCommunities/{communityId}/members)

struct ArkMember: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var joinedAt: Timestamp
    var covenantSignedAt: Timestamp
    var arkScore: Double               // 0.0 – 100.0
    var arkScoreBreakdown: ArkScoreBreakdown
    var warningCount: Int
    var lastWarningReason: String?
    var status: String                 // "active" | "on_notice" | "suspended" | "restored"
}

struct ArkScoreBreakdown: Codable {
    var truthfulness: Double       // consistency, no retraction patterns
    var encouragement: Double      // how often member uplifts others
    var conflictGrace: Double      // how member handles disagreement
    var consistency: Double        // regular participation
    var testimonySharing: Double   // vulnerability and contribution
    var prayerSupport: Double      // responds to others' prayer requests

    static var empty: ArkScoreBreakdown {
        ArkScoreBreakdown(
            truthfulness: 50,
            encouragement: 50,
            conflictGrace: 50,
            consistency: 50,
            testimonySharing: 50,
            prayerSupport: 50
        )
    }
}

// MARK: - ArkPost (subcollection under arkCommunities/{communityId}/posts)

struct ArkPost: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var content: String
    var createdAt: Timestamp
    var aiModerationStatus: String     // "approved" | "flagged" | "pending_review" | "removed"
    var aiModerationReason: String?
    var aiCovenantViolations: [String]?
    var communityReports: Int
    var isAnonymous: Bool
}

// MARK: - ArkScoreEvent

enum ArkScoreEvent {
    case encouragedMember(targetUserId: String)
    case sharedTestimony
    case respondedToPrayer(requestId: String)
    case receivedWarning(reason: String)
    case consistentWeek
    case handledConflictWell
    case covenantViolation(principle: String)

    /// The score delta applied to the primary dimension
    var delta: Double {
        switch self {
        case .encouragedMember:    return  2.0
        case .sharedTestimony:     return  3.0
        case .respondedToPrayer:   return  2.5
        case .receivedWarning:     return -5.0
        case .consistentWeek:      return  1.0
        case .handledConflictWell: return  4.0
        case .covenantViolation:   return -3.0
        }
    }

    /// The breakdown dimension(s) this event affects
    var dimension: ArkScoreDimension {
        switch self {
        case .encouragedMember:    return .encouragement
        case .sharedTestimony:     return .testimonySharing
        case .respondedToPrayer:   return .prayerSupport
        case .receivedWarning:     return .truthfulness
        case .consistentWeek:      return .consistency
        case .handledConflictWell: return .conflictGrace
        case .covenantViolation:   return .truthfulness
        }
    }
}

enum ArkScoreDimension {
    case truthfulness, encouragement, conflictGrace, consistency, testimonySharing, prayerSupport
}

// MARK: - Moderation Result

struct ModerationResult {
    var status: String              // "approved" | "flagged" | "removed"
    var violations: [String]
    var reason: String
    var suggestedEdit: String?
    var graceNote: String
}
