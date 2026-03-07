import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

/// Service for generating intelligent mute suggestions
@MainActor
class SmartMuteService: ObservableObject {
    static let shared = SmartMuteService()
    
    private let db = Firestore.firestore()
    @Published var suggestions: [MuteSuggestion] = []
    
    // MARK: - Analyze Thread Activity
    
    /// Check if a thread should be suggested for muting
    func analyzeThread(threadId: String, userId: String) async -> MuteSuggestion? {
        // Get thread messages from last 24 hours
        let oneDayAgo = Date().addingTimeInterval(-24 * 3600)
        
        let recentMessages = try? await db.collection("conversations")
            .document(threadId)
            .collection("messages")
            .whereField("timestamp", isGreaterThan: Timestamp(date: oneDayAgo))
            .order(by: "timestamp", descending: false)
            .getDocuments()
        
        guard let messages = recentMessages?.documents, !messages.isEmpty else {
            return nil
        }
        
        // Check for activity spike
        if let spikeSuggestion = detectActivitySpike(messages: messages, threadId: threadId) {
            return spikeSuggestion
        }
        
        // Check for off-hours activity
        if let offHoursSuggestion = detectOffHoursActivity(messages: messages, threadId: threadId) {
            return offHoursSuggestion
        }
        
        // Check for low engagement
        if let lowEngagementSuggestion = await detectLowEngagement(messages: messages, threadId: threadId, userId: userId) {
            return lowEngagementSuggestion
        }
        
        return nil
    }
    
    // MARK: - Activity Spike Detection
    
    private func detectActivitySpike(messages: [QueryDocumentSnapshot], threadId: String) -> MuteSuggestion? {
        // Calculate messages per hour (based on recent count below)
        // Get historical baseline (last 7 days)
        // For simplicity, assume normal rate is 2 messages/hour
        let normalRate: Double = 2.0
        
        // Calculate current rate (last hour)
        let oneHourAgo = Date().addingTimeInterval(-3600)
        let recentCount = messages.filter { doc in
            if let timestamp = (doc.data()["timestamp"] as? Timestamp)?.dateValue() {
                return timestamp > oneHourAgo
            }
            return false
        }.count
        
        let currentRate = Double(recentCount)
        
        // Spike if current rate is 3x normal
        if currentRate >= normalRate * 3 {
            return MuteSuggestion(
                id: UUID().uuidString,
                threadId: threadId,
                reason: .activitySpike,
                suggestedDuration: 28800,  // 8 hours
                confidence: min(1.0, currentRate / (normalRate * 5)),
                activitySpike: MuteSuggestion.ActivitySpike(
                    normalRate: normalRate,
                    currentRate: currentRate,
                    duration: 3600
                )
            )
        }
        
        return nil
    }
    
    // MARK: - Off-Hours Detection
    
    private func detectOffHoursActivity(messages: [QueryDocumentSnapshot], threadId: String) -> MuteSuggestion? {
        let calendar = Calendar.current
        let now = Date()
        let currentHour = calendar.component(.hour, from: now)
        
        // Consider 22:00-08:00 as off-hours
        let isOffHours = currentHour >= 22 || currentHour < 8
        
        if !isOffHours {
            return nil
        }
        
        // Check if recent activity (last 30 min)
        let thirtyMinAgo = now.addingTimeInterval(-1800)
        let recentCount = messages.filter { doc in
            if let timestamp = (doc.data()["timestamp"] as? Timestamp)?.dateValue() {
                return timestamp > thirtyMinAgo
            }
            return false
        }.count
        
        if recentCount >= 5 {
            // Multiple messages during quiet hours
            let hoursUntilMorning: TimeInterval = currentHour >= 22 ? Double(32 - currentHour) * 3600 : Double(8 - currentHour) * 3600
            
            return MuteSuggestion(
                id: UUID().uuidString,
                threadId: threadId,
                reason: .offHours,
                suggestedDuration: hoursUntilMorning,
                confidence: 0.8,
                activitySpike: nil
            )
        }
        
        return nil
    }
    
    // MARK: - Low Engagement Detection
    
    private func detectLowEngagement(messages: [QueryDocumentSnapshot], threadId: String, userId: String) async -> MuteSuggestion? {
        // Check if user has sent any messages in last 50 messages
        let lastMessages = messages.suffix(50)
        
        let userMessageCount = lastMessages.filter { doc in
            let senderId = doc.data()["senderId"] as? String
            return senderId == userId
        }.count
        
        // If user hasn't sent any messages in last 50, suggest mute
        if userMessageCount == 0 && lastMessages.count >= 20 {
            return MuteSuggestion(
                id: UUID().uuidString,
                threadId: threadId,
                reason: .lowEngagement,
                suggestedDuration: 86400,  // 24 hours
                confidence: 0.7,
                activitySpike: nil
            )
        }
        
        return nil
    }
    
    // MARK: - Repeated Notifications Detection
    
    /// Check if user is getting too many notifications from a specific source
    func detectRepeatedNotifications(fromUserId: String, toUserId: String) async -> MuteSuggestion? {
        // Count notifications from this user in last 2 hours
        let twoHoursAgo = Date().addingTimeInterval(-7200)
        
        let snapshot = try? await db.collection("users").document(toUserId)
            .collection("notifications")
            .whereField("timestamp", isGreaterThan: Timestamp(date: twoHoursAgo))
            .getDocuments()
        
        var notificationCount = 0
        for doc in snapshot?.documents ?? [] {
            // Check if notification is from this user (stored in metadata)
            if let metadata = doc.data()["metadata"] as? [String: String],
               metadata["fromUserId"] == fromUserId {
                notificationCount += 1
            }
        }
        
        // If 10+ notifications in 2 hours, suggest mute
        if notificationCount >= 10 {
            return MuteSuggestion(
                id: UUID().uuidString,
                threadId: fromUserId,  // Use userId as threadId
                reason: .repeatedNotifications,
                suggestedDuration: 14400,  // 4 hours
                confidence: min(1.0, Double(notificationCount) / 20.0),
                activitySpike: nil
            )
        }
        
        return nil
    }
    
    // MARK: - Load Suggestions
    
    /// Generate mute suggestions for user's active threads
    func loadSuggestions() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        var suggestions: [MuteSuggestion] = []
        
        // Get user's active conversations
        let conversations = try? await db.collection("conversations")
            .whereField("participants", arrayContains: userId)
            .whereField("lastMessageAt", isGreaterThan: Timestamp(date: Date().addingTimeInterval(-86400)))
            .limit(to: 20)
            .getDocuments()
        
        for doc in conversations?.documents ?? [] {
            let threadId = doc.documentID
            
            if let suggestion = await analyzeThread(threadId: threadId, userId: userId) {
                suggestions.append(suggestion)
            }
        }
        
        // Sort by confidence
        self.suggestions = suggestions.sorted { $0.confidence > $1.confidence }
    }
    
    // MARK: - Apply Suggestion
    
    func applySuggestion(_ suggestion: MuteSuggestion) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let muteUntil = Date().addingTimeInterval(suggestion.suggestedDuration)
        
        try await db.collection("users").document(userId)
            .collection("mutedThreads").document(suggestion.threadId)
            .setData([
                "mutedAt": FieldValue.serverTimestamp(),
                "mutedUntil": Timestamp(date: muteUntil),
                "reason": suggestion.reason.rawValue,
                "suggestionId": suggestion.id
            ])
        
        // Remove from suggestions
        suggestions.removeAll { $0.id == suggestion.id }
    }
    
    func dismissSuggestion(_ suggestionId: String) {
        suggestions.removeAll { $0.id == suggestionId }
    }
}
