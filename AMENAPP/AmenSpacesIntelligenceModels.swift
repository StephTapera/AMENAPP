// AmenSpacesIntelligenceModels.swift
// AMEN App — Spaces Ambient Intelligence OS: Core Models
//
// Extends AMENSpace with intelligence layers. Does NOT replace ConversationOSModels —
// these types compose with ConversationSummary, ConversationTopicCluster, etc.
// All AI-generated fields are server-write only (enforced in Firestore rules).

import Foundation
import FirebaseFirestore

// MARK: - Space Intelligence Context

/// The type of a Space determines which intelligence features are enabled.
enum AmenSpaceType: String, Codable, CaseIterable {
    case churchMinistry      = "church_ministry"
    case prayerGroup         = "prayer_group"
    case sermonPrep          = "sermon_prep"
    case bibleStudy          = "bible_study"
    case schoolClassroom     = "school_classroom"
    case leadershipRoom      = "leadership_room"
    case operationsHub       = "operations_hub"
    case creatorCommunity    = "creator_community"
    case familyGroup         = "family_group"
    case discipleshipCohort  = "discipleship_cohort"
    case eventWorkspace      = "event_workspace"
    case supportCommunity    = "support_community"

    /// Support/recovery spaces block all AI inference.
    var aiInferenceAllowed: Bool {
        switch self {
        case .supportCommunity: return false
        default: return true
        }
    }

    /// Prayer groups and leadership rooms require explicit opt-in for summaries.
    var requiresSummaryOptIn: Bool {
        switch self {
        case .prayerGroup, .leadershipRoom: return true
        default: return false
        }
    }

    /// Emotional context signals are suppressed for family groups to protect privacy.
    var emotionalContextAllowed: Bool {
        switch self {
        case .familyGroup, .supportCommunity: return false
        default: return true
        }
    }
}

// MARK: - Persistent Memory Graph Node

enum AmenMemoryLayer: String, Codable {
    case user           = "user"
    case relationship   = "relationship"
    case group          = "group"
    case spiritual      = "spiritual"
    case organizational = "organizational"
    case temporal       = "temporal"
}

struct AmenMemoryNode: Identifiable, Codable {
    let id: String
    let spaceId: String
    let userId: String?
    let layer: AmenMemoryLayer
    let title: String
    let body: String
    let tags: [String]
    let scriptureRefs: [String]
    let relatedNodeIds: [String]
    let confidence: Double
    let generatedAt: Date
    let expiresAt: Date?
    var dismissed: Bool

    /// Server-generated. Never set from client.
    let provenance: String

    var isActive: Bool {
        guard let exp = expiresAt else { return !dismissed }
        return !dismissed && exp > Date()
    }

    var humblePrefix: String {
        confidence >= 0.78 ? "" : "A recurring theme appears to be: "
    }
}

// MARK: - Semantic Pin

enum AmenPinType: String, Codable, CaseIterable {
    // Spiritual pins
    case prayer         = "prayer"
    case scripture      = "scripture"
    case reflection     = "reflection"
    case testimony      = "testimony"

    // Organizational pins
    case task           = "task"
    case announcement   = "announcement"
    case meeting        = "meeting"
    case decision       = "decision"

    // Intelligent pins (server-assigned)
    case highlyReferenced  = "highly_referenced"
    case emotionallyImportant = "emotionally_important"
    case unresolved        = "unresolved"
    case requiresFollowUp  = "requires_follow_up"

    // Dynamic pins (evolve over time)
    case momentumBuilding  = "momentum_building"
    case fadingUrgency     = "fading_urgency"
    case resolved          = "resolved"

    var isIntelligent: Bool {
        switch self {
        case .highlyReferenced, .emotionallyImportant, .unresolved, .requiresFollowUp,
             .momentumBuilding, .fadingUrgency, .resolved:
            return true
        default:
            return false
        }
    }

    var icon: String {
        switch self {
        case .prayer:            return "hands.sparkles.fill"
        case .scripture:         return "book.closed.fill"
        case .reflection:        return "moon.stars.fill"
        case .testimony:         return "star.fill"
        case .task:              return "checkmark.circle.fill"
        case .announcement:      return "megaphone.fill"
        case .meeting:           return "calendar.circle.fill"
        case .decision:          return "checkmark.seal.fill"
        case .highlyReferenced:  return "arrow.triangle.2.circlepath"
        case .emotionallyImportant: return "heart.fill"
        case .unresolved:        return "questionmark.circle.fill"
        case .requiresFollowUp:  return "arrow.clockwise.circle.fill"
        case .momentumBuilding:  return "flame.fill"
        case .fadingUrgency:     return "hourglass"
        case .resolved:          return "checkmark.circle.fill"
        }
    }
}

struct AmenSemanticPin: Identifiable, Codable {
    let id: String
    let spaceId: String
    let threadId: String?
    let messageId: String?
    let pinnedBy: String
    let pinType: AmenPinType
    let title: String
    let preview: String
    let tags: [String]
    let scriptureRef: String?
    let score: Double
    let createdAt: Date
    var updatedAt: Date
    var evolutionHistory: [AmenPinEvolutionEvent]

    var isServerGenerated: Bool { pinType.isIntelligent }
}

struct AmenPinEvolutionEvent: Codable {
    let fromType: AmenPinType
    let toType: AmenPinType
    let reason: String
    let occurredAt: Date
}

// MARK: - Ambient Intelligence Signal

enum AmenAmbientSignalType: String, Codable {
    case prayerRequestUpdated    = "prayer_request_updated"
    case relatedToSermon         = "related_to_sermon"
    case convergingTheme         = "converging_theme"
    case unresolvedFollowUp      = "unresolved_follow_up"
    case participationDrop       = "participation_drop"
    case bibleStudyLink          = "bible_study_link"
    case leadershipActionNeeded  = "leadership_action_needed"
    case spiritualThemeRecurring = "spiritual_theme_recurring"
}

struct AmenAmbientSignal: Identifiable, Codable {
    let id: String
    let spaceId: String
    let signalType: AmenAmbientSignalType
    let title: String
    let body: String
    let confidence: Double
    let relevantToUserId: String?
    let threadId: String?
    let createdAt: Date
    var dismissed: Bool

    /// Humble, non-authoritative language only.
    var displayBody: String {
        confidence >= 0.75 ? body : "This may relate to: \(body)"
    }
}

// MARK: - Multi-Thread Branch

struct AmenThreadBranch: Identifiable, Codable {
    let id: String
    let parentThreadId: String
    let spaceId: String
    let title: String
    let branchType: AmenBranchType
    let createdBy: String
    let createdAt: Date
    var messageCount: Int
    var participantCount: Int
    var summary: String?
    var isResolved: Bool
}

enum AmenBranchType: String, Codable, CaseIterable {
    case theology        = "theology"
    case counseling      = "counseling"
    case prayer          = "prayer"
    case operations      = "operations"
    case youthDiscussion = "youth_discussion"
    case leadershipFollowUp = "leadership_follow_up"
    case studyDeepDive   = "study_deep_dive"
    case general         = "general"

    var icon: String {
        switch self {
        case .theology:         return "book.pages"
        case .counseling:       return "person.2.fill"
        case .prayer:           return "hands.sparkles.fill"
        case .operations:       return "gearshape.fill"
        case .youthDiscussion:  return "person.3.fill"
        case .leadershipFollowUp: return "crown.fill"
        case .studyDeepDive:    return "magnifyingglass.circle.fill"
        case .general:          return "bubble.left.and.bubble.right.fill"
        }
    }
}

// MARK: - Catch-Up Intelligence Layer

enum AmenCatchUpLayer: String, Codable, CaseIterable {
    case emotional       = "emotional"
    case organizational  = "organizational"
    case spiritual       = "spiritual"
    case personal        = "personal"

    var displayName: String {
        switch self {
        case .emotional:      return "Emotional"
        case .organizational: return "Organizational"
        case .spiritual:      return "Spiritual"
        case .personal:       return "Personal"
        }
    }

    var icon: String {
        switch self {
        case .emotional:      return "heart.fill"
        case .organizational: return "building.2.fill"
        case .spiritual:      return "sparkles"
        case .personal:       return "person.fill"
        }
    }
}

struct AmenCatchUpIntelligence: Identifiable, Codable {
    let id: String
    let spaceId: String
    let userId: String
    let generatedAt: Date
    let coverageWindowStart: Date
    let coverageWindowEnd: Date
    let emotionalLayer: AmenCatchUpEmotionalLayer?
    let organizationalLayer: AmenCatchUpOrgLayer?
    let spiritualLayer: AmenCatchUpSpiritualLayer?
    let personalLayer: AmenCatchUpPersonalLayer?
    let confidence: Double
    var dismissed: Bool
}

struct AmenCatchUpEmotionalLayer: Codable {
    let urgencyLevel: String
    let prayerIntensity: String
    let encouragementHighlights: [String]
    let tensionIndicators: [String]

    var isEmpty: Bool {
        urgencyLevel.isEmpty && prayerIntensity.isEmpty
            && encouragementHighlights.isEmpty && tensionIndicators.isEmpty
    }
}

struct AmenCatchUpOrgLayer: Codable {
    let decisions: [String]
    let blockers: [String]
    let deadlines: [String]
    let unresolvedItems: Int

    var isEmpty: Bool {
        decisions.isEmpty && blockers.isEmpty && deadlines.isEmpty && unresolvedItems == 0
    }
}

struct AmenCatchUpSpiritualLayer: Codable {
    let scriptureThemes: [String]
    let theologicalDevelopments: [String]
    let prayerOutcomes: [String]
    let recurringVerses: [String]

    var isEmpty: Bool {
        scriptureThemes.isEmpty && theologicalDevelopments.isEmpty
            && prayerOutcomes.isEmpty && recurringVerses.isEmpty
    }
}

struct AmenCatchUpPersonalLayer: Codable {
    let mentionsForUser: [String]
    let closePeopleUpdates: [String]
    let unresolvedResponses: [String]

    var isEmpty: Bool {
        mentionsForUser.isEmpty && closePeopleUpdates.isEmpty && unresolvedResponses.isEmpty
    }
}

// MARK: - Spiritual Continuity

struct AmenSpiritualContinuityRecord: Identifiable, Codable {
    let id: String
    let userId: String
    let spaceId: String?
    let theme: String
    let scriptureJourney: [String]
    let recurringPrayerTopics: [String]
    let unfinishedReflections: [String]
    let selahMoments: Int
    let discipleshipContinuityScore: Double
    let lastActivityAt: Date
    let generatedAt: Date

    /// Language is always humble — never claims spiritual certainty.
    var reflectionPrompt: String {
        "You may want to revisit: \(theme)"
    }
}

// MARK: - Presence-Aware UI Mode

enum AmenPresenceUIMode: String, Codable, CaseIterable {
    case prayer        = "prayer"
    case leadership    = "leadership"
    case study         = "study"
    case counseling    = "counseling"
    case worship       = "worship"
    case focus         = "focus"
    case classroom     = "classroom"
    case operations    = "operations"
    case ambient       = "ambient"

    var isCalm: Bool { true }

    var suggestedSelahActive: Bool {
        switch self {
        case .prayer, .worship: return true
        default: return false
        }
    }
}

// MARK: - Intent-Aware Search Result

struct AmenIntentSearchResult: Identifiable, Codable {
    let id: String
    let query: String
    let matchType: AmenSearchMatchType
    let title: String
    let preview: String
    let spaceId: String?
    let threadId: String?
    let messageId: String?
    let scriptureRef: String?
    let timestamp: Date
    let relevanceScore: Double

    var humbleRelevanceNote: String? {
        relevanceScore < 0.65 ? "This may be related to your search." : nil
    }
}

enum AmenSearchMatchType: String, Codable {
    case exactMessage    = "exact_message"
    case topicCluster    = "topic_cluster"
    case scriptureRef    = "scripture_ref"
    case prayerRequest   = "prayer_request"
    case decision        = "decision"
    case semanticTheme   = "semantic_theme"
    case memoryNode      = "memory_node"
}
