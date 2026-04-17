import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class UserIntelligenceOrchestrator: ObservableObject {

    static let shared = UserIntelligenceOrchestrator()

    @Published private(set) var latestRecommendations: [AgentRecommendation] = []
    @Published private(set) var isProcessing = false

    private let db = Firestore.firestore()
    private var cooldowns: [String: Date] = [:]
    private let defaultCooldownInterval: TimeInterval = 3600
    private let minimumSurfacingConfidence: Double = 0.40

    private init() {}

    func evaluate(context: UserContextWindow) async -> [AgentRecommendation] {
        guard AMENFeatureFlags.shared.compoundIdentityGraphEnabled else { return [] }
        isProcessing = true
        defer { isProcessing = false }

        let prioritySignals = computePriorities(for: context)
        let relevantAgents = prioritySignals
            .filter { $0.relevanceScore >= 0.25 }
            .sorted { $0.urgency > $1.urgency || ($0.urgency == $1.urgency && $0.relevanceScore > $1.relevanceScore) }

        var allRecommendations: [AgentRecommendation] = []
        for signal in relevantAgents.prefix(3) {
            allRecommendations.append(contentsOf: evaluateAgent(signal.agentType, context: context))
        }

        let filtered = allRecommendations.filter { rec in
            guard rec.confidence >= minimumSurfacingConfidence else { return false }
            if let lastFired = cooldowns[rec.cooldownKey],
               Date().timeIntervalSince(lastFired) < defaultCooldownInterval {
                return false
            }
            return true
        }

        let result = Array(filtered.sorted { $0.priority > $1.priority }.prefix(5))
        for rec in result {
            cooldowns[rec.cooldownKey] = Date()
        }
        latestRecommendations = result
        await persistRecommendations(result, userId: context.userId)
        return result
    }

    private func computePriorities(for context: UserContextWindow) -> [AgentPrioritySignal] {
        var signals: [AgentPrioritySignal] = []
        let scriptureSurfaces = ["berean_chat", "church_notes", "prayer_wall", "wisdom_library"]
        if scriptureSurfaces.contains(context.currentSurface) {
            signals.append(.init(agentType: .berean, relevanceScore: 0.70, urgency: .normal, reason: "Scripture-related surface"))
        }
        if ["feed", "discovery", "profile"].contains(context.currentSurface) {
            signals.append(.init(agentType: .community, relevanceScore: 0.40, urgency: .low, reason: "Social surface"))
        }
        if context.recentPostCategories.contains("prayer") || context.recentPostCategories.contains("testimonies") {
            signals.append(.init(agentType: .growth, relevanceScore: 0.45, urgency: .normal, reason: "Growth content engagement"))
        }
        if AMENFeatureFlags.shared.trustSignalsEnabled {
            signals.append(.init(agentType: .trust, relevanceScore: 0.30, urgency: .low, reason: "Background trust computation"))
        }
        return signals
    }

    private func evaluateAgent(_ agentType: AgentType, context: UserContextWindow) -> [AgentRecommendation] {
        switch agentType {
        case .care:
            if let signal = context.sessionSignal, ["crisisContentDwell", "elevatedConcern"].contains(signal) {
                return [.init(id: UUID().uuidString, agentType: .care, userId: context.userId, targetSurface: .internalOnly, title: "Support resources available", body: "Consider surfacing crisis support resources", actionType: .surfaceResource, actionPayload: ["resourceType": "crisis"], confidence: 0.85, priority: 95, reasoning: "Session signal indicates elevated distress", createdAt: Date(), expiresAt: Date().addingTimeInterval(3600), status: .pending, cooldownKey: "\(context.userId)_care_crisis_\(signal)")]
            }
        case .growth:
            let prayerPosts = context.recentPostCategories.filter { $0 == "prayer" }
            if prayerPosts.count >= 1 {
                return [.init(id: UUID().uuidString, agentType: .growth, userId: context.userId, targetSurface: .internalOnly, title: "Prayer consistency detected", body: "User has been engaging with prayer content", actionType: .nudgeGrowth, actionPayload: ["area": "prayer_consistency"], confidence: 0.50, priority: 40, reasoning: "Recent prayer activity", createdAt: Date(), expiresAt: Date().addingTimeInterval(86_400), status: .pending, cooldownKey: "\(context.userId)_growth_prayer_consistency")]
            }
        default:
            break
        }
        return []
    }

    private func persistRecommendations(_ recommendations: [AgentRecommendation], userId: String) async {
        guard !recommendations.isEmpty, Auth.auth().currentUser?.uid == userId else { return }
        let batch = db.batch()
        for rec in recommendations {
            let ref = db.collection("users").document(userId)
                .collection("intelligence").document("recommendations")
                .collection("items").document(rec.id)
            try? batch.setData(from: rec, forDocument: ref)
        }
        try? await batch.commit()
    }
}
