//
//  UserIntelligenceOrchestrator.swift
//  AMENAPP
//
//  Lightweight orchestration pipeline for the Compound Identity Graph.
//  Routes context to relevant specialized agents, merges outputs,
//  ranks suggestions, and explains why each suggestion was produced.
//  Surfaces nothing if confidence is low.
//
//  This orchestrator does NOT have its own visible UI. It operates as
//  infrastructure that other services can query.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class UserIntelligenceOrchestrator: ObservableObject {
    
    static let shared = UserIntelligenceOrchestrator()
    
    @Published private(set) var latestRecommendations: [AgentRecommendation] = []
    @Published private(set) var isProcessing = false
    
    private let db = Firestore.firestore()
    
    // Agent services (lazy — only instantiated when the graph is enabled)
    private lazy var agentServices: [AgentType: AgentServiceProtocol] = {
        var services: [AgentType: AgentServiceProtocol] = [:]
        services[.berean] = BereanAgentAdapter()
        services[.care] = CareAgentService()
        services[.trust] = TrustAgentService()
        services[.growth] = GrowthAgentService()
        services[.community] = CommunityAgentService()
        services[.creator] = CreatorAgentService()
        return services
    }()
    
    // Cooldown per recommendation type: key → last timestamp
    private var cooldowns: [String: Date] = [:]
    private let defaultCooldownInterval: TimeInterval = 3600  // 1 hour
    
    // Minimum confidence to surface a recommendation
    private let minimumSurfacingConfidence: Double = 0.40
    
    private init() {}
    
    // MARK: - Feature Guard
    
    private var isEnabled: Bool {
        AMENFeatureFlags.shared.compoundIdentityGraphEnabled
    }
    
    // MARK: - Evaluate Context
    
    /// Main entry point: given a user context, determine which agents should
    /// respond and produce ranked recommendations.
    func evaluate(context: UserContextWindow) async -> [AgentRecommendation] {
        guard isEnabled else { return [] }
        isProcessing = true
        defer { isProcessing = false }
        
        // Step 1: Determine which agents are relevant
        let prioritySignals = computePriorities(for: context)
        
        // Step 2: Filter to agents above relevance threshold
        let relevantAgents = prioritySignals
            .filter { $0.relevanceScore >= 0.25 }
            .sorted { $0.urgency > $1.urgency || ($0.urgency == $1.urgency && $0.relevanceScore > $1.relevanceScore) }
        
        guard !relevantAgents.isEmpty else { return [] }
        
        // Step 3: Run relevant agents concurrently
        var allRecommendations: [AgentRecommendation] = []
        
        await withTaskGroup(of: [AgentRecommendation].self) { group in
            for signal in relevantAgents.prefix(3) {  // Max 3 concurrent agents
                guard let service = agentServices[signal.agentType] else { continue }
                let boundary = AgentPermissionBoundary.defaults(for: signal.agentType)
                
                group.addTask {
                    await service.evaluate(context: context, boundary: boundary)
                }
            }
            
            for await recommendations in group {
                allRecommendations.append(contentsOf: recommendations)
            }
        }
        
        // Step 4: Filter by confidence and cooldown
        let filtered = allRecommendations.filter { rec in
            guard rec.confidence >= minimumSurfacingConfidence else { return false }
            
            // Check cooldown
            if let lastFired = cooldowns[rec.cooldownKey],
               Date().timeIntervalSince(lastFired) < defaultCooldownInterval {
                return false
            }
            
            return true
        }
        
        // Step 5: Rank and deduplicate
        let ranked = filtered
            .sorted { $0.priority > $1.priority }
            .prefix(5)  // Max 5 recommendations at once
        
        let result = Array(ranked)
        
        // Update cooldowns
        for rec in result {
            cooldowns[rec.cooldownKey] = Date()
        }
        
        latestRecommendations = result
        
        // Persist for audit
        if !result.isEmpty {
            Task.detached {
                await self.persistRecommendations(Array(result))
            }
        }
        
        return result
    }
    
    // MARK: - Priority Computation
    
    private func computePriorities(for context: UserContextWindow) -> [AgentPrioritySignal] {
        var signals: [AgentPrioritySignal] = []
        
        // Care agent is relevant when session signals indicate distress
        if let sessionSignal = context.sessionSignal,
           ["mildDistress", "repeatedHeavyContent", "distressedScrolling",
            "crisisContentDwell", "elevatedConcern"].contains(sessionSignal) {
            signals.append(AgentPrioritySignal(
                agentType: .care,
                relevanceScore: sessionSignal == "elevatedConcern" ? 0.95 :
                               sessionSignal == "crisisContentDwell" ? 0.90 : 0.60,
                urgency: sessionSignal == "elevatedConcern" ? .urgent : .elevated,
                reason: "Session distress signal: \(sessionSignal)"
            ))
        }
        
        // Berean agent for scripture/prayer-related surfaces
        let scriptureSurfaces = ["berean_chat", "church_notes", "prayer_wall", "wisdom_library"]
        if scriptureSurfaces.contains(context.currentSurface) {
            signals.append(AgentPrioritySignal(
                agentType: .berean,
                relevanceScore: 0.70,
                urgency: .normal,
                reason: "User on scripture-related surface: \(context.currentSurface)"
            ))
        }
        
        // Growth agent for prayer/testimony categories
        let growthCategories = ["prayer", "testimonies"]
        let recentGrowthPosts = context.recentPostCategories.filter { growthCategories.contains($0) }
        if !recentGrowthPosts.isEmpty {
            signals.append(AgentPrioritySignal(
                agentType: .growth,
                relevanceScore: min(0.80, 0.30 + Double(recentGrowthPosts.count) * 0.15),
                urgency: .normal,
                reason: "Recent engagement with growth content"
            ))
        }
        
        // Community agent for social surfaces
        let socialSurfaces = ["feed", "discovery", "profile"]
        if socialSurfaces.contains(context.currentSurface) {
            signals.append(AgentPrioritySignal(
                agentType: .community,
                relevanceScore: 0.40,
                urgency: .low,
                reason: "User on social surface"
            ))
        }
        
        // Trust agent runs in background for all contexts
        if AMENFeatureFlags.shared.trustSignalsEnabled {
            signals.append(AgentPrioritySignal(
                agentType: .trust,
                relevanceScore: 0.30,
                urgency: .low,
                reason: "Background trust signal computation"
            ))
        }
        
        // Creator agent for studio/creation surfaces
        if context.currentSurface == "creator_studio" || context.currentSurface == "post_creation" {
            signals.append(AgentPrioritySignal(
                agentType: .creator,
                relevanceScore: 0.60,
                urgency: .normal,
                reason: "User on creation surface"
            ))
        }
        
        return signals
    }
    
    // MARK: - Persistence
    
    private func persistRecommendations(_ recommendations: [AgentRecommendation]) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let batch = db.batch()
        for rec in recommendations {
            let ref = db.collection("users").document(userId)
                .collection("intelligence").document("recommendations")
                .collection("items").document(rec.id)
            try? batch.setData(from: rec, forDocument: ref)
        }
        try? await batch.commit()
    }
    
    // MARK: - Cache Management
    
    func clearCache() {
        latestRecommendations.removeAll()
        cooldowns.removeAll()
    }
}

// MARK: - Agent Service Protocol

/// Protocol that all agent services must conform to.
protocol AgentServiceProtocol: Sendable {
    func evaluate(
        context: UserContextWindow,
        boundary: AgentPermissionBoundary
    ) async -> [AgentRecommendation]
}

// MARK: - Agent Service Implementations

/// Adapter for the existing BereanCoreService.
struct BereanAgentAdapter: AgentServiceProtocol {
    func evaluate(context: UserContextWindow, boundary: AgentPermissionBoundary) async -> [AgentRecommendation] {
        // Delegates to existing BereanCoreService for scripture recommendations
        // Returns empty when no relevant scripture is found
        guard boundary.canWriteRecommendations else { return [] }
        // The actual BereanCoreService integration happens through existing patterns.
        // This adapter provides the compound identity graph interface.
        return []
    }
}

/// Care Agent: emotional support, crisis detection, check-in suggestions.
struct CareAgentService: AgentServiceProtocol {
    func evaluate(context: UserContextWindow, boundary: AgentPermissionBoundary) async -> [AgentRecommendation] {
        guard boundary.canWriteRecommendations else { return [] }
        
        var recommendations: [AgentRecommendation] = []
        
        // If session indicates distress, suggest check-in resources
        if let signal = context.sessionSignal {
            switch signal {
            case "crisisContentDwell", "elevatedConcern":
                recommendations.append(AgentRecommendation(
                    id: UUID().uuidString,
                    agentType: .care,
                    userId: context.userId,
                    targetSurface: .internalOnly,
                    title: "Support resources available",
                    body: "Consider surfacing crisis support resources",
                    actionType: .surfaceResource,
                    actionPayload: ["resourceType": "crisis"],
                    confidence: 0.85,
                    priority: 95,
                    reasoning: "Session signal indicates elevated distress: \(signal)",
                    createdAt: Date(),
                    expiresAt: Calendar.current.date(byAdding: .hour, value: 1, to: Date())!,
                    status: .pending,
                    cooldownKey: "\(context.userId)_care_crisis_\(signal)"
                ))
            case "distressedScrolling", "repeatedHeavyContent":
                recommendations.append(AgentRecommendation(
                    id: UUID().uuidString,
                    agentType: .care,
                    userId: context.userId,
                    targetSurface: .internalOnly,
                    title: "Gentle check-in opportunity",
                    body: "User may benefit from a break or reflection prompt",
                    actionType: .suggestCheckIn,
                    actionPayload: nil,
                    confidence: 0.55,
                    priority: 60,
                    reasoning: "Behavioral signal suggests repeated heavy content exposure",
                    createdAt: Date(),
                    expiresAt: Calendar.current.date(byAdding: .hour, value: 2, to: Date())!,
                    status: .pending,
                    cooldownKey: "\(context.userId)_care_checkin_\(signal)"
                ))
            default:
                break
            }
        }
        
        return recommendations
    }
}

/// Trust Agent: background trust signal computation.
struct TrustAgentService: AgentServiceProtocol {
    func evaluate(context: UserContextWindow, boundary: AgentPermissionBoundary) async -> [AgentRecommendation] {
        // Trust agent produces insights, not user-facing recommendations
        // It feeds into the ProofOfHumanService and ProofOfCareService
        return []
    }
}

/// Growth Agent: spiritual growth nudges and reflection prompts.
struct GrowthAgentService: AgentServiceProtocol {
    func evaluate(context: UserContextWindow, boundary: AgentPermissionBoundary) async -> [AgentRecommendation] {
        guard boundary.canWriteRecommendations else { return [] }
        
        // Suggest growth-related follow-ups based on recent activity
        let prayerPosts = context.recentPostCategories.filter { $0 == "prayer" }
        if prayerPosts.count >= 2 {
            return [AgentRecommendation(
                id: UUID().uuidString,
                agentType: .growth,
                userId: context.userId,
                targetSurface: .internalOnly,
                title: "Prayer consistency detected",
                body: "User has been engaging with prayer content regularly",
                actionType: .nudgeGrowth,
                actionPayload: ["area": "prayer_consistency"],
                confidence: 0.50,
                priority: 40,
                reasoning: "\(prayerPosts.count) prayer posts in recent activity window",
                createdAt: Date(),
                expiresAt: Calendar.current.date(byAdding: .day, value: 1, to: Date())!,
                status: .pending,
                cooldownKey: "\(context.userId)_growth_prayer_consistency"
            )]
        }
        return []
    }
}

/// Community Agent: social connection suggestions.
struct CommunityAgentService: AgentServiceProtocol {
    func evaluate(context: UserContextWindow, boundary: AgentPermissionBoundary) async -> [AgentRecommendation] {
        // Community suggestions are handled by existing RecommendationIntelligenceService
        // This agent provides the compound identity graph interface
        return []
    }
}

/// Creator Agent: content creation assistance.
struct CreatorAgentService: AgentServiceProtocol {
    func evaluate(context: UserContextWindow, boundary: AgentPermissionBoundary) async -> [AgentRecommendation] {
        // Creator suggestions are handled by existing ComposerInsightEngine
        return []
    }
}
