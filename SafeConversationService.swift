//
//  SafeConversationService.swift
//  AMENAPP
//
//  Safe Conversation Mode for protecting vulnerable users
//  Prevents pile-on, harassment, and toxic messages
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
class SafeConversationService {
    static let shared = SafeConversationService()
    
    private let db = Firestore.firestore()
    private init() {}
    
    // MARK: - Safe Mode Management
    
    /// Load user's safe conversation settings
    func loadSettings(userId: String) async throws -> SafeConversationSettings {
        let doc = try await db.collection("safeConversationSettings")
            .document(userId)
            .getDocument()
        
        if let data = doc.data(),
           let settings = try? Firestore.Decoder().decode(SafeConversationSettings.self, from: data) {
            return settings
        }
        
        // Return defaults
        return SafeConversationSettings(
            userId: userId,
            isEnabled: false,
            mode: .off,
            trustedUserIds: [],
            enableKindnessFilter: false,
            enableSlowMode: false,
            showSupportiveReplySuggestions: false,
            autoEnabledUntil: nil,
            enabledAt: Date(),
            updatedAt: Date()
        )
    }
    
    /// Save settings
    func saveSettings(_ settings: SafeConversationSettings) async throws {
        let data = try Firestore.Encoder().encode(settings)
        try await db.collection("safeConversationSettings")
            .document(settings.userId)
            .setData(data, merge: true)
    }
    
    /// Auto-enable safe mode for high-risk users
    func autoEnableSafeMode(
        userId: String,
        riskLevel: CrisisRiskAssessment.RiskLevel,
        durationHours: Int = 24
    ) async throws {
        var settings = try await loadSettings(userId: userId)
        
        // Only auto-enable for high/critical risk
        guard riskLevel == .high || riskLevel == .critical else { return }
        
        settings.isEnabled = true
        settings.mode = .requestsOnly
        settings.enableKindnessFilter = true
        settings.showSupportiveReplySuggestions = true
        settings.autoEnabledUntil = Date().addingTimeInterval(TimeInterval(durationHours * 3600))
        settings.updatedAt = Date()
        
        try await saveSettings(settings)
        
        #if DEBUG
        dlog("🛡️ [SAFE MODE] Auto-enabled for user \(userId) for \(durationHours) hours")
        #endif
    }
    
    // MARK: - Message Filtering
    
    /// Check if a message should be filtered or moved to requests
    func shouldFilterMessage(
        from senderId: String,
        to recipientId: String,
        messageText: String
    ) async -> MessageFilterResult {
        
        guard let settings = try? await loadSettings(userId: recipientId),
              settings.isEnabled else {
            return MessageFilterResult(action: .allow, reason: nil)
        }
        
        // Check if sender is trusted
        if settings.trustedUserIds.contains(senderId) {
            return MessageFilterResult(action: .allow, reason: nil)
        }
        
        // Apply mode-specific rules
        switch settings.mode {
        case .off:
            return MessageFilterResult(action: .allow, reason: nil)
            
        case .lockdown:
            // Only trusted can message
            return MessageFilterResult(action: .block, reason: "Safe Conversation Mode is on (Trusted Only)")
            
        case .requestsOnly:
            // Non-trusted go to requests
            return MessageFilterResult(action: .moveToRequests, reason: nil)
            
        case .filtered:
            // Check for harmful content
            if settings.enableKindnessFilter {
                let toxicityScore = await assessToxicity(messageText)
                if toxicityScore > 0.6 {
                    return MessageFilterResult(action: .filter, reason: "This message may be harmful")
                }
            }
            return MessageFilterResult(action: .moveToRequests, reason: nil)
        }
    }
    
    /// Assess toxicity of message content (pattern-based, fast)
    private func assessToxicity(_ text: String) async -> Double {
        let text = text.lowercased()
        var score: Double = 0.0
        
        // Insults and slurs
        let insults = ["idiot", "stupid", "dumb", "loser", "pathetic", "waste"]
        for insult in insults {
            if text.contains(insult) {
                score += 0.2
            }
        }
        
        // Threats
        let threats = ["hurt you", "kill you", "find you", "get you", "gonna regret"]
        for threat in threats {
            if text.contains(threat) {
                score += 0.4
            }
        }
        
        // Sexual harassment
        let sexual = ["send pics", "sexy", "hot body", "dtf"]
        for term in sexual {
            if text.contains(term) {
                score += 0.3
            }
        }
        
        // Profanity (light penalty)
        let profanity = ["fuck", "shit", "bitch", "ass", "damn"]
        for word in profanity {
            if text.contains(word) {
                score += 0.1
            }
        }
        
        return min(1.0, score)
    }
    
    struct MessageFilterResult {
        let action: FilterAction
        let reason: String?
        
        enum FilterAction {
            case allow          // Normal delivery
            case moveToRequests // Goes to message requests (no notification)
            case filter         // Hidden locally with kindness filter
            case block          // Rejected completely
        }
    }
    
    // MARK: - Conversation Heat Score
    
    /// Calculate heat score for a conversation (escalation detection)
    func calculateConversationHeat(
        conversationId: String,
        recentMessages: [ConversationHeatScore.MessageHeat]
    ) async -> ConversationHeatScore {
        
        var score: Double = 0.0
        let warnings: [String: Int] = [:]
        
        // Check message frequency (rapid-fire = escalation)
        let last5Minutes = Date().addingTimeInterval(-300)
        let recentCount = recentMessages.filter { $0.timestamp > last5Minutes }.count
        if recentCount > 20 {
            score += 0.2
        }
        
        // Check toxicity scores
        let avgToxicity = recentMessages.map { $0.toxicityScore }.reduce(0, +) / Double(max(recentMessages.count, 1))
        score += avgToxicity * 0.5
        
        // Check for escalation pattern (toxicity increasing over time)
        if recentMessages.count >= 5 {
            let recent3 = recentMessages.suffix(3).map { $0.toxicityScore }.reduce(0, +) / 3.0
            let previous5 = recentMessages.prefix(5).map { $0.toxicityScore }.reduce(0, +) / 5.0
            
            if recent3 > previous5 + 0.2 {
                score += 0.3  // Conversation is heating up
            }
        }
        
        score = min(1.0, score)
        
        return ConversationHeatScore(
            conversationId: conversationId,
            score: score,
            recentMessages: recentMessages,
            slowModeEnabled: score > 0.6,
            participantWarnings: warnings,
            calculatedAt: Date()
        )
    }
    
    /// Get slow mode delay based on heat score
    func getSlowModeDelay(heatScore: Double) -> TimeInterval? {
        switch heatScore {
        case 0.6..<0.7:
            return 10  // 10 seconds between messages
        case 0.7..<0.8:
            return 30  // 30 seconds
        case 0.8...:
            return 60  // 1 minute
        default:
            return nil
        }
    }
    
    // MARK: - Supportive Reply Suggestions
    
    /// Get supportive reply suggestions for friends
    func getSupportiveSuggestions() -> [String] {
        return [
            "I'm here for you. Want to talk?",
            "Thinking of you. How can I help?",
            "I care about you. Please reach out if you need anything.",
            "You're not alone. I'm here.",
            "Want to grab coffee and chat?",
            "Praying for you ❤️"
        ]
    }
    
    // MARK: - Trusted Users
    
    /// Add user to trusted list
    func addTrustedUser(userId: String, trustedUserId: String) async throws {
        var settings = try await loadSettings(userId: userId)
        settings.trustedUserIds.insert(trustedUserId)
        settings.updatedAt = Date()
        try await saveSettings(settings)
    }
    
    /// Remove from trusted list
    func removeTrustedUser(userId: String, trustedUserId: String) async throws {
        var settings = try await loadSettings(userId: userId)
        settings.trustedUserIds.remove(trustedUserId)
        settings.updatedAt = Date()
        try await saveSettings(settings)
    }
}
