//
//  MLNotificationClassifier.swift
//  AMENAPP
//
//  Machine learning-based intent and safety detection for notifications
//

import Foundation
import NaturalLanguage
import CoreML
import FirebaseFirestore

/// ML-powered notification content classifier
@MainActor
class MLNotificationClassifier: ObservableObject {
    static let shared = MLNotificationClassifier()

    // MARK: - Intent Detection

    /// Detect intent from notification content using NLP
    func detectIntent(content: String, category: NotificationCategory) async -> NotificationIntent {
        // Use Apple's NaturalLanguage framework for on-device ML

        let tagger = NLTagger(tagSchemes: [.sentimentScore, .lemma])
        tagger.string = content

        var intentType: NotificationIntent.IntentType = .informational
        var priorityBoost: Double = 0.0
        var confidence: Double = 0.5
        var keywords: [String] = []

        // 1. Sentiment Analysis
        let (sentiment, sentimentConfidence) = analyzeSentiment(content, tagger: tagger)

        // 2. Question Detection
        let hasQuestion = detectQuestion(content)
        if hasQuestion {
            intentType = .question
            priorityBoost += 0.3
            keywords.append("question")
        }

        // 3. Urgency Detection
        let urgencyScore = detectUrgency(content)
        if urgencyScore > 0.6 {
            intentType = .urgent
            priorityBoost += urgencyScore * 0.4
            keywords.append("urgent")
        }

        // 4. Prayer Request Detection
        if category == .prayerUpdates || detectPrayerKeywords(content) {
            intentType = .prayerRequest
            priorityBoost += 0.2
            keywords.append("prayer")
        }

        // 5. Personal/Direct Detection
        if detectPersonalAddress(content) {
            priorityBoost += 0.2
            keywords.append("personal")
        }

        // 6. Scripture Reference Detection
        if detectScriptureReference(content) {
            priorityBoost += 0.1
            keywords.append("scripture")
        }

        // Calculate final confidence
        confidence = calculateIntentConfidence(
            sentiment: sentimentConfidence,
            hasQuestion: hasQuestion,
            urgencyScore: urgencyScore
        )

        return NotificationIntent(
            type: intentType,
            priorityBoost: priorityBoost,
            confidence: confidence,
            sentiment: sentiment,
            detectedKeywords: keywords
        )
    }

    private func analyzeSentiment(_ text: String, tagger: NLTagger) -> (NotificationIntent.Sentiment, Double) {
        var sentimentScore: Double = 0.0
        var confidence: Double = 0.0

        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .paragraph, scheme: .sentimentScore) { tag, _ in
            if let tag = tag,
               let score = Double(tag.rawValue) {
                sentimentScore = score
                confidence = abs(score)  // Distance from neutral (0)
            }
            return true
        }

        let sentiment: NotificationIntent.Sentiment
        if sentimentScore > 0.3 {
            sentiment = .positive
        } else if sentimentScore < -0.3 {
            sentiment = .negative
        } else {
            sentiment = .neutral
        }

        return (sentiment, confidence)
    }

    private func detectQuestion(_ text: String) -> Bool {
        // Check for question marks
        if text.contains("?") {
            return true
        }

        // Check for question keywords
        let questionStarters = ["what", "when", "where", "why", "how", "who", "can you", "could you", "would you", "will you", "are you", "do you"]
        let lowercased = text.lowercased()

        return questionStarters.contains { lowercased.contains($0) }
    }

    private func detectUrgency(_ text: String) -> Double {
        let urgentKeywords: [String: Double] = [
            "urgent": 1.0,
            "emergency": 1.0,
            "asap": 0.9,
            "immediately": 0.9,
            "right now": 0.8,
            "need help": 0.8,
            "please help": 0.8,
            "crisis": 1.0,
            "struggling": 0.7,
            "hurting": 0.7,
            "desperate": 0.9,
            "today": 0.4,
            "soon": 0.3
        ]

        let lowercased = text.lowercased()
        var maxScore: Double = 0.0

        for (keyword, score) in urgentKeywords {
            if lowercased.contains(keyword) {
                maxScore = max(maxScore, score)
            }
        }

        return maxScore
    }

    private func detectPrayerKeywords(_ text: String) -> Bool {
        let prayerKeywords = ["pray", "prayer", "praying", "intercession", "petition", "amen"]
        let lowercased = text.lowercased()

        return prayerKeywords.contains { lowercased.contains($0) }
    }

    private func detectPersonalAddress(_ text: String) -> Bool {
        // Check for "you" or direct address patterns
        let personalPatterns = ["you ", " you", "@", "your", "you're"]
        let lowercased = text.lowercased()

        return personalPatterns.contains { lowercased.contains($0) }
    }

    private func detectScriptureReference(_ text: String) -> Bool {
        // Simple regex for Bible references (e.g., John 3:16, Romans 8:28)
        let pattern = #"\b[1-3]?\s?[A-Z][a-z]+\s+\d+:\d+(-\d+)?\b"#

        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        return regex?.firstMatch(in: text, range: range) != nil
    }

    private func calculateIntentConfidence(sentiment: Double, hasQuestion: Bool, urgencyScore: Double) -> Double {
        var confidence = 0.5  // Base confidence

        // Higher sentiment confidence = higher overall confidence
        confidence += sentiment * 0.2

        // Questions are easier to detect
        if hasQuestion {
            confidence += 0.2
        }

        // High urgency keywords are strong signals
        confidence += urgencyScore * 0.3

        return min(1.0, confidence)
    }

    // MARK: - Safety Detection

    /// Detect spam, harassment, or inappropriate content
    func assessSafety(content: String, fromUserId: String) async -> SafetyAssessment {
        var safetyScore: Double = 1.0  // Start safe
        var flags: [SafetyAssessment.SafetyFlag] = []

        // 1. Spam Detection
        let spamScore = detectSpam(content)
        if spamScore > 0.6 {
            safetyScore -= spamScore * 0.5
            flags.append(.potentialSpam(confidence: spamScore))
        }

        // 2. Profanity Detection
        let profanityScore = detectProfanity(content)
        if profanityScore > 0.5 {
            safetyScore -= profanityScore * 0.4
            flags.append(.profanity(confidence: profanityScore))
        }

        // 3. Harassment Detection
        let harassmentScore = detectHarassment(content)
        if harassmentScore > 0.5 {
            safetyScore -= harassmentScore * 0.6
            flags.append(.harassment(confidence: harassmentScore))
        }

        // 4. Link/Phishing Detection
        let linkScore = detectSuspiciousLinks(content)
        if linkScore > 0.6 {
            safetyScore -= linkScore * 0.3
            flags.append(.suspiciousLinks(confidence: linkScore))
        }

        // 5. User History Check
        let userRiskScore = await checkUserHistory(userId: fromUserId)
        safetyScore *= (1.0 - userRiskScore)

        // Normalize to 0-1
        safetyScore = max(0.0, min(1.0, safetyScore))

        return SafetyAssessment(
            safetyScore: safetyScore,
            flags: flags,
            shouldBlock: safetyScore < 0.3,
            shouldReview: safetyScore < 0.6
        )
    }

    private func detectSpam(_ text: String) -> Double {
        var score: Double = 0.0

        // Check for excessive capitalization
        let uppercaseCount = text.filter { $0.isUppercase }.count
        let uppercaseRatio = Double(uppercaseCount) / max(1, Double(text.count))
        if uppercaseRatio > 0.7 {
            score += 0.4
        }

        // Check for excessive punctuation
        let punctuationCount = text.filter { "!?".contains($0) }.count
        if punctuationCount > 5 {
            score += 0.3
        }

        // Check for spam keywords
        let spamKeywords = ["buy now", "click here", "free money", "earn $", "limited time", "act now", "subscribe"]
        let lowercased = text.lowercased()
        for keyword in spamKeywords {
            if lowercased.contains(keyword) {
                score += 0.2
                break
            }
        }

        // Check for repeated characters
        let repeatedPattern = #"(.)\1{3,}"#  // e.g., "heyyyy"
        if text.range(of: repeatedPattern, options: .regularExpression) != nil {
            score += 0.2
        }

        return min(1.0, score)
    }

    private func detectProfanity(_ text: String) -> Double {
        // Use NaturalLanguage profanity filter
        // Note: Apple doesn't provide a built-in profanity list, so you'd maintain your own
        // or use a third-party library

        // Placeholder implementation
        let profanityList = ["damn", "hell"]  // Extend with actual list
        let lowercased = text.lowercased()

        for word in profanityList {
            if lowercased.contains(word) {
                return 0.7
            }
        }

        return 0.0
    }

    private func detectHarassment(_ text: String) -> Double {
        var score: Double = 0.0

        let harassmentKeywords: [String: Double] = [
            "hate": 0.6,
            "stupid": 0.5,
            "idiot": 0.6,
            "shut up": 0.7,
            "kill yourself": 1.0,
            "kys": 1.0,
            "loser": 0.5,
            "worthless": 0.7
        ]

        let lowercased = text.lowercased()
        for (keyword, weight) in harassmentKeywords {
            if lowercased.contains(keyword) {
                score = max(score, weight)
            }
        }

        return score
    }

    private func detectSuspiciousLinks(_ text: String) -> Double {
        // Check for URLs
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, range: NSRange(text.startIndex..., in: text))

        guard let links = matches, !links.isEmpty else {
            return 0.0
        }

        var suspicionScore: Double = 0.0

        // Multiple links = more suspicious
        if links.count > 2 {
            suspicionScore += 0.3
        }

        // Check for shortened URLs (bit.ly, tinyurl, etc.)
        let shortenedDomains = ["bit.ly", "tinyurl", "goo.gl", "t.co"]
        for link in links {
            if let url = (text as NSString).substring(with: link.range) as String?,
               shortenedDomains.contains(where: { url.contains($0) }) {
                suspicionScore += 0.4
                break
            }
        }

        return min(1.0, suspicionScore)
    }

    private func checkUserHistory(userId: String) async -> Double {
        // Check if user has history of spam/harassment reports
        let db = Firestore.firestore()

        do {
            let doc = try await db.collection("users").document(userId)
                .collection("moderationFlags").document("summary").getDocument()

            if let data = doc.data() {
                let reportCount = data["reportCount"] as? Int ?? 0
                let warningCount = data["warningCount"] as? Int ?? 0

                if reportCount > 3 || warningCount > 1 {
                    return 0.5  // High risk
                } else if reportCount > 0 {
                    return 0.2  // Moderate risk
                }
            }
        } catch {
            dlog("❌ Failed to check user history: \(error.localizedDescription)")
        }

        return 0.0  // No history, assume safe
    }
}

// MARK: - Models

struct NotificationIntent {
    enum IntentType {
        case question
        case urgent
        case prayerRequest
        case informational
        case social
        case promotional
    }

    enum Sentiment {
        case positive
        case neutral
        case negative
    }

    let type: IntentType
    let priorityBoost: Double  // 0-1
    let confidence: Double     // 0-1
    let sentiment: Sentiment
    let detectedKeywords: [String]
}

struct SafetyAssessment {
    enum SafetyFlag {
        case potentialSpam(confidence: Double)
        case profanity(confidence: Double)
        case harassment(confidence: Double)
        case suspiciousLinks(confidence: Double)
    }

    let safetyScore: Double  // 0-1, higher = safer
    let flags: [SafetyFlag]
    let shouldBlock: Bool
    let shouldReview: Bool
}
