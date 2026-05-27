// AmenConversationOSModels.swift
// AMEN Intelligent Conversation OS — Core Models
//
// Shared data layer for all Conversation OS surfaces: spaces, group messages,
// church discussions, classrooms, leadership rooms, prayer groups, and org hubs.

import Foundation

// MARK: - Surface Classification

enum ConversationOSSurface: String, Codable, CaseIterable {
    case amenSpaces        = "amen_spaces"
    case directMessages    = "direct_messages"
    case groupMessages     = "group_messages"
    case churchDiscussion  = "church_discussion"
    case prayerRoom        = "prayer_room"
    case bereanStudy       = "berean_study"
    case eventChat         = "event_chat"
    case leadershipRoom    = "leadership_room"
    case creatorCommunity  = "creator_community"
    case classroomDiscussion = "classroom_discussion"
    case mediaComments     = "media_comments"
    case orgHub            = "org_hub"
    case adminChannel      = "admin_channel"

    var isSensitive: Bool {
        switch self {
        case .prayerRoom, .leadershipRoom, .adminChannel: return true
        default: return false
        }
    }

    var requiresExplicitOptIn: Bool { isSensitive }

    var displayName: String {
        switch self {
        case .amenSpaces:          return "Spaces"
        case .directMessages:      return "Direct Messages"
        case .groupMessages:       return "Group"
        case .churchDiscussion:    return "Church Discussion"
        case .prayerRoom:          return "Prayer Room"
        case .bereanStudy:         return "Berean Study"
        case .eventChat:           return "Event Chat"
        case .leadershipRoom:      return "Leadership"
        case .creatorCommunity:    return "Creator Community"
        case .classroomDiscussion: return "Classroom"
        case .mediaComments:       return "Media Comments"
        case .orgHub:              return "Organization Hub"
        case .adminChannel:        return "Admin"
        }
    }
}

// MARK: - Organization Type

enum ConversationOSOrgType: String, Codable {
    case church
    case school
    case business
    case enterprise
    case ministry
    case creatorCommunity  = "creator_community"
    case prayerGroup       = "prayer_group"
    case studyGroup        = "study_group"
    case leadershipTeam    = "leadership_team"
    case event
    case operationalTeam   = "operational_team"
}

// MARK: - User Role

enum ConversationOSUserRole: String, Codable {
    case teacher
    case student
    case churchLeader    = "church_leader"
    case volunteer
    case businessManager = "business_manager"
    case creator
    case moderator
    case admin
    case groupMember     = "group_member"
}

// MARK: - Semantic Tags

enum ConversationSemanticTag: String, Codable, CaseIterable {
    case decision
    case question
    case announcement
    case task
    case prayerRequest   = "prayer_request"
    case teachingMoment  = "teaching_moment"
    case blocker
    case reminder
    case conflict
    case escalation
    case encouragement
    case consensus
}

// MARK: - Topic Cluster

struct ConversationTopicCluster: Identifiable, Codable {
    let id: String
    let title: String
    let summary: String
    let tags: [ConversationSemanticTag]
    let messageCount: Int
    let participantCount: Int
    let createdAt: Date
    let updatedAt: Date
    let confidence: Double
    var messages: [ConversationMessageRef]

    var confidencePrefix: String {
        confidence >= 0.75 ? "" : "Discussion appears to suggest: "
    }
}

// MARK: - Message Reference

struct ConversationMessageRef: Identifiable, Codable {
    let id: String
    let senderId: String
    let senderDisplayName: String
    let preview: String
    let timestamp: Date
    let threadId: String
}

// MARK: - Summary Provenance

struct ConversationSummaryProvenance: Codable {
    let provider: String
    let modelVersion: String
    let generatedAt: Date
    let compressionRatio: Double
    let moderationPassed: Bool
    let permissionsValidated: Bool
}

// MARK: - Conversation Summary

struct ConversationSummary: Identifiable, Codable {
    let id: String
    let spaceId: String
    let threadId: String?
    let surface: ConversationOSSurface
    let summaryText: String
    let summaryType: ConversationSummaryType
    let topicClusters: [ConversationTopicCluster]
    let decisions: [ConversationDecision]
    let actionItems: [ConversationActionItem]
    let unresolvedQuestions: [ConversationUnresolvedQuestion]
    let blockers: [ConversationBlocker]
    let generatedAt: Date
    let coverageWindowStart: Date
    let coverageWindowEnd: Date
    let messageCount: Int
    let confidence: Double
    let provenance: ConversationSummaryProvenance

    var isHighConfidence: Bool { confidence >= 0.75 }

    var confidenceLabel: String {
        isHighConfidence ? "" : "Discussion appears to suggest: "
    }
}

enum ConversationSummaryType: String, Codable {
    case catchUp       = "catch_up"
    case decision      = "decision"
    case operational   = "operational"
    case educational   = "educational"
    case reflection    = "reflection"
    case community     = "community"
    case unresolved    = "unresolved"
    case weeklyMemory  = "weekly_memory"
    case prayerDigest  = "prayer_digest"
}

// MARK: - Action Items

struct ConversationActionItem: Identifiable, Codable {
    let id: String
    let title: String
    let description: String
    let assigneeId: String?
    let assigneeDisplayName: String?
    let dueDate: Date?
    let sourceMessageId: String
    let threadId: String
    var status: ConversationActionStatus
    let createdAt: Date
    let confidence: Double
}

enum ConversationActionStatus: String, Codable {
    case pending
    case inProgress  = "in_progress"
    case resolved
    case dismissed
}

// MARK: - Decisions

struct ConversationDecision: Identifiable, Codable {
    let id: String
    let summary: String
    let sourceSnippet: String
    let participants: [String]
    let confirmedBy: [String]
    var status: ConversationDecisionStatus
    let threadId: String
    let createdAt: Date
    let confidence: Double
}

enum ConversationDecisionStatus: String, Codable {
    case proposed
    case confirmed
    case challenged
    case outdated
}

// MARK: - Unresolved Questions

struct ConversationUnresolvedQuestion: Identifiable, Codable {
    let id: String
    let question: String
    let sourceSnippet: String
    let askedByDisplayName: String
    let threadId: String
    let askedAt: Date
    var dismissed: Bool
}

// MARK: - Blockers

struct ConversationBlocker: Identifiable, Codable {
    let id: String
    let description: String
    let sourceSnippet: String
    let threadId: String
    let detectedAt: Date
    var resolved: Bool
    let confidence: Double
}

// MARK: - Follow-Ups

struct ConversationFollowUp: Identifiable, Codable {
    let id: String
    let description: String
    let targetUserId: String?
    let targetDisplayName: String?
    let threadId: String
    let dueDate: Date?
    var status: ConversationActionStatus
    let createdAt: Date
}

// MARK: - Organizational Memory

struct ConversationOrganizationalMemory: Identifiable, Codable {
    let id: String
    let orgId: String
    let weekLabel: String
    let recurringTopics: [String]
    let keyDecisions: [ConversationDecision]
    let unresolvedItems: [ConversationUnresolvedQuestion]
    let collaborationPatterns: [String]
    let generatedAt: Date
    let summaryText: String
}

// MARK: - Priority Signal

struct ConversationPrioritySignal: Identifiable, Codable {
    let id: String
    let type: ConversationPriorityType
    let title: String
    let description: String
    let urgency: ConversationUrgency
    let threadId: String
    let spaceId: String
    let relevantToRoles: [ConversationOSUserRole]
    let createdAt: Date
    let score: Double
}

enum ConversationPriorityType: String, Codable {
    case mention
    case unresolvedQuestion  = "unresolved_question"
    case pendingDecision     = "pending_decision"
    case blocker
    case urgentThread        = "urgent_thread"
    case consensusForming    = "consensus_forming"
    case actionRequired      = "action_required"
}

enum ConversationUrgency: String, Codable, Comparable {
    case low, medium, high, critical

    private var order: Int {
        switch self {
        case .low: return 0; case .medium: return 1
        case .high: return 2; case .critical: return 3
        }
    }

    static func < (lhs: ConversationUrgency, rhs: ConversationUrgency) -> Bool {
        lhs.order < rhs.order
    }
}

// MARK: - Personalized Summary Request

struct PersonalizedSummaryRequest: Codable {
    let spaceId: String
    let surface: ConversationOSSurface
    let userRole: ConversationOSUserRole
    let orgType: ConversationOSOrgType
    let unreadCount: Int
    let lastVisitedAt: Date?
    let followedTopics: [String]
    let preferredLength: SummaryLength
}

enum SummaryLength: String, Codable {
    case brief, balanced, deep
}

// MARK: - Ingestion Event

struct ConversationIngestionEvent: Codable {
    let eventId: String
    let spaceId: String
    let threadId: String
    let eventType: IngestionEventType
    let senderId: String
    let timestamp: Date
}

enum IngestionEventType: String, Codable {
    case newMessage    = "new_message"
    case reply
    case reaction
    case edit
    case media
    case file
    case link
    case poll
    case task
    case mention
    case prayerRequest = "prayer_request"
    case studyPrompt   = "study_prompt"
    case event
}

// MARK: - Load State

enum ConversationOSLoadState: Equatable {
    case idle
    case loading
    case loaded
    case empty
    case error(String)
    case sensitiveSpaceBlocked

    static func == (lhs: ConversationOSLoadState, rhs: ConversationOSLoadState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.loaded, .loaded),
             (.empty, .empty), (.sensitiveSpaceBlocked, .sensitiveSpaceBlocked):
            return true
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}
