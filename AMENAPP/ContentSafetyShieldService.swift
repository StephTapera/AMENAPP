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
        
        // Use ContentRiskAnalyzer for AI-grade, context-aware scoring.
        // This replaces the old simple keyword approach with 100+ weighted signals
        // covering grooming, trafficking, explicit sexual content, harassment,
        // violence threats, profanity/hate, spam/scam, and self-harm.
        let riskResult = ContentRiskAnalyzer.shared.analyze(text: content, context: .unknown)

        var threatScore = 0
        var reasons: [String] = []
        var threatLevel: ThreatLevel = .safe

        // Map ContentRiskAnalyzer categories to the legacy shield result format.
        // Score scale: ContentRiskAnalyzer is 0.0–1.0; ThreatLevel expects 0–100.
        let categoryScores: [ContentRiskCategory: Double] = riskResult.categoryScores

        if detectHarassment {
            let score = max(
                categoryScores[ContentRiskCategory.harassmentExploitation] ?? 0,
                categoryScores[ContentRiskCategory.profanityHate] ?? 0
            )
            if score >= 0.25 {
                let points = Int(score * 80)
                threatScore += points
                reasons.append("Harassment or hostile language detected")
            }
        }

        if detectSexualContent {
            let score = max(
                categoryScores[ContentRiskCategory.explicitSexual] ?? 0,
                categoryScores[ContentRiskCategory.groomingTrafficking] ?? 0
            )
            if score >= 0.20 {
                let points = Int(score * 100)
                threatScore += points
                reasons.append("Potentially inappropriate content detected")
            }
        }

        if detectViolence {
            let score = categoryScores[ContentRiskCategory.violenceThreat] ?? 0
            if score >= 0.25 {
                let points = Int(score * 80)
                threatScore += points
                reasons.append("Violent or threatening language detected")
            }
        }

        if detectBullying {
            // Bullying overlaps with harassment; also pick up direct-attack signals
            let score = categoryScores[ContentRiskCategory.harassmentExploitation] ?? 0
            if score >= 0.30 {
                let points = Int(score * 60)
                threatScore = max(threatScore, points) // don't double-count with harassment
                if !reasons.contains("Harassment or hostile language detected") {
                    reasons.append("Bullying or targeted attack detected")
                }
            }
        }

        // Cap at 100
        threatScore = min(threatScore, 100)
        
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
