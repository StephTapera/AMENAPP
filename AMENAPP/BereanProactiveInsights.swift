//
//  BereanProactiveInsights.swift
//  AMENAPP
//
//  Makes Berean proactively smart instead of purely reactive:
//  - Post context: When viewing a post with a verse, offer "Explore this passage"
//  - Prayer companion: After writing a prayer, suggest related scriptures
//  - Reading plan awareness: Personalize based on what user is studying
//  - Daily verse + insight: Push notification with tailored devotional
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - Proactive Insight Models

struct ProactiveInsight: Identifiable {
    let id: String
    let type: InsightType
    let title: String
    let content: String
    let relatedScripture: [String]
    let actionLabel: String        // e.g., "Explore deeper", "Pray this"
    let actionPayload: String      // Data to pass when user taps
    let priority: InsightPriority
    let createdAt: Date
    let expiresAt: Date

    enum InsightType: String {
        case verseExploration = "verse_exploration"     // Post has a verse
        case prayerCompanion = "prayer_companion"       // Related to user's prayer
        case readingPlanLink = "reading_plan"           // Connected to current study
        case dailyDevotional = "daily_devotional"       // Personalized daily insight
        case themeConnection = "theme_connection"       // Connects to recurring theme
        case crossReference = "cross_reference"         // Related passage suggestion
    }

    enum InsightPriority: Int, Comparable {
        case low = 0
        case medium = 1
        case high = 2

        static func < (lhs: InsightPriority, rhs: InsightPriority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
}

struct DailyVerse: Codable, Identifiable {
    let id: String
    let verse: String
    let reference: String
    let insight: String            // 2-sentence personalized devotional
    let theme: String              // Why this verse was chosen
    let date: Date
}

// MARK: - Proactive Insights Service

@MainActor
final class BereanProactiveInsights: ObservableObject {
    static let shared = BereanProactiveInsights()

    @Published var pendingInsights: [ProactiveInsight] = []
    @Published var dailyVerse: DailyVerse?
    @Published var isGenerating = false

    private let claude = ClaudeService.shared
    private let memory = BereanMemory.shared
    private let semanticSearch = BereanSemanticSearch.shared

    private init() {}

    // MARK: - Post Context Insights

    /// Generate an insight when user views a post containing a Bible verse
    func generatePostInsight(postContent: String, verseReferences: [String]) async -> ProactiveInsight? {
        guard !verseReferences.isEmpty else { return nil }

        let primaryRef = verseReferences.first ?? ""

        // Check if this connects to user's study themes
        let memoryContext = memory.generateContextSummary()
        let hasPersonalConnection = !memoryContext.isEmpty

        let prompt = """
        A user is viewing a post that references \(primaryRef).
        \(hasPersonalConnection ? "User context: \(memoryContext)" : "")

        Generate a brief, engaging one-sentence insight about this verse that would \
        make the user want to explore it deeper. \
        Be specific to the verse content, not generic.
        """

        do {
            let insight = try await claude.sendMessageSync(prompt, mode: .shepherd)

            return ProactiveInsight(
                id: UUID().uuidString,
                type: .verseExploration,
                title: "Explore \(primaryRef)",
                content: insight,
                relatedScripture: verseReferences,
                actionLabel: "Dive deeper",
                actionPayload: primaryRef,
                priority: .medium,
                createdAt: Date(),
                expiresAt: Date().addingTimeInterval(3600)
            )
        } catch {
            return nil
        }
    }

    // MARK: - Prayer Companion

    /// After a user writes a prayer, suggest related scriptures
    func generatePrayerInsight(prayerText: String) async -> ProactiveInsight? {
        // Use semantic search to find related passages
        let results = await semanticSearch.search(query: prayerText, topK: 3)

        guard !results.isEmpty else { return nil }

        let topVerses = results.flatMap { $0.keyVerses }.prefix(3).map { String($0) }
        let topSummary = results.first?.summary ?? ""

        let prompt = """
        A user just wrote a prayer. Based on their prayer theme, suggest how \
        \(topVerses.first ?? "Scripture") speaks to their heart in one warm sentence.
        Prayer theme: \(prayerText.prefix(200))
        Related passage: \(topSummary)
        """

        do {
            let insight = try await claude.sendMessageSync(prompt, mode: .shepherd)

            return ProactiveInsight(
                id: UUID().uuidString,
                type: .prayerCompanion,
                title: "Scripture for your prayer",
                content: insight,
                relatedScripture: Array(topVerses),
                actionLabel: "Read this passage",
                actionPayload: topVerses.first ?? "",
                priority: .high,
                createdAt: Date(),
                expiresAt: Date().addingTimeInterval(7200)
            )
        } catch {
            return nil
        }
    }

    // MARK: - Daily Personalized Verse

    /// Generate a personalized daily verse based on user's themes and journey
    func generateDailyVerse() async -> DailyVerse? {
        isGenerating = true
        defer { isGenerating = false }

        let memoryContext = memory.generateContextSummary()

        let prompt: String
        if memoryContext.isEmpty {
            prompt = """
            Generate a daily Bible verse and a 2-sentence devotional insight.
            Output strict JSON: {"reference": "string", "verse": "string (verse text)", \
            "insight": "string (2 sentences)", "theme": "string (one word)"}
            Choose a verse that is encouraging and practically applicable.
            """
        } else {
            prompt = """
            Generate a personalized daily Bible verse for this user.
            \(memoryContext)

            Choose a verse that connects to their journey and current themes.
            Output strict JSON: {"reference": "string", "verse": "string (verse text)", \
            "insight": "string (2 sentences, personalized)", "theme": "string (one word)"}
            """
        }

        do {
            let response = try await claude.sendMessageSync(prompt, mode: .scholar)

            let cleaned = response
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            struct DailyVerseDTO: Decodable {
                let reference: String
                let verse: String
                let insight: String
                let theme: String
            }

            if let data = cleaned.data(using: .utf8),
               let dto = try? JSONDecoder().decode(DailyVerseDTO.self, from: data) {
                let daily = DailyVerse(
                    id: UUID().uuidString,
                    verse: dto.verse,
                    reference: dto.reference,
                    insight: dto.insight,
                    theme: dto.theme,
                    date: Date()
                )
                dailyVerse = daily
                return daily
            }
        } catch {
            print("⚠️ ProactiveInsights: Failed to generate daily verse: \(error.localizedDescription)")
        }

        return nil
    }

    // MARK: - Theme Connection

    /// When a user asks about a topic, surface connections to their past questions
    func generateThemeConnection(currentQuery: String) async -> ProactiveInsight? {
        guard let profile = memory.profile, memory.memoryEnabled else { return nil }

        let lowercased = currentQuery.lowercased()

        // Find matching themes from user's history
        let matchingThemes = profile.themes.filter { theme in
            lowercased.contains(theme.theme)
        }

        guard let topTheme = matchingThemes.first, topTheme.frequency >= 2 else { return nil }

        let relatedVerses = topTheme.relatedVerses.prefix(3).map { String($0) }

        return ProactiveInsight(
            id: UUID().uuidString,
            type: .themeConnection,
            title: "You've explored \(topTheme.theme) before",
            content: "You've asked about \(topTheme.theme) \(topTheme.frequency) times. " +
                     "Shall I connect today's question with your previous study?",
            relatedScripture: Array(relatedVerses),
            actionLabel: "Connect my studies",
            actionPayload: topTheme.theme,
            priority: .low,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(3600)
        )
    }

    // MARK: - Insight Queue Management

    /// Add an insight to the pending queue
    func enqueue(_ insight: ProactiveInsight) {
        // Prevent duplicates
        guard !pendingInsights.contains(where: { $0.type == insight.type && $0.actionPayload == insight.actionPayload }) else {
            return
        }

        pendingInsights.append(insight)

        // Keep sorted by priority (highest first)
        pendingInsights.sort { $0.priority > $1.priority }

        // Max 5 pending insights
        if pendingInsights.count > 5 {
            pendingInsights = Array(pendingInsights.prefix(5))
        }

        // Remove expired
        pendingInsights.removeAll { $0.expiresAt < Date() }
    }

    /// Dismiss an insight
    func dismiss(_ insightId: String) {
        pendingInsights.removeAll { $0.id == insightId }
    }

    /// Clear all pending insights
    func clearAll() {
        pendingInsights.removeAll()
    }
}
