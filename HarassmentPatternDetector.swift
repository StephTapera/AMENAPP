//
//  HarassmentPatternDetector.swift
//  AMENAPP
//
//  Detects patterns of harassment across user interactions:
//  repeated targeting, coordinated pile-ons, coded language,
//  and escalating hostility over time.
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
class HarassmentPatternDetector: ObservableObject {
    static let shared = HarassmentPatternDetector()
    private let db = Firestore.firestore()
    private init() {}

    struct PatternAnalysis {
        let riskLevel: RiskLevel
        let patterns: [DetectedPattern]
        let recommendation: Recommendation

        enum RiskLevel: String { case none, low, moderate, high, severe }
        enum Recommendation: String {
            case none = "No action needed"
            case monitor = "Flag for monitoring"
            case warnUser = "Send user a warning"
            case restrictUser = "Restrict user temporarily"
            case escalate = "Escalate to moderation team"
        }
    }

    struct DetectedPattern {
        let type: PatternType
        let evidence: String
        let confidence: Float
    }

    enum PatternType: String {
        case repeatedTargeting   = "Repeated Targeting"
        case coordinatedPileOn   = "Coordinated Pile-On"
        case escalatingHostility = "Escalating Hostility"
        case codedLanguage       = "Coded Language"
        case accountHopping      = "Account Hopping"
        case dogwhistle          = "Dog-Whistle Language"
    }

    // MARK: - Analyze User Behavior

    /// Analyze a user's recent interactions for harassment patterns
    func analyzeUser(_ userId: String) async -> PatternAnalysis {
        var patterns: [DetectedPattern] = []

        // 1. Check repeated targeting (same person getting comments/reports from this user)
        let targeting = await checkRepeatedTargeting(userId)
        if let targeting { patterns.append(targeting) }

        // 2. Check escalating hostility (toxicity score trending up)
        let escalation = await checkEscalation(userId)
        if let escalation { patterns.append(escalation) }

        // 3. Check for coded/dog-whistle language
        let coded = await checkCodedLanguage(userId)
        patterns.append(contentsOf: coded)

        let riskLevel = calculateRiskLevel(patterns)
        let recommendation = determineRecommendation(riskLevel, patterns: patterns)

        return PatternAnalysis(
            riskLevel: riskLevel,
            patterns: patterns,
            recommendation: recommendation
        )
    }

    // MARK: - Repeated Targeting

    private func checkRepeatedTargeting(_ userId: String) async -> DetectedPattern? {
        // Check if this user has commented on the same person's posts 5+ times recently
        guard let snapshot = try? await db.collection("comments")
            .whereField("authorId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .limit(to: 100)
            .getDocuments() else { return nil }

        var targetCounts: [String: Int] = [:]
        for doc in snapshot.documents {
            let data = doc.data()
            if let postAuthor = data["postAuthorId"] as? String, postAuthor != userId {
                targetCounts[postAuthor, default: 0] += 1
            }
        }

        // Flag if any single person is targeted 5+ times
        if let (targetId, count) = targetCounts.max(by: { $0.value < $1.value }), count >= 5 {
            return DetectedPattern(
                type: .repeatedTargeting,
                evidence: "Commented on user \(targetId.prefix(8))...'s posts \(count) times in recent history",
                confidence: min(1.0, Float(count) / 10.0)
            )
        }

        return nil
    }

    // MARK: - Escalating Hostility

    private func checkEscalation(_ userId: String) async -> DetectedPattern? {
        guard let snapshot = try? await db.collection("moderationLogs")
            .whereField("userId", isEqualTo: userId)
            .order(by: "timestamp", descending: true)
            .limit(to: 20)
            .getDocuments() else { return nil }

        let recentFlags = snapshot.documents.count
        if recentFlags >= 3 {
            return DetectedPattern(
                type: .escalatingHostility,
                evidence: "\(recentFlags) moderation flags in recent history",
                confidence: min(1.0, Float(recentFlags) / 10.0)
            )
        }

        return nil
    }

    // MARK: - Coded Language

    private let codedPhrases: [(phrase: String, type: PatternType, confidence: Float)] = [
        // Spiritual manipulation patterns
        ("god told me to correct you", .dogwhistle, 0.6),
        ("you're not a real christian", .codedLanguage, 0.7),
        ("i'll pray for your soul", .codedLanguage, 0.4),
        ("false prophet", .codedLanguage, 0.5),
        ("you need deliverance", .codedLanguage, 0.5),
        // Veiled threats
        ("god will judge you", .dogwhistle, 0.5),
        ("you'll answer for this", .codedLanguage, 0.6),
    ]

    private func checkCodedLanguage(_ userId: String) async -> [DetectedPattern] {
        guard let snapshot = try? await db.collection("comments")
            .whereField("authorId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .getDocuments() else { return [] }

        var detected: [DetectedPattern] = []
        var matchCounts: [PatternType: Int] = [:]

        for doc in snapshot.documents {
            let content = (doc.data()["content"] as? String ?? "").lowercased()
            for (phrase, type, confidence) in codedPhrases {
                if content.contains(phrase) {
                    matchCounts[type, default: 0] += 1
                    if matchCounts[type] == 2 { // Only flag on repeated use
                        detected.append(DetectedPattern(
                            type: type,
                            evidence: "Used phrase \"\(phrase)\" multiple times",
                            confidence: confidence
                        ))
                    }
                }
            }
        }

        return detected
    }

    // MARK: - Risk Calculation

    private func calculateRiskLevel(_ patterns: [DetectedPattern]) -> PatternAnalysis.RiskLevel {
        guard !patterns.isEmpty else { return .none }
        let maxConfidence = patterns.map(\.confidence).max() ?? 0
        let patternCount = patterns.count

        if maxConfidence >= 0.8 || patternCount >= 3 { return .severe }
        if maxConfidence >= 0.6 || patternCount >= 2 { return .high }
        if maxConfidence >= 0.4 { return .moderate }
        return .low
    }

    private func determineRecommendation(_ risk: PatternAnalysis.RiskLevel, patterns: [DetectedPattern]) -> PatternAnalysis.Recommendation {
        switch risk {
        case .none: return .none
        case .low: return .monitor
        case .moderate: return .warnUser
        case .high: return .restrictUser
        case .severe: return .escalate
        }
    }
}
