//
//  ChurchNotesDiscoveryService.swift
//  AMENAPP
//
//  Intelligent discovery and ranking algorithm for Church Notes
//  Helps users find relevant notes and connect with people
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

class ChurchNotesDiscoveryService {
    static let shared = ChurchNotesDiscoveryService()

    private init() {}

    /// Ranking signals and weights for note discovery
    enum RankingSignal {
        case recency(score: Double)           // Recent notes get higher scores
        case authorConnection(score: Double)  // Notes from followed users
        case churchAffinity(score: Double)    // Notes from user's church/denomination
        case engagementQuality(score: Double) // Notes with high-quality engagement
        case relevanceTags(score: Double)     // Matching topics/tags
        case mutualConnections(score: Double) // Friends of friends
        case scripture(score: Double)         // Scripture references user cares about

        var weight: Double {
            switch self {
            case .recency: return 0.15
            case .authorConnection: return 0.25
            case .churchAffinity: return 0.20
            case .engagementQuality: return 0.15
            case .relevanceTags: return 0.10
            case .mutualConnections: return 0.10
            case .scripture: return 0.05
            }
        }

        var score: Double {
            switch self {
            case .recency(let s): return s
            case .authorConnection(let s): return s
            case .churchAffinity(let s): return s
            case .engagementQuality(let s): return s
            case .relevanceTags(let s): return s
            case .mutualConnections(let s): return s
            case .scripture(let s): return s
            }
        }
    }

    /// Scored note with ranking explanation
    struct ScoredNote {
        let note: ChurchNote
        let totalScore: Double
        let signals: [RankingSignal]
        let debugInfo: String
    }

    /// Rank notes using discovery algorithm
    func rankNotes(
        _ notes: [ChurchNote],
        userFollowing: Set<String> = [],
        userChurch: String? = nil,
        userTags: Set<String> = [],
        userScriptures: Set<String> = [],
        mutualConnections: Set<String> = []
    ) -> [ScoredNote] {
        let scoredNotes = notes.compactMap { note -> ScoredNote? in
            guard let userId = Auth.auth().currentUser?.uid else { return nil }

            // Skip user's own notes in discovery
            if note.userId == userId {
                return nil
            }

            var signals: [RankingSignal] = []

            // 1. RECENCY SIGNAL (0.0 - 1.0)
            // Exponential decay: notes lose 50% score every 7 days
            let daysSinceCreated = Calendar.current.dateComponents([.day], from: note.createdAt, to: Date()).day ?? 0
            let recencyScore = exp(-Double(daysSinceCreated) / 7.0)
            signals.append(.recency(score: recencyScore))

            // 2. AUTHOR CONNECTION SIGNAL (0.0 or 1.0)
            // Binary: user follows author = 1.0, else 0.0
            let authorConnectionScore = userFollowing.contains(note.userId) ? 1.0 : 0.0
            signals.append(.authorConnection(score: authorConnectionScore))

            // 3. CHURCH AFFINITY SIGNAL (0.0 - 1.0)
            // Match based on church name similarity
            var churchScore = 0.0
            if let noteChurch = note.churchName?.lowercased(),
               let userChurchName = userChurch?.lowercased() {
                if noteChurch == userChurchName {
                    churchScore = 1.0
                } else if noteChurch.contains(userChurchName) || userChurchName.contains(noteChurch) {
                    churchScore = 0.7
                } else if sharesDenomination(noteChurch, userChurchName) {
                    churchScore = 0.4
                }
            }
            signals.append(.churchAffinity(score: churchScore))

            // 4. ENGAGEMENT QUALITY SIGNAL (0.0 - 1.0)
            // Based on reactions, comments, shares
            // Normalize by log scale to handle outliers
            let amenCount = 0.0 // TODO: Fetch from postInteractions
            let commentCount = 0.0 // TODO: Fetch from postInteractions
            let shareCount = 0.0 // TODO: Fetch share data
            let totalEngagement = amenCount + (commentCount * 2.0) + (shareCount * 3.0)
            let engagementScore = min(1.0, log10(totalEngagement + 1.0) / 2.0)
            signals.append(.engagementQuality(score: engagementScore))

            // 5. RELEVANCE TAGS SIGNAL (0.0 - 1.0)
            // Jaccard similarity: |intersection| / |union|
            let noteTags = Set(note.tags.map { $0.lowercased() })
            let intersection = noteTags.intersection(userTags)
            let union = noteTags.union(userTags)
            let tagScore = union.isEmpty ? 0.0 : Double(intersection.count) / Double(union.count)
            signals.append(.relevanceTags(score: tagScore))

            // 6. MUTUAL CONNECTIONS SIGNAL (0.0 - 1.0)
            // Notes from friends of friends
            let mutualScore = mutualConnections.contains(note.userId) ? 0.8 : 0.0
            signals.append(.mutualConnections(score: mutualScore))

            // 7. SCRIPTURE SIGNAL (0.0 - 1.0)
            // Match scripture references
            let noteScriptures = Set(note.scriptureReferences.map { $0.lowercased() })
            let scriptureIntersection = noteScriptures.intersection(userScriptures)
            let scriptureScore = userScriptures.isEmpty ? 0.0 : Double(scriptureIntersection.count) / Double(userScriptures.count)
            signals.append(.scripture(score: scriptureScore))

            // FINAL SCORE CALCULATION
            // Weighted sum of all signals
            let totalScore = signals.reduce(0.0) { sum, signal in
                sum + (signal.score * signal.weight)
            }

            // DEBUG INFO FOR DEVELOPMENT BUILDS
            let debugInfo = buildDebugInfo(note: note, signals: signals, totalScore: totalScore)

            return ScoredNote(note: note, totalScore: totalScore, signals: signals, debugInfo: debugInfo)
        }

        // Sort by total score descending
        return scoredNotes.sorted { $0.totalScore > $1.totalScore }
    }

    /// Build debug info string for logging
    private func buildDebugInfo(note: ChurchNote, signals: [RankingSignal], totalScore: Double) -> String {
        var info = "📊 Note: \(note.title) | Total Score: \(String(format: "%.3f", totalScore))\n"
        info += "   Top Contributing Factors:\n"

        // Sort signals by contribution (score * weight)
        let sortedSignals = signals.sorted { s1, s2 in
            (s1.score * s1.weight) > (s2.score * s2.weight)
        }

        for signal in sortedSignals.prefix(3) {
            let contribution = signal.score * signal.weight
            let percentage = (contribution / totalScore) * 100.0
            info += "   - \(signalName(signal)): \(String(format: "%.1f%%", percentage)) "
            info += "(score: \(String(format: "%.2f", signal.score)))\n"
        }

        return info
    }

    /// Get human-readable signal name
    private func signalName(_ signal: RankingSignal) -> String {
        switch signal {
        case .recency: return "Recency"
        case .authorConnection: return "Following Author"
        case .churchAffinity: return "Church Match"
        case .engagementQuality: return "Engagement"
        case .relevanceTags: return "Topic Relevance"
        case .mutualConnections: return "Mutual Friends"
        case .scripture: return "Scripture Match"
        }
    }

    /// Check if churches share denomination
    private func sharesDenomination(_ church1: String, _ church2: String) -> Bool {
        let denominations = [
            "baptist", "methodist", "presbyterian", "pentecostal",
            "lutheran", "episcopal", "catholic", "assemblies",
            "non-denominational", "charismatic", "reformed"
        ]

        for denom in denominations {
            if church1.contains(denom) && church2.contains(denom) {
                return true
            }
        }
        return false
    }

    /// Log discovery results for debugging (development builds only)
    func logDiscoveryResults(_ scoredNotes: [ScoredNote], limit: Int = 5) {
        #if DEBUG
        print("\n🔍 CHURCH NOTES DISCOVERY RESULTS (Top \(limit))")
        print("=" + String(repeating: "=", count: 60))

        for (index, scoredNote) in scoredNotes.prefix(limit).enumerated() {
            print("\n[\(index + 1)] \(scoredNote.debugInfo)")
        }

        print("=" + String(repeating: "=", count: 60) + "\n")
        #endif
    }

    /// Get "For You" feed with personalized ranking
    func getForYouFeed(
        from notes: [ChurchNote],
        userFollowing: Set<String> = [],
        userChurch: String? = nil,
        userTags: Set<String> = [],
        limit: Int = 50
    ) -> [ChurchNote] {
        let scoredNotes = rankNotes(
            notes,
            userFollowing: userFollowing,
            userChurch: userChurch,
            userTags: userTags
        )

        logDiscoveryResults(scoredNotes, limit: min(10, scoredNotes.count))

        return scoredNotes.prefix(limit).map { $0.note }
    }

    /// Get "Following" feed - notes from followed users only
    func getFollowingFeed(
        from notes: [ChurchNote],
        userFollowing: Set<String>
    ) -> [ChurchNote] {
        return notes
            .filter { userFollowing.contains($0.userId) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Get "Recent" feed - chronological order
    func getRecentFeed(from notes: [ChurchNote]) -> [ChurchNote] {
        return notes.sorted { $0.createdAt > $1.createdAt }
    }
}
