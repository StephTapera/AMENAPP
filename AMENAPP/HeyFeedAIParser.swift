//
//  HeyFeedAIParser.swift
//  AMENAPP
//
//  Local heuristic parser for detecting post intent and pastoral care signals.
//  No external API calls — pure keyword/pattern matching.
//

import Foundation

// MARK: - HeyFeedIntent

enum HeyFeedIntent: String, Codable, CaseIterable {
    case prayerRequest  = "prayerRequest"
    case testimony      = "testimony"
    case question       = "question"
    case crisis         = "crisis"
    case grief          = "grief"
    case encouragement  = "encouragement"
    case fellowship     = "fellowship"
    case biblicalStudy  = "biblicalStudy"
    case neutral        = "neutral"

    var displayName: String {
        switch self {
        case .prayerRequest: return "Prayer Request"
        case .testimony:     return "Testimony"
        case .question:      return "Question"
        case .crisis:        return "Crisis"
        case .grief:         return "Grief"
        case .encouragement: return "Encouragement"
        case .fellowship:    return "Fellowship"
        case .biblicalStudy: return "Biblical Study"
        case .neutral:       return "Neutral"
        }
    }

    var icon: String {
        switch self {
        case .prayerRequest: return "hands.sparkles"
        case .testimony:     return "star.bubble"
        case .question:      return "questionmark.circle"
        case .crisis:        return "exclamationmark.triangle.fill"
        case .grief:         return "heart.slash"
        case .encouragement: return "sun.max"
        case .fellowship:    return "person.2"
        case .biblicalStudy: return "book.closed"
        case .neutral:       return "text.bubble"
        }
    }

    /// Higher priority = surfaces earlier in pastoral dashboards / safety routing.
    var priority: Int {
        switch self {
        case .crisis:        return 10
        case .prayerRequest: return 8
        case .grief:         return 7
        case .fellowship:    return 6
        case .question:      return 5
        case .testimony:     return 5
        case .encouragement: return 4
        case .biblicalStudy: return 3
        case .neutral:       return 0
        }
    }
}

// MARK: - HeyFeedParseResult

struct HeyFeedParseResult {
    let intent: HeyFeedIntent
    /// 0.0 – 1.0 confidence based on number of matched signals.
    let confidence: Double
    /// The specific keywords/patterns that triggered classification.
    let signals: [String]
    /// True when the post may need pastoral follow-up (crisis or high-confidence grief).
    let needsPastoralAttention: Bool
    /// 0.0 – 1.0 urgency for triage ordering.
    let urgencyScore: Double
}

// MARK: - HeyFeedAIParser

@MainActor
final class HeyFeedAIParser {

    static let shared = HeyFeedAIParser()
    private init() {}

    // MARK: Keyword Dictionaries

    private let crisisKeywords: [String] = [
        "suicidal", "self harm", "want to die", "can't go on",
        "end it all", "no reason to live", "hopeless", "desperate",
        "crying out"
    ]

    private let griefKeywords: [String] = [
        "lost my", "passed away", "died", "grieving",
        "funeral", "mourning", "miss them so much", "departed"
    ]

    private let prayerRequestKeywords: [String] = [
        "please pray", "need prayer", "pray for me", "intercede",
        "lifting up", "standing in prayer", "prayer request"
    ]

    private let testimonyKeywords: [String] = [
        "god answered", "testimony", "miracle happened", "praise report",
        "breakthrough", "god came through", "answered prayer"
    ]

    private let questionKeywords: [String] = [
        "can someone explain", "does anyone know", "confused about",
        "help me understand", "what does", "seeking wisdom",
        "what does the bible say"
    ]

    private let encouragementKeywords: [String] = [
        "encouragement", "blessed someone today", "random act",
        "sharing a blessing", "want to encourage"
    ]

    private let fellowshipKeywords: [String] = [
        "looking for community", "anyone want to", "seeking fellowship",
        "anyone else feel", "connect with others"
    ]

    private let biblicalStudyKeywords: [String] = [
        "studying", "sermon notes", "bible study", "devotional",
        "commentary", "exegesis", "scripture says"
    ]

    // MARK: - Public API

    /// Parses a single post's text and returns a `HeyFeedParseResult`.
    /// - Parameters:
    ///   - text: The full post content string.
    ///   - category: Raw category string from the post (e.g. "prayer", "testimonies").
    func parse(text: String, category: String) -> HeyFeedParseResult {
        let normalised = text.lowercased()

        // Score each intent by counting matched keywords.
        var scores: [(intent: HeyFeedIntent, matches: [String])] = []

        scores.append((
            .crisis,
            matchedSignals(in: normalised, keywords: crisisKeywords)
        ))
        scores.append((
            .grief,
            matchedSignals(in: normalised, keywords: griefKeywords)
        ))
        scores.append((
            .prayerRequest,
            matchedSignals(in: normalised, keywords: prayerRequestKeywords)
        ))
        scores.append((
            .testimony,
            matchedSignals(in: normalised, keywords: testimonyKeywords)
        ))
        scores.append((
            .question,
            matchedSignals(in: normalised, keywords: questionKeywords)
        ))
        scores.append((
            .encouragement,
            matchedSignals(in: normalised, keywords: encouragementKeywords)
        ))
        scores.append((
            .fellowship,
            matchedSignals(in: normalised, keywords: fellowshipKeywords)
        ))
        scores.append((
            .biblicalStudy,
            matchedSignals(in: normalised, keywords: biblicalStudyKeywords)
        ))

        // Apply category hint: boost score for the matching intent.
        let categoryBoostIntent = hintIntent(from: category)

        // Pick the intent with the most matches; break ties by priority.
        let best = scores
            .filter { !$0.matches.isEmpty }
            .sorted {
                let aCount = $0.matches.count + (categoryBoostIntent == $0.intent ? 1 : 0)
                let bCount = $1.matches.count + (categoryBoostIntent == $1.intent ? 1 : 0)
                if aCount != bCount { return aCount > bCount }
                return $0.intent.priority > $1.intent.priority
            }
            .first

        guard let winner = best else {
            // No keyword matched — return neutral.
            return HeyFeedParseResult(
                intent: .neutral,
                confidence: 0.0,
                signals: [],
                needsPastoralAttention: false,
                urgencyScore: 0.0
            )
        }

        let confidence = confidence(for: winner.matches.count)
        let urgency    = urgencyScore(for: winner.intent, confidence: confidence)
        let pastoral   = needsPastoralAttention(intent: winner.intent, confidence: confidence)

        dlog("[HeyFeedAIParser] intent=\(winner.intent.rawValue) confidence=\(confidence) signals=\(winner.matches)")

        return HeyFeedParseResult(
            intent: winner.intent,
            confidence: confidence,
            signals: winner.matches,
            needsPastoralAttention: pastoral,
            urgencyScore: urgency
        )
    }

    /// Parses a batch of posts and returns a dictionary of postId → result.
    func batchParse(
        posts: [(id: String, text: String, category: String)]
    ) -> [String: HeyFeedParseResult] {
        var results: [String: HeyFeedParseResult] = [:]
        results.reserveCapacity(posts.count)
        for post in posts {
            results[post.id] = parse(text: post.text, category: post.category)
        }
        dlog("[HeyFeedAIParser] batchParse completed — \(results.count) posts parsed")
        return results
    }

    // MARK: - Private Helpers

    private func matchedSignals(in text: String, keywords: [String]) -> [String] {
        keywords.filter { text.contains($0) }
    }

    /// Confidence from raw match count: 1=0.5, 2=0.75, 3+=0.9
    private func confidence(for matchCount: Int) -> Double {
        switch matchCount {
        case 1:      return 0.5
        case 2:      return 0.75
        default:     return 0.9   // 3 or more
        }
    }

    private func urgencyScore(for intent: HeyFeedIntent, confidence: Double) -> Double {
        switch intent {
        case .crisis:        return 0.95
        case .grief:         return 0.7
        case .prayerRequest: return 0.6
        case .testimony:     return 0.35
        case .question:      return 0.3
        case .encouragement: return 0.25
        case .fellowship:    return 0.2
        case .biblicalStudy: return 0.15
        case .neutral:       return 0.0
        }
    }

    private func needsPastoralAttention(intent: HeyFeedIntent, confidence: Double) -> Bool {
        switch intent {
        case .crisis:
            return true   // Always flag crisis regardless of confidence
        case .grief:
            return confidence > 0.5
        default:
            return false
        }
    }

    /// Maps the post's category string to a hinting intent for tie-breaking.
    private func hintIntent(from category: String) -> HeyFeedIntent? {
        switch category.lowercased() {
        case "prayer":      return .prayerRequest
        case "testimonies": return .testimony
        default:            return nil
        }
    }
}
