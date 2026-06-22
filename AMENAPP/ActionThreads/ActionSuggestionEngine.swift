import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class ActionSuggestionEngine: ObservableObject {

    static let shared = ActionSuggestionEngine()

    @Published private(set) var pendingSuggestions: [String: ActionSuggestion] = [:]

    private var cooldowns: [String: Date] = [:]
    private let cooldownInterval: TimeInterval = 86_400
    private let minimumConfidence: Double = 0.45
    private var evaluatedPosts: Set<String> = []
    private let db = Firestore.firestore()

    private init() {}

    private var isEnabled: Bool {
        AMENFeatureFlags.shared.actionSuggestionsEnabled
    }

    func evaluatePost(_ post: Post) {
        guard isEnabled else { return }
        guard let postId = post.firebaseId, !evaluatedPosts.contains(postId) else { return }
        guard let userId = Auth.auth().currentUser?.uid, post.authorId == userId else { return }

        evaluatedPosts.insert(postId)

        Task {
            guard let suggestion = await computeSuggestion(for: post) else { return }
            if let lastSuggested = cooldowns[suggestion.cooldownKey],
               Date().timeIntervalSince(lastSuggested) < cooldownInterval {
                return
            }

            cooldowns[suggestion.cooldownKey] = Date()
            pendingSuggestions[postId] = suggestion
            try? await persistSuggestion(suggestion)
        }
    }

    private func computeSuggestion(for post: Post) async -> ActionSuggestion? {
        let postId = post.firebaseId ?? post.id.uuidString
        let privacyTier: ActionIntelligencePrivacyTier = post.visibility == .everyone ? .publicCommunity : .confidential
        let source = ActionIntelligenceSource(
            id: postId,
            text: post.content,
            surface: .feedPost,
            privacyTier: privacyTier,
            authorId: post.authorId,
            currentUserId: Auth.auth().currentUser?.uid,
            createdAt: Date()
        )

        if let analysis = ActionIntelligenceEngine.shared.analyze(source: source),
           !analysis.shouldSuppressCapsule {
            return buildSuggestion(from: analysis, postId: postId)
        }

        let content = post.content.lowercased()
        var bestType: ActionThreadType?
        var confidence = 0.0
        var detectedSignals: [String] = []
        var suggestedSteps: [ActionSuggestion.SuggestedStep] = []
        var sensitivity: CareSensitivityLevel = .standard

        if post.category == .prayer {
            let urgencySignals = ["urgent", "surgery", "hospital", "tomorrow", "tonight", "please pray"]
            let matches = urgencySignals.filter { content.contains($0) }
            if !matches.isEmpty {
                bestType = .prayerCircle
                confidence = min(0.85, 0.5 + Double(matches.count) * 0.12)
                detectedSignals = matches
                suggestedSteps = [
                    .init(title: "Pray for this request", type: .prayer, scheduledOffset: nil),
                    .init(title: "Check in after 3 days", type: .checkIn, scheduledOffset: 259_200)
                ]
            }
        }

        let distressSignals = ["struggling", "overwhelmed", "losing hope", "feeling alone", "need help"]
        let distressMatches = distressSignals.filter { content.contains($0) }
        if !distressMatches.isEmpty {
            let distressConfidence = min(0.8, 0.45 + Double(distressMatches.count) * 0.15)
            if distressConfidence > confidence {
                bestType = .checkIn
                confidence = distressConfidence
                detectedSignals = distressMatches
                sensitivity = .elevated
                suggestedSteps = [
                    .init(title: "Private check-in", type: .checkIn, scheduledOffset: 86_400),
                    .init(title: "Share an encouraging word", type: .encouragement, scheduledOffset: nil)
                ]
            }
        }

        let careSignals = ["surgery", "hospital", "diagnosis", "treatment", "recovery"]
        let careMatches = careSignals.filter { content.contains($0) }
        if !careMatches.isEmpty {
            let careConfidence = min(0.75, 0.5 + Double(careMatches.count) * 0.12)
            if careConfidence > confidence {
                bestType = .mealSupport
                confidence = careConfidence
                detectedSignals = careMatches
                sensitivity = .elevated
                suggestedSteps = [
                    .init(title: "Coordinate meals", type: .mealDelivery, scheduledOffset: nil),
                    .init(title: "Check in daily", type: .checkIn, scheduledOffset: 86_400)
                ]
            }
        }

        if post.category == .testimonies || post.isAnsweredPrayer {
            let testimonySignals = ["answered", "breakthrough", "miracle", "healed", "restored"]
            let matches = testimonySignals.filter { content.contains($0) }
            if !matches.isEmpty {
                let score = min(0.7, 0.4 + Double(matches.count) * 0.1)
                if score > confidence {
                    bestType = .encouragementFlow
                    confidence = score
                    detectedSignals = matches
                    suggestedSteps = [
                        .init(title: "Share rejoicing", type: .encouragement, scheduledOffset: nil)
                    ]
                }
            }
        }

        if post.verseReference != nil {
            let reflectionSignals = ["meditation", "reflecting", "devotional", "quiet time"]
            let matches = reflectionSignals.filter { content.contains($0) }
            if !matches.isEmpty {
                let score = min(0.65, 0.35 + Double(matches.count) * 0.12)
                if score > confidence {
                    bestType = .scriptureSupport
                    confidence = score
                    detectedSignals = matches
                    suggestedSteps = [
                        .init(title: "Suggest related passages", type: .scripture, scheduledOffset: nil)
                    ]
                }
            }
        }

        let riskResult = ContentRiskAnalyzer.shared.quickScan(text: post.content)
        if riskResult.primaryCategory == .selfHarmCrisis, riskResult.totalScore > 0.35 {
            bestType = .crisisResource
            confidence = min(0.9, riskResult.totalScore + 0.2)
            detectedSignals = ["crisis_risk_detected"]
            sensitivity = .critical
            suggestedSteps = [
                .init(title: "Crisis resources", type: .resource, scheduledOffset: nil)
            ]
        }

        guard let threadType = bestType, confidence >= minimumConfidence else { return nil }
        let userId = Auth.auth().currentUser?.uid ?? ""
        return ActionSuggestion(
            id: UUID().uuidString,
            postId: postId,
            suggestedThreadType: threadType,
            intent: SupportIntent(
                category: threadType,
                sensitivityLevel: sensitivity,
                description: nil,
                detectedSignals: detectedSignals,
                confidence: confidence,
                sourcePostId: postId
            ),
            suggestedSteps: suggestedSteps,
            createdAt: Date(),
            expiresAt: Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date(),
            status: .pending,
            cooldownKey: "\(userId)_\(postId)_\(threadType.rawValue)"
        )
    }

    private func buildSuggestion(from analysis: AmenIntentAnalysis, postId: String) -> ActionSuggestion? {
        guard analysis.confidence >= minimumConfidence else { return nil }
        let userId = Auth.auth().currentUser?.uid ?? ""
        let threadType = analysis.suggestedActionThreadType

        return ActionSuggestion(
            id: UUID().uuidString,
            postId: postId,
            suggestedThreadType: threadType,
            intent: SupportIntent(
                category: threadType,
                sensitivityLevel: analysis.sensitivityLevel,
                description: analysis.explanation,
                detectedSignals: analysis.detectedSignals,
                confidence: analysis.confidence,
                sourcePostId: postId
            ),
            suggestedSteps: analysis.suggestedSteps,
            createdAt: Date(),
            expiresAt: Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date(),
            status: .pending,
            cooldownKey: "\(userId)_\(postId)_\(threadType.rawValue)"
        )
    }

    private func persistSuggestion(_ suggestion: ActionSuggestion) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        try db.collection("users")
            .document(userId)
            .collection("actionSuggestions")
            .document(suggestion.id)
            .setData(from: suggestion)
    }
}
