// ChurchNotesIntelligenceModels.swift
// AMENAPP
//
// Intelligence layer models for Church Notes.
// Additive — does not replace existing block/highlight models.
// Covers: anchor types, reflections, posture signals, note connections,
//         sermon bridge (Monday bridge), God Has Been Saying summary.

import Foundation
import SwiftUI

// MARK: - Anchor Type

/// User-facing anchor types for marking meaningful content in a church note block.
/// Maps to ChurchNoteSemanticType for compatibility with the existing block system.
enum CNAnchorType: String, Codable, CaseIterable, Hashable, Identifiable {
    case conviction          // Something that challenged or convicted me
    case revelation          // A new understanding or spiritual insight
    case prayer              // A specific prayer response or request
    case actionStep          // Something I need to do this week
    case question            // A question for my pastor, mentor, or small group
    case verse               // A verse to revisit, memorize, or study
    case quote               // A pastor quote or key phrase worth keeping
    case testimonySeed       // Something that may become a testimony later

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .conviction:    return "Conviction"
        case .revelation:    return "Revelation"
        case .prayer:        return "Prayer"
        case .actionStep:    return "Action Step"
        case .question:      return "Question"
        case .verse:         return "Verse"
        case .quote:         return "Quote"
        case .testimonySeed: return "Testimony Seed"
        }
    }

    var shortLabel: String {
        switch self {
        case .conviction:    return "Conviction"
        case .revelation:    return "Insight"
        case .prayer:        return "Prayer"
        case .actionStep:    return "Action"
        case .question:      return "Question"
        case .verse:         return "Verse"
        case .quote:         return "Quote"
        case .testimonySeed: return "Testimony"
        }
    }

    var icon: String {
        switch self {
        case .conviction:    return "heart.circle.fill"
        case .revelation:    return "lightbulb.fill"
        case .prayer:        return "hands.sparkles.fill"
        case .actionStep:    return "checkmark.circle.fill"
        case .question:      return "questionmark.circle"
        case .verse:         return "book.fill"
        case .quote:         return "quote.opening"
        case .testimonySeed: return "person.wave.2.fill"
        }
    }

    /// Low-saturation fill for anchor highlight — light/dark compatible.
    var fillColor: Color {
        switch self {
        case .conviction:    return Color(cnIntel: "F5E8D0", dark: "4A3A20").opacity(0.55)
        case .revelation:    return Color(cnIntel: "DDE8EE", dark: "1E3040").opacity(0.55)
        case .prayer:        return Color(cnIntel: "EFE4EE", dark: "3A2040").opacity(0.55)
        case .actionStep:    return Color(cnIntel: "DDE8D8", dark: "1E3820").opacity(0.55)
        case .question:      return Color(cnIntel: "E8E2D0", dark: "3A3018").opacity(0.55)
        case .verse:         return Color(cnIntel: "DCE7F7", dark: "1A2A44").opacity(0.55)
        case .quote:         return Color(cnIntel: "E4E3EA", dark: "2A2A38").opacity(0.55)
        case .testimonySeed: return Color(cnIntel: "F0E4E4", dark: "402020").opacity(0.55)
        }
    }

    var borderColor: Color {
        switch self {
        case .conviction:    return Color(cnIntel: "C8A870", dark: "C8A870")
        case .revelation:    return Color(cnIntel: "90B0C8", dark: "90B0C8")
        case .prayer:        return Color(cnIntel: "C0A0C4", dark: "C0A0C4")
        case .actionStep:    return Color(cnIntel: "90B888", dark: "90B888")
        case .question:      return Color(cnIntel: "B8A870", dark: "B8A870")
        case .verse:         return Color(cnIntel: "90A8C8", dark: "90A8C8")
        case .quote:         return Color(cnIntel: "A0A0B0", dark: "A0A0B0")
        case .testimonySeed: return Color(cnIntel: "C0909A", dark: "C0909A")
        }
    }

    var accentColor: Color { borderColor }

    /// Downstream workflow suggestion shown when anchor is applied.
    var downstreamHint: String {
        switch self {
        case .conviction:    return "Would you like to carry this into prayer?"
        case .revelation:    return "Would you like Berean to help you go deeper?"
        case .prayer:        return "Would you like to save this as a prayer?"
        case .actionStep:    return "Would you like to set a reminder for Tuesday?"
        case .question:      return "Save this for your pastor or small group?"
        case .verse:         return "Would you like to study this in Selah?"
        case .quote:         return "Would you like to save this as a shareable card?"
        case .testimonySeed: return "This could become a testimony. Keep going."
        }
    }

    /// Maps to existing ChurchNoteSemanticType for block compatibility.
    var semanticType: ChurchNoteSemanticType {
        switch self {
        case .conviction:    return .conviction
        case .revelation:    return .keyTruth
        case .prayer:        return .prayerPoint
        case .actionStep:    return .actionStep
        case .question:      return .question
        case .verse:         return .verseInsight
        case .quote:         return .pastorQuote
        case .testimonySeed: return .testimony
        }
    }

    init(from semanticType: ChurchNoteSemanticType) {
        switch semanticType {
        case .conviction:    self = .conviction
        case .keyTruth:      self = .revelation
        case .prayerPoint:   self = .prayer
        case .actionStep:    self = .actionStep
        case .question:      self = .question
        case .verseInsight:  self = .verse
        case .pastorQuote:   self = .quote
        case .testimony:     self = .testimonySeed
        default:             self = .revelation
        }
    }
}

// MARK: - Anchor Color init (scoped)

private extension Color {
    init(cnIntel lightHex: String, dark darkHex: String) {
        // Light-mode color used in all contexts.
        // Dark adaptation is handled by SwiftUI's adaptive color resolution
        // via asset catalog — here we use the light value as a reasonable default.
        let hex = lightHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

// MARK: - Reflection Replay

enum CNReflectionPromptType: String, Codable, CaseIterable, Hashable {
    case boreAnyFruit           = "bore_any_fruit"
    case didYouObey             = "did_you_obey"
    case prayerAnswered         = "prayer_answered"
    case stillWrestling         = "still_wrestling"
    case deepenedUnderstanding  = "deepened_understanding"

    var question: String {
        switch self {
        case .boreAnyFruit:           return "Did this word bear fruit in your life?"
        case .didYouObey:             return "Did you act on what you felt called to do?"
        case .prayerAnswered:         return "Has God answered this prayer?"
        case .stillWrestling:         return "Are you still wrestling with this?"
        case .deepenedUnderstanding:  return "Has your understanding of this deepened?"
        }
    }

    var followUpPrompt: String {
        switch self {
        case .boreAnyFruit:           return "What fruit, if any, did you see?"
        case .didYouObey:             return "What happened when you stepped out?"
        case .prayerAnswered:         return "How did God respond?"
        case .stillWrestling:         return "What is still unresolved for you?"
        case .deepenedUnderstanding:  return "What do you understand now that you didn't before?"
        }
    }
}

enum CNReflectionOutcome: String, Codable, CaseIterable, Hashable {
    case fruitSeen       = "fruit_seen"
    case obeyed          = "obeyed"
    case answered        = "answered"
    case stillWrestling  = "still_wrestling"
    case stillProcessing = "still_processing"
    case notSure         = "not_sure"

    var displayName: String {
        switch self {
        case .fruitSeen:       return "Saw fruit"
        case .obeyed:          return "Obeyed"
        case .answered:        return "Answered"
        case .stillWrestling:  return "Still wrestling"
        case .stillProcessing: return "Still processing"
        case .notSure:         return "Not sure yet"
        }
    }

    var icon: String {
        switch self {
        case .fruitSeen:       return "leaf.fill"
        case .obeyed:          return "checkmark.circle.fill"
        case .answered:        return "checkmark.seal.fill"
        case .stillWrestling:  return "arrow.circlepath"
        case .stillProcessing: return "circle.dotted"
        case .notSure:         return "questionmark.circle"
        }
    }

    var isPositive: Bool {
        self == .fruitSeen || self == .obeyed || self == .answered
    }
}

struct ChurchNoteReflection: Codable, Identifiable, Hashable {
    var id: String
    var noteId: String
    var promptType: CNReflectionPromptType
    var responseText: String
    var outcome: CNReflectionOutcome?
    var replayIntervalDays: Int   // 1, 7, 30, 90
    var createdAt: Date
    var surfacedAt: Date

    init(
        id: String = UUID().uuidString,
        noteId: String,
        promptType: CNReflectionPromptType = .boreAnyFruit,
        responseText: String = "",
        outcome: CNReflectionOutcome? = nil,
        replayIntervalDays: Int = 7,
        createdAt: Date = Date(),
        surfacedAt: Date = Date()
    ) {
        self.id = id
        self.noteId = noteId
        self.promptType = promptType
        self.responseText = responseText
        self.outcome = outcome
        self.replayIntervalDays = replayIntervalDays
        self.createdAt = createdAt
        self.surfacedAt = surfacedAt
    }
}

// MARK: - Posture Signal

/// Reflects the spiritual/emotional posture detected or selected in a note.
/// Always framed as "possible tone" — never diagnostic or prescriptive.
enum CNPostureSignal: String, Codable, CaseIterable, Hashable {
    case convicted
    case comforted
    case expectant
    case burdened
    case grateful
    case confused
    case repentant
    case encouraged
    case challenged

    var displayName: String {
        switch self {
        case .convicted:   return "Convicted"
        case .comforted:   return "Comforted"
        case .expectant:   return "Expectant"
        case .burdened:    return "Carrying something"
        case .grateful:    return "Grateful"
        case .confused:    return "Searching"
        case .repentant:   return "Repentant"
        case .encouraged:  return "Encouraged"
        case .challenged:  return "Challenged"
        }
    }

    var icon: String {
        switch self {
        case .convicted:   return "heart.circle.fill"
        case .comforted:   return "hand.raised.fill"
        case .expectant:   return "sparkles"
        case .burdened:    return "cloud.fill"
        case .grateful:    return "sun.max.fill"
        case .confused:    return "questionmark.circle"
        case .repentant:   return "arrow.circlepath"
        case .encouraged:  return "flag.fill"
        case .challenged:  return "mountain.2.fill"
        }
    }

    /// Suggested contextual action for this posture state.
    var suggestedAction: String {
        switch self {
        case .convicted:   return "Would you like to carry this into prayer?"
        case .comforted:   return "Would you like to save this as a promise to hold?"
        case .expectant:   return "Would you like to write a prayer of expectation?"
        case .burdened:    return "Would you like to open a guided prayer?"
        case .grateful:    return "Would you like to start a testimony draft?"
        case .confused:    return "Would you like Berean to help you study this?"
        case .repentant:   return "Would you like to write a prayer of surrender?"
        case .encouraged:  return "Would you like to save an encouragement to share?"
        case .challenged:  return "Would you like to set an action step?"
        }
    }

    /// Keyword signals used by local heuristic detection.
    var keywords: [String] {
        switch self {
        case .convicted:   return ["convicted", "challenged", "this hit me", "i felt called", "can't ignore", "check myself"]
        case .comforted:   return ["comfort", "peace", "rest", "reassured", "held", "safe", "gentle"]
        case .expectant:   return ["excited", "expecting", "anticipate", "can't wait", "hope", "looking forward"]
        case .burdened:    return ["heavy", "burden", "weary", "tired", "grieving", "hard", "struggling"]
        case .grateful:    return ["grateful", "thankful", "blessed", "grace", "mercy", "thank God"]
        case .confused:    return ["confused", "don't understand", "wrestling", "unsure", "question", "why"]
        case .repentant:   return ["repent", "sorry", "forgive me", "turn away", "sin", "wrong", "failed"]
        case .encouraged:  return ["encouraged", "lifted", "inspired", "reminded", "yes", "fired up"]
        case .challenged:  return ["challenge", "pushed", "step out", "uncomfortable", "obey", "hard step"]
        }
    }
}

// MARK: - Note Connection (Sermon Threading)

struct ChurchNoteConnection: Identifiable, Hashable {
    var id: String { relatedNoteId }
    var relatedNoteId: String
    var relatedNoteTitle: String
    var relatedNoteDate: Date
    var sharedThemes: [String]       // e.g. ["trust", "waiting"]
    var connectionStrength: Double   // 0.0 – 1.0

    var strengthLabel: String {
        if connectionStrength > 0.7 { return "Strong connection" }
        if connectionStrength > 0.4 { return "Related" }
        return "Possibly connected"
    }
}

// MARK: - God Has Been Saying Summary

struct CNThemePattern: Codable, Identifiable, Hashable {
    var id: String
    var theme: String
    var noteCount: Int
    var recentNoteIds: [String]
    var firstSeenAt: Date
    var lastSeenAt: Date

    var isRecurring: Bool { noteCount >= 3 }

    var summaryLabel: String {
        if noteCount == 1 { return "Appeared in 1 note" }
        return "Appeared in \(noteCount) notes"
    }
}

struct CNScripturePattern: Codable, Identifiable, Hashable {
    var id: String { reference }
    var reference: String
    var book: String
    var timesAttached: Int
    var lastSeenAt: Date
}

struct ChurchNotesSummary: Codable, Identifiable {
    var id: String                        // == userId
    var topThemes: [CNThemePattern]
    var repeatedScriptures: [CNScripturePattern]
    var postureTrend: CNPostureSignal?
    var noteCountLast30Days: Int
    var noteCountAllTime: Int
    /// Reflective statement — never claims divine certainty.
    /// e.g. "Your recent notes often return to trust and surrender."
    var reflectionStatement: String
    var generatedAt: Date
    var showInsights: Bool
    var dismissedAt: Date?

    var hasContent: Bool {
        !topThemes.isEmpty || !repeatedScriptures.isEmpty || !reflectionStatement.isEmpty
    }

    static func empty(userId: String) -> ChurchNotesSummary {
        ChurchNotesSummary(
            id: userId,
            topThemes: [],
            repeatedScriptures: [],
            postureTrend: nil,
            noteCountLast30Days: 0,
            noteCountAllTime: 0,
            reflectionStatement: "",
            generatedAt: Date(),
            showInsights: true,
            dismissedAt: nil
        )
    }
}

// MARK: - Sermon Bridge (Monday Bridge)

/// Lightweight "live this out" data attached to a note.
struct CNSermonBridge: Codable, Identifiable {
    var id: String      // == noteId
    var noteId: String
    var oneLineToRemember: String
    var actionThisWeek: String
    var prayerThisWeek: String
    var personToEncourage: String
    var reminderDayOffset: Int   // 0 = no reminder, 2 = Tue, 3 = Wed, etc.

    // Spiritual completion tracking — not productivity framing
    var actionStatus: CNObedienceStatus
    var prayerStatus: CNObedienceStatus
    var personStatus: CNObedienceStatus

    var completedAt: Date?
    var updatedAt: Date
    var createdAt: Date

    var isPopulated: Bool {
        !oneLineToRemember.isEmpty || !actionThisWeek.isEmpty || !prayerThisWeek.isEmpty
    }

    static func empty(noteId: String) -> CNSermonBridge {
        CNSermonBridge(
            id: noteId,
            noteId: noteId,
            oneLineToRemember: "",
            actionThisWeek: "",
            prayerThisWeek: "",
            personToEncourage: "",
            reminderDayOffset: 0,
            actionStatus: .open,
            prayerStatus: .open,
            personStatus: .open,
            completedAt: nil,
            updatedAt: Date(),
            createdAt: Date()
        )
    }
}

/// Spiritually-framed completion status. Avoids productivity/task-list framing.
enum CNObedienceStatus: String, Codable, CaseIterable, Hashable {
    case open            = "open"
    case prayed          = "prayed"
    case obeyed          = "obeyed"
    case stillProcessing = "still_processing"
    case needCounsel     = "need_counsel"
    case sawFruit        = "saw_fruit"

    var displayName: String {
        switch self {
        case .open:            return "Not yet"
        case .prayed:          return "Prayed through"
        case .obeyed:          return "Obeyed"
        case .stillProcessing: return "Still wrestling"
        case .needCounsel:     return "Need counsel"
        case .sawFruit:        return "Saw fruit"
        }
    }

    var icon: String {
        switch self {
        case .open:            return "circle"
        case .prayed:          return "hands.sparkles.fill"
        case .obeyed:          return "checkmark.circle.fill"
        case .stillProcessing: return "arrow.circlepath"
        case .needCounsel:     return "person.2.fill"
        case .sawFruit:        return "leaf.fill"
        }
    }

    var isResolved: Bool {
        self == .obeyed || self == .sawFruit
    }
}

// MARK: - Pre-Save Review Suggestion

struct CNReviewSuggestion: Identifiable {
    var id: String { action.rawId }
    var icon: String
    var label: String
    var action: CNReviewAction
}

enum CNReviewAction: Hashable {
    case addTakeaway
    case addPrayer
    case addVerse
    case addAction
    case markAnchor
    case setReflectionReminder
    case fillBridge

    var rawId: String {
        switch self {
        case .addTakeaway:           return "takeaway"
        case .addPrayer:             return "prayer"
        case .addVerse:              return "verse"
        case .addAction:             return "action"
        case .markAnchor:            return "anchor"
        case .setReflectionReminder: return "reminder"
        case .fillBridge:            return "bridge"
        }
    }
}
