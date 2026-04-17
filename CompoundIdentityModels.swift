//
//  CompoundIdentityModels.swift
//  AMENAPP
//
//  Domain models for the Compound Identity Graph — a system of scoped
//  intelligence agents per user. Each agent operates as a service-level
//  specialist, not a visible chatbot. Agents have bounded inputs, outputs,
//  permissions, and memory scopes.
//
//  Firestore paths:
//    users/{userId}/intelligence/profile
//    users/{userId}/intelligence/agentInsights/{insightId}
//    users/{userId}/intelligence/agentMemory/{agentType}
//

import Foundation

// MARK: - Agent Types

/// The six core intelligence agents in the AMEN compound identity system.
enum AgentType: String, Codable, CaseIterable {
    case berean    = "berean"       // Scripture, theology, biblical Q&A
    case care      = "care"         // Emotional support, crisis detection, check-ins
    case trust     = "trust"        // Authenticity, safety signals, risk assessment
    case growth    = "growth"       // Spiritual growth, habits, reflection prompts
    case community = "community"    // Social connections, church fit, group dynamics
    case creator   = "creator"      // Content creation, publishing, audience
    
    var displayName: String {
        switch self {
        case .berean:    return "Berean"
        case .care:      return "Care"
        case .trust:     return "Trust"
        case .growth:    return "Growth"
        case .community: return "Community"
        case .creator:   return "Creator"
        }
    }
    
    /// Surfaces this agent is allowed to read from.
    var allowedInputSurfaces: Set<AgentInputSurface> {
        switch self {
        case .berean:    return [.posts, .comments, .bereanChat, .churchNotes, .prayerRequests]
        case .care:      return [.posts, .prayerRequests, .behavioralSignals, .sessionState, .crisisSignals]
        case .trust:     return [.composerIntegrity, .moderationHistory, .accountMetadata, .interactionPatterns]
        case .growth:    return [.posts, .prayerRequests, .churchNotes, .bereanChat, .checkIns, .sessionState]
        case .community: return [.followGraph, .mutuals, .churchMembership, .groupActivity, .interactionPatterns]
        case .creator:   return [.posts, .creatorStudio, .audienceMetrics, .contentPerformance]
        }
    }
}

/// Surfaces that agents can read data from.
enum AgentInputSurface: String, Codable {
    case posts              = "posts"
    case comments           = "comments"
    case bereanChat         = "berean_chat"
    case churchNotes        = "church_notes"
    case prayerRequests     = "prayer_requests"
    case behavioralSignals  = "behavioral_signals"
    case sessionState       = "session_state"
    case crisisSignals      = "crisis_signals"
    case composerIntegrity  = "composer_integrity"
    case moderationHistory  = "moderation_history"
    case accountMetadata    = "account_metadata"
    case interactionPatterns = "interaction_patterns"
    case followGraph        = "follow_graph"
    case mutuals            = "mutuals"
    case churchMembership   = "church_membership"
    case groupActivity      = "group_activity"
    case checkIns           = "check_ins"
    case creatorStudio      = "creator_studio"
    case audienceMetrics    = "audience_metrics"
    case contentPerformance = "content_performance"
}

// MARK: - Agent Permission Boundary

/// Defines what an agent is allowed to do. Prevents unrestricted data access.
struct AgentPermissionBoundary: Codable, Equatable {
    let agentType: AgentType
    let canReadUserContent: Bool          // Can read user's own posts/notes
    let canReadOtherUserContent: Bool     // Can read other users' public content
    let canWriteInsights: Bool            // Can produce insights
    let canWriteRecommendations: Bool     // Can produce recommendations
    let canTriggerNotifications: Bool     // Can schedule/send notifications
    let canAccessSensitiveData: Bool      // Can read crisis/moderation data
    let maxMemoryItems: Int               // Max items in agent's memory scope
    let memoryRetentionDays: Int          // How long memory persists
    
    /// Default permission boundaries per agent type.
    static func defaults(for agentType: AgentType) -> AgentPermissionBoundary {
        switch agentType {
        case .berean:
            return AgentPermissionBoundary(
                agentType: .berean, canReadUserContent: true, canReadOtherUserContent: false,
                canWriteInsights: true, canWriteRecommendations: true,
                canTriggerNotifications: false, canAccessSensitiveData: false,
                maxMemoryItems: 200, memoryRetentionDays: 90
            )
        case .care:
            return AgentPermissionBoundary(
                agentType: .care, canReadUserContent: true, canReadOtherUserContent: false,
                canWriteInsights: true, canWriteRecommendations: true,
                canTriggerNotifications: true, canAccessSensitiveData: true,
                maxMemoryItems: 100, memoryRetentionDays: 30
            )
        case .trust:
            return AgentPermissionBoundary(
                agentType: .trust, canReadUserContent: false, canReadOtherUserContent: false,
                canWriteInsights: true, canWriteRecommendations: false,
                canTriggerNotifications: false, canAccessSensitiveData: true,
                maxMemoryItems: 50, memoryRetentionDays: 180
            )
        case .growth:
            return AgentPermissionBoundary(
                agentType: .growth, canReadUserContent: true, canReadOtherUserContent: false,
                canWriteInsights: true, canWriteRecommendations: true,
                canTriggerNotifications: true, canAccessSensitiveData: false,
                maxMemoryItems: 150, memoryRetentionDays: 365
            )
        case .community:
            return AgentPermissionBoundary(
                agentType: .community, canReadUserContent: false, canReadOtherUserContent: true,
                canWriteInsights: true, canWriteRecommendations: true,
                canTriggerNotifications: false, canAccessSensitiveData: false,
                maxMemoryItems: 100, memoryRetentionDays: 60
            )
        case .creator:
            return AgentPermissionBoundary(
                agentType: .creator, canReadUserContent: true, canReadOtherUserContent: false,
                canWriteInsights: true, canWriteRecommendations: true,
                canTriggerNotifications: false, canAccessSensitiveData: false,
                maxMemoryItems: 100, memoryRetentionDays: 90
            )
        }
    }
}

// MARK: - Agent Insight

/// A single insight produced by an agent. Insights are the primary output of agents.
struct AgentInsight: Codable, Identifiable, Equatable {
    let id: String
    let agentType: AgentType
    let userId: String
    let category: InsightCategory
    let title: String                     // Short summary
    let content: String                   // Full insight text
    let confidence: Double                // 0.0–1.0
    let sourceSurface: AgentInputSurface  // What input produced this
    let sourceIds: [String]?              // Post IDs, note IDs, etc. that informed this
    let createdAt: Date
    let expiresAt: Date?                  // Insights can age out
    var isConsumed: Bool                  // Has this insight been surfaced/used
    let metadata: [String: String]?       // Arbitrary context
    
    enum InsightCategory: String, Codable {
        case spiritualTheme     = "spiritual_theme"
        case emotionalState     = "emotional_state"
        case growthOpportunity  = "growth_opportunity"
        case communitySignal    = "community_signal"
        case trustAssessment    = "trust_assessment"
        case careNeed           = "care_need"
        case contentSuggestion  = "content_suggestion"
        case scriptureRelevance = "scripture_relevance"
        case behavioralPattern  = "behavioral_pattern"
    }
}

// MARK: - Agent Recommendation

/// A recommendation from an agent to be surfaced somewhere in the app.
/// Recommendations are ranked and may be suppressed by confidence thresholds or cooldowns.
struct AgentRecommendation: Codable, Identifiable, Equatable {
    let id: String
    let agentType: AgentType
    let userId: String
    let targetSurface: RecommendationSurface
    let title: String
    let body: String?
    let actionType: RecommendationAction
    let actionPayload: [String: String]?  // Context for executing the action
    let confidence: Double                // 0.0–1.0
    let priority: Int                     // 0–100 ranking score
    let reasoning: String                 // Internal explanation of why this was produced
    let createdAt: Date
    let expiresAt: Date
    var status: RecommendationStatus
    let cooldownKey: String               // Dedup: "{userId}_{agentType}_{actionType}_{targetId}"
    
    enum RecommendationSurface: String, Codable {
        case postDetail     = "post_detail"
        case prayerWall     = "prayer_wall"
        case bereanChat     = "berean_chat"
        case feedInline     = "feed_inline"
        case notifications  = "notifications"
        case churchNotes    = "church_notes"
        case profile        = "profile"
        case internalOnly   = "internal_only"    // Never surfaced to user
    }
    
    enum RecommendationAction: String, Codable {
        case suggestActionThread  = "suggest_action_thread"
        case suggestScripture     = "suggest_scripture"
        case suggestCheckIn       = "suggest_check_in"
        case suggestPrayerCircle  = "suggest_prayer_circle"
        case suggestFollowUp      = "suggest_follow_up"
        case suggestConnection    = "suggest_connection"
        case surfaceResource      = "surface_resource"
        case nudgeGrowth          = "nudge_growth"
        case informational        = "informational"
    }
    
    enum RecommendationStatus: String, Codable {
        case pending    = "pending"
        case surfaced   = "surfaced"
        case accepted   = "accepted"
        case dismissed  = "dismissed"
        case expired    = "expired"
    }
}

// MARK: - Agent Memory

/// Scoped memory for a specific agent. Each agent has its own memory store.
struct AgentMemory: Codable, Identifiable, Equatable {
    let id: String                        // "{userId}_{agentType}"
    let agentType: AgentType
    let userId: String
    var entries: [MemoryEntry]
    var lastUpdatedAt: Date
    let maxEntries: Int                   // From AgentPermissionBoundary
    
    struct MemoryEntry: Codable, Equatable {
        let key: String                   // Topic/signal identifier
        let value: String                 // Stored observation
        let source: AgentInputSurface
        let recordedAt: Date
        let expiresAt: Date?
        let weight: Double                // 0.0–1.0 importance
    }
}

// MARK: - Agent Execution Log

/// Audit trail for agent operations. Tracks what each agent did and why.
struct AgentExecutionLog: Codable, Identifiable, Equatable {
    let id: String
    let agentType: AgentType
    let userId: String
    let action: String                    // What the agent did
    let inputSummary: String              // Brief description of input (no raw content)
    let outputSummary: String             // Brief description of output
    let confidence: Double
    let latencyMs: Int
    let timestamp: Date
    let wasSupressed: Bool                // True if output was below threshold
    let suppressionReason: String?
}

// MARK: - User Intelligence Profile

/// The root profile document for a user's compound identity graph.
/// Firestore: users/{userId}/intelligence/profile
struct UserIntelligenceProfile: Codable, Equatable {
    let userId: String
    var activeAgents: Set<AgentType>      // Which agents are enabled for this user
    var lastComputedAt: Date?
    var insightCount: Int
    var recommendationCount: Int
    
    // Aggregated signals from across agents (summary level only)
    var spiritualInterests: [String]?     // Topics the user engages with
    var careNeedSignals: [CareNeedSignal]?
    var communityFitSignals: [CommunityFitSignal]?
    var growthSignals: [GrowthSignal]?
    
    /// Lightweight signal structs for cross-agent aggregation.
    
    struct CareNeedSignal: Codable, Equatable {
        let category: String              // "grief", "anxiety", "illness", etc.
        let intensity: Double             // 0.0–1.0
        let detectedAt: Date
        let sourceAgentType: AgentType
    }
    
    struct CommunityFitSignal: Codable, Equatable {
        let category: String              // "church_engagement", "group_activity", etc.
        let strength: Double              // 0.0–1.0
        let detectedAt: Date
    }
    
    struct GrowthSignal: Codable, Equatable {
        let area: String                  // "prayer_consistency", "scripture_depth", etc.
        let trend: Trend                  // Improving, stable, declining
        let detectedAt: Date
        
        enum Trend: String, Codable {
            case improving = "improving"
            case stable    = "stable"
            case declining = "declining"
        }
    }
}

// MARK: - Agent Priority Signal

/// Used by the orchestrator to decide which agent(s) should respond to a given context.
struct AgentPrioritySignal: Codable, Equatable {
    let agentType: AgentType
    let relevanceScore: Double            // 0.0–1.0 how relevant this agent is
    let urgency: Urgency
    let reason: String                    // Brief explanation
    
    enum Urgency: String, Codable, Comparable {
        case low      = "low"
        case normal   = "normal"
        case elevated = "elevated"
        case urgent   = "urgent"
        
        static func < (lhs: Urgency, rhs: Urgency) -> Bool {
            let order: [Urgency] = [.low, .normal, .elevated, .urgent]
            return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
        }
    }
}

// MARK: - User Context Window

/// A snapshot of the user's current context, passed to agents for evaluation.
/// Contains only what's needed — no raw content, no PII beyond userId.
struct UserContextWindow: Equatable {
    let userId: String
    let currentSurface: String            // Which screen the user is on
    let sessionSignal: String?            // From BehavioralAwarenessEngine
    let recentPostCategories: [String]    // Last 5 post categories viewed
    let recentActionTypes: [String]       // Last 5 interaction types
    let accountAgeDays: Int
    let isMinor: Bool
    let trustTier: String                 // From MinorSafetyService
    let activeActionThreadCount: Int
    let timestamp: Date
}
