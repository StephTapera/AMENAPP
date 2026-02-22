//
//  InteractionThrottleService.swift
//  AMENAPP
//
//  Smart rate-limiting and anti-spam intelligence
//  Prevents harassment, spam, and coordinated attacks
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
class InteractionThrottleService: ObservableObject {
    static let shared = InteractionThrottleService()
    
    @Published var isThrottlingEnabled = true
    @Published var detectionStats = ThrottleStats()
    
    private let db = Firestore.firestore()
    
    // Track user interactions
    private var interactionHistory: [String: [InteractionRecord]] = [:] // userId -> records
    private var suspiciousUsers: Set<String> = []
    
    struct ThrottleStats {
        var totalInteractions = 0
        var totalThrottled = 0
        var totalSpamDetected = 0
        var totalBrigadingDetected = 0
    }
    
    struct InteractionRecord {
        let action: InteractionAction
        let targetId: String
        let timestamp: Date
        let metadata: [String: Any]?
    }
    
    enum InteractionAction: String {
        case lightbulb
        case amen
        case comment
        case repost
        case follow
        case report
        case message
    }
    
    struct ThrottleResult {
        let allowed: Bool
        let reason: String?
        let waitTime: TimeInterval? // Seconds to wait
        let threatLevel: ThreatLevel
    }
    
    enum ThreatLevel {
        case normal
        case suspicious
        case spam
        case brigading
    }
    
    // Rate limits (per action type)
    private let limits: [InteractionAction: RateLimit] = [
        .lightbulb: RateLimit(maxPer60Seconds: 30, minDelaySeconds: 0.5),
        .amen: RateLimit(maxPer60Seconds: 30, minDelaySeconds: 0.5),
        .comment: RateLimit(maxPer60Seconds: 6, minDelaySeconds: 10),
        .repost: RateLimit(maxPer60Seconds: 5, minDelaySeconds: 12),
        .follow: RateLimit(maxPer60Seconds: 20, minDelaySeconds: 2),
        .report: RateLimit(maxPer24Hours: 3, minDelaySeconds: 60),
        .message: RateLimit(maxPer60Seconds: 10, minDelaySeconds: 5)
    ]
    
    struct RateLimit {
        let maxPer60Seconds: Int?
        let maxPer24Hours: Int?
        let minDelaySeconds: TimeInterval
        
        init(maxPer60Seconds: Int? = nil, maxPer24Hours: Int? = nil, minDelaySeconds: TimeInterval) {
            self.maxPer60Seconds = maxPer60Seconds
            self.maxPer24Hours = maxPer24Hours
            self.minDelaySeconds = minDelaySeconds
        }
    }
    
    private init() {
        // Clean up old records periodically
        Task {
            await cleanupOldRecords()
        }
    }
    
    // MARK: - Main Throttle Check
    
    func checkInteraction(
        userId: String,
        action: InteractionAction,
        targetPostId: String? = nil,
        targetUserId: String? = nil
    ) async -> ThrottleResult {
        
        guard isThrottlingEnabled else {
            return ThrottleResult(allowed: true, reason: nil, waitTime: nil, threatLevel: .normal)
        }
        
        detectionStats.totalInteractions += 1
        
        // Get user's interaction history
        var userHistory = interactionHistory[userId] ?? []
        let now = Date()
        
        // Remove old records (keep last 24 hours)
        userHistory = userHistory.filter { now.timeIntervalSince($0.timestamp) < 86400 }
        
        // Get rate limit for this action
        guard let limit = limits[action] else {
            return ThrottleResult(allowed: true, reason: nil, waitTime: nil, threatLevel: .normal)
        }
        
        // Check 1: Minimum delay between actions
        if let lastAction = userHistory.last(where: { $0.action == action }) {
            let timeSinceLastAction = now.timeIntervalSince(lastAction.timestamp)
            if timeSinceLastAction < limit.minDelaySeconds {
                detectionStats.totalThrottled += 1
                let waitTime = limit.minDelaySeconds - timeSinceLastAction
                return ThrottleResult(
                    allowed: false,
                    reason: "Please wait \(Int(waitTime)) seconds between \(action.rawValue) actions",
                    waitTime: waitTime,
                    threatLevel: .normal
                )
            }
        }
        
        // Check 2: Max per 60 seconds
        if let max60 = limit.maxPer60Seconds {
            let recent60 = userHistory.filter {
                $0.action == action && now.timeIntervalSince($0.timestamp) < 60
            }
            if recent60.count >= max60 {
                detectionStats.totalThrottled += 1
                return ThrottleResult(
                    allowed: false,
                    reason: "Too many \(action.rawValue) actions. Please slow down.",
                    waitTime: 60,
                    threatLevel: .suspicious
                )
            }
        }
        
        // Check 3: Max per 24 hours
        if let max24h = limit.maxPer24Hours {
            let recent24h = userHistory.filter {
                $0.action == action && now.timeIntervalSince($0.timestamp) < 86400
            }
            if recent24h.count >= max24h {
                detectionStats.totalThrottled += 1
                return ThrottleResult(
                    allowed: false,
                    reason: "Daily limit for \(action.rawValue) reached. Try again tomorrow.",
                    waitTime: nil,
                    threatLevel: .suspicious
                )
            }
        }
        
        // Check 4: Spam detection - same content across multiple posts
        if action == .comment, let targetId = targetPostId {
            let recentComments = userHistory.filter {
                $0.action == .comment && now.timeIntervalSince($0.timestamp) < 300 // 5 minutes
            }
            
            // If commenting on 5+ different posts in 5 minutes, likely spam
            let uniqueTargets = Set(recentComments.map { $0.targetId })
            if uniqueTargets.count >= 5 {
                detectionStats.totalSpamDetected += 1
                markUserAsSuspicious(userId: userId, reason: "Rapid commenting across multiple posts")
                return ThrottleResult(
                    allowed: false,
                    reason: "Slow down! You're commenting too quickly across multiple posts.",
                    waitTime: 300,
                    threatLevel: .spam
                )
            }
        }
        
        // Check 5: Harassment pattern - user visiting profile then commenting negatively on all posts
        if action == .comment, let targetUserId = targetUserId {
            let recentInteractions = userHistory.filter {
                ($0.action == .comment || $0.action == .lightbulb) &&
                now.timeIntervalSince($0.timestamp) < 600 && // 10 minutes
                $0.metadata?["targetUserId"] as? String == targetUserId
            }
            
            // If interacting with same user's posts 10+ times in 10 minutes
            if recentInteractions.count >= 10 {
                detectionStats.totalBrigadingDetected += 1
                markUserAsSuspicious(userId: userId, reason: "Potential harassment pattern detected")
                return ThrottleResult(
                    allowed: false,
                    reason: "Take a break. You've been interacting with this user's content frequently.",
                    waitTime: 600,
                    threatLevel: .brigading
                )
            }
        }
        
        // Check 6: Brigading detection - multiple users hitting same post rapidly
        if let targetId = targetPostId {
            await detectBrigading(targetPostId: targetId, action: action)
        }
        
        // Record this interaction
        let record = InteractionRecord(
            action: action,
            targetId: targetPostId ?? targetUserId ?? "unknown",
            timestamp: now,
            metadata: targetUserId != nil ? ["targetUserId": targetUserId!] : nil
        )
        userHistory.append(record)
        interactionHistory[userId] = userHistory
        
        return ThrottleResult(
            allowed: true,
            reason: nil,
            waitTime: nil,
            threatLevel: suspiciousUsers.contains(userId) ? .suspicious : .normal
        )
    }
    
    // MARK: - Spam Detection
    
    private func markUserAsSuspicious(userId: String, reason: String) {
        suspiciousUsers.insert(userId)
        
        // Log to Firestore for admin review
        Task {
            try? await db.collection("suspiciousActivity").document().setData([
                "userId": userId,
                "reason": reason,
                "timestamp": FieldValue.serverTimestamp(),
                "type": "throttle_violation"
            ])
        }
        
        print("🚨 User marked as suspicious: \(userId) - \(reason)")
    }
    
    private func detectBrigading(targetPostId: String, action: InteractionAction) async {
        // Check if multiple users are hitting the same post from similar IPs/patterns
        // This would require additional backend infrastructure
        // For now, we'll log potential brigading for manual review
        
        let allRecords = interactionHistory.values.flatMap { $0 }
        let recentOnPost = allRecords.filter {
            $0.targetId == targetPostId &&
            $0.action == action &&
            Date().timeIntervalSince($0.timestamp) < 300 // 5 minutes
        }
        
        // If 20+ different users interacted with same post in 5 minutes
        if recentOnPost.count >= 20 {
            print("⚠️ Potential brigading detected on post: \(targetPostId)")
            
            try? await db.collection("brigadingAlerts").document().setData([
                "postId": targetPostId,
                "action": action.rawValue,
                "interactionCount": recentOnPost.count,
                "timestamp": FieldValue.serverTimestamp()
            ])
        }
    }
    
    // MARK: - Cleanup
    
    private func cleanupOldRecords() async {
        while true {
            try? await Task.sleep(for: .seconds(3600)) // Every hour
            
            let now = Date()
            for (userId, records) in interactionHistory {
                let recentRecords = records.filter {
                    now.timeIntervalSince($0.timestamp) < 86400 // Keep 24 hours
                }
                if recentRecords.isEmpty {
                    interactionHistory.removeValue(forKey: userId)
                } else {
                    interactionHistory[userId] = recentRecords
                }
            }
            
            print("🧹 Cleaned up old interaction records")
        }
    }
    
    // MARK: - Admin Functions
    
    func resetUserThrottle(userId: String) {
        interactionHistory.removeValue(forKey: userId)
        suspiciousUsers.remove(userId)
        print("✅ Reset throttle for user: \(userId)")
    }
    
    func getStats() -> ThrottleStats {
        return detectionStats
    }
    
    func resetStats() {
        detectionStats = ThrottleStats()
    }
    
    func isUserSuspicious(userId: String) -> Bool {
        return suspiciousUsers.contains(userId)
    }
}
