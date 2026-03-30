import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

/// Smart notification routing with priority scoring and channel selection
@MainActor
class SmartNotificationRouter: ObservableObject {
    static let shared = SmartNotificationRouter()
    
    private let db = Firestore.firestore()
    private var userPreferences: SmartNotificationPreferences = SmartNotificationPreferences()
    private var relationshipCache: [String: RelationshipContext] = [:]

    // Preferences cache: userId → (prefs, fetchedAt)
    private var preferencesCache: [String: (SmartNotificationPreferences, Date)] = [:]
    private let preferencesCacheTTL: TimeInterval = 300  // 5 minutes
    
    // MARK: - Main Routing Function
    
    /// Route a notification event through priority scoring to delivery channel
    func route(
        category: NotificationCategory,
        fromUserId: String,
        toUserId: String,
        content: String,
        entityId: String?,
        metadata: [String: Any] = [:]
    ) async throws -> SmartNotificationRouting {
        
        // Load user preferences
        await loadPreferences(for: toUserId)
        
        // Check if category is enabled
        guard isCategoryEnabled(category) else {
            return SmartNotificationRouting(
                channel: .suppress,
                deliverAt: Date(),
                collapseKey: nil,
                priority: SmartNotificationPriority(score: 0, level: .minimal, factors: [], timestamp: Date()),
                ttl: 0
            )
        }
        
        // Calculate priority score
        let priority = await calculatePriority(
            category: category,
            fromUserId: fromUserId,
            toUserId: toUserId,
            content: content,
            metadata: metadata
        )
        
        // Determine delivery channel based on priority and preferences
        let channel = determineChannel(priority: priority, category: category)
        
        // Calculate delivery time (immediate or delayed)
        let deliverAt = calculateDeliveryTime(priority: priority, channel: channel)
        
        // Generate collapse key for grouping
        let collapseKey = NotificationCollapseKey.generate(
            category: category,
            entityId: entityId,
            userId: toUserId
        )
        
        // Set TTL based on importance
        let ttl = calculateTTL(priority: priority)
        
        return SmartNotificationRouting(
            channel: channel,
            deliverAt: deliverAt,
            collapseKey: collapseKey,
            priority: priority,
            ttl: ttl
        )
    }
    
    // MARK: - Priority Calculation
    
    private func calculatePriority(
        category: NotificationCategory,
        fromUserId: String,
        toUserId: String,
        content: String,
        metadata: [String: Any]
    ) async -> SmartNotificationPriority {
        
        var factors: [SmartNotificationPriority.PriorityFactor] = []
        var totalScore: Double = 0.0
        
        // 1. Relationship factor (0-0.4 weight)
        let relationship = await getRelationshipContext(userId: fromUserId, forUser: toUserId)
        let relationshipWeight = relationship.relationshipScore * 0.4
        totalScore += relationshipWeight
        factors.append(.init(
            type: .relationship,
            weight: relationshipWeight,
            reason: "Relationship: \(relationship.level.rawValue)"
        ))
        
        // 2. Intent factor (0-0.3 weight)
        let intent = detectIntent(content: content, category: category)
        let intentWeight = (0.5 + intent.priorityBoost) * 0.3
        totalScore += intentWeight
        factors.append(.init(
            type: .intent,
            weight: intentWeight,
            reason: "Intent: \(intent.type.rawValue)"
        ))
        
        // 3. Safety factor (0-0.2 weight)
        let safetyScore = await assessSafety(content: content, fromUserId: fromUserId)
        let safetyWeight = safetyScore * 0.2
        totalScore += safetyWeight
        factors.append(.init(
            type: .safety,
            weight: safetyWeight,
            reason: safetyScore < 0.5 ? "Potential spam/harassment" : "Safe content"
        ))
        
        // 4. User preference factor (0-0.1 weight)
        let preferenceBoost = getPreferenceBoost(category: category)
        totalScore += preferenceBoost
        factors.append(.init(
            type: .userPreference,
            weight: preferenceBoost,
            reason: "User mode: \(userPreferences.mode.rawValue)"
        ))
        
        // Normalize to 0.0-1.0
        totalScore = min(1.0, max(0.0, totalScore))
        
        let level = priorityLevel(for: totalScore)
        
        return SmartNotificationPriority(
            score: totalScore,
            level: level,
            factors: factors,
            timestamp: Date()
        )
    }
    
    private func priorityLevel(for score: Double) -> SmartNotificationPriority.PriorityLevel {
        switch score {
        case 0.8...1.0: return .critical
        case 0.6..<0.8: return .high
        case 0.4..<0.6: return .medium
        case 0.2..<0.4: return .low
        default: return .minimal
        }
    }
    
    // MARK: - Relationship Scoring
    
    private func getRelationshipContext(userId: String, forUser: String) async -> RelationshipContext {
        // Check cache first
        if let cached = relationshipCache[userId] {
            // Cache valid for 1 hour
            if Date().timeIntervalSince(cached.computedAt) < 3600 {
                return cached
            }
        }
        
        // Compute relationship score
        var factors: [RelationshipContext.Factor] = []
        var totalScore: Double = 0.0
        
        // 1. Mutual follow (0.3 weight)
        let mutualFollow = await checkMutualFollow(userId: userId, otherUserId: forUser)
        if mutualFollow {
            factors.append(.init(type: .mutualFollow, value: 1.0, weight: 0.3))
            totalScore += 0.3
        }
        
        // 2. Messaging history (0.25 weight)
        let messageScore = await getMessagingScore(userId: userId, otherUserId: forUser)
        factors.append(.init(type: .messagingHistory, value: messageScore, weight: 0.25))
        totalScore += messageScore * 0.25
        
        // 3. Shared prayers (0.15 weight)
        let prayerScore = await getSharedPrayerScore(userId: userId, otherUserId: forUser)
        factors.append(.init(type: .sharedPrayers, value: prayerScore, weight: 0.15))
        totalScore += prayerScore * 0.15
        
        // 4. Engagement (0.15 weight)
        let engagementScore = await getEngagementScore(userId: userId, otherUserId: forUser)
        factors.append(.init(type: .engagement, value: engagementScore, weight: 0.15))
        totalScore += engagementScore * 0.15
        
        // 5. Shared church (0.1 weight)
        let sharedChurch = await checkSharedChurch(userId: userId, otherUserId: forUser)
        if sharedChurch {
            factors.append(.init(type: .sharedChurch, value: 1.0, weight: 0.1))
            totalScore += 0.1
        }
        
        // 6. Recency (0.05 weight)
        let recencyScore = await getRecencyScore(userId: userId, otherUserId: forUser)
        factors.append(.init(type: .recency, value: recencyScore, weight: 0.05))
        totalScore += recencyScore * 0.05
        
        let context = RelationshipContext(
            targetUserId: userId,
            relationshipScore: totalScore,
            factors: factors,
            computedAt: Date()
        )
        
        // Cache result
        relationshipCache[userId] = context
        
        return context
    }
    
    private func checkMutualFollow(userId: String, otherUserId: String) async -> Bool {
        // Check if both users follow each other
        guard let currentUser = Auth.auth().currentUser?.uid else { return false }
        
        let following = try? await db.collection("users").document(currentUser)
            .collection("following").document(userId).getDocument().exists
        
        let followedBy = try? await db.collection("users").document(userId)
            .collection("following").document(currentUser).getDocument().exists
        
        return (following ?? false) && (followedBy ?? false)
    }
    
    private func getMessagingScore(userId: String, otherUserId: String) async -> Double {
        // Count DM messages between users (capped at 50 for score = 1.0)
        let conversationId = [userId, otherUserId].sorted().joined(separator: "_")
        
        let snapshot = try? await db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .limit(to: 50)
            .getDocuments()
        
        let messageCount = snapshot?.documents.count ?? 0
        return min(1.0, Double(messageCount) / 50.0)
    }
    
    private func getSharedPrayerScore(userId: String, otherUserId: String) async -> Double {
        // Count shared prayer interactions
        let snapshot = try? await db.collection("prayers")
            .whereField("authorId", isEqualTo: userId)
            .whereField("prayedBy", arrayContains: otherUserId)
            .limit(to: 20)
            .getDocuments()
        
        let count = snapshot?.documents.count ?? 0
        return min(1.0, Double(count) / 20.0)
    }
    
    private func getEngagementScore(userId: String, otherUserId: String) async -> Double {
        // Count likes/comments on each other's posts (last 30 days)
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 3600)
        
        let snapshot = try? await db.collection("posts")
            .whereField("authorId", isEqualTo: userId)
            .whereField("timestamp", isGreaterThan: Timestamp(date: thirtyDaysAgo))
            .getDocuments()
        
        var engagementCount = 0
        for doc in snapshot?.documents ?? [] {
            let reactions = doc.data()["reactions"] as? [String: String] ?? [:]
            if reactions.keys.contains(otherUserId) {
                engagementCount += 1
            }
        }
        
        return min(1.0, Double(engagementCount) / 10.0)
    }
    
    private func checkSharedChurch(userId: String, otherUserId: String) async -> Bool {
        // Check if users attend same church
        let user1Church = try? await db.collection("users").document(userId).getDocument().data()?["churchId"] as? String
        let user2Church = try? await db.collection("users").document(otherUserId).getDocument().data()?["churchId"] as? String
        
        return user1Church != nil && user1Church == user2Church
    }
    
    private func getRecencyScore(userId: String, otherUserId: String) async -> Double {
        // Find the most recent notification or message from otherUserId to userId.
        // Score = 1.0 if within 24 h, decaying exponentially to 0 at 30 days.
        let snapshot = try? await db.collection("users").document(userId)
            .collection("notifications")
            .whereField("actorUid", isEqualTo: otherUserId)
            .order(by: "createdAt", descending: true)
            .limit(to: 1)
            .getDocuments()

        guard let doc = snapshot?.documents.first,
              let ts = doc.data()["createdAt"] as? Timestamp else {
            return 0.0
        }

        let daysSince = Date().timeIntervalSince(ts.dateValue()) / 86400.0
        // Exponential decay: score = e^(-daysSince / 7)  →  1.0 at 0 days, ~0.37 at 7 days, ~0.01 at 30 days
        return exp(-daysSince / 7.0)
    }
    
    // MARK: - Intent Detection
    
    private func detectIntent(content: String, category: NotificationCategory) -> ContentIntent {
        let lowercased = content.lowercased()
        
        // Question detection
        if lowercased.contains("?") || 
           lowercased.hasPrefix("what ") ||
           lowercased.hasPrefix("how ") ||
           lowercased.hasPrefix("why ") ||
           lowercased.hasPrefix("when ") ||
           lowercased.hasPrefix("where ") ||
           lowercased.hasPrefix("who ") {
            return ContentIntent(type: .question, confidence: 0.9, signals: ["question_mark", "question_word"])
        }
        
        // Direct request
        if lowercased.contains("can you") ||
           lowercased.contains("could you") ||
           lowercased.contains("please") ||
           lowercased.contains("need ") {
            return ContentIntent(type: .directRequest, confidence: 0.8, signals: ["polite_request"])
        }
        
        // Casual engagement (reactions)
        if category == .reactions || category == .reposts {
            return ContentIntent(type: .casualEngagement, confidence: 1.0, signals: ["passive_action"])
        }
        
        // Default to informational
        return ContentIntent(type: .informational, confidence: 0.6, signals: ["default"])
    }
    
    // MARK: - Safety Assessment
    
    private func assessSafety(content: String, fromUserId: String) async -> Double {
        // Check for spam/harassment signals
        let lowercased = content.lowercased()
        
        // Spam patterns
        let spamPatterns = ["buy now", "click here", "limited time", "earn money", "congratulations"]
        if spamPatterns.contains(where: { lowercased.contains($0) }) {
            return 0.2  // Low safety = suppress
        }
        
        // Check if user is blocked/restricted
        guard let currentUser = Auth.auth().currentUser?.uid else { return 0.5 }
        let isBlocked = try? await db.collection("users").document(currentUser)
            .collection("blocked").document(fromUserId).getDocument().exists
        
        if isBlocked == true {
            return 0.0  // Blocked user = suppress
        }
        
        // Default safe
        return 1.0
    }
    
    // MARK: - Channel Determination
    
    private func determineChannel(priority: SmartNotificationPriority, category: NotificationCategory) -> SmartNotificationRouting.DeliveryChannel {
        
        // Crisis alerts always push
        if category == .crisisAlerts {
            return .push
        }
        
        // Check quiet hours
        if isQuietHours() && priority.level != .critical {
            return .digest
        }
        
        // Check Sunday mode
        if userPreferences.sundayMode && Calendar.current.isDateInWeekend(Date()) {
            if priority.level == .critical {
                return .push
            } else {
                return .digest
            }
        }
        
        // Route by priority level and category setting
        let categorySetting = userPreferences.categorySettings[category] ?? SmartNotificationPreferences.CategorySetting(mode: .meaningful, pushEnabled: true, soundEnabled: false)
        
        switch userPreferences.mode {
        case .meaningful:
            return meaningfulModeChannel(priority: priority, categorySetting: categorySetting)
        case .balanced:
            return balancedModeChannel(priority: priority, categorySetting: categorySetting)
        case .everything:
            return everythingModeChannel(priority: priority, categorySetting: categorySetting)
        }
    }
    
    private func meaningfulModeChannel(priority: SmartNotificationPriority, categorySetting: SmartNotificationPreferences.CategorySetting) -> SmartNotificationRouting.DeliveryChannel {
        guard categorySetting.pushEnabled else { return .inApp }
        
        switch priority.level {
        case .critical: return .push
        case .high: return .push
        case .medium: return .inApp
        case .low: return .digest
        case .minimal: return .suppress
        }
    }
    
    private func balancedModeChannel(priority: SmartNotificationPriority, categorySetting: SmartNotificationPreferences.CategorySetting) -> SmartNotificationRouting.DeliveryChannel {
        guard categorySetting.pushEnabled else { return .inApp }
        
        switch priority.level {
        case .critical: return .push
        case .high: return .push
        case .medium: return .push
        case .low: return .inApp
        case .minimal: return .digest
        }
    }
    
    private func everythingModeChannel(priority: SmartNotificationPriority, categorySetting: SmartNotificationPreferences.CategorySetting) -> SmartNotificationRouting.DeliveryChannel {
        guard categorySetting.pushEnabled else { return .inApp }
        return .push  // Push everything (except suppressed)
    }
    
    private func isQuietHours() -> Bool {
        guard let quietHours = userPreferences.quietHours, quietHours.enabled else {
            return false
        }
        
        let now = Date()
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)
        
        // Parse start/end times
        let startComponents = quietHours.startTime.split(separator: ":")
        let endComponents = quietHours.endTime.split(separator: ":")
        
        guard startComponents.count == 2, endComponents.count == 2,
              let startHour = Int(startComponents[0]), let startMin = Int(startComponents[1]),
              let endHour = Int(endComponents[0]), let endMin = Int(endComponents[1]) else {
            return false
        }
        
        let currentMinutes = currentHour * 60 + currentMinute
        let startMinutes = startHour * 60 + startMin
        let endMinutes = endHour * 60 + endMin
        
        if startMinutes < endMinutes {
            return currentMinutes >= startMinutes && currentMinutes < endMinutes
        } else {
            return currentMinutes >= startMinutes || currentMinutes < endMinutes
        }
    }
    
    // MARK: - Delivery Timing
    
    private func calculateDeliveryTime(priority: SmartNotificationPriority, channel: SmartNotificationRouting.DeliveryChannel) -> Date {
        switch channel {
        case .push, .inApp, .silent:
            // Immediate or slight delay for batching
            if priority.level == .critical {
                return Date()
            } else {
                return Date().addingTimeInterval(30)  // 30 second delay for batching
            }
        case .digest:
            return nextDigestTime()
        case .suppress:
            return Date.distantFuture
        }
    }
    
    private func nextDigestTime() -> Date {
        let now = Date()
        let calendar = Calendar.current
        
        switch userPreferences.digestCadence {
        case .realtime:
            return now
        case .twiceDaily:
            let hour = calendar.component(.hour, from: now)
            if hour < 9 {
                return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now) ?? now
            } else if hour < 18 {
                return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now) ?? now
            } else {
                return calendar.date(byAdding: .day, value: 1, to: calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now) ?? now) ?? now
            }
        case .daily:
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: calendar.date(byAdding: .day, value: 1, to: now) ?? now) ?? now
        case .weekly:
            var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
            components.weekday = 1  // Sunday
            components.hour = 9
            return calendar.date(from: components) ?? now
        }
    }
    
    private func calculateTTL(priority: SmartNotificationPriority) -> TimeInterval {
        switch priority.level {
        case .critical: return 3600  // 1 hour
        case .high: return 86400  // 24 hours
        case .medium: return 86400 * 3  // 3 days
        case .low: return 86400 * 7  // 7 days
        case .minimal: return 86400 * 30  // 30 days
        }
    }
    
    // MARK: - Preferences Management
    
    private func loadPreferences(for userId: String) async {
        // Return cached prefs if still fresh (avoids Firestore read on every route() call)
        if let (cached, fetchedAt) = preferencesCache[userId],
           Date().timeIntervalSince(fetchedAt) < preferencesCacheTTL {
            self.userPreferences = cached
            return
        }

        let doc = try? await db.collection("users").document(userId)
            .collection("settings").document("notifications").getDocument()

        if let data = doc?.data(),
           let jsonData = try? JSONSerialization.data(withJSONObject: data),
           let prefs = try? JSONDecoder().decode(SmartNotificationPreferences.self, from: jsonData) {
            self.userPreferences = prefs
            preferencesCache[userId] = (prefs, Date())
        } else {
            let defaultPrefs = SmartNotificationPreferences()
            self.userPreferences = defaultPrefs
            preferencesCache[userId] = (defaultPrefs, Date())
        }
    }
    
    private func isCategoryEnabled(_ category: NotificationCategory) -> Bool {
        let setting = userPreferences.categorySettings[category] ?? category.defaultSetting
        return setting.mode != .off
    }
    
    private func getPreferenceBoost(category: NotificationCategory) -> Double {
        switch userPreferences.mode {
        case .meaningful: return 0.0
        case .balanced: return 0.05
        case .everything: return 0.1
        }
    }
}
