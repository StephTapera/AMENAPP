//
//  PassiveInterestGraph.swift
//  AMENAPP
//
//  Builds a private interest graph from ghost signals: draft text,
//  profile visit sequences, search queries without engagement,
//  abandoned comment drafts. Never exposed publicly.
//

import Foundation

class PassiveInterestGraph {
    static let shared = PassiveInterestGraph()

    // Private embedding: topic → implicit interest weight
    private var interestWeights: [String: Float] = [:]
    private let decayFactor: Float = 0.95 // Weekly decay

    private init() {
        loadFromDisk()
    }

    // MARK: - Signal Tracking

    /// Track a draft that was typed but never posted.
    func trackDraft(text: String) {
        let topics = extractTopics(from: text)
        for topic in topics {
            interestWeights[topic, default: 0] += 0.3 // Drafts = moderate signal
        }
        saveToDisk()
    }

    /// Track a profile visit (who they visited after who).
    func trackProfileVisit(userId: String, afterUserId: String?) {
        // Profile visit sequences reveal social interest patterns
        interestWeights["profile_visit_\(userId)", default: 0] += 0.2
        saveToDisk()
    }

    /// Track a search query that didn't result in engagement.
    func trackSearchWithoutEngagement(query: String) {
        let topics = extractTopics(from: query)
        for topic in topics {
            interestWeights[topic, default: 0] += 0.5 // Search = strong signal
        }
        saveToDisk()
    }

    /// Track a comment that was started but abandoned.
    func trackAbandonedComment(text: String) {
        let topics = extractTopics(from: text)
        for topic in topics {
            interestWeights[topic, default: 0] += 0.4 // Abandoned comments = medium-strong
        }
        saveToDisk()
    }

    /// Track content the user paused on (scroll dwell time).
    func trackDwellTime(postTopics: [String], seconds: Float) {
        guard seconds > 3 else { return } // Only count meaningful pauses
        for topic in postTopics {
            interestWeights[topic, default: 0] += min(0.3, seconds / 30.0)
        }
    }

    // MARK: - Query

    /// Get top N interests sorted by weight.
    func topInterests(limit: Int = 10) -> [(topic: String, weight: Float)] {
        interestWeights
            .filter { !$0.key.hasPrefix("profile_visit_") }
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { (topic: $0.key, weight: $0.value) }
    }

    /// Get interest score for a specific topic (for feed ranking).
    func interestScore(for topic: String) -> Float {
        interestWeights[topic] ?? 0
    }

    /// Apply weekly decay to all interests (call once per session start).
    func applyDecay() {
        for key in interestWeights.keys {
            interestWeights[key]! *= decayFactor
        }
        // Remove near-zero entries
        interestWeights = interestWeights.filter { $0.value > 0.01 }
        saveToDisk()
    }

    // MARK: - Topic Extraction

    private let topicKeywords: [String: [String]] = [
        "prayer": ["pray", "prayer", "intercede", "intercession"],
        "healing": ["heal", "healing", "recovery", "restored"],
        "faith": ["faith", "believe", "trust", "faithful"],
        "anxiety": ["anxiety", "anxious", "worry", "fear"],
        "marriage": ["marriage", "spouse", "husband", "wife"],
        "parenting": ["child", "children", "parenting", "kids"],
        "business": ["business", "startup", "entrepreneur", "career"],
        "leadership": ["leader", "leadership", "lead", "vision"],
        "worship": ["worship", "praise", "song", "music"],
        "testimony": ["testimony", "testify", "story", "journey"],
        "scripture": ["bible", "scripture", "verse", "word of god"],
        "community": ["church", "community", "fellowship", "congregation"],
    ]

    private func extractTopics(from text: String) -> [String] {
        let lower = text.lowercased()
        return topicKeywords.compactMap { topic, keywords in
            keywords.contains(where: { lower.contains($0) }) ? topic : nil
        }
    }

    // MARK: - Persistence

    private let storageKey = "passiveInterestGraph_v1"

    private func saveToDisk() {
        if let data = try? JSONEncoder().encode(interestWeights) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let loaded = try? JSONDecoder().decode([String: Float].self, from: data) else { return }
        interestWeights = loaded
    }
}
