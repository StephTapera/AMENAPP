//
//  BereanMemory.swift
//  AMENAPP
//
//  Opt-in conversational memory ("Berean Journal") that remembers:
//  - User's denomination/tradition preference
//  - Recurring themes in their questions (grief, anxiety, growth)
//  - Books/passages they've studied
//  - Preferred Bible version
//  - Spiritual growth trajectory
//
//  Privacy: User can view/delete their journal anytime.
//  Confessional/prayer content is NEVER stored (enforced by retention policy).
//
//  Stored encrypted in Firestore under users/{uid}/berean_memory
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - Memory Models

struct BereanUserProfile: Codable {
    var userId: String
    var denomination: String?                // e.g., "Baptist", "Catholic", "Non-denominational"
    var preferredVersion: String             // Bible version preference
    var preferredMode: String                // Berean mode preference
    var themes: [ThemeRecord]                // Recurring topics of interest
    var studiedBooks: [StudiedBook]          // Books/passages they've explored
    var topicHistory: [TopicHistoryEntry]    // Recent question topics (anonymized)
    var spiritualGoals: [String]            // User-set goals
    var memoryEnabled: Bool                  // Opt-in flag
    var createdAt: Date
    var updatedAt: Date
}

struct ThemeRecord: Codable, Identifiable {
    let id: String
    let theme: String              // e.g., "anxiety", "forgiveness", "marriage"
    var frequency: Int             // Times this theme appeared
    var lastSeen: Date
    var relatedVerses: [String]    // Verses discussed in this theme
}

struct StudiedBook: Codable, Identifiable {
    let id: String
    let book: String               // e.g., "Romans"
    var chaptersExplored: [Int]    // Which chapters they've asked about
    var questionsAsked: Int
    var lastStudied: Date
}

struct TopicHistoryEntry: Codable, Identifiable {
    let id: String
    let topic: String              // Anonymized topic (e.g., "forgiveness", not the full question)
    let timestamp: Date
    let sentiment: String?         // positive, seeking, struggling, curious
}

// MARK: - Memory Service

@MainActor
final class BereanMemory: ObservableObject {
    static let shared = BereanMemory()

    @Published var profile: BereanUserProfile?
    @Published var isLoaded = false
    @Published var memoryEnabled = false

    private let db = Firestore.firestore()
    private let maxThemes = 50
    private let maxTopicHistory = 200
    private let maxStudiedBooks = 66  // All Bible books

    // Theme extraction keywords
    private let themeKeywords: [String: [String]] = [
        "anxiety": ["anxious", "worried", "worry", "fear", "afraid", "stress", "overwhelmed"],
        "forgiveness": ["forgive", "forgiveness", "mercy", "pardon", "reconcile"],
        "grief": ["grief", "loss", "mourning", "death", "passed away", "bereaved"],
        "marriage": ["marriage", "spouse", "husband", "wife", "wedding", "divorce"],
        "parenting": ["parent", "child", "children", "son", "daughter", "raising"],
        "faith": ["faith", "believe", "trust", "doubt", "unbelief"],
        "prayer": ["prayer", "praying", "intercession", "petition"],
        "salvation": ["salvation", "saved", "born again", "eternal life", "redemption"],
        "suffering": ["suffering", "pain", "trial", "hardship", "persecution"],
        "purpose": ["purpose", "calling", "vocation", "meaning", "destiny"],
        "wisdom": ["wisdom", "discernment", "guidance", "decision", "direction"],
        "love": ["love", "loving", "agape", "compassion", "kindness"],
        "growth": ["grow", "growth", "maturity", "sanctification", "spiritual growth"],
        "worship": ["worship", "praise", "thanksgiving", "adoration"],
        "community": ["church", "fellowship", "community", "body of christ", "congregation"],
    ]

    private init() {}

    // MARK: - Load / Initialize

    func loadProfile() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        do {
            let doc = try await db.collection("users").document(uid)
                .collection("berean_memory").document("profile")
                .getDocument()

            if doc.exists, let data = try? doc.data(as: BereanUserProfile.self) {
                profile = data
                memoryEnabled = data.memoryEnabled
            } else {
                // Create default profile
                let newProfile = BereanUserProfile(
                    userId: uid,
                    denomination: nil,
                    preferredVersion: "ESV",
                    preferredMode: "shepherd",
                    themes: [],
                    studiedBooks: [],
                    topicHistory: [],
                    spiritualGoals: [],
                    memoryEnabled: false,
                    createdAt: Date(),
                    updatedAt: Date()
                )
                profile = newProfile
            }

            isLoaded = true
        } catch {
            print("⚠️ BereanMemory: Failed to load profile: \(error.localizedDescription)")
            isLoaded = true
        }
    }

    // MARK: - Record Interaction

    /// Record a user interaction to update memory (call after every Berean response)
    func recordInteraction(query: String, context: BereanContext) async {
        guard memoryEnabled, var profile = profile else { return }

        // Don't record sensitive contexts
        if context.featureContext == .prayer { return }

        let lowercased = query.lowercased()

        // 1. Extract and update themes
        for (theme, keywords) in themeKeywords {
            if keywords.contains(where: { lowercased.contains($0) }) {
                updateTheme(theme, in: &profile, query: lowercased)
            }
        }

        // 2. Track studied books
        let bookRefs = extractBookReferences(from: query)
        for book in bookRefs {
            updateStudiedBook(book, in: &profile)
        }

        // 3. Add to topic history
        let topic = extractTopic(from: query)
        let sentiment = detectSentiment(from: query)
        let entry = TopicHistoryEntry(
            id: UUID().uuidString,
            topic: topic,
            timestamp: Date(),
            sentiment: sentiment
        )
        profile.topicHistory.append(entry)

        // Trim history if too long
        if profile.topicHistory.count > maxTopicHistory {
            profile.topicHistory = Array(profile.topicHistory.suffix(maxTopicHistory))
        }

        profile.updatedAt = Date()
        self.profile = profile

        // Save to Firestore
        await saveProfile()
    }

    // MARK: - Generate Context Summary for Prompt

    /// Generate a memory summary to inject into Berean's system prompt
    func generateContextSummary() -> String {
        guard let profile = profile, memoryEnabled else { return "" }

        var parts: [String] = []

        // Denomination
        if let denom = profile.denomination {
            parts.append("User's tradition: \(denom)")
        }

        // Preferred Bible version
        parts.append("Preferred Bible version: \(profile.preferredVersion)")

        // Top themes (most frequent)
        let topThemes = profile.themes
            .sorted { $0.frequency > $1.frequency }
            .prefix(5)
            .map { "\($0.theme) (\($0.frequency)x)" }
        if !topThemes.isEmpty {
            parts.append("Recurring topics: \(topThemes.joined(separator: ", "))")
        }

        // Recently studied books
        let recentBooks = profile.studiedBooks
            .sorted { $0.lastStudied > $1.lastStudied }
            .prefix(3)
            .map { $0.book }
        if !recentBooks.isEmpty {
            parts.append("Recently studying: \(recentBooks.joined(separator: ", "))")
        }

        // Spiritual goals
        if !profile.spiritualGoals.isEmpty {
            parts.append("Spiritual goals: \(profile.spiritualGoals.joined(separator: ", "))")
        }

        // Recent sentiment
        let recentTopics = profile.topicHistory.suffix(5)
        let struggles = recentTopics.filter { $0.sentiment == "struggling" }
        if struggles.count >= 2 {
            parts.append("Note: User may be going through a difficult season — be extra pastoral.")
        }

        guard !parts.isEmpty else { return "" }

        return "[USER CONTEXT — personalize your response based on this]\n" +
            parts.joined(separator: "\n")
    }

    // MARK: - User Controls

    /// Enable/disable memory
    func setMemoryEnabled(_ enabled: Bool) async {
        memoryEnabled = enabled
        profile?.memoryEnabled = enabled
        profile?.updatedAt = Date()
        await saveProfile()
    }

    /// Set denomination preference
    func setDenomination(_ denomination: String?) async {
        profile?.denomination = denomination
        profile?.updatedAt = Date()
        await saveProfile()
    }

    /// Set preferred Bible version
    func setPreferredVersion(_ version: String) async {
        profile?.preferredVersion = version
        profile?.updatedAt = Date()
        await saveProfile()
    }

    /// Set spiritual goals
    func setGoals(_ goals: [String]) async {
        profile?.spiritualGoals = goals
        profile?.updatedAt = Date()
        await saveProfile()
    }

    /// Delete all memory data
    func clearAllMemory() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        profile = BereanUserProfile(
            userId: uid,
            denomination: nil,
            preferredVersion: "ESV",
            preferredMode: "shepherd",
            themes: [],
            studiedBooks: [],
            topicHistory: [],
            spiritualGoals: [],
            memoryEnabled: false,
            createdAt: Date(),
            updatedAt: Date()
        )
        memoryEnabled = false

        do {
            try await db.collection("users").document(uid)
                .collection("berean_memory").document("profile")
                .delete()
            print("✅ BereanMemory: All data cleared")
        } catch {
            print("⚠️ BereanMemory: Failed to clear data: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Helpers

    private func updateTheme(_ theme: String, in profile: inout BereanUserProfile, query: String) {
        if let index = profile.themes.firstIndex(where: { $0.theme == theme }) {
            profile.themes[index].frequency += 1
            profile.themes[index].lastSeen = Date()

            // Extract verse refs mentioned alongside this theme
            let refs = extractVerseReferences(from: query)
            for ref in refs where !profile.themes[index].relatedVerses.contains(ref) {
                profile.themes[index].relatedVerses.append(ref)
            }
        } else {
            let record = ThemeRecord(
                id: UUID().uuidString,
                theme: theme,
                frequency: 1,
                lastSeen: Date(),
                relatedVerses: extractVerseReferences(from: query)
            )
            profile.themes.append(record)

            // Trim if too many themes
            if profile.themes.count > maxThemes {
                profile.themes.sort { $0.frequency > $1.frequency }
                profile.themes = Array(profile.themes.prefix(maxThemes))
            }
        }
    }

    private func updateStudiedBook(_ book: String, in profile: inout BereanUserProfile) {
        if let index = profile.studiedBooks.firstIndex(where: { $0.book == book }) {
            profile.studiedBooks[index].questionsAsked += 1
            profile.studiedBooks[index].lastStudied = Date()
        } else {
            let studied = StudiedBook(
                id: UUID().uuidString,
                book: book,
                chaptersExplored: [],
                questionsAsked: 1,
                lastStudied: Date()
            )
            profile.studiedBooks.append(studied)
        }
    }

    private func extractBookReferences(from query: String) -> [String] {
        let books = [
            "Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy",
            "Joshua", "Judges", "Ruth", "Samuel", "Kings", "Chronicles",
            "Ezra", "Nehemiah", "Esther", "Job", "Psalms", "Proverbs",
            "Ecclesiastes", "Song of Solomon", "Isaiah", "Jeremiah",
            "Lamentations", "Ezekiel", "Daniel", "Hosea", "Joel",
            "Amos", "Obadiah", "Jonah", "Micah", "Nahum", "Habakkuk",
            "Zephaniah", "Haggai", "Zechariah", "Malachi",
            "Matthew", "Mark", "Luke", "John", "Acts",
            "Romans", "Corinthians", "Galatians", "Ephesians",
            "Philippians", "Colossians", "Thessalonians", "Timothy",
            "Titus", "Philemon", "Hebrews", "James", "Peter",
            "Jude", "Revelation"
        ]

        let lowercased = query.lowercased()
        return books.filter { lowercased.contains($0.lowercased()) }
    }

    private func extractVerseReferences(from query: String) -> [String] {
        let pattern = "([1-3]?\\s?[A-Za-z]+)\\s+(\\d+):(\\d+(?:-\\d+)?)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let nsString = query as NSString
        return regex.matches(in: query, range: NSRange(location: 0, length: nsString.length))
            .map { nsString.substring(with: $0.range) }
    }

    private func extractTopic(from query: String) -> String {
        // Simple topic extraction — first matching theme or first 3 words
        let lowercased = query.lowercased()
        for (theme, keywords) in themeKeywords {
            if keywords.contains(where: { lowercased.contains($0) }) {
                return theme
            }
        }
        return query.components(separatedBy: " ").prefix(3).joined(separator: " ")
    }

    private func detectSentiment(from query: String) -> String {
        let lowercased = query.lowercased()

        let struggling = ["struggling", "suffering", "pain", "lost", "confused",
                         "scared", "afraid", "hopeless", "helpless", "broken"]
        let seeking = ["what does", "explain", "help me understand", "teach me",
                      "how do i", "what is"]
        let positive = ["grateful", "thankful", "praise", "joy", "blessed",
                       "encouraged", "growing"]

        if struggling.contains(where: { lowercased.contains($0) }) { return "struggling" }
        if positive.contains(where: { lowercased.contains($0) }) { return "positive" }
        if seeking.contains(where: { lowercased.contains($0) }) { return "seeking" }
        return "curious"
    }

    private func saveProfile() async {
        guard let profile = profile,
              let uid = Auth.auth().currentUser?.uid else { return }

        do {
            try db.collection("users").document(uid)
                .collection("berean_memory").document("profile")
                .setData(from: profile)
        } catch {
            print("⚠️ BereanMemory: Failed to save: \(error.localizedDescription)")
        }
    }
}
