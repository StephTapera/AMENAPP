import Foundation

enum AgentType: String, Codable, CaseIterable {
    case berean = "berean"
    case care = "care"
    case trust = "trust"
    case growth = "growth"
    case community = "community"
    case creator = "creator"
}

enum AgentInputSurface: String, Codable {
    case posts = "posts"
    case comments = "comments"
    case bereanChat = "berean_chat"
    case churchNotes = "church_notes"
    case prayerRequests = "prayer_requests"
    case behavioralSignals = "behavioral_signals"
    case sessionState = "session_state"
    case crisisSignals = "crisis_signals"
    case composerIntegrity = "composer_integrity"
    case moderationHistory = "moderation_history"
    case accountMetadata = "account_metadata"
    case interactionPatterns = "interaction_patterns"
    case followGraph = "follow_graph"
    case mutuals = "mutuals"
    case churchMembership = "church_membership"
    case groupActivity = "group_activity"
    case checkIns = "check_ins"
    case creatorStudio = "creator_studio"
    case audienceMetrics = "audience_metrics"
    case contentPerformance = "content_performance"
}

struct AgentPermissionBoundary: Codable, Equatable {
    let agentType: AgentType
    let canReadUserContent: Bool
    let canReadOtherUserContent: Bool
    let canWriteInsights: Bool
    let canWriteRecommendations: Bool
    let canTriggerNotifications: Bool
    let canAccessSensitiveData: Bool
    let maxMemoryItems: Int
    let memoryRetentionDays: Int

    static func defaults(for agentType: AgentType) -> AgentPermissionBoundary {
        switch agentType {
        case .berean:
            return .init(agentType: .berean, canReadUserContent: true, canReadOtherUserContent: false, canWriteInsights: true, canWriteRecommendations: true, canTriggerNotifications: false, canAccessSensitiveData: false, maxMemoryItems: 200, memoryRetentionDays: 90)
        case .care:
            return .init(agentType: .care, canReadUserContent: true, canReadOtherUserContent: false, canWriteInsights: true, canWriteRecommendations: true, canTriggerNotifications: true, canAccessSensitiveData: true, maxMemoryItems: 100, memoryRetentionDays: 30)
        case .trust:
            return .init(agentType: .trust, canReadUserContent: false, canReadOtherUserContent: false, canWriteInsights: true, canWriteRecommendations: false, canTriggerNotifications: false, canAccessSensitiveData: true, maxMemoryItems: 50, memoryRetentionDays: 180)
        case .growth:
            return .init(agentType: .growth, canReadUserContent: true, canReadOtherUserContent: false, canWriteInsights: true, canWriteRecommendations: true, canTriggerNotifications: true, canAccessSensitiveData: false, maxMemoryItems: 150, memoryRetentionDays: 365)
        case .community:
            return .init(agentType: .community, canReadUserContent: false, canReadOtherUserContent: true, canWriteInsights: true, canWriteRecommendations: true, canTriggerNotifications: false, canAccessSensitiveData: false, maxMemoryItems: 100, memoryRetentionDays: 60)
        case .creator:
            return .init(agentType: .creator, canReadUserContent: true, canReadOtherUserContent: false, canWriteInsights: true, canWriteRecommendations: true, canTriggerNotifications: false, canAccessSensitiveData: false, maxMemoryItems: 100, memoryRetentionDays: 90)
        }
    }
}

struct AgentRecommendation: Codable, Identifiable, Equatable {
    let id: String
    let agentType: AgentType
    let userId: String
    let targetSurface: RecommendationSurface
    let title: String
    let body: String?
    let actionType: RecommendationAction
    let actionPayload: [String: String]?
    let confidence: Double
    let priority: Int
    let reasoning: String
    let createdAt: Date
    let expiresAt: Date
    var status: RecommendationStatus
    let cooldownKey: String

    enum RecommendationSurface: String, Codable {
        case internalOnly = "internal_only"
    }

    enum RecommendationAction: String, Codable {
        case surfaceResource = "surface_resource"
        case suggestCheckIn = "suggest_check_in"
        case nudgeGrowth = "nudge_growth"
    }

    enum RecommendationStatus: String, Codable {
        case pending = "pending"
        case surfaced = "surfaced"
        case accepted = "accepted"
        case dismissed = "dismissed"
        case expired = "expired"
    }
}

struct AgentPrioritySignal: Codable, Equatable {
    let agentType: AgentType
    let relevanceScore: Double
    let urgency: Urgency
    let reason: String

    enum Urgency: String, Codable, Comparable {
        case low = "low"
        case normal = "normal"
        case elevated = "elevated"
        case urgent = "urgent"

        static func < (lhs: Urgency, rhs: Urgency) -> Bool {
            let order: [Urgency] = [.low, .normal, .elevated, .urgent]
            return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
        }
    }
}

struct UserContextWindow: Equatable {
    let userId: String
    let currentSurface: String
    let sessionSignal: String?
    let recentPostCategories: [String]
    let recentActionTypes: [String]
    let accountAgeDays: Int
    let isMinor: Bool
    let trustTier: String
    let activeActionThreadCount: Int
    let timestamp: Date
}
