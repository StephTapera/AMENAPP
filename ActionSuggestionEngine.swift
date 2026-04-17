//
//  ActionSuggestionEngine.swift
//  AMENAPP
//
//  Detects when a post may qualify for an Action Thread suggestion.
//  Uses on-device signals from ContentRiskAnalyzer and keyword matching.
//  Never auto-executes — always produces suggestions for user approval.
//
//  Constraints:
//    - Confidence thresholds before surfacing
//    - Cooldowns per user/post/category (24h minimum)
//    - Private by default
//    - Ask before executing meaningful actions
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class ActionSuggestionEngine: ObservableObject {
    
    static let shared = ActionSuggestionEngine()
    
    @Published private(set) var pendingSuggestions: [String: ActionSuggestion] = [:]  // postId → suggestion
    
    // Cooldown tracking: key → last suggestion timestamp
    private var cooldowns: [String: Date] = [:]
    private let cooldownInterval: TimeInterval = 86400  // 24 hours
    private let minimumConfidence: Double = 0.45
    
    // Suppress repeated evaluations for the same post
    private var evaluatedPosts: Set<String> = []
    
    private let db = Firestore.firestore()
    private init() {}
    
    // MARK: - Feature Guard
    
    private var isEnabled: Bool {
        AMENFeatureFlags.shared.actionSuggestionsEnabled
    }
    
    // MARK: - Evaluate Post for Suggestions
    
    /// Analyze a post's content and context to determine if an Action Thread
    /// should be suggested to the post author. This runs passively and never
    /// auto-creates threads.
    func evaluatePost(_ post: Post) {
        guard isEnabled else { return }
        guard let postId = post.firebaseId, !evaluatedPosts.contains(postId) else { return }
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        // Only suggest to post author
        guard post.authorId == userId else { return }
        
        evaluatedPosts.insert(postId)
        
        Task {
            let suggestion = await computeSuggestion(for: post)
            guard let suggestion = suggestion else { return }
            
            // Check cooldown
            let cooldownKey = suggestion.cooldownKey
            if let lastSuggested = cooldowns[cooldownKey],
               Date().timeIntervalSince(lastSuggested) < cooldownInterval {
                return  // Still in cooldown
            }
            
            cooldowns[cooldownKey] = Date()
            pendingSuggestions[postId] = suggestion
            
            // Persist suggestion to Firestore for later retrieval
            try? await persistSuggestion(suggestion, postId: postId)
        }
    }
    
    /// Dismiss a suggestion. The user chose not to create a thread.
    func dismissSuggestion(postId: String) {
        guard var suggestion = pendingSuggestions.removeValue(forKey: postId) else { return }
        suggestion.status = .dismissed
        
        Task {
            try? await db.collection("users")
                .document(Auth.auth().currentUser?.uid ?? "")
                .collection("actionSuggestions").document(suggestion.id)
                .updateData(["status": "dismissed"])
        }
    }
    
    /// Mark a suggestion as accepted (thread was created from it).
    func markAccepted(postId: String) {
        guard var suggestion = pendingSuggestions.removeValue(forKey: postId) else { return }
        suggestion.status = .accepted
        
        Task {
            try? await db.collection("users")
                .document(Auth.auth().currentUser?.uid ?? "")
                .collection("actionSuggestions").document(suggestion.id)
                .updateData(["status": "accepted"])
        }
    }
    
    // MARK: - Suggestion Computation
    
    private func computeSuggestion(for post: Post) async -> ActionSuggestion? {
        let content = post.content.lowercased()
        let category = post.category
        
        var bestType: ActionThreadType?
        var confidence: Double = 0.0
        var detectedSignals: [String] = []
        var suggestedSteps: [ActionSuggestion.SuggestedStep] = []
        var sensitivity: CareSensitivityLevel = .standard
        
        // Rule 1: Prayer request with time/urgency signal → prayer circle
        if category == .prayer {
            let urgencySignals = ["urgent", "surgery", "hospital", "tomorrow", "tonight",
                                  "this week", "critical", "emergency", "please pray"]
            let matchedSignals = urgencySignals.filter { content.contains($0) }
            if !matchedSignals.isEmpty {
                bestType = .prayerCircle
                confidence = min(0.85, 0.5 + Double(matchedSignals.count) * 0.12)
                detectedSignals = matchedSignals
                suggestedSteps = [
                    .init(title: "Pray for this request", type: .prayer, scheduledOffset: nil),
                    .init(title: "Check in after 3 days", type: .checkIn, scheduledOffset: 259200),
                    .init(title: "Follow-up reminder", type: .reminder, scheduledOffset: 604800)
                ]
            }
        }
        
        // Rule 2: Post expressing burden/distress → check-in
        let distressSignals = ["struggling", "overwhelmed", "can't cope", "so tired",
                               "burned out", "losing hope", "feeling alone", "breaking point",
                               "don't know what to do", "need help"]
        let distressMatches = distressSignals.filter { content.contains($0) }
        if !distressMatches.isEmpty {
            let distressConfidence = min(0.80, 0.45 + Double(distressMatches.count) * 0.15)
            if distressConfidence > confidence {
                bestType = .checkIn
                confidence = distressConfidence
                detectedSignals = distressMatches
                sensitivity = .elevated
                suggestedSteps = [
                    .init(title: "Private check-in", type: .checkIn, scheduledOffset: 86400),
                    .init(title: "Share an encouraging word", type: .encouragement, scheduledOffset: nil),
                    .init(title: "Follow-up in 3 days", type: .checkIn, scheduledOffset: 259200)
                ]
            }
        }
        
        // Rule 3: Illness/surgery → meal support or follow-up
        let careSignals = ["surgery", "hospital", "diagnosis", "chemo", "treatment",
                           "recovery", "bedridden", "broken", "accident"]
        let careMatches = careSignals.filter { content.contains($0) }
        if !careMatches.isEmpty {
            let careConfidence = min(0.75, 0.50 + Double(careMatches.count) * 0.12)
            if careConfidence > confidence {
                bestType = .mealSupport
                confidence = careConfidence
                detectedSignals = careMatches
                sensitivity = .elevated
                suggestedSteps = [
                    .init(title: "Coordinate meals", type: .mealDelivery, scheduledOffset: nil),
                    .init(title: "Check in daily", type: .checkIn, scheduledOffset: 86400),
                    .init(title: "Scripture for healing", type: .scripture, scheduledOffset: nil)
                ]
            }
        }
        
        // Rule 4: Testimony / breakthrough → encouragement thread
        if category == .testimonies || post.isAnsweredPrayer {
            let celebrationSignals = ["answered", "breakthrough", "miracle", "healed",
                                      "restored", "freedom", "delivered", "grateful"]
            let celebrationMatches = celebrationSignals.filter { content.contains($0) }
            if !celebrationMatches.isEmpty {
                let celebrationConfidence = min(0.70, 0.40 + Double(celebrationMatches.count) * 0.10)
                if celebrationConfidence > confidence {
                    bestType = .encouragementFlow
                    confidence = celebrationConfidence
                    detectedSignals = celebrationMatches
                    suggestedSteps = [
                        .init(title: "Share rejoicing", type: .encouragement, scheduledOffset: nil),
                        .init(title: "Related scripture", type: .scripture, scheduledOffset: nil)
                    ]
                }
            }
        }
        
        // Rule 5: Scripture-heavy reflection → scripture support
        if post.verseReference != nil {
            let reflectionSignals = ["meditation", "studying", "reflecting", "devotional",
                                     "quiet time", "word study"]
            let reflectionMatches = reflectionSignals.filter { content.contains($0) }
            if !reflectionMatches.isEmpty {
                let reflectionConfidence = min(0.65, 0.35 + Double(reflectionMatches.count) * 0.12)
                if reflectionConfidence > confidence {
                    bestType = .scriptureSupport
                    confidence = reflectionConfidence
                    detectedSignals = reflectionMatches
                    suggestedSteps = [
                        .init(title: "Suggest related passages", type: .scripture, scheduledOffset: nil),
                        .init(title: "Reflection prompt in 2 days", type: .reminder, scheduledOffset: 172800)
                    ]
                }
            }
        }
        
        // Rule 6: Crisis signals → resource prompt (highest sensitivity)
        // Uses ContentRiskAnalyzer signals for crisis detection
        let riskResult = ContentRiskAnalyzer.quickScan(post.content)
        if riskResult.flagged {
            // Only suggest crisis resources if BehavioralAwarenessEngine confirms
            // or if the risk analyzer detected self-harm/crisis signals
            if riskResult.primaryCategory == "selfHarmCrisis" && riskResult.score > 0.35 {
                bestType = .crisisResource
                confidence = min(0.90, riskResult.score + 0.20)
                detectedSignals = ["crisis_risk_detected"]
                sensitivity = .critical
                suggestedSteps = [
                    .init(title: "Crisis resources", type: .resource, scheduledOffset: nil)
                ]
            }
        }
        
        // Apply confidence threshold
        guard let threadType = bestType, confidence >= minimumConfidence else {
            return nil
        }
        
        let userId = Auth.auth().currentUser?.uid ?? ""
        let postId = post.firebaseId ?? post.id.uuidString
        
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
            expiresAt: Calendar.current.date(byAdding: .day, value: 7, to: Date())!,
            status: .pending,
            cooldownKey: "\(userId)_\(postId)_\(threadType.rawValue)"
        )
    }
    
    // MARK: - Persistence
    
    private func persistSuggestion(_ suggestion: ActionSuggestion, postId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        try await db.collection("users").document(userId)
            .collection("actionSuggestions").document(suggestion.id)
            .setData(from: suggestion)
    }
    
    // MARK: - Cache Management
    
    func clearCache() {
        evaluatedPosts.removeAll()
        pendingSuggestions.removeAll()
        cooldowns.removeAll()
    }
}
