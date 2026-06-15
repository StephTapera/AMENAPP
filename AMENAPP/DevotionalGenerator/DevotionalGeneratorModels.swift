//
//  DevotionalGeneratorModels.swift
//  AMENAPP
//
//  Data models for the full-stack Devotional Generator feature:
//  request configuration, AI response structure, tone/context enums,
//  safety modes, spiritual rhythm snapshots, and the scripture topic map.
//

import SwiftUI
import FirebaseFirestore

// MARK: - Tone

/// The devotional tone the user wants — affects AI prompt style.
enum DevotionalTone: String, CaseIterable, Identifiable, Codable {
    case contemplative  = "Contemplative"
    case prophetic      = "Prophetic"
    case practical      = "Practical"
    case intercessory   = "Intercessory"
    case celebratory    = "Celebratory"
    case lament         = "Lament"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .contemplative:  return "moon.stars.fill"
        case .prophetic:      return "flame.fill"
        case .practical:      return "hammer.fill"
        case .intercessory:   return "hands.sparkles.fill"
        case .celebratory:    return "star.fill"
        case .lament:         return "drop.fill"
        }
    }

    var color: Color {
        switch self {
        case .contemplative:  return .indigo
        case .prophetic:      return .orange
        case .practical:      return .blue
        case .intercessory:   return .purple
        case .celebratory:    return .yellow
        case .lament:         return .teal
        }
    }

    var promptDescription: String {
        switch self {
        case .contemplative:  return "reflective and meditative, drawing the reader inward"
        case .prophetic:      return "bold and Spirit-led, speaking to God's current word"
        case .practical:      return "action-oriented, grounded in everyday application"
        case .intercessory:   return "prayer-focused, lifting others and circumstances before God"
        case .celebratory:    return "joyful and doxological, celebrating God's goodness"
        case .lament:         return "honest and raw, holding space for grief and unanswered questions"
        }
    }
}

// MARK: - Safety Mode

/// How strictly to apply spiritual guardrails to the generated content.
enum DevotionalSafetyMode: String, Codable {
    case standard    = "standard"    // Default — block harmful, allow exploration
    case strict      = "strict"      // Children / youth — no dark themes
    case open        = "open"        // Mature believers — allow lament, wrestling
}

// MARK: - Community Mode

/// Whether to generate personal or group-oriented devotional content.
enum CommunityMode: String, CaseIterable, Identifiable, Codable {
    case personal = "Personal"
    case couple   = "Couple"
    case family   = "Family"
    case smallGroup = "Small Group"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .personal:   return "person.fill"
        case .couple:     return "person.2.fill"
        case .family:     return "house.fill"
        case .smallGroup: return "person.3.fill"
        }
    }

    var promptNuance: String {
        switch self {
        case .personal:   return "written in first person, deeply personal"
        case .couple:     return "written for two people growing together in faith"
        case .family:     return "written for a family with children, age-appropriate and accessible"
        case .smallGroup: return "written for a small group of believers, discussion-oriented"
        }
    }
}

// MARK: - Devotional Context

/// User-supplied context that personalises the generated devotional.
struct DevotionalContext: Codable {
    var topic: String                    // Free-form topic or season of life
    var tone: DevotionalTone
    var communityMode: CommunityMode
    var selectedVerses: [String]         // Optional pre-selected scripture refs
    var churchNotesSnippet: String?      // Optional snippet from recent church notes
    var prayerSnippet: String?           // Optional snippet from recent prayers
    var specificQuestion: String?        // "What I really need today..."
    var safetyMode: DevotionalSafetyMode

    init(
        topic: String = "",
        tone: DevotionalTone = .contemplative,
        communityMode: CommunityMode = .personal,
        selectedVerses: [String] = [],
        churchNotesSnippet: String? = nil,
        prayerSnippet: String? = nil,
        specificQuestion: String? = nil,
        safetyMode: DevotionalSafetyMode = .standard
    ) {
        self.topic = topic
        self.tone = tone
        self.communityMode = communityMode
        self.selectedVerses = selectedVerses
        self.churchNotesSnippet = churchNotesSnippet
        self.prayerSnippet = prayerSnippet
        self.specificQuestion = specificQuestion
        self.safetyMode = safetyMode
    }
}

// MARK: - Devotional Request

/// The full request object sent to DevotionalGenerationService.
struct DevotionalRequest: Identifiable, Codable {
    let id: String
    let userId: String
    let context: DevotionalContext
    let requestedAt: Date

    init(userId: String, context: DevotionalContext) {
        self.id = UUID().uuidString
        self.userId = userId
        self.context = context
        self.requestedAt = Date()
    }
}

// MARK: - Devotional Response Sections

/// A single scripture card within the generated devotional.
struct DevotionalScriptureCard: Identifiable, Codable {
    let id: String
    let reference: String
    let text: String
    let version: String
    let whyThisVerse: String  // AI-generated reason this verse was chosen

    init(reference: String, text: String, version: String = "NIV", whyThisVerse: String = "") {
        self.id = UUID().uuidString
        self.reference = reference
        self.text = text
        self.version = version
        self.whyThisVerse = whyThisVerse
    }
}

/// The reflection section of the generated devotional.
struct DevotionalReflectionCard: Identifiable, Codable {
    let id: String
    let heading: String
    let body: String

    init(heading: String = "Reflection", body: String) {
        self.id = UUID().uuidString
        self.heading = heading
        self.body = body
    }
}

/// The guided prayer section.
struct DevotionalPrayerCard: Identifiable, Codable {
    let id: String
    let heading: String
    let body: String
    let closingAmen: Bool

    init(heading: String = "Prayer", body: String, closingAmen: Bool = true) {
        self.id = UUID().uuidString
        self.heading = heading
        self.body = body
        self.closingAmen = closingAmen
    }
}

/// The practical application / "Live It Out" card.
struct DevotionalPracticeCard: Identifiable, Codable {
    let id: String
    let heading: String
    let steps: [String]   // 1-3 concrete action steps

    init(heading: String = "Live It Out", steps: [String]) {
        self.id = UUID().uuidString
        self.heading = heading
        self.steps = steps
    }
}

/// Community companion discussion prompts (for small group / family modes).
struct DevotionalCommunityCard: Identifiable, Codable {
    let id: String
    let heading: String
    let prompts: [String]

    init(heading: String = "Together", prompts: [String]) {
        self.id = UUID().uuidString
        self.heading = heading
        self.prompts = prompts
    }
}

/// A safety or theological notice appended when guardrails are triggered.
struct DevotionalGuardrailNotice: Identifiable, Codable {
    let id: String
    let message: String
    let severity: Severity

    enum Severity: String, Codable {
        case info    = "info"
        case caution = "caution"
    }

    init(message: String, severity: Severity = .info) {
        self.id = UUID().uuidString
        self.message = message
        self.severity = severity
    }
}

// MARK: - Full Devotional Response

/// The complete AI-generated devotional returned by DevotionalGenerationService.
struct DevotionalResponse: Identifiable, Codable {
    let id: String
    let requestId: String
    let userId: String
    let title: String
    let openingVerse: DevotionalScriptureCard
    let additionalScriptures: [DevotionalScriptureCard]
    let reflection: DevotionalReflectionCard
    let prayer: DevotionalPrayerCard
    let practice: DevotionalPracticeCard
    let community: DevotionalCommunityCard?
    let guardrailNotice: DevotionalGuardrailNotice?
    let tone: DevotionalTone
    let topicTags: [String]
    let generatedAt: Date
    var isSavedToNotes: Bool
    var churchNoteId: String?

    init(
        requestId: String,
        userId: String,
        title: String,
        openingVerse: DevotionalScriptureCard,
        additionalScriptures: [DevotionalScriptureCard] = [],
        reflection: DevotionalReflectionCard,
        prayer: DevotionalPrayerCard,
        practice: DevotionalPracticeCard,
        community: DevotionalCommunityCard? = nil,
        guardrailNotice: DevotionalGuardrailNotice? = nil,
        tone: DevotionalTone,
        topicTags: [String] = []
    ) {
        self.id = UUID().uuidString
        self.requestId = requestId
        self.userId = userId
        self.title = title
        self.openingVerse = openingVerse
        self.additionalScriptures = additionalScriptures
        self.reflection = reflection
        self.prayer = prayer
        self.practice = practice
        self.community = community
        self.guardrailNotice = guardrailNotice
        self.tone = tone
        self.topicTags = topicTags
        self.generatedAt = Date()
        self.isSavedToNotes = false
        self.churchNoteId = nil
    }

    /// All scripture refs in this devotional, opening first.
    var allScriptureRefs: [String] {
        [openingVerse.reference] + additionalScriptures.map(\.reference)
    }
}

// MARK: - Spiritual Rhythm Snapshot

/// A lightweight record of a completed devotional for streak / cadence tracking.
struct SpiritualRhythmEntry: Identifiable, Codable {
    @DocumentID var id: String?
    let userId: String
    let devotionalId: String
    let topic: String
    let tone: String       // DevotionalTone rawValue
    let completedAt: Date

    init(userId: String, devotionalId: String, topic: String, tone: DevotionalTone) {
        self.userId = userId
        self.devotionalId = devotionalId
        self.topic = topic
        self.tone = tone.rawValue
        self.completedAt = Date()
    }
}

/// Aggregated rhythm data shown in the SpiritualRhythmCard.
struct SpiritualRhythmSnapshot {
    let currentStreakDays: Int
    let longestStreakDays: Int
    let totalDevotionalsCompleted: Int
    let mostUsedTone: DevotionalTone?
    let topTopics: [String]
    let lastCompletedAt: Date?

    var streakDescription: String {
        if currentStreakDays == 0 { return "Begin your devotional rhythm." }
        if currentStreakDays == 1 { return "1 day streak" }
        return "\(currentStreakDays) day streak"
    }
}

// MARK: - Scripture Topic Map

/// Recommended scripture passages for common spiritual topics.
/// Used by ScriptureRecommendationService when the user picks a topic chip.
enum DevotionalTopicMap {
    static let passages: [String: [String]] = [
        "anxiety":        ["Matthew 6:25-27", "Philippians 4:6-7", "1 Peter 5:7", "Psalm 94:19"],
        "grief":          ["Psalm 34:18", "John 11:35", "Revelation 21:4", "Matthew 5:4"],
        "purpose":        ["Jeremiah 29:11", "Romans 8:28", "Ephesians 2:10", "Proverbs 19:21"],
        "faith":          ["Hebrews 11:1", "Romans 10:17", "Mark 9:23", "James 1:3"],
        "forgiveness":    ["Ephesians 4:32", "Colossians 3:13", "Matthew 6:14", "1 John 1:9"],
        "identity":       ["1 Peter 2:9", "Galatians 3:26", "John 1:12", "2 Corinthians 5:17"],
        "love":           ["1 Corinthians 13:4-7", "John 3:16", "Romans 5:8", "1 John 4:19"],
        "healing":        ["Psalm 147:3", "Isaiah 53:5", "James 5:14-15", "Jeremiah 30:17"],
        "strength":       ["Philippians 4:13", "Isaiah 40:31", "2 Corinthians 12:9", "Psalm 46:1"],
        "peace":          ["John 14:27", "Isaiah 26:3", "Philippians 4:7", "Romans 15:13"],
        "joy":            ["Nehemiah 8:10", "Psalm 16:11", "James 1:2-3", "John 15:11"],
        "hope":           ["Romans 15:13", "Lamentations 3:22-23", "Hebrews 6:19", "Romans 8:24-25"],
        "wisdom":         ["James 1:5", "Proverbs 3:5-6", "Psalm 111:10", "1 Corinthians 1:25"],
        "provision":      ["Philippians 4:19", "Matthew 6:33", "Psalm 23:1", "Luke 12:29-31"],
        "worship":        ["Psalm 150:1-6", "John 4:24", "Revelation 4:11", "Psalm 95:1-3"],
        "relationships":  ["Proverbs 27:17", "Ecclesiastes 4:9-10", "1 Thessalonians 5:11", "Romans 12:10"],
        "obedience":      ["John 14:15", "Deuteronomy 28:1", "James 1:22", "1 Samuel 15:22"],
        "suffering":      ["Romans 8:18", "James 1:2-4", "2 Corinthians 4:17", "1 Peter 4:12-13"],
        "gratitude":      ["1 Thessalonians 5:18", "Psalm 107:1", "Colossians 3:17", "Ephesians 5:20"],
        "new beginnings": ["2 Corinthians 5:17", "Isaiah 43:18-19", "Lamentations 3:22-23", "Revelation 21:5"],
        "salvation":      ["John 3:16", "Romans 10:9", "Ephesians 2:8-9", "Acts 4:12"],
        "prayer":         ["Matthew 7:7-8", "1 Thessalonians 5:17", "Philippians 4:6", "Psalm 145:18"],
        "community":      ["Acts 2:42-47", "Hebrews 10:24-25", "Matthew 18:20", "Romans 12:4-5"],
        "holiness":       ["1 Peter 1:16", "Romans 12:1", "Leviticus 20:26", "2 Corinthians 7:1"],
        "grace":          ["Ephesians 2:8", "Romans 5:20", "2 Corinthians 12:9", "Titus 2:11"],
    ]

    /// Returns recommended passage references for a given topic.
    static func passages(for topic: String) -> [String] {
        let normalised = topic.lowercased().trimmingCharacters(in: .whitespaces)
        // Exact match first
        if let refs = passages[normalised] { return refs }
        // Partial match
        for (key, refs) in passages where normalised.contains(key) || key.contains(normalised) {
            return refs
        }
        return []
    }

    /// Returns suggested topic chips based on the user's text input.
    static func suggestedTopics(for query: String) -> [String] {
        let lower = query.lowercased()
        return passages.keys.filter { lower.contains($0) || $0.contains(lower) }.sorted()
    }

    /// All available topic chips, sorted alphabetically.
    static var allTopics: [String] {
        passages.keys.sorted()
    }
}

// MARK: - Generation Phase

/// Tracks which stage the devotional generator is in.
enum DevotionalGenerationPhase: Equatable, Hashable {
    case idle
    case gatheringContext
    case fetchingScripture
    case composing
    case validatingSafety
    case complete
    case failed(String)

    var displayLabel: String {
        switch self {
        case .idle:              return "Ready"
        case .gatheringContext:  return "Gathering your context…"
        case .fetchingScripture: return "Finding scripture…"
        case .composing:         return "Writing your devotional…"
        case .validatingSafety:  return "Reviewing content…"
        case .complete:          return "Done"
        case .failed:            return "Something went wrong"
        }
    }

    var isLoading: Bool {
        switch self {
        case .idle, .complete, .failed: return false
        default: return true
        }
    }
}
