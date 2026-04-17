//
//  DiscipleshipModels.swift
//  AMENAPP
//
//  Domain models for the Guided Discipleship Engine —
//  longitudinal spiritual formation tracking.
//
//  Non-negotiable design constraints:
//    - No gamified holiness (no streaks, points, leaderboards)
//    - No public spiritual scores
//    - Growth paths are invitations, never obligations
//    - AI is a guide under Scripture; humans (pastors) have final authority
//    - All data is private to the user and their chosen leaders
//
//  Firestore collections:
//    discipleship_profiles     — /users/{uid}/discipleshipProfile/{uid}
//    discipleship_events       — /users/{uid}/discipleshipEvents/{eventId}
//    growth_paths              — /users/{uid}/growthPaths/{pathId}
//    reflection_entries        — /users/{uid}/reflectionEntries/{entryId}
//    practice_recommendations  — /users/{uid}/practiceRecommendations/{recId}
//    follow_up_prompts         — /users/{uid}/followUpPrompts/{promptId}
//    leader_connections        — /users/{uid}/leaderConnections/{connectionId}
//    leadership_referrals      — leadership_referrals/{referralId}
//

import Foundation

// MARK: - Discipleship Profile

/// The root profile for a user's spiritual formation journey.
/// Private to the user; optionally shared with a connected pastor/leader.
/// Firestore: /users/{uid}/discipleshipProfile/{uid}
struct DiscipleshipProfile: Codable, Identifiable, Equatable {
    let id: String             // Same as userId
    let userId: String
    /// Self-reported spiritual background / tradition.
    let tradition: String?
    /// Areas the user has indicated interest in growing.
    let focusAreas: [DiscipleshipFocusArea]
    /// The user's current active growth path IDs.
    var activeGrowthPathIds: [String]
    /// Total study sessions completed (for longitudinal context only; never shown publicly).
    var totalStudySessions: Int
    /// Most recently studied book of the Bible.
    var lastStudiedBook: String?
    /// IDs of connected leaders (pastors, mentors) who can see this profile.
    var connectedLeaderIds: [String]
    let createdAt: Date
    var updatedAt: Date
}

// MARK: - Discipleship Focus Area

/// Areas of spiritual formation the user has expressed interest in.
enum DiscipleshipFocusArea: String, Codable, CaseIterable {
    case prayerLife         = "prayer_life"
    case biblicalLiteracy   = "biblical_literacy"
    case evangelism         = "evangelism"
    case communityLife      = "community_life"
    case worship            = "worship"
    case servantLeadership  = "servant_leadership"
    case spiritualDisciplines = "spiritual_disciplines"
    case apologetics        = "apologetics"
    case theologyFoundations = "theology_foundations"
    case griefAndHealing    = "grief_and_healing"
    case marriageAndFamily  = "marriage_and_family"
    case vocationAndPurpose = "vocation_and_purpose"

    var displayName: String {
        switch self {
        case .prayerLife:           return "Prayer Life"
        case .biblicalLiteracy:     return "Biblical Literacy"
        case .evangelism:           return "Evangelism"
        case .communityLife:        return "Community Life"
        case .worship:              return "Worship"
        case .servantLeadership:    return "Servant Leadership"
        case .spiritualDisciplines: return "Spiritual Disciplines"
        case .apologetics:          return "Apologetics"
        case .theologyFoundations:  return "Theology Foundations"
        case .griefAndHealing:      return "Grief & Healing"
        case .marriageAndFamily:    return "Marriage & Family"
        case .vocationAndPurpose:   return "Vocation & Purpose"
        }
    }
}

// MARK: - Discipleship Event

/// A single discrete event in the user's discipleship journey (study session,
/// reflection completed, practice recommended, etc.).
/// Used to build the longitudinal context window for AI recommendations.
/// Firestore: /users/{uid}/discipleshipEvents/{eventId}
struct DiscipleshipEvent: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let eventType: DiscipleshipEventType
    /// The scripture passage involved, if any.
    let passageId: String?
    let passageReference: String?     // Denormalized display string
    /// The Berean conversation session, if applicable.
    let bereanSessionId: String?
    /// Free-form note the user optionally attached to this event.
    let note: String?
    let occurredAt: Date
}

// MARK: - Discipleship Event Type

enum DiscipleshipEventType: String, Codable, CaseIterable {
    case studySessionCompleted  = "study_session_completed"
    case reflectionSubmitted    = "reflection_submitted"
    case practiceCompleted      = "practice_completed"
    case leaderConnected        = "leader_connected"
    case leaderReferralAccepted = "leader_referral_accepted"
    case growthPathStarted      = "growth_path_started"
    case growthPathCompleted    = "growth_path_completed"
    case crisisEscalated        = "crisis_escalated"
    case prayerRecorded         = "prayer_recorded"
    case scriptureMemorized     = "scripture_memorized"
}

// MARK: - Growth Path

/// A structured, multi-step journey the user can follow for focused formation.
/// Growth paths are offered as invitations, never automatically activated.
/// Firestore: /users/{uid}/growthPaths/{pathId}
struct GrowthPath: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let title: String
    let description: String
    let focusArea: DiscipleshipFocusArea
    let steps: [GrowthPathStep]
    var completedStepIds: [String]
    var status: GrowthPathStatus
    let suggestedByAI: Bool          // Whether this path was AI-recommended
    let createdAt: Date
    var updatedAt: Date
    var completedAt: Date?

    /// Whether every step has been completed.
    var isComplete: Bool {
        steps.allSatisfy { completedStepIds.contains($0.id) }
    }
}

// MARK: - Growth Path Status

enum GrowthPathStatus: String, Codable {
    case suggested  = "suggested"   // AI offered; user hasn't started
    case active     = "active"      // User is working through it
    case paused     = "paused"      // User paused
    case completed  = "completed"   // All steps done
    case dismissed  = "dismissed"   // User declined
}

// MARK: - Growth Path Step

/// A single step within a growth path.
struct GrowthPathStep: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let description: String
    let stepType: GrowthStepType
    /// Suggested scripture to engage with for this step.
    let scriptureRef: String?
    /// Estimated number of minutes for this step.
    let estimatedMinutes: Int?
    let sortOrder: Int

    enum GrowthStepType: String, Codable {
        case reading        = "reading"        // Read a passage
        case reflection     = "reflection"     // Answer a reflection question
        case practice       = "practice"       // Spiritual discipline exercise
        case conversation   = "conversation"   // Talk with Berean about the passage
        case prayer         = "prayer"         // Guided prayer exercise
        case memorization   = "memorization"   // Memorize a verse
        case communityAct   = "community_act"  // Engage with another person
    }
}

// MARK: - Practice Recommendation

/// An AI-suggested spiritual discipline or practice.
/// Never auto-scheduled; always requires user opt-in.
/// Firestore: /users/{uid}/practiceRecommendations/{recId}
struct PracticeRecommendation: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let title: String
    let description: String
    let practiceType: PracticeType
    /// The scripture that motivates this practice.
    let motivatingPassage: String?
    let suggestedFrequency: String?    // e.g. "Daily", "Weekly"
    var status: PracticeStatus
    let suggestedAt: Date
    var acceptedAt: Date?
    var dismissedAt: Date?

    enum PracticeType: String, Codable {
        case prayer             = "prayer"
        case fasting            = "fasting"
        case meditation         = "meditation"    // Lectio Divina / contemplative
        case journaling         = "journaling"
        case scripture          = "scripture_reading"
        case memorization       = "memorization"
        case service            = "service"
        case accountability     = "accountability"
        case sabbath            = "sabbath"
        case gratitude          = "gratitude"
        case confession         = "confession"    // Private; handled with care
        case worship            = "worship"
    }

    enum PracticeStatus: String, Codable {
        case suggested  = "suggested"
        case accepted   = "accepted"
        case active     = "active"
        case completed  = "completed"
        case dismissed  = "dismissed"
    }
}

// MARK: - Reflection Entry

/// A private journal/reflection entry the user writes in response to a study.
/// Firestore: /users/{uid}/reflectionEntries/{entryId}
struct DiscipleshipReflectionEntry: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    /// The reflection prompt that was answered.
    let promptText: String
    /// The user's response.
    let responseText: String
    /// Scripture reference this reflection is anchored to.
    let passageReference: String?
    let bereanSessionId: String?
    let createdAt: Date
    /// Whether the user has shared this with a connected leader.
    var sharedWithLeader: Bool
}

// MARK: - Follow-Up Prompt

/// A system-generated follow-up to continue a study session at a later time.
/// Stored and surfaced by the Guided Discipleship Engine.
/// Firestore: /users/{uid}/followUpPrompts/{promptId}
struct FollowUpPrompt: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let promptText: String
    /// The previous session this follows up on.
    let sourceSessionId: String?
    /// The scripture this prompt is anchored to.
    let passageReference: String?
    let scheduledFor: Date?
    var status: FollowUpStatus
    let createdAt: Date
    var dismissedAt: Date?
    var engagedAt: Date?

    enum FollowUpStatus: String, Codable {
        case pending    = "pending"
        case delivered  = "delivered"
        case engaged    = "engaged"
        case dismissed  = "dismissed"
        case expired    = "expired"
    }
}

// MARK: - Leader Connection

/// A connection between a user and a pastor/mentor who can view their
/// discipleship profile with consent.
/// Firestore: /users/{uid}/leaderConnections/{connectionId}
struct LeaderConnection: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let leaderUserId: String
    let leaderDisplayName: String
    let leaderRole: String?            // e.g. "Pastor", "Mentor", "Small Group Leader"
    var consentGranted: Bool           // User must explicitly grant consent
    var profileSharingEnabled: Bool    // Whether growth data is shared
    let connectedAt: Date
    var revokedAt: Date?
}

// MARK: - Leadership Referral

/// A specific referral generated by the Authority Alignment system when a topic
/// exceeds AI scope and needs human pastoral wisdom.
/// Firestore: leadership_referrals/{referralId}
struct LeadershipReferral: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let leaderUserId: String?          // Targeted leader if known; nil if general
    let triggerFlag: SensitivityFlag   // The sensitivity flag that triggered this
    let contextSummary: String         // Brief, privacy-respecting summary for the leader
    let suggestedNextStep: String      // What the AI suggested the user do
    var status: ReferralStatus
    let createdAt: Date
    var acknowledgedAt: Date?
    var resolvedAt: Date?

    enum ReferralStatus: String, Codable {
        case pending        = "pending"
        case notified       = "notified"
        case acknowledged   = "acknowledged"
        case resolved       = "resolved"
        case expired        = "expired"
    }
}
