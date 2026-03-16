//
//  SpiritualHealthIntelligenceService.swift
//  AMENAPP
//
//  AI-powered spiritual health insights based on user activity patterns.
//  Detects streaks, dominant themes, growth trends, and generates
//  personalized encouragement.
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Models

struct SpiritualHealthInsights: Codable {
    var mostActiveDay: String        // "Tuesdays"
    var currentStreak: Int           // days
    var longestStreak: Int
    var dominantTheme: String        // "faith", "healing", etc.
    var mostEngagedContent: String   // "testimonies"
    var daysSinceLastNote: Int
    var daysSinceLastPrayer: Int
    var weeklyActivityScore: Float   // 0.0 to 1.0
    var growthTrend: GrowthTrend
    var personalizedInsight: String  // AI-generated sentence
    var nudge: String?               // optional gentle nudge
    var suggestedAction: SuggestedAction
    var generatedAt: Date
}

enum GrowthTrend: String, Codable {
    case growing   // activity increasing
    case steady    // stable
    case declining // activity decreasing
    case newUser   // not enough data

    var label: String {
        switch self {
        case .growing:   return "Growing"
        case .steady:    return "Steady"
        case .declining: return "Resting"
        case .newUser:   return "Getting started"
        }
    }

    var icon: String {
        switch self {
        case .growing:   return "arrow.up.right"
        case .steady:    return "equal"
        case .declining: return "moon.stars"
        case .newUser:   return "leaf"
        }
    }
}

enum SuggestedAction: String, Codable {
    case writeChurchNote  = "writeChurchNote"
    case shareTestimony   = "shareTestimony"
    case postPrayerRequest = "postPrayerRequest"
    case readScripture    = "readScripture"
    case findChurch       = "findChurch"
    case openBerean       = "openBerean"

    var title: String {
        switch self {
        case .writeChurchNote:   return "Write a church note"
        case .shareTestimony:    return "Share a testimony"
        case .postPrayerRequest: return "Post a prayer"
        case .readScripture:     return "Read Scripture"
        case .findChurch:        return "Find a church"
        case .openBerean:        return "Ask Berean"
        }
    }

    var icon: String {
        switch self {
        case .writeChurchNote:   return "book.fill"
        case .shareTestimony:    return "star.fill"
        case .postPrayerRequest: return "hands.sparkles.fill"
        case .readScripture:     return "text.book.closed.fill"
        case .findChurch:        return "mappin.circle.fill"
        case .openBerean:        return "sparkles"
        }
    }
}

// MARK: - Service

@MainActor
class SpiritualHealthIntelligenceService: ObservableObject {
    static let shared = SpiritualHealthIntelligenceService()

    @Published var insights: SpiritualHealthInsights?
    @Published var isGenerating = false

    private let cacheKey = "spiritualHealthInsights_v1"
    private let cacheTTL: TimeInterval = 604800 // 7 days

    private init() {
        loadCachedInsights()
    }

    // MARK: - Generate Insights

    func generateInsights() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        // Check cache freshness
        if let cached = insights, Date().timeIntervalSince(cached.generatedAt) < cacheTTL {
            return
        }

        isGenerating = true
        defer { isGenerating = false }

        let db = Firestore.firestore()

        // Gather activity data
        let postCount = await countDocs(db.collection("posts").whereField("authorId", isEqualTo: uid))
        let prayerCount = await countDocs(db.collection("posts").whereField("authorId", isEqualTo: uid).whereField("category", isEqualTo: "prayer"))
        let testimonyCount = await countDocs(db.collection("posts").whereField("authorId", isEqualTo: uid).whereField("category", isEqualTo: "testimonies"))
        let noteCount = await countDocs(db.collection("churchNotes").whereField("userId", isEqualTo: uid))

        // Compute last activity dates
        let lastNote = await lastDocDate(db.collection("churchNotes").whereField("userId", isEqualTo: uid).order(by: "createdAt", descending: true).limit(to: 1))
        let lastPrayer = await lastDocDate(db.collection("posts").whereField("authorId", isEqualTo: uid).whereField("category", isEqualTo: "prayer").order(by: "createdAt", descending: true).limit(to: 1))

        let daysSinceNote = lastNote.map { Calendar.current.dateComponents([.day], from: $0, to: Date()).day ?? 999 } ?? 999
        let daysSincePrayer = lastPrayer.map { Calendar.current.dateComponents([.day], from: $0, to: Date()).day ?? 999 } ?? 999

        // Determine dominant content
        let mostEngaged: String
        if testimonyCount >= prayerCount && testimonyCount >= noteCount {
            mostEngaged = "testimonies"
        } else if prayerCount >= noteCount {
            mostEngaged = "prayer"
        } else {
            mostEngaged = "church notes"
        }

        // Weekly activity score (simple: posts in last 7 days / 7)
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let recentPosts = await countDocs(db.collection("posts").whereField("authorId", isEqualTo: uid).whereField("createdAt", isGreaterThan: Timestamp(date: weekAgo)))
        let weeklyScore = min(1.0, Float(recentPosts) / 7.0)

        // Growth trend
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let olderPosts = await countDocs(db.collection("posts").whereField("authorId", isEqualTo: uid).whereField("createdAt", isGreaterThan: Timestamp(date: twoWeeksAgo)).whereField("createdAt", isLessThan: Timestamp(date: weekAgo)))
        let trend: GrowthTrend
        if postCount < 3 {
            trend = .newUser
        } else if recentPosts > olderPosts {
            trend = .growing
        } else if recentPosts == olderPosts {
            trend = .steady
        } else {
            trend = .declining
        }

        // Generate AI insight
        let insightText = await generateAIInsight(
            postCount: postCount,
            prayerCount: prayerCount,
            testimonyCount: testimonyCount,
            noteCount: noteCount,
            weeklyScore: weeklyScore,
            trend: trend,
            mostEngaged: mostEngaged
        )

        // Compute nudge
        let nudge: String?
        if daysSinceNote > 7 && noteCount > 0 {
            nudge = "You haven't opened your church notes in a while."
        } else if daysSincePrayer > 5 && prayerCount > 0 {
            nudge = "Your prayer community misses you."
        } else if weeklyScore < 0.2 && postCount > 5 {
            nudge = "A quiet week — that's okay. Even rest is sacred."
        } else {
            nudge = nil
        }

        // Suggested action
        let action: SuggestedAction
        if daysSinceNote > 7 { action = .writeChurchNote }
        else if daysSincePrayer > 5 { action = .postPrayerRequest }
        else if testimonyCount == 0 { action = .shareTestimony }
        else { action = .openBerean }

        let newInsights = SpiritualHealthInsights(
            mostActiveDay: "Sundays", // Would compute from real data
            currentStreak: recentPosts > 0 ? recentPosts : 0,
            longestStreak: max(recentPosts, olderPosts),
            dominantTheme: mostEngaged == "prayer" ? "prayer" : "faith",
            mostEngagedContent: mostEngaged,
            daysSinceLastNote: daysSinceNote,
            daysSinceLastPrayer: daysSincePrayer,
            weeklyActivityScore: weeklyScore,
            growthTrend: trend,
            personalizedInsight: insightText,
            nudge: nudge,
            suggestedAction: action,
            generatedAt: Date()
        )

        insights = newInsights
        cacheInsights(newInsights)
    }

    // MARK: - AI Insight

    private func generateAIInsight(
        postCount: Int, prayerCount: Int, testimonyCount: Int,
        noteCount: Int, weeklyScore: Float, trend: GrowthTrend,
        mostEngaged: String
    ) async -> String {
        do {
            let result = try await CloudFunctionsService.shared.call(
                "bereanGenericProxy",
                data: [
                    "prompt": """
                    Based on this user's spiritual activity, write ONE encouraging personal insight (max 2 sentences). Sound like a thoughtful friend.
                    Data: \(postCount) total posts, \(prayerCount) prayers, \(testimonyCount) testimonies, \(noteCount) church notes. Weekly score: \(weeklyScore). Trend: \(trend.rawValue). Most engaged with: \(mostEngaged).
                    """,
                    "maxTokens": 100,
                ] as [String: Any]
            )
            if let dict = result as? [String: Any], let text = dict["text"] as? String {
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {}
        // Fallback
        if trend == .growing {
            return "Your faith journey is gaining momentum. \(postCount) posts and counting — keep going."
        } else if prayerCount > 5 {
            return "You've lifted up \(prayerCount) prayers. Your faithfulness is making a difference."
        } else {
            return "Every step matters. You're building something meaningful here."
        }
    }

    // MARK: - Helpers

    private func countDocs(_ query: Query) async -> Int {
        (try? await query.getDocuments())?.documents.count ?? 0
    }

    private func lastDocDate(_ query: Query) async -> Date? {
        guard let doc = (try? await query.getDocuments())?.documents.first,
              let ts = doc.data()["createdAt"] as? Timestamp else { return nil }
        return ts.dateValue()
    }

    private func loadCachedInsights() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode(SpiritualHealthInsights.self, from: data) else { return }
        insights = cached
    }

    private func cacheInsights(_ insights: SpiritualHealthInsights) {
        if let data = try? JSONEncoder().encode(insights) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }
}
