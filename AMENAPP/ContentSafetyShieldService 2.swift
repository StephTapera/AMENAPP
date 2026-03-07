//
//  ContentSafetyShieldService.swift
//  AMENAPP
//
//  AI-Powered Content Moderation Shield
//  Proactive real-time content filtering for user safety
//

import Foundation
import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth

@MainActor
class ContentSafetyShieldService: ObservableObject {
    static let shared = ContentSafetyShieldService()
    
    @Published var isAutoModerationEnabled = true
    @Published var detectionStats = ModerationStats()
    
    private let db = Firestore.firestore()
    private let moderationService = ModerationService.shared
    
    // Detection settings
    private var detectBullying = true
    private var detectSexualContent = true
    private var detectViolence = true
    private var detectHarassment = true
    private var autoHideContent = true
    
    struct ModerationStats {
        var totalScanned = 0
        var totalFlagged = 0
        var totalHidden = 0
        var lastScanTime: Date?
    }
    
    enum ThreatLevel: Int, Comparable {
        case safe = 0
        case low = 25
        case medium = 50
        case high = 75
        case critical = 100
        
        static func < (lhs: ThreatLevel, rhs: ThreatLevel) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
        
        var description: String {
            switch self {
            case .safe: return "Safe"
            case .low: return "Low Risk"
            case .medium: return "Medium Risk"
            case .high: return "High Risk"
            case .critical: return "Critical"
            }
        }
        
        var color: String {
            switch self {
            case .safe: return "green"
            case .low: return "yellow"
            case .medium: return "orange"
            case .high: return "red"
            case .critical: return "red"
            }
        }
    }
    
    struct ContentSafetyResult {
        let isAllowed: Bool
        let threatLevel: ThreatLevel
        let threatScore: Int // 0-100
        let reasons: [String]
        let shouldBlur: Bool
        let warningMessage: String?
    }
    
    private init() {}
    
    // MARK: - Configuration
    
    func enableAutoModeration(
        detectBullying: Bool = true,
        detectSexualContent: Bool = true,
        detectViolence: Bool = true,
        detectHarassment: Bool = true,
        autoHide: Bool = true
    ) {
        self.detectBullying = detectBullying
        self.detectSexualContent = detectSexualContent
        self.detectViolence = detectViolence
        self.detectHarassment = detectHarassment
        self.autoHideContent = autoHide
        self.isAutoModerationEnabled = true
        
        print("🛡️ Content Safety Shield ENABLED")
        print("   - Bullying Detection: \(detectBullying)")
        print("   - Sexual Content: \(detectSexualContent)")
        print("   - Violence Detection: \(detectViolence)")
        print("   - Harassment Detection: \(detectHarassment)")
        print("   - Auto-Hide: \(autoHide)")
    }
    
    func disableAutoModeration() {
        isAutoModerationEnabled = false
        print("🛡️ Content Safety Shield DISABLED")
    }
    
    // MARK: - Content Screening
    
    func screenContent(_ content: String, userId: String? = nil) async -> ContentSafetyResult {
        guard isAutoModerationEnabled else {
            return ContentSafetyResult(
                isAllowed: true,
                threatLevel: .safe,
                threatScore: 0,
                reasons: [],
                shouldBlur: false,
                warningMessage: nil
            )
        }
        
        detectionStats.totalScanned += 1
        detectionStats.lastScanTime = Date()
        
        // Use existing ModerationService for AI detection
        // Note: This calls the backend moderation API
        // For now, use a simple keyword-based approach
        let result = await performSimpleModeration(content: content)
        
        var threatScore = 0
        var reasons: [String] = []
        var threatLevel: ThreatLevel = .safe
        
        // Analyze moderation result
        if result.containsBullying && detectBullying {
            threatScore += 35
            reasons.append("Potential bullying detected")
        }
        
        if result.containsSexualContent && detectSexualContent {
            threatScore += 40
            reasons.append("Inappropriate content detected")
        }
        
        if result.containsViolence && detectViolence {
            threatScore += 35
            reasons.append("Violent content detected")
        }
        
        if result.containsHarassment && detectHarassment {
            threatScore += 30
            reasons.append("Harassment detected")
        }
        
        // Determine threat level
        switch threatScore {
        case 0..<25:
            threatLevel = .safe
        case 25..<50:
            threatLevel = .low
        case 50..<75:
            threatLevel = .medium
        case 75..<90:
            threatLevel = .high
        default:
            threatLevel = .critical
        }
        
        let shouldBlur = threatScore >= 50 && autoHideContent
        let isAllowed = threatScore < 90 // Block critical content
        
        if threatScore > 0 {
            detectionStats.totalFlagged += 1
        }
        
        if shouldBlur {
            detectionStats.totalHidden += 1
        }
        
        let warningMessage = generateWarningMessage(for: threatLevel, reasons: reasons)
        
        print("🛡️ Content Screened: Score=\(threatScore), Level=\(threatLevel.description), Blur=\(shouldBlur)")
        
        return ContentSafetyResult(
            isAllowed: isAllowed,
            threatLevel: threatLevel,
            threatScore: threatScore,
            reasons: reasons,
            shouldBlur: shouldBlur,
            warningMessage: warningMessage
        )
    }
    
    func screenPost(_ post: Post) async -> ContentSafetyResult {
        let content = post.content
        let userId = post.authorId
        return await screenContent(content, userId: userId)
    }
    
    // Simple moderation helper
    private func performSimpleModeration(content: String) async -> (containsBullying: Bool, containsSexualContent: Bool, containsViolence: Bool, containsHarassment: Bool) {
        let lowerContent = content.lowercased()
        
        let bullyingKeywords = ["stupid", "idiot", "loser", "hate you", "kill yourself"]
        let sexualKeywords = ["sex", "porn", "nude"]
        let violenceKeywords = ["kill", "murder", "attack", "bomb", "shoot"]
        let harassmentKeywords = ["stalk", "harass", "threaten"]
        
        return (
            containsBullying: bullyingKeywords.contains { lowerContent.contains($0) },
            containsSexualContent: sexualKeywords.contains { lowerContent.contains($0) },
            containsViolence: violenceKeywords.contains { lowerContent.contains($0) },
            containsHarassment: harassmentKeywords.contains { lowerContent.contains($0) }
        )
    }
    
    // MARK: - Warning Messages
    
    private func generateWarningMessage(for threatLevel: ThreatLevel, reasons: [String]) -> String? {
        guard threatLevel != .safe else { return nil }
        
        let reasonText = reasons.isEmpty ? "community guidelines" : reasons.joined(separator: ", ")
        
        switch threatLevel {
        case .low:
            return "This content may contain: \(reasonText)"
        case .medium:
            return "⚠️ Sensitive Content: \(reasonText)"
        case .high, .critical:
            return "🚫 Content Hidden: This post contains \(reasonText) and has been hidden for your safety."
        default:
            return nil
        }
    }
    
    // MARK: - User Appeals
    
    func requestReview(postId: String, userId: String, reason: String) async throws {
        try await db.collection("moderationAppeals").document().setData([
            "postId": postId,
            "userId": userId,
            "reason": reason,
            "status": "pending",
            "createdAt": FieldValue.serverTimestamp()
        ])
        
        print("🛡️ Appeal submitted for post: \(postId)")
    }
    
    // MARK: - Statistics
    
    func getStats() -> ModerationStats {
        return detectionStats
    }
    
    func resetStats() {
        detectionStats = ModerationStats()
    }
}
