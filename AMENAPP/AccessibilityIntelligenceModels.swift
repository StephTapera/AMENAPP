// AccessibilityIntelligenceModels.swift
// AMEN App — Accessibility Intelligence Layer
//
// Shared models for the Accessibility Intelligence system (System 15).
// Includes: TranslationMode, ReadabilityMode, ContentDifficultyScore,
// AudioPreferences, ContextAssist, and AdaptiveAccessibility models.
//
// All types are Codable for Firestore/UserDefaults persistence.

import Foundation
import FirebaseFirestore

// MARK: - Translation Modes (Phase 1)

/// Translation rendering modes for meaning-aware translation
enum TranslationMode: String, Codable, CaseIterable, Hashable {
    case original = "original"         // Show post in its original language (no translation)
    case literal = "literal"           // Direct machine translation (GCP / Apple on-device)
    case natural = "natural"           // LLM-refined to sound native in target language
    case contextual = "contextual"     // LLM + faith/tone/emotional context preservation

    var displayLabel: String {
        switch self {
        case .original: return "Original"
        case .literal: return "Literal"
        case .natural: return "Natural"
        case .contextual: return "Contextual"
        }
    }

    var description: String {
        switch self {
        case .original: return "View in the author's language"
        case .literal: return "Closest to original phrasing"
        case .natural: return "Sounds native in your language"
        case .contextual: return "Preserves spiritual meaning and tone"
        }
    }

    var icon: String {
        switch self {
        case .original: return "globe"
        case .literal: return "text.quote"
        case .natural: return "text.bubble"
        case .contextual: return "heart.text.clipboard"
        }
    }

    /// Whether this mode requires an LLM refinement pass
    var requiresLLM: Bool { self != .literal && self != .original }

    /// Whether this mode actually performs a translation
    var performsTranslation: Bool { self != .original }
}

/// Entity types preserved during translation
enum PreservedEntityType: String, Codable {
    case mention            // @username
    case hashtag            // #topic
    case verseReference     // John 3:16
    case bibleTranslation   // KJV, ESV, NIV
    case url                // https://...
    case email              // user@example.com
}

/// An entity extracted before translation and re-inserted after
struct PreservedEntity: Codable, Equatable {
    let type: PreservedEntityType
    let originalText: String
    let placeholder: String     // Placeholder used during translation, e.g. "[ENTITY_0]"
}

// MARK: - Readability Modes (Phase 2)

/// Content transformation modes for the Understand Sheet
enum ReadabilityMode: String, Codable, CaseIterable, Hashable {
    case simplify = "simplify"
    case summarize = "summarize"
    case keyTerms = "key_terms"
    case explain = "explain"
    case expandContext = "expand_context"

    var displayLabel: String {
        switch self {
        case .simplify: return "Simplify"
        case .summarize: return "Summarize"
        case .keyTerms: return "Key Terms"
        case .explain: return "Explain"
        case .expandContext: return "Context"
        }
    }

    var icon: String {
        switch self {
        case .simplify: return "text.redaction"
        case .summarize: return "list.bullet"
        case .keyTerms: return "text.magnifyingglass"
        case .explain: return "questionmark.circle"
        case .expandContext: return "arrow.up.left.and.arrow.down.right"
        }
    }

    /// LLM prompt instruction fragment for each mode
    var promptInstruction: String {
        switch self {
        case .simplify:
            return "Rewrite this at an 8th-grade reading level. Use short sentences and common words. Keep any Bible verse references exactly as they are."
        case .summarize:
            return "Provide a 3-5 bullet point summary of the key ideas. Preserve all Scripture references. Keep it concise."
        case .keyTerms:
            return "Extract the 3-5 most important terms or concepts. For each, provide a short plain-language definition and one related Bible verse if applicable. Return as JSON array with keys: term, definition, relatedVerse."
        case .explain:
            return "Explain this as if to someone completely new to Christianity. Define any church-specific terms. Be warm and welcoming. Keep Bible references but add brief context for each."
        case .expandContext:
            return "Add historical and theological context. What broader Scripture themes does this connect to? What is the original cultural background? Keep the explanation accessible."
        }
    }
}

/// On-device content difficulty analysis result
struct ContentDifficultyScore: Codable, Equatable {
    let score: Double                   // 0.0 (trivial) to 1.0 (very complex)
    let avgSentenceLength: Double       // Average words per sentence
    let uncommonWordRatio: Double       // Ratio of uncommon vocabulary
    let conceptDensity: Double          // Distinct ideas per sentence
    let scriptureDensity: Double        // Ratio of verse references to total content
    let suggestedMode: ReadabilityMode? // Nil if score below threshold

    /// Threshold above which the "Understand" pill appears
    static let displayThreshold: Double = 0.6
}

/// Cached readability transform result
struct ReadabilityTransform: Codable, Equatable, Identifiable {
    let id: String                      // contentId_mode_lang
    let mode: ReadabilityMode
    let originalContentId: String
    let transformedText: String
    let language: String
    let createdAt: Date
    var keyTerms: [KeyTermDefinition]?  // Populated for .keyTerms mode
}

/// A single key term definition from the .keyTerms mode
struct KeyTermDefinition: Codable, Equatable, Identifiable {
    var id: String { term }
    let term: String
    let definition: String
    let relatedVerse: String?
}

/// User's readability preferences
struct UserReadabilityProfile: Codable, Equatable {
    var preferredReadingDensity: ReadingDensity
    var prefersBulletSummaries: Bool
    var autoSuggestSimplify: Bool
    var updatedAt: Date

    static var `default`: UserReadabilityProfile {
        UserReadabilityProfile(
            preferredReadingDensity: .standard,
            prefersBulletSummaries: false,
            autoSuggestSimplify: false,
            updatedAt: Date()
        )
    }
}

enum ReadingDensity: String, Codable {
    case compact
    case standard
    case expanded
}

// MARK: - Audio Preferences (Phase 3)

/// User's audio narration preferences (stored in UserDefaults, local-only)
struct AudioPreferences: Codable, Equatable {
    var defaultPlaybackRate: Float
    var voiceLocale: String?            // Nil = match content language
    var pauseBetweenPosts: TimeInterval
    var autoPlayTranslated: Bool        // Auto-play audio when translating

    static var `default`: AudioPreferences {
        AudioPreferences(
            defaultPlaybackRate: 1.0,
            voiceLocale: nil,
            pauseBetweenPosts: 1.0,
            autoPlayTranslated: false
        )
    }
}

/// Item in the speech playback queue
struct SpeechQueueItem: Identifiable {
    let id: String                      // Post/content ID
    let text: String
    let title: String?                  // e.g. "Post by @username"
    let language: String?               // BCP 47 locale for voice selection (nil = device default)
}

// MARK: - Context Assist (Phase 4)

/// A faith/church term entry from the glossary
struct FaithTermEntry: Codable, Identifiable {
    let id: String                      // Normalized key, e.g. "sanctification"
    let term: String
    let shortDefinition: String
    let longDefinition: String
    let relatedVerse: String?
    let category: String                // Free-form category label
    let aliases: [String]               // Alternate forms of this term
    var regionalNotes: [String: String]?
    var denominationalVariance: String?
}

/// A term detected in content that may need explanation
struct DetectedTerm: Identifiable {
    var id: String { term }
    let term: String
    let range: Range<String.Index>
    let glossaryEntry: FaithTermEntry
}

/// User-specific context assist state
struct UserContextAssistProfile: Codable {
    var dismissedTerms: [String]
    var savedTerms: [String]
    var preferredContextDepth: ContextDepth
    var newToFaithMode: Bool
    var showCulturalNotes: Bool
    var showDenominationNotes: Bool

    static var `default`: UserContextAssistProfile {
        UserContextAssistProfile(
            dismissedTerms: [],
            savedTerms: [],
            preferredContextDepth: .short,
            newToFaithMode: false,
            showCulturalNotes: true,
            showDenominationNotes: false
        )
    }
}

enum ContextDepth: String, Codable {
    case short
    case medium
    case detailed
}

// MARK: - Adaptive Accessibility (Phase 5)

/// Aggregated behavioral signals (privacy-safe — never stores raw content)
struct AggregatedAccessibilitySignals: Codable, Equatable {
    var translateCount: Int
    var simplifyCount: Int
    var listenCount: Int
    var contextCardCount: Int
    var textSizeChangedCount: Int
    // Phase 4: Translation-specific counters
    var modeChangedCount: Int
    var sideBySideToggledCount: Int
    var perLanguageAutoTranslateSetCount: Int
    var lastRecordedAt: Date?

    static var `default`: AggregatedAccessibilitySignals {
        AggregatedAccessibilitySignals(
            translateCount: 0,
            simplifyCount: 0,
            listenCount: 0,
            contextCardCount: 0,
            textSizeChangedCount: 0,
            modeChangedCount: 0,
            sideBySideToggledCount: 0,
            perLanguageAutoTranslateSetCount: 0,
            lastRecordedAt: nil
        )
    }

    // Backward-compatible decoding for existing persisted data
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        translateCount = try container.decodeIfPresent(Int.self, forKey: .translateCount) ?? 0
        simplifyCount = try container.decodeIfPresent(Int.self, forKey: .simplifyCount) ?? 0
        listenCount = try container.decodeIfPresent(Int.self, forKey: .listenCount) ?? 0
        contextCardCount = try container.decodeIfPresent(Int.self, forKey: .contextCardCount) ?? 0
        textSizeChangedCount = try container.decodeIfPresent(Int.self, forKey: .textSizeChangedCount) ?? 0
        modeChangedCount = try container.decodeIfPresent(Int.self, forKey: .modeChangedCount) ?? 0
        sideBySideToggledCount = try container.decodeIfPresent(Int.self, forKey: .sideBySideToggledCount) ?? 0
        perLanguageAutoTranslateSetCount = try container.decodeIfPresent(Int.self, forKey: .perLanguageAutoTranslateSetCount) ?? 0
        lastRecordedAt = try container.decodeIfPresent(Date.self, forKey: .lastRecordedAt)
    }

    init(translateCount: Int, simplifyCount: Int, listenCount: Int, contextCardCount: Int,
         textSizeChangedCount: Int, modeChangedCount: Int = 0, sideBySideToggledCount: Int = 0,
         perLanguageAutoTranslateSetCount: Int = 0, lastRecordedAt: Date?) {
        self.translateCount = translateCount
        self.simplifyCount = simplifyCount
        self.listenCount = listenCount
        self.contextCardCount = contextCardCount
        self.textSizeChangedCount = textSizeChangedCount
        self.modeChangedCount = modeChangedCount
        self.sideBySideToggledCount = sideBySideToggledCount
        self.perLanguageAutoTranslateSetCount = perLanguageAutoTranslateSetCount
        self.lastRecordedAt = lastRecordedAt
    }

    /// Convert a raw count into a frequency bucket
    static func bucket(for count: Int) -> FrequencyBucket {
        if count >= 15 { return .high }
        if count >= 5 { return .moderate }
        return .low
    }
}

enum FrequencyBucket: String, Codable {
    case low            // < 2 per week
    case moderate       // 2–10 per week
    case high           // > 10 per week
}

/// Signal types the collector tracks
enum AccessibilitySignal {
    case translated
    case simplified
    case listenedToPost
    case textSizeChanged
    case contextCardOpened
    // Phase 4: Translation-specific signals
    case modeChanged                    // User switched translation mode
    case sideBySideToggled              // User toggled side-by-side display
    case perLanguageAutoTranslateSet    // User set a per-language auto-translate override
}

/// A proactive suggestion generated by the adaptive engine
struct AccessibilitySuggestion: Identifiable, Equatable {
    var id: String { type.rawValue }
    let type: AccessibilitySuggestionType
    let title: String
    let message: String
    let actionLabel: String         // Primary action button label

    static func == (lhs: AccessibilitySuggestion, rhs: AccessibilitySuggestion) -> Bool {
        lhs.type == rhs.type
    }
}

enum AccessibilitySuggestionType: String, Codable {
    case enableAutoTranslate
    case enableDefaultSimplify
    case configureAudio
    case enableContextCards
    // Phase 4: Translation-specific suggestions
    case enablePerLanguageAutoTranslate
    case enableSideBySide
    case setDefaultTranslationMode
}
