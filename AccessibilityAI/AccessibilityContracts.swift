// AccessibilityContracts.swift
// AMEN Universal Accessibility Engine — Frozen Shared Contracts (Phase 0)
// DO NOT MODIFY without versioning through the Orchestrator.

import Foundation

// MARK: - Reading Level

enum ReadingLevel: String, Codable, CaseIterable {
    case elementary   // Grade 3–5
    case middleSchool // Grade 6–8
    case plain        // Plain language / 8th grade
    case standard     // Standard adult reading
    case academic     // College / academic
    case esl          // ESL-optimized: simple vocab, short sentences
}

// MARK: - Font Prefs

struct FontPrefs: Codable, Equatable {
    var dyslexiaOptimized: Bool
    var lineHeightMultiplier: Double   // 1.0 normal, 1.5 dyslexia, 2.0 high
    var wordSpacing: Double            // 0.0 normal, 0.1+ dyslexia
    var chunkSize: Int                 // words per chunk; 0 = no chunking

    static let standard = FontPrefs(
        dyslexiaOptimized: false,
        lineHeightMultiplier: 1.0,
        wordSpacing: 0.0,
        chunkSize: 0
    )
}

// MARK: - Contrast Prefs

struct ContrastPrefs: Codable, Equatable {
    var forceHighContrast: Bool
    var smartContrast: Bool            // auto-adjust by environment/content
    var invertForNight: Bool

    static let standard = ContrastPrefs(
        forceHighContrast: false,
        smartContrast: true,
        invertForNight: false
    )
}

// MARK: - Narration Voice (fixed labeled library — NEVER cloned from real people)

enum NarrationVoice: String, Codable, CaseIterable {
    case conversational = "conversational"
    case pastor         = "pastor"
    case narrator       = "narrator"
    case teacher        = "teacher"

    var displayName: String {
        switch self {
        case .conversational: return "Conversational"
        case .pastor:         return "Pastor"
        case .narrator:       return "Narrator"
        case .teacher:        return "Teacher"
        }
    }
}

// MARK: - Narration Prefs

struct NarrationPrefs: Codable, Equatable {
    var enabled: Bool
    var voice: NarrationVoice
    var speed: Double                  // 0.5–2.0; 1.0 normal

    static let standard = NarrationPrefs(
        enabled: false,
        voice: .conversational,
        speed: 1.0
    )
}

// MARK: - Caption Style

struct CaptionStyle: Codable, Equatable {
    var fontSize: Double               // 14–32; 18 default
    var fontWeight: String             // "regular", "medium", "bold"
    var backgroundColor: String        // "black", "dark", "none"
    var showNonSpeech: Bool            // [music], [congregation], etc.

    static let standard = CaptionStyle(
        fontSize: 18,
        fontWeight: "medium",
        backgroundColor: "dark",
        showNonSpeech: true
    )
}

// MARK: - Accessibility Profile (persists across all content)

struct AccessibilityProfile: Codable {
    var preferredLanguage: String
    var readingLevel: ReadingLevel
    var fontPrefs: FontPrefs
    var contrastPrefs: ContrastPrefs
    var narration: NarrationPrefs
    var captionStyle: CaptionStyle
    var reducedMotion: Bool            // synced with UIAccessibility.isReduceMotionEnabled
    var visualSimplification: Bool
    var struggleTerms: [String]        // words the user has flagged; drives proactive simplification
    var gestureFree: Bool

    static let `default` = AccessibilityProfile(
        preferredLanguage: Locale.current.language.languageCode?.identifier ?? "en",
        readingLevel: .standard,
        fontPrefs: .standard,
        contrastPrefs: .standard,
        narration: .standard,
        captionStyle: .standard,
        reducedMotion: false,
        visualSimplification: false,
        struggleTerms: [],
        gestureFree: false
    )
}

// MARK: - Voice Library (fixed set — never cloned, never presented as a person)

enum A11yVoiceLibrary {
    static let voices: [NarrationVoice] = NarrationVoice.allCases
    static let disclaimer = "Clearly-labeled synthetic voices. None are cloned from or presented as any real person."
}
