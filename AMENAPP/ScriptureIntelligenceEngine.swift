//
//  ScriptureIntelligenceEngine.swift
//  AMENAPP
//
//  Scripture-to-System Intelligence Layer.
//  Each verse is transformed into a modular AI behavior unit with:
//    - Context tags (when to trigger)
//    - Berean prompts (what to ask)
//    - Daily training prompts (action steps)
//    - Church Notes integration hooks
//    - Find a Church hooks (where applicable)
//    - Safety layer behaviors
//
//  This is NOT devotional content — this is intelligence architecture.
//  The engine maps user state → verse cluster → response strategy.
//
//  Architecture:
//    ScriptureIntelligenceEngine (singleton)
//    ├── ScriptureIntelligenceUnit     (one per verse — the intelligence atom)
//    ├── ContextTag                    (emotional/behavioral/spiritual classifiers)
//    ├── IntelligencePrompt            (Berean + daily + church notes prompts)
//    ├── SafetyBehavior                (detection → response rules)
//    └── matchUnits(for:)              (context → ranked verse units)
//

import Foundation

// MARK: - Context Tag

/// Classifies the user's current state for verse matching.
/// Multiple tags can apply simultaneously.
enum ContextTag: String, Codable, CaseIterable {
    // Emotional states
    case fear               = "fear"
    case anxiety            = "anxiety"
    case anger              = "anger"
    case guilt              = "guilt"
    case shame              = "shame"
    case isolation          = "isolation"
    case stress             = "stress"
    case hopelessness       = "hopelessness"

    // Behavioral patterns
    case inconsistency      = "inconsistency"
    case laziness           = "laziness"
    case impulsivity        = "impulsivity"
    case contentConsumption = "content_consumption"
    case compulsiveUse      = "compulsive_use"
    case inactivity         = "inactivity"
    case avoidance          = "avoidance"

    // Spiritual categories
    case discipline         = "discipline"
    case temptation         = "temptation"
    case pride              = "pride"
    case conflict           = "conflict"
    case decisionMaking     = "decision_making"
    case priorities         = "priorities"
    case relationships      = "relationships"
    case purpose            = "purpose"
    case spiritualStagnation = "spiritual_stagnation"
    case emotionalInstability = "emotional_instability"
    case worldlyInfluence   = "worldly_influence"

    /// Human-readable label for transparency layer.
    var displayLabel: String {
        switch self {
        case .fear: return "Fear"
        case .anxiety: return "Anxiety"
        case .anger: return "Anger"
        case .guilt: return "Guilt"
        case .shame: return "Shame"
        case .isolation: return "Isolation"
        case .stress: return "Stress"
        case .hopelessness: return "Hopelessness"
        case .inconsistency: return "Inconsistency"
        case .laziness: return "Lack of motivation"
        case .impulsivity: return "Impulsivity"
        case .contentConsumption: return "Content intake patterns"
        case .compulsiveUse: return "Compulsive usage"
        case .inactivity: return "Inactivity"
        case .avoidance: return "Avoidance"
        case .discipline: return "Discipline"
        case .temptation: return "Temptation"
        case .pride: return "Pride"
        case .conflict: return "Conflict"
        case .decisionMaking: return "Decision-making"
        case .priorities: return "Priorities"
        case .relationships: return "Relationships"
        case .purpose: return "Purpose"
        case .spiritualStagnation: return "Spiritual stagnation"
        case .emotionalInstability: return "Emotional instability"
        case .worldlyInfluence: return "Worldly influence"
        }
    }
}

// MARK: - Intelligence Prompt

/// A single prompt that Berean can surface in a specific context.
struct IntelligencePrompt: Codable, Identifiable {
    let id: String
    let text: String
    let surface: PromptSurface

    enum PromptSurface: String, Codable {
        case bereanChat       = "berean_chat"        // In-chat question
        case dailyTraining    = "daily_training"     // Push/local notification or daily card
        case churchNotes      = "church_notes"       // Follow-up in church notes
        case findAChurch      = "find_a_church"      // Church discovery trigger
    }
}

// MARK: - Safety Behavior

/// Defines what the safety layer should do when this verse's context is detected.
struct SafetyBehavior: Codable {
    let detectionPattern: String       // What to look for (e.g. "repeated temptation")
    let response: SafetyResponse

    enum SafetyResponse: String, Codable {
        case suggestStructure           // Offer a plan, not guilt
        case escalateReflection         // Deepen the reflection loop
        case interventionPrompt         // Preemptive prompt before action
        case suggestChurch              // Surface Find a Church
        case suggestHumanConnection     // Escalate to real person
        case preventShameSpiral         // Break condemnation loop
        case suggestAccountability      // Suggest accountability partner
    }
}

// MARK: - Scripture Intelligence Unit

/// The atomic intelligence unit — one per verse.
/// Maps a scripture to context tags, prompts, and safety behaviors.
struct ScriptureIntelligenceUnit: Identifiable, Codable {
    let id: String                          // e.g. "1tim4_7"
    let reference: String                   // e.g. "1 Timothy 4:7-8"
    let shortTitle: String                  // e.g. "Train Yourself to Be Godly"
    let contextTags: [ContextTag]           // When to trigger
    let bereanPrompts: [IntelligencePrompt] // Questions Berean asks
    let dailyPrompt: IntelligencePrompt?    // Daily training action
    let churchNotesPrompt: IntelligencePrompt? // Church notes follow-up
    let findAChurchHook: IntelligencePrompt?   // Church discovery trigger
    let safetyBehaviors: [SafetyBehavior]   // Safety layer rules
    let priority: Int                       // Higher = more important (1-10)
}

// MARK: - Scripture Intelligence Engine

/// Singleton that holds all scripture intelligence units and matches them
/// to user context. This is the brain that connects detected user state
/// to scripture-grounded responses.
final class ScriptureIntelligenceEngine {

    static let shared = ScriptureIntelligenceEngine()

    /// All registered intelligence units.
    let units: [ScriptureIntelligenceUnit]

    /// Index: contextTag → [unit IDs] for fast lookup.
    private let tagIndex: [ContextTag: [String]]

    private init() {
        let allUnits = ScriptureIntelligenceEngine.buildUnits()
        self.units = allUnits

        var index: [ContextTag: [String]] = [:]
        for unit in allUnits {
            for tag in unit.contextTags {
                index[tag, default: []].append(unit.id)
            }
        }
        self.tagIndex = index
    }

    // MARK: - Matching API

    /// Returns intelligence units matching the given context tags, ranked by relevance.
    /// - Parameter tags: The detected context tags from user state.
    /// - Parameter limit: Max units to return (default 3).
    /// - Returns: Ranked array of matching units.
    func matchUnits(for tags: Set<ContextTag>, limit: Int = 3) -> [ScriptureIntelligenceUnit] {
        guard !tags.isEmpty else { return [] }

        var scored: [(unit: ScriptureIntelligenceUnit, score: Double)] = []
        var seen = Set<String>()

        for tag in tags {
            guard let unitIDs = tagIndex[tag] else { continue }
            for unitID in unitIDs {
                guard !seen.contains(unitID),
                      let unit = units.first(where: { $0.id == unitID }) else { continue }
                seen.insert(unitID)

                // Score = number of matching tags * priority
                let matchCount = Double(unit.contextTags.filter { tags.contains($0) }.count)
                let score = matchCount * Double(unit.priority)
                scored.append((unit, score))
            }
        }

        return scored
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map(\.unit)
    }

    /// Returns all Berean prompts for a given set of context tags.
    func bereanPrompts(for tags: Set<ContextTag>, limit: Int = 5) -> [IntelligencePrompt] {
        matchUnits(for: tags, limit: limit)
            .flatMap(\.bereanPrompts)
    }

    /// Returns daily training prompts for a given set of context tags.
    func dailyPrompts(for tags: Set<ContextTag>, limit: Int = 3) -> [IntelligencePrompt] {
        matchUnits(for: tags, limit: limit)
            .compactMap(\.dailyPrompt)
    }

    /// Returns safety behaviors triggered by the given context tags.
    func safetyBehaviors(for tags: Set<ContextTag>) -> [SafetyBehavior] {
        matchUnits(for: tags, limit: 5)
            .flatMap(\.safetyBehaviors)
    }

    /// Returns Find a Church hooks if applicable for the given context.
    func findAChurchHooks(for tags: Set<ContextTag>) -> [IntelligencePrompt] {
        matchUnits(for: tags, limit: 5)
            .compactMap(\.findAChurchHook)
    }

    /// Builds a system prompt injection for Berean based on detected context.
    /// This is appended to the system prompt so Berean "knows" what the user needs.
    func systemPromptContext(for tags: Set<ContextTag>) -> String {
        let matched = matchUnits(for: tags, limit: 3)
        guard !matched.isEmpty else { return "" }

        var lines: [String] = []
        lines.append("--- Detected Spiritual Context ---")
        lines.append("Detected patterns: \(tags.map(\.displayLabel).joined(separator: ", "))")
        lines.append("")

        for unit in matched {
            lines.append("Relevant Scripture: \(unit.reference) — \(unit.shortTitle)")
            let prompts = unit.bereanPrompts.map(\.text).joined(separator: " | ")
            lines.append("Suggested questions to ask the user: \(prompts)")
        }

        lines.append("")
        lines.append("Use these scriptures and questions naturally in your response.")
        lines.append("Do not list them mechanically — weave them into compassionate dialogue.")
        lines.append("--- End Context ---")

        return lines.joined(separator: "\n")
    }

    // MARK: - Unit Definitions (20 Scriptures)

    private static func buildUnits() -> [ScriptureIntelligenceUnit] {
        [
            // 1. 1 Timothy 4:7-8 — Train Yourself to Be Godly
            ScriptureIntelligenceUnit(
                id: "1tim4_7",
                reference: "1 Timothy 4:7-8",
                shortTitle: "Train Yourself to Be Godly",
                contextTags: [.discipline, .inconsistency, .spiritualStagnation],
                bereanPrompts: [
                    IntelligencePrompt(id: "1tim4_7_b1", text: "Where are you being passive instead of training intentionally?", surface: .bereanChat),
                    IntelligencePrompt(id: "1tim4_7_b2", text: "What would disciplined obedience look like today?", surface: .bereanChat)
                ],
                dailyPrompt: IntelligencePrompt(id: "1tim4_7_d", text: "Choose one spiritual practice and complete it fully today.", surface: .dailyTraining),
                churchNotesPrompt: IntelligencePrompt(id: "1tim4_7_cn", text: "Turn this into a 7-day training loop?", surface: .churchNotes),
                findAChurchHook: nil,
                safetyBehaviors: [
                    SafetyBehavior(detectionPattern: "repeated inconsistency in spiritual habits", response: .suggestStructure)
                ],
                priority: 8
            ),

            // 2. James 1:22 — Doers of the Word
            ScriptureIntelligenceUnit(
                id: "jas1_22",
                reference: "James 1:22",
                shortTitle: "Doers of the Word",
                contextTags: [.contentConsumption, .avoidance, .inconsistency],
                bereanPrompts: [
                    IntelligencePrompt(id: "jas1_22_b1", text: "What did you learn recently but haven't obeyed?", surface: .bereanChat),
                    IntelligencePrompt(id: "jas1_22_b2", text: "What is one action you are avoiding?", surface: .bereanChat)
                ],
                dailyPrompt: IntelligencePrompt(id: "jas1_22_d", text: "Apply one truth you've learned immediately today.", surface: .dailyTraining),
                churchNotesPrompt: IntelligencePrompt(id: "jas1_22_cn", text: "Convert this insight to an action step.", surface: .churchNotes),
                findAChurchHook: nil,
                safetyBehaviors: [],
                priority: 7
            ),

            // 3. Proverbs 4:23 — Guard Your Heart
            ScriptureIntelligenceUnit(
                id: "prov4_23",
                reference: "Proverbs 4:23",
                shortTitle: "Guard Your Heart",
                contextTags: [.contentConsumption, .emotionalInstability, .compulsiveUse],
                bereanPrompts: [
                    IntelligencePrompt(id: "prov4_23_b1", text: "What has been shaping your thoughts lately?", surface: .bereanChat),
                    IntelligencePrompt(id: "prov4_23_b2", text: "What input is weakening your clarity?", surface: .bereanChat)
                ],
                dailyPrompt: IntelligencePrompt(id: "prov4_23_d", text: "Remove one unhealthy input from your life today.", surface: .dailyTraining),
                churchNotesPrompt: nil,
                findAChurchHook: nil,
                safetyBehaviors: [
                    SafetyBehavior(detectionPattern: "doomscrolling or compulsive content consumption", response: .interventionPrompt)
                ],
                priority: 8
            ),

            // 4. Romans 12:2 — Renew Your Mind
            ScriptureIntelligenceUnit(
                id: "rom12_2",
                reference: "Romans 12:2",
                shortTitle: "Renew Your Mind",
                contextTags: [.worldlyInfluence, .emotionalInstability, .contentConsumption],
                bereanPrompts: [
                    IntelligencePrompt(id: "rom12_2_b1", text: "What belief needs to be replaced with truth?", surface: .bereanChat),
                    IntelligencePrompt(id: "rom12_2_b2", text: "Are you conforming or being transformed?", surface: .bereanChat)
                ],
                dailyPrompt: IntelligencePrompt(id: "rom12_2_d", text: "Identify one worldly pattern and replace it with a scriptural truth today.", surface: .dailyTraining),
                churchNotesPrompt: IntelligencePrompt(id: "rom12_2_cn", text: "Map this to a Scripture replacement practice.", surface: .churchNotes),
                findAChurchHook: nil,
                safetyBehaviors: [],
                priority: 7
            ),

            // 5. Galatians 5:16 — Walk by the Spirit
            ScriptureIntelligenceUnit(
                id: "gal5_16",
                reference: "Galatians 5:16",
                shortTitle: "Walk by the Spirit",
                contextTags: [.temptation, .impulsivity],
                bereanPrompts: [
                    IntelligencePrompt(id: "gal5_16_b1", text: "What desire are you following right now?", surface: .bereanChat),
                    IntelligencePrompt(id: "gal5_16_b2", text: "What would walking by the Spirit look like here?", surface: .bereanChat)
                ],
                dailyPrompt: IntelligencePrompt(id: "gal5_16_d", text: "Before each decision today, pause and ask: 'Is this the Spirit or the flesh?'", surface: .dailyTraining),
                churchNotesPrompt: nil,
                findAChurchHook: nil,
                safetyBehaviors: [
                    SafetyBehavior(detectionPattern: "repeated temptation patterns", response: .escalateReflection)
                ],
                priority: 9
            ),

            // 6. Matthew 5:37 — Let Your Yes Be Yes
            ScriptureIntelligenceUnit(
                id: "matt5_37",
                reference: "Matthew 5:37",
                shortTitle: "Let Your Yes Be Yes",
                contextTags: [.inconsistency, .avoidance],
                bereanPrompts: [
                    IntelligencePrompt(id: "matt5_37_b1", text: "Where are you being unclear or dishonest?", surface: .bereanChat),
                    IntelligencePrompt(id: "matt5_37_b2", text: "What commitment are you avoiding?", surface: .bereanChat)
                ],
                dailyPrompt: IntelligencePrompt(id: "matt5_37_d", text: "Follow through on one commitment you've been putting off.", surface: .dailyTraining),
                churchNotesPrompt: nil,
                findAChurchHook: nil,
                safetyBehaviors: [],
                priority: 6
            ),

            // 7. Philippians 4:6-7 — Do Not Be Anxious
            ScriptureIntelligenceUnit(
                id: "phil4_6",
                reference: "Philippians 4:6-7",
                shortTitle: "Do Not Be Anxious",
                contextTags: [.anxiety, .stress, .fear],
                bereanPrompts: [
                    IntelligencePrompt(id: "phil4_6_b1", text: "Have you brought this to God or just carried it?", surface: .bereanChat),
                    IntelligencePrompt(id: "phil4_6_b2", text: "What are you holding onto instead of surrendering?", surface: .bereanChat)
                ],
                dailyPrompt: IntelligencePrompt(id: "phil4_6_d", text: "Write down your anxieties, then pray through each one specifically.", surface: .dailyTraining),
                churchNotesPrompt: nil,
                findAChurchHook: IntelligencePrompt(id: "phil4_6_fc", text: "Would you like prayer support from a local church?", surface: .findAChurch),
                safetyBehaviors: [],
                priority: 9
            ),

            // 8. Hebrews 10:24-25 — Do Not Neglect Meeting
            ScriptureIntelligenceUnit(
                id: "heb10_24",
                reference: "Hebrews 10:24-25",
                shortTitle: "Do Not Neglect Meeting Together",
                contextTags: [.isolation, .inactivity],
                bereanPrompts: [
                    IntelligencePrompt(id: "heb10_24_b1", text: "When was the last time you gathered with believers?", surface: .bereanChat),
                    IntelligencePrompt(id: "heb10_24_b2", text: "Who could you encourage this week?", surface: .bereanChat)
                ],
                dailyPrompt: IntelligencePrompt(id: "heb10_24_d", text: "Reach out to one believer today — a text, call, or visit.", surface: .dailyTraining),
                churchNotesPrompt: nil,
                findAChurchHook: IntelligencePrompt(id: "heb10_24_fc", text: "Find a church near you to connect with this week.", surface: .findAChurch),
                safetyBehaviors: [
                    SafetyBehavior(detectionPattern: "prolonged isolation from community", response: .suggestChurch),
                    SafetyBehavior(detectionPattern: "social withdrawal signals", response: .suggestHumanConnection)
                ],
                priority: 9
            ),

            // 9. Ephesians 4:29 — Speech Check
            ScriptureIntelligenceUnit(
                id: "eph4_29",
                reference: "Ephesians 4:29",
                shortTitle: "Let No Corrupt Talk Come Out",
                contextTags: [.conflict, .anger, .relationships],
                bereanPrompts: [
                    IntelligencePrompt(id: "eph4_29_b1", text: "Did your words build up or tear down today?", surface: .bereanChat),
                    IntelligencePrompt(id: "eph4_29_b2", text: "Is there someone you need to speak life to?", surface: .bereanChat)
                ],
                dailyPrompt: IntelligencePrompt(id: "eph4_29_d", text: "Speak one intentional encouragement to someone today.", surface: .dailyTraining),
                churchNotesPrompt: nil,
                findAChurchHook: nil,
                safetyBehaviors: [],
                priority: 7
            ),

            // 10. Colossians 3:23 — Work as for the Lord
            ScriptureIntelligenceUnit(
                id: "col3_23",
                reference: "Colossians 3:23",
                shortTitle: "Work as for the Lord",
                contextTags: [.laziness, .purpose, .inconsistency],
                bereanPrompts: [
                    IntelligencePrompt(id: "col3_23_b1", text: "Are you working with excellence or just finishing tasks?", surface: .bereanChat),
                    IntelligencePrompt(id: "col3_23_b2", text: "What would it look like to serve God through your work today?", surface: .bereanChat)
                ],
                dailyPrompt: IntelligencePrompt(id: "col3_23_d", text: "Do your next task with full focus, as if doing it directly for God.", surface: .dailyTraining),
                churchNotesPrompt: nil,
                findAChurchHook: nil,
                safetyBehaviors: [],
                priority: 6
            ),

            // 11. Luke 16:10 — Faithful in Little
            ScriptureIntelligenceUnit(
                id: "luke16_10",
                reference: "Luke 16:10",
                shortTitle: "Faithful in Little",
                contextTags: [.inconsistency, .discipline, .avoidance],
                bereanPrompts: [
                    IntelligencePrompt(id: "luke16_10_b1", text: "What small responsibility are you neglecting?", surface: .bereanChat),
                    IntelligencePrompt(id: "luke16_10_b2", text: "What is the smallest act of faithfulness you can do right now?", surface: .bereanChat)
                ],
                dailyPrompt: IntelligencePrompt(id: "luke16_10_d", text: "Complete one small, overlooked task with excellence today.", surface: .dailyTraining),
                churchNotesPrompt: nil,
                findAChurchHook: nil,
                safetyBehaviors: [],
                priority: 6
            ),

            // 12. Psalm 119:105 — Word as a Lamp
            ScriptureIntelligenceUnit(
                id: "ps119_105",
                reference: "Psalm 119:105",
                shortTitle: "Your Word Is a Lamp",
                contextTags: [.decisionMaking, .worldlyInfluence],
                bereanPrompts: [
                    IntelligencePrompt(id: "ps119_105_b1", text: "Have you consulted Scripture before making this decision?", surface: .bereanChat),
                    IntelligencePrompt(id: "ps119_105_b2", text: "What does God's Word say about the path you're considering?", surface: .bereanChat)
                ],
                dailyPrompt: IntelligencePrompt(id: "ps119_105_d", text: "Before your next decision today, find one verse that speaks into it.", surface: .dailyTraining),
                churchNotesPrompt: nil,
                findAChurchHook: nil,
                safetyBehaviors: [],
                priority: 7
            ),

            // 13. 2 Timothy 1:7 — Spirit of Power
            ScriptureIntelligenceUnit(
                id: "2tim1_7",
                reference: "2 Timothy 1:7",
                shortTitle: "Spirit of Power, Love, and Self-Control",
                contextTags: [.fear, .anxiety, .avoidance],
                bereanPrompts: [
                    IntelligencePrompt(id: "2tim1_7_b1", text: "Is this fear from God or something else?", surface: .bereanChat),
                    IntelligencePrompt(id: "2tim1_7_b2", text: "What would courage look like in this situation?", surface: .bereanChat)
                ],
                dailyPrompt: IntelligencePrompt(id: "2tim1_7_d", text: "Face one thing you've been avoiding out of fear today.", surface: .dailyTraining),
                churchNotesPrompt: nil,
                findAChurchHook: nil,
                safetyBehaviors: [],
                priority: 8
            ),

            // 14. 1 Corinthians 10:13 — Temptation Escape
            ScriptureIntelligenceUnit(
                id: "1cor10_13",
                reference: "1 Corinthians 10:13",
                shortTitle: "No Temptation Beyond What You Can Bear",
                contextTags: [.temptation, .impulsivity, .compulsiveUse],
                bereanPrompts: [
                    IntelligencePrompt(id: "1cor10_13_b1", text: "What is your exit strategy right now?", surface: .bereanChat),
                    IntelligencePrompt(id: "1cor10_13_b2", text: "God has provided a way out — can you see it?", surface: .bereanChat)
                ],
                dailyPrompt: IntelligencePrompt(id: "1cor10_13_d", text: "Identify your top temptation trigger and write down your escape plan.", surface: .dailyTraining),
                churchNotesPrompt: nil,
                findAChurchHook: nil,
                safetyBehaviors: [
                    SafetyBehavior(detectionPattern: "repeated temptation cycle", response: .suggestAccountability),
                    SafetyBehavior(detectionPattern: "late-night compulsive usage", response: .interventionPrompt)
                ],
                priority: 9
            ),

            // 15. Matthew 6:33 — Seek First the Kingdom
            ScriptureIntelligenceUnit(
                id: "matt6_33",
                reference: "Matthew 6:33",
                shortTitle: "Seek First the Kingdom",
                contextTags: [.priorities, .worldlyInfluence, .stress],
                bereanPrompts: [
                    IntelligencePrompt(id: "matt6_33_b1", text: "What are you prioritizing over God today?", surface: .bereanChat),
                    IntelligencePrompt(id: "matt6_33_b2", text: "If you sought God first today, what would change?", surface: .bereanChat)
                ],
                dailyPrompt: IntelligencePrompt(id: "matt6_33_d", text: "Start your day with God before checking anything else.", surface: .dailyTraining),
                churchNotesPrompt: nil,
                findAChurchHook: nil,
                safetyBehaviors: [],
                priority: 8
            ),

            // 16. James 1:19 — Slow to Speak
            ScriptureIntelligenceUnit(
                id: "jas1_19",
                reference: "James 1:19",
                shortTitle: "Quick to Listen, Slow to Speak",
                contextTags: [.anger, .conflict, .impulsivity],
                bereanPrompts: [
                    IntelligencePrompt(id: "jas1_19_b1", text: "What triggered your reaction?", surface: .bereanChat),
                    IntelligencePrompt(id: "jas1_19_b2", text: "Did you listen before responding?", surface: .bereanChat)
                ],
                dailyPrompt: IntelligencePrompt(id: "jas1_19_d", text: "In your next conversation, listen fully before speaking.", surface: .dailyTraining),
                churchNotesPrompt: nil,
                findAChurchHook: nil,
                safetyBehaviors: [],
                priority: 7
            ),

            // 17. Micah 6:8 — Walk Humbly
            ScriptureIntelligenceUnit(
                id: "micah6_8",
                reference: "Micah 6:8",
                shortTitle: "Act Justly, Love Mercy, Walk Humbly",
                contextTags: [.pride, .conflict, .relationships],
                bereanPrompts: [
                    IntelligencePrompt(id: "micah6_8_b1", text: "Where is pride influencing your response?", surface: .bereanChat),
                    IntelligencePrompt(id: "micah6_8_b2", text: "What does humility look like in this situation?", surface: .bereanChat)
                ],
                dailyPrompt: IntelligencePrompt(id: "micah6_8_d", text: "Choose mercy over being right in one interaction today.", surface: .dailyTraining),
                churchNotesPrompt: nil,
                findAChurchHook: nil,
                safetyBehaviors: [],
                priority: 7
            ),

            // 18. John 13:35 — Love One Another
            ScriptureIntelligenceUnit(
                id: "john13_35",
                reference: "John 13:35",
                shortTitle: "By This All People Will Know",
                contextTags: [.relationships, .isolation, .conflict],
                bereanPrompts: [
                    IntelligencePrompt(id: "john13_35_b1", text: "Who needs love from you today?", surface: .bereanChat),
                    IntelligencePrompt(id: "john13_35_b2", text: "How can you show Christ's love in a tangible way?", surface: .bereanChat)
                ],
                dailyPrompt: IntelligencePrompt(id: "john13_35_d", text: "Perform one act of love for someone — expected or unexpected.", surface: .dailyTraining),
                churchNotesPrompt: nil,
                findAChurchHook: nil,
                safetyBehaviors: [],
                priority: 7
            ),

            // 19. Romans 8:1 — No Condemnation
            ScriptureIntelligenceUnit(
                id: "rom8_1",
                reference: "Romans 8:1",
                shortTitle: "No Condemnation in Christ",
                contextTags: [.guilt, .shame, .hopelessness],
                bereanPrompts: [
                    IntelligencePrompt(id: "rom8_1_b1", text: "Are you convicted or condemning yourself?", surface: .bereanChat),
                    IntelligencePrompt(id: "rom8_1_b2", text: "What truth about grace do you need to hear right now?", surface: .bereanChat)
                ],
                dailyPrompt: IntelligencePrompt(id: "rom8_1_d", text: "Write down one area of guilt and declare God's grace over it.", surface: .dailyTraining),
                churchNotesPrompt: nil,
                findAChurchHook: nil,
                safetyBehaviors: [
                    SafetyBehavior(detectionPattern: "shame spiral or self-condemnation loop", response: .preventShameSpiral)
                ],
                priority: 10
            ),

            // 20. Psalm 139:23-24 — Search Me
            ScriptureIntelligenceUnit(
                id: "ps139_23",
                reference: "Psalm 139:23-24",
                shortTitle: "Search Me, O God",
                contextTags: [.avoidance, .pride, .spiritualStagnation],
                bereanPrompts: [
                    IntelligencePrompt(id: "ps139_23_b1", text: "What might you be avoiding seeing about yourself?", surface: .bereanChat),
                    IntelligencePrompt(id: "ps139_23_b2", text: "Are you willing to let God reveal what needs to change?", surface: .bereanChat)
                ],
                dailyPrompt: IntelligencePrompt(id: "ps139_23_d", text: "Spend 5 minutes in silence asking God to search your heart. Write what comes.", surface: .dailyTraining),
                churchNotesPrompt: nil,
                findAChurchHook: nil,
                safetyBehaviors: [],
                priority: 8
            )
        ]
    }
}
