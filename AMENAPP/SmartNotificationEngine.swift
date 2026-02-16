//
//  SmartNotificationEngine.swift
//  AMENAPP
//
//  Created by Claude on 2/9/26.
//
//  Instagram/Threads-level smart notification prioritization

import Foundation
import FirebaseFirestore
import FirebaseAuth

/// Smart notification engine that prioritizes notifications like Instagram/Threads
/// Uses ML-style scoring to surface the most important notifications first
final class SmartNotificationEngine {
    
    static let shared = SmartNotificationEngine()
    
    private let db = Firestore.firestore()
    
    // MARK: - User Engagement Data
    
    /// Track which users the current user interacts with most
    private var userEngagementScores: [String: Double] = [:]
    
    /// Track notification interaction patterns
    private var notificationInteractionHistory: [String: [Date]] = [:]
    
    private init() {
        loadEngagementData()
    }
    
    // MARK: - Smart Priority Calculation
    
    /// Calculate priority score (0-100) for a notification
    /// Higher scores = more important notifications
    func calculatePriority(for notification: AppNotification) -> Int {
        var score: Double = 50.0  // Base score
        
        // 1. Time Decay (Recency Bonus: 0-20 points)
        let recencyScore = calculateRecencyScore(notification.createdAt.dateValue())
        score += recencyScore
        
        // 2. Interaction Type Weight (0-25 points)
        let typeScore = calculateTypeScore(notification.type)
        score += typeScore
        
        // 3. User Relationship Score (0-25 points)
        if let actorId = notification.actorId {
            let relationshipScore = calculateRelationshipScore(actorId)
            score += relationshipScore
        }
        
        // 4. Engagement Pattern Bonus (0-10 points)
        let engagementBonus = calculateEngagementBonus(notification)
        score += engagementBonus
        
        // Cap at 100
        return min(100, Int(score))
    }
    
    // MARK: - Recency Score
    
    /// Recent notifications get higher priority (Instagram-style)
    private func calculateRecencyScore(_ date: Date) -> Double {
        let now = Date()
        let minutesAgo = now.timeIntervalSince(date) / 60.0
        
        // Exponential decay curve
        // 0-5 min: 20 points
        // 5-30 min: 15 points
        // 30-60 min: 10 points
        // 1-6 hours: 5 points
        // 6+ hours: 0 points
        
        if minutesAgo < 5 {
            return 20.0
        } else if minutesAgo < 30 {
            return 15.0
        } else if minutesAgo < 60 {
            return 10.0
        } else if minutesAgo < 360 {  // 6 hours
            return 5.0
        } else {
            return 0.0
        }
    }
    
    // MARK: - Type Score
    
    /// Different notification types have different importance
    private func calculateTypeScore(_ type: AppNotification.NotificationType) -> Double {
        switch type {
        case .follow, .followRequestAccepted:
            return 20.0  // New connections are important
        case .comment, .reply:
            return 25.0  // Direct engagement is highest priority
        case .mention:
            return 23.0  // Being mentioned is very important
        case .amen:
            return 15.0  // Reactions are nice but less urgent
        case .repost:
            return 18.0  // Someone sharing your content
        case .messageRequestAccepted:
            return 22.0  // Communication opportunities
        case .prayerReminder:
            return 12.0  // Helpful but not urgent
        case .prayerAnswered:
            return 20.0  // Meaningful but not immediate
        case .churchNoteShared:
            return 21.0  // Shared church notes are meaningful content
        case .unknown:
            return 5.0
        }
    }
    
    // MARK: - Relationship Score
    
    /// Notifications from users you interact with more get higher priority
    private func calculateRelationshipScore(_ actorId: String) -> Double {
        // Check if we have engagement data for this user
        if let engagementScore = userEngagementScores[actorId] {
            // Scale engagement score to 0-25 range
            return min(25.0, engagementScore)
        }
        
        // No engagement data = neutral score
        return 10.0
    }
    
    // MARK: - Engagement Pattern Bonus
    
    /// Bonus points for notifications matching user's interaction patterns
    private func calculateEngagementBonus(_ notification: AppNotification) -> Double {
        var bonus = 0.0
        
        // If user typically interacts with this notification type quickly, boost it
        let typeKey = notification.type.rawValue
        if let history = notificationInteractionHistory[typeKey], !history.isEmpty {
            // Calculate average time to interaction
            let sortedHistory = history.sorted(by: >)
            let recentInteractions = Array(sortedHistory.prefix(10))
            
            if !recentInteractions.isEmpty {
                // User regularly interacts with this type = +10 points
                bonus += 10.0
            }
        }
        
        return bonus
    }
    
    // MARK: - Batch Priority Calculation
    
    /// Calculate priorities for all notifications in batch (performance optimized)
    func calculatePriorities(for notifications: [AppNotification]) -> [String: Int] {
        var priorities: [String: Int] = [:]
        
        for notification in notifications {
            if let id = notification.id {
                priorities[id] = calculatePriority(for: notification)
            }
        }
        
        return priorities
    }
    
    // MARK: - Sort Notifications Smartly
    
    /// Sort notifications by priority score (Instagram/Threads algorithm)
    func sortByPriority(_ notifications: [AppNotification]) -> [AppNotification] {
        return notifications.sorted { notification1, notification2 in
            let priority1 = notification1.priority ?? calculatePriority(for: notification1)
            let priority2 = notification2.priority ?? calculatePriority(for: notification2)
            
            if priority1 != priority2 {
                return priority1 > priority2
            }
            
            // If priorities are equal, sort by recency
            return notification1.createdAt.dateValue() > notification2.createdAt.dateValue()
        }
    }
    
    // MARK: - Track User Engagement
    
    /// Update engagement scores when user interacts with someone
    func recordEngagement(withUser userId: String, engagementType: EngagementType) {
        let currentScore = userEngagementScores[userId] ?? 0.0
        let boost = engagementType.scoreBoost
        
        // Add boost but cap at 50
        userEngagementScores[userId] = min(50.0, currentScore + boost)
        
        // Save to UserDefaults for persistence
        saveEngagementData()
    }
    
    enum EngagementType {
        case viewProfile
        case sendMessage
        case followUser
        case likePost
        case commentOnPost
        case sharePost
        
        var scoreBoost: Double {
            switch self {
            case .viewProfile: return 0.5
            case .sendMessage: return 5.0
            case .followUser: return 10.0
            case .likePost: return 1.0
            case .commentOnPost: return 3.0
            case .sharePost: return 4.0
            }
        }
    }
    
    /// Track when user interacts with a notification type
    func recordNotificationInteraction(_ notification: AppNotification) {
        let typeKey = notification.type.rawValue
        var history = notificationInteractionHistory[typeKey] ?? []
        history.append(Date())
        
        // Keep only last 50 interactions per type
        if history.count > 50 {
            history = Array(history.suffix(50))
        }
        
        notificationInteractionHistory[typeKey] = history
        saveEngagementData()
    }
    
    // MARK: - Persistence
    
    private func loadEngagementData() {
        if let data = UserDefaults.standard.data(forKey: "notificationEngagementScores"),
           let scores = try? JSONDecoder().decode([String: Double].self, from: data) {
            userEngagementScores = scores
        }
        
        if let data = UserDefaults.standard.data(forKey: "notificationInteractionHistory"),
           let history = try? JSONDecoder().decode([String: [Date]].self, from: data) {
            notificationInteractionHistory = history
        }
    }
    
    private func saveEngagementData() {
        if let data = try? JSONEncoder().encode(userEngagementScores) {
            UserDefaults.standard.set(data, forKey: "notificationEngagementScores")
        }
        
        if let data = try? JSONEncoder().encode(notificationInteractionHistory) {
            UserDefaults.standard.set(data, forKey: "notificationInteractionHistory")
        }
    }
    
    // MARK: - Smart Grouping
    
    /// Group similar notifications together (like Instagram)
    /// Example: "John and 5 others liked your post"
    func groupNotifications(_ notifications: [AppNotification]) -> [SmartNotificationGroup] {
        var groups: [String: [AppNotification]] = [:]
        
        for notification in notifications {
            // Create group key based on type and post
            let groupKey: String
            if let postId = notification.postId {
                groupKey = "\(notification.type.rawValue)_\(postId)"
            } else {
                // Standalone notifications (follows, etc.)
                groupKey = "\(notification.type.rawValue)_\(notification.id ?? UUID().uuidString)"
            }
            
            groups[groupKey, default: []].append(notification)
        }
        
        // Convert to SmartNotificationGroup objects
        return groups.compactMap { key, notifs in
            SmartNotificationGroup(notifications: notifs)
        }
    }
}

// MARK: - Smart Notification Group Model (distinct from NotificationsView's NotificationGroup)

struct SmartNotificationGroup: Identifiable, Hashable {
    let id: String
    let type: AppNotification.NotificationType
    let notifications: [AppNotification]
    let primaryNotification: AppNotification  // The most important one to display
    let postId: String?
    let timestamp: Date
    let priority: Int
    
    init?(notifications: [AppNotification]) {
        guard !notifications.isEmpty else { return nil }
        
        // Sort by priority and recency
        let sorted = notifications.sorted { n1, n2 in
            let priority1 = n1.priority ?? 50
            let priority2 = n2.priority ?? 50
            if priority1 != priority2 {
                return priority1 > priority2
            }
            return n1.createdAt.dateValue() > n2.createdAt.dateValue()
        }
        
        guard let primary = sorted.first else { return nil }
        
        self.id = primary.id ?? UUID().uuidString
        self.type = primary.type
        self.notifications = sorted
        self.primaryNotification = primary
        self.postId = primary.postId
        self.timestamp = primary.createdAt.dateValue()
        
        // Use shared instance's calculatePriority method
        let engine = SmartNotificationEngine.shared
        self.priority = primary.priority ?? engine.calculatePriority(for: primary)
    }
    
    var isGrouped: Bool {
        notifications.count > 1
    }
    
    var count: Int {
        notifications.count
    }
    
    var actorNames: [String] {
        notifications.compactMap { $0.actorName }
    }
    
    var actorProfileImages: [String] {
        notifications.compactMap { $0.actorProfileImageURL }.filter { !$0.isEmpty }
    }
    
    /// Display text like "John and 3 others liked your post"
    var displayText: String {
        guard let firstName = primaryNotification.actorName else {
            return primaryNotification.actionText
        }
        
        if notifications.count == 1 {
            return "\(firstName) \(primaryNotification.actionText)"
        } else if notifications.count == 2 {
            let secondName = notifications[1].actorName ?? "someone"
            return "\(firstName) and \(secondName) \(primaryNotification.actionText)"
        } else {
            let othersCount = notifications.count - 1
            return "\(firstName) and \(othersCount) others \(primaryNotification.actionText)"
        }
    }
    
    var timeAgo: String {
        primaryNotification.timeAgo
    }
    
    var isRead: Bool {
        notifications.allSatisfy { $0.read }
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: SmartNotificationGroup, rhs: SmartNotificationGroup) -> Bool {
        lhs.id == rhs.id
    }
}
