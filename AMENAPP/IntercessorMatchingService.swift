//
//  IntercessorMatchingService.swift
//  AMENAPP
//
//  Intercession Matching + Spiritual Gift Detection + Grief Detection
//  + Personal Verse Engine + Authenticity Scoring + Saturation Detection
//
//  Six ML/AI features in one service layer for spiritual intelligence.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - Feature 4: Intercession Matching

@MainActor
class IntercessorMatchingService: ObservableObject {
    static let shared = IntercessorMatchingService()
    @Published var matchedIntercessors: [IntercessorMatch] = []
    private let db = Firestore.firestore()
    private init() {}

    struct IntercessorMatch: Identifiable {
        let id: String
        let name: String
        let profileImageURL: String?
        let matchReason: String // "Has prayed for healing 12 times"
        let matchScore: Float
    }

    /// Find prayer warriors best suited for this request based on their history.
    func findIntercessors(for prayerText: String, prayerThemes: [String]) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        // Fetch active prayer warriors (users who've prayed for others recently)
        guard let snapshot = try? await db.collection("posts")
            .whereField("category", isEqualTo: "prayer")
            .order(by: "createdAt", descending: true)
            .limit(to: 200)
            .getDocuments() else { return }

        var intercessorScores: [String: (score: Float, reasons: [String], name: String, photo: String?)] = [:]

        for doc in snapshot.documents {
            let data = doc.data()
            let authorId = data["authorId"] as? String ?? ""
            guard authorId != uid else { continue }

            let content = (data["content"] as? String ?? "").lowercased()
            let authorName = data["authorName"] as? String ?? "Someone"
            let authorPhoto = data["authorProfileImageURL"] as? String

            // Score based on theme overlap
            var themeScore: Float = 0
            var reasons: [String] = []
            for theme in prayerThemes {
                if content.contains(theme.lowercased()) {
                    themeScore += 1.0
                    reasons.append("Prays about \(theme)")
                }
            }

            if themeScore > 0 {
                var entry = intercessorScores[authorId] ?? (score: 0, reasons: [], name: authorName, photo: authorPhoto)
                entry.score += themeScore
                entry.reasons.append(contentsOf: reasons)
                intercessorScores[authorId] = entry
            }
        }

        matchedIntercessors = intercessorScores
            .sorted { $0.value.score > $1.value.score }
            .prefix(5)
            .map { IntercessorMatch(
                id: $0.key,
                name: $0.value.name,
                profileImageURL: $0.value.photo,
                matchReason: $0.value.reasons.first ?? "Active prayer warrior",
                matchScore: $0.value.score
            )}
    }
}

// MARK: - Feature 5: Spiritual Gift Detection

class SpiritualGiftDetector {
    static let shared = SpiritualGiftDetector()
    private init() {}

    enum SpiritualGift: String, CaseIterable {
        case encouragement = "Encouragement"
        case teaching      = "Teaching"
        case prophecy       = "Prophecy"
        case service        = "Service"
        case leadership     = "Leadership"
        case mercy          = "Mercy"
        case giving         = "Giving"
        case faith          = "Faith"
        case wisdom         = "Wisdom"
        case intercession   = "Intercession"

        var keywords: [String] {
            switch self {
            case .encouragement: return ["encourage", "uplift", "support", "strengthen", "comfort"]
            case .teaching:      return ["teach", "explain", "study", "learn", "understand", "theology"]
            case .prophecy:      return ["prophetic", "vision", "revelation", "discern", "word from"]
            case .service:       return ["serve", "help", "volunteer", "assist", "ministry"]
            case .leadership:    return ["lead", "organize", "vision", "strategy", "build"]
            case .mercy:         return ["compassion", "hurt", "suffering", "empathy", "gentle"]
            case .giving:        return ["give", "generous", "tithe", "donate", "bless"]
            case .faith:         return ["trust", "believe", "faith", "impossible", "miracle"]
            case .wisdom:        return ["wise", "counsel", "advice", "discernment", "guide"]
            case .intercession:  return ["pray", "intercede", "warfare", "battle", "covering"]
            }
        }

        var verseReference: String {
            "1 Corinthians 12" // Framework reference
        }
    }

    /// Analyze user's content history and suggest spiritual gifts.
    func detectGifts(from posts: [String]) -> [(gift: SpiritualGift, confidence: Float)] {
        var giftScores: [SpiritualGift: Float] = [:]

        for post in posts {
            let lower = post.lowercased()
            for gift in SpiritualGift.allCases {
                let matches = gift.keywords.filter { lower.contains($0) }.count
                giftScores[gift, default: 0] += Float(matches)
            }
        }

        // Normalize and return top 3
        let total = giftScores.values.reduce(0, +)
        guard total > 0 else { return [] }

        return giftScores
            .map { (gift: $0.key, confidence: $0.value / total) }
            .sorted { $0.confidence > $1.confidence }
            .prefix(3)
            .map { $0 }
    }
}

// MARK: - Feature 6: Grief & Crisis Detection (quiet pastoral routing)

class GriefCrisisDetector {
    static let shared = GriefCrisisDetector()
    private init() {}

    struct CrisisSignal {
        let severity: Severity
        let matchedPhrases: [String]
        let suggestedAction: String

        enum Severity: String {
            case low    = "low"
            case medium = "medium"
            case high   = "high"
        }
    }

    private let crisisIndicators: [String: CrisisSignal.Severity] = [
        "i want to die": .high,
        "end it all": .high,
        "no reason to live": .high,
        "can't go on": .high,
        "nobody cares": .medium,
        "completely alone": .medium,
        "lost everything": .medium,
        "don't know what to do": .low,
        "feel so empty": .medium,
        "dark place": .medium,
        "giving up": .medium,
    ]

    /// Detect crisis language. Does NOT notify the user — quietly flags for pastoral care.
    func detectCrisis(in text: String) -> CrisisSignal? {
        let lower = text.lowercased()
        var maxSeverity: CrisisSignal.Severity = .low
        var matched: [String] = []

        for (phrase, severity) in crisisIndicators {
            if lower.contains(phrase) {
                matched.append(phrase)
                if severity == .high || (severity == .medium && maxSeverity == .low) {
                    maxSeverity = severity
                }
            }
        }

        guard !matched.isEmpty else { return nil }

        return CrisisSignal(
            severity: maxSeverity,
            matchedPhrases: matched,
            suggestedAction: maxSeverity == .high
                ? "Route to pastoral care team immediately"
                : "Flag for gentle follow-up"
        )
    }
}

// MARK: - Feature 7: Personal Verse Engine

class PersonalVerseEngine {
    static let shared = PersonalVerseEngine()
    private init() {}

    struct PersonalVerse {
        let reference: String
        let text: String
        let reason: String // "You've been praying about patience"
    }

    private let verseThemes: [String: (ref: String, text: String)] = [
        "anxiety": ("Philippians 4:6-7", "Do not be anxious about anything, but in every situation..."),
        "patience": ("James 1:4", "Let perseverance finish its work so that you may be mature..."),
        "strength": ("Isaiah 40:31", "Those who hope in the LORD will renew their strength..."),
        "grief": ("Psalm 34:18", "The LORD is close to the brokenhearted..."),
        "purpose": ("Jeremiah 29:11", "For I know the plans I have for you..."),
        "forgiveness": ("Ephesians 4:32", "Be kind and compassionate to one another, forgiving each other..."),
        "healing": ("Psalm 147:3", "He heals the brokenhearted and binds up their wounds."),
        "faith": ("Hebrews 11:1", "Now faith is confidence in what we hope for..."),
        "love": ("1 Corinthians 13:4-7", "Love is patient, love is kind..."),
        "wisdom": ("James 1:5", "If any of you lacks wisdom, you should ask God..."),
    ]

    /// Get a personalized verse based on user's recent activity themes.
    func getPersonalVerse(recentThemes: [String]) -> PersonalVerse {
        for theme in recentThemes {
            if let verse = verseThemes[theme.lowercased()] {
                return PersonalVerse(
                    reference: verse.ref,
                    text: verse.text,
                    reason: "You've been reflecting on \(theme)"
                )
            }
        }

        // Default
        return PersonalVerse(
            reference: "Romans 8:28",
            text: "And we know that in all things God works for the good of those who love him.",
            reason: "A daily anchor for your faith"
        )
    }
}

// MARK: - Feature 10: Authenticity Scoring

class AuthenticityScorer {
    static let shared = AuthenticityScorer()
    private init() {}

    /// Score content authenticity (0.0 = performative, 1.0 = genuine).
    /// Used to weight the feed algorithm — not shown publicly.
    func score(text: String, postHistory: [String]) -> Float {
        var authenticity: Float = 0.5 // Neutral default

        let lower = text.lowercased()

        // Personal language signals (genuine)
        let personalIndicators = ["i struggled", "god showed me", "my journey", "i realized",
                                  "honestly", "vulnerable", "real talk", "truth is"]
        let personalMatches = personalIndicators.filter { lower.contains($0) }.count
        authenticity += Float(personalMatches) * 0.1

        // Performative signals (reduce score)
        let performativeIndicators = ["like and share", "follow for", "tag someone",
                                       "drop an amen", "type yes if", "share this"]
        let performativeMatches = performativeIndicators.filter { lower.contains($0) }.count
        authenticity -= Float(performativeMatches) * 0.15

        // Variety in posting (genuine users vary topics)
        if postHistory.count >= 5 {
            let uniqueStarts = Set(postHistory.prefix(10).map { String($0.prefix(20)) })
            let variety = Float(uniqueStarts.count) / Float(min(10, postHistory.count))
            authenticity += (variety - 0.5) * 0.2
        }

        return max(0, min(1, authenticity))
    }
}

// MARK: - Feature: Content Saturation Detection

class ContentSaturationDetector {
    static let shared = ContentSaturationDetector()
    private init() {}

    private var sessionTopicCounts: [String: Int] = [:]

    /// Track that the user has seen a post about a topic.
    func trackExposure(topic: String) {
        sessionTopicCounts[topic, default: 0] += 1
    }

    /// Check if user is saturated on a topic (seen 8+ in this session).
    func isSaturated(topic: String) -> Bool {
        (sessionTopicCounts[topic] ?? 0) >= 8
    }

    /// Reset on new session.
    func resetSession() {
        sessionTopicCounts.removeAll()
    }

    /// Get suppressed topics for feed filtering.
    func suppressedTopics() -> Set<String> {
        Set(sessionTopicCounts.filter { $0.value >= 8 }.keys)
    }
}
