// CompoundIdentityGraphService.swift
// AMENAPP — Compound Identity Graph
//
// Service facade for the Compound Identity Graph system.
// Provides typed, permission-respecting write operations for agent insights
// and recommendations. Reads existing recommendations from Firestore and
// forwards evaluation requests to UserIntelligenceOrchestrator.
//
// This service is the single call-site entry point. The Orchestrator handles
// agent routing and prioritization. This service handles:
//   - Context window construction from available app state
//   - Insight + recommendation persistence (via Cloud Functions for server-auth)
//   - Fetching pending recommendations
//   - Insight expiry and cleanup
//
// Feature flag: compoundIdentityGraphEnabled must be true.

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

@MainActor
final class CompoundIdentityGraphService: ObservableObject {

    static let shared = CompoundIdentityGraphService()

    @Published private(set) var pendingRecommendations: [AgentRecommendation] = []

    private let db = Firestore.firestore()
    private let functions = Functions.functions()
    private let orchestrator = UserIntelligenceOrchestrator.shared

    private var recommendationListener: ListenerRegistration?
    private var lastEvaluatedSurface: String?
    private let surfaceCooldown: TimeInterval = 300  // Don't re-evaluate same surface < 5min

    private init() {}

    // MARK: - Guards

    private var isEnabled: Bool {
        AMENFeatureFlags.shared.compoundIdentityGraphEnabled
    }

    private var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }

    // MARK: - Context Evaluation

    /// Main entry point. Call this when the user enters a significant surface.
    /// Builds a context window and routes to relevant agents via the Orchestrator.
    func evaluateCurrentContext(
        surface: String,
        sessionSignal: String? = nil,
        recentPostCategories: [String] = [],
        recentActionTypes: [String] = [],
        accountCreatedAt: Date? = nil,
        isMinor: Bool = false
    ) async {
        guard isEnabled else { return }
        guard let userId = currentUserId else { return }

        // Surface cooldown — don't thrash on rapid navigation
        if lastEvaluatedSurface == surface { return }
        lastEvaluatedSurface = surface

        let accountAgeDays: Int
        if let created = accountCreatedAt {
            accountAgeDays = Calendar.current.dateComponents([.day], from: created, to: Date()).day ?? 0
        } else {
            accountAgeDays = 0
        }

        let context = UserContextWindow(
            userId: userId,
            currentSurface: surface,
            sessionSignal: sessionSignal,
            recentPostCategories: recentPostCategories,
            recentActionTypes: recentActionTypes,
            accountAgeDays: accountAgeDays,
            isMinor: isMinor,
            trustTier: await currentTrustTier(userId: userId),
            activeActionThreadCount: 0,  // Could be fetched if needed
            timestamp: Date()
        )

        let recommendations = await orchestrator.evaluate(context: context)

        // Persist via Cloud Functions for server-authoritative logging
        if AMENFeatureFlags.shared.agentRecommendationsEnabled {
            for rec in recommendations.prefix(3) {
                await persistRecommendationViaFunction(rec, userId: userId)
            }
        }
    }

    // MARK: - Write Agent Insight

    /// Writes an agent insight for the current user via Cloud Function.
    /// Use this when an agent has produced a meaningful insight worth persisting.
    func writeInsight(
        agentType: AgentType,
        title: String,
        detail: String,
        confidence: Double
    ) async {
        guard isEnabled, let userId = currentUserId else { return }
        let boundary = AgentPermissionBoundary.defaults(for: agentType)
        guard boundary.canWriteInsights else { return }

        do {
            _ = try await functions.httpsCallable("writeAgentInsight").call([
                "userId": userId,
                "agentType": agentType.rawValue,
                "title": title,
                "detail": detail,
                "confidence": confidence
            ])
            dlog("[CompoundIdentityGraphService] Insight written for agent \(agentType.rawValue)")
        } catch {
            dlog("[CompoundIdentityGraphService] writeInsight failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Fetch Recommendations

    /// Fetches pending recommendations for the current user.
    func fetchPendingRecommendations() async -> [AgentRecommendation] {
        guard isEnabled, let userId = currentUserId else { return [] }
        do {
            let snapshot = try await db.collection("users").document(userId)
                .collection("intelligence").document("recommendations")
                .collection("items")
                .whereField("status", isEqualTo: AgentRecommendation.RecommendationStatus.pending.rawValue)
                .order(by: "priority", descending: true)
                .limit(to: 10)
                .getDocuments()
            let recs = snapshot.documents.compactMap { try? $0.data(as: AgentRecommendation.self) }
            pendingRecommendations = recs
            return recs
        } catch {
            dlog("[CompoundIdentityGraphService] fetchPendingRecommendations failed: \(error.localizedDescription)")
            return []
        }
    }

    /// Starts a real-time listener for pending recommendations.
    func startListeningForRecommendations() {
        guard isEnabled, let userId = currentUserId else { return }
        stopListening()
        recommendationListener = db.collection("users").document(userId)
            .collection("intelligence").document("recommendations")
            .collection("items")
            .whereField("status", isEqualTo: AgentRecommendation.RecommendationStatus.pending.rawValue)
            .order(by: "createdAt", descending: true)
            .limit(to: 10)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, error == nil else { return }
                let recs = snapshot?.documents.compactMap { try? $0.data(as: AgentRecommendation.self) } ?? []
                self.pendingRecommendations = recs
            }
    }

    func stopListening() {
        recommendationListener?.remove()
        recommendationListener = nil
    }

    // MARK: - Dismiss Recommendation

    /// Dismisses a recommendation. Dismissed recs are not shown again.
    func dismissRecommendation(_ recommendation: AgentRecommendation) async {
        guard let userId = currentUserId else { return }
        do {
            try await db.collection("users").document(userId)
                .collection("intelligence").document("recommendations")
                .collection("items").document(recommendation.id)
                .updateData(["status": AgentRecommendation.RecommendationStatus.dismissed.rawValue])
            pendingRecommendations.removeAll { $0.id == recommendation.id }
        } catch {
            dlog("[CompoundIdentityGraphService] dismiss failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Accept Recommendation

    func acceptRecommendation(_ recommendation: AgentRecommendation) async {
        guard let userId = currentUserId else { return }
        do {
            try await db.collection("users").document(userId)
                .collection("intelligence").document("recommendations")
                .collection("items").document(recommendation.id)
                .updateData(["status": AgentRecommendation.RecommendationStatus.accepted.rawValue])
            pendingRecommendations.removeAll { $0.id == recommendation.id }
        } catch {
            dlog("[CompoundIdentityGraphService] accept failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Cleanup

    /// Removes expired recommendations (TTL-based). Safe to call periodically.
    func cleanupExpiredRecommendations() async {
        guard isEnabled, let userId = currentUserId else { return }
        do {
            let snapshot = try await db.collection("users").document(userId)
                .collection("intelligence").document("recommendations")
                .collection("items")
                .whereField("expiresAt", isLessThan: Timestamp(date: Date()))
                .limit(to: 50)
                .getDocuments()

            guard !snapshot.documents.isEmpty else { return }
            let batch = db.batch()
            for doc in snapshot.documents {
                batch.updateData(
                    ["status": AgentRecommendation.RecommendationStatus.expired.rawValue],
                    forDocument: doc.reference
                )
            }
            try await batch.commit()
            dlog("[CompoundIdentityGraphService] Cleaned up \(snapshot.documents.count) expired recommendations")
        } catch {
            dlog("[CompoundIdentityGraphService] cleanup failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private func persistRecommendationViaFunction(_ recommendation: AgentRecommendation, userId: String) async {
        do {
            _ = try await functions.httpsCallable("writeAgentRecommendation").call([
                "userId": userId,
                "id": recommendation.id,
                "agentType": recommendation.agentType.rawValue,
                "recommendation": recommendation.title,
                "confidence": recommendation.confidence
            ])
        } catch {
            dlog("[CompoundIdentityGraphService] persistRec via CF failed: \(error.localizedDescription)")
        }
    }

    private func currentTrustTier(userId: String) async -> String {
        guard AMENFeatureFlags.shared.trustSignalsEnabled else { return "standard" }
        if let score = await ProofOfHumanService.shared.getScore(for: userId) {
            switch score.score {
            case 0.8...: return "high"
            case 0.5..<0.8: return "standard"
            default: return "new"
            }
        }
        return "standard"
    }
}
