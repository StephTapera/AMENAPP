import Foundation
import FirebaseFirestore

// MARK: - PostAIUsage
// Attached to a post when any Amen AI tool was used during creation.
// Server-written or server-verified — clients cannot falsely remove required labels.

struct PostAIUsage: Codable, Equatable {

    var usedAI: Bool

    // Which AI capabilities were involved (ordered by involvement level)
    var aiUseTypes: [AIUseType]

    // The resolved public label (server sets this; matches priority table below)
    var primaryLabel: AIPublicLabel

    // Free-form secondary detail for the disclosure sheet (e.g. "kindness score 0.82")
    var secondaryDetail: String?

    var userAcceptedSuggestion: Bool

    // 0–100 percentage of content that is AI-generated (nil if not measurable)
    var aiGeneratedPercentageEstimate: Int?

    var toneCheckSummary: ToneCheckSummary?

    // If true, the label cannot be removed by the client after creation
    var disclosureRequired: Bool

    // Privacy: raw prompts are never stored unless explicitly audited
    var rawPromptStored: Bool
    var rawUserTextStored: Bool

    // The model version that handled this (for audit trail)
    var modelVersion: String?

    @ServerTimestamp var createdAt: Date?
}

// MARK: - AIUseType

enum AIUseType: String, Codable, CaseIterable {
    case toneCheck              = "tone_check"
    case toneRewriteMinor       = "tone_rewrite_minor"
    case toneRewriteMajor       = "tone_rewrite_major"
    case draftGeneration        = "draft_generation"
    case scriptureSuggestion    = "scripture_suggestion"
    case sermonNotesSummary     = "sermon_notes_summary"
    case prayerGeneration       = "prayer_generation"
    case translation            = "translation"
    case safetyRewrite          = "safety_rewrite"
    case bereanInsert           = "berean_insert"
    case altTextGeneration      = "alt_text_generation"
}

// MARK: - AIPublicLabel

enum AIPublicLabel: String, Codable, CaseIterable {
    case toneChecked        = "tone_checked"
    case aiAssistedTone     = "ai_assisted_tone"
    case aiAssistedPost     = "ai_assisted_post"
    case scriptureSuggested = "scripture_suggested"
    case notesSummarized    = "notes_summarized"
    case prayerAssisted     = "prayer_assisted"
    case translatedWithAI   = "translated_with_ai"
    case editedForSafety    = "edited_for_safety"
    case bereanAssisted     = "berean_assisted"
    case altTextAssisted    = "alt_text_assisted"

    // Public-facing display string shown in the pill
    var displayText: String {
        switch self {
        case .toneChecked:        return "Tone checked"
        case .aiAssistedTone:     return "AI-assisted tone"
        case .aiAssistedPost:     return "AI-assisted post"
        case .scriptureSuggested: return "Scripture suggested"
        case .notesSummarized:    return "Notes summarized"
        case .prayerAssisted:     return "Prayer assisted"
        case .translatedWithAI:   return "Translated with AI"
        case .editedForSafety:    return "Edited for safety"
        case .bereanAssisted:     return "Berean assisted"
        case .altTextAssisted:    return "Alt text assisted"
        }
    }

    // Disclosure sheet copy explaining what AI actually did
    var disclosureCopy: String {
        switch self {
        case .toneChecked:
            return "Amen AI reviewed this post for tone, clarity, kindness, and humility. The author controlled the final wording."
        case .aiAssistedTone:
            return "Amen AI suggested wording improvements. The author reviewed and accepted changes before publishing."
        case .aiAssistedPost:
            return "Amen AI helped draft this post. The author reviewed and published it."
        case .scriptureSuggested:
            return "Amen AI suggested scripture references related to this post. The author chose what to include."
        case .notesSummarized:
            return "Amen AI helped summarize the author's church notes into a reflection. The author reviewed and published it."
        case .prayerAssisted:
            return "Amen AI helped shape this prayer from the author's own request. The author reviewed and published it."
        case .translatedWithAI:
            return "Amen AI translated this post from another language. The author reviewed it before publishing."
        case .editedForSafety:
            return "Amen AI helped revise language that may have been harmful, coercive, shaming, or unsafe. The author reviewed the final wording."
        case .bereanAssisted:
            return "Amen AI (Berean) contributed insights or study content to this post. The author reviewed and published it."
        case .altTextAssisted:
            return "Amen AI generated accessibility descriptions for the media in this post."
        }
    }

    // Whether this label is immutable once set (client cannot remove it)
    var isRequired: Bool {
        switch self {
        case .toneChecked, .altTextAssisted: return false
        default: return true
        }
    }
}

// MARK: - Label priority resolver

extension PostAIUsage {
    /// Resolves the highest-priority public label from the use-type list.
    /// Priority (highest → lowest):
    ///   1. AI-assisted post
    ///   2. Translated with AI
    ///   3. AI-assisted tone
    ///   4. Edited for safety
    ///   5. Notes summarized
    ///   6. Prayer assisted
    ///   7. Scripture suggested
    ///   8. Berean assisted
    ///   9. Tone checked
    ///  10. Alt text assisted
    static func resolveLabel(from types: [AIUseType]) -> AIPublicLabel? {
        guard !types.isEmpty else { return nil }

        if types.contains(.draftGeneration) || types.contains(.toneRewriteMajor) {
            return .aiAssistedPost
        }
        if types.contains(.translation) {
            return .translatedWithAI
        }
        if types.contains(.toneRewriteMinor) {
            return .aiAssistedTone
        }
        if types.contains(.safetyRewrite) {
            return .editedForSafety
        }
        if types.contains(.sermonNotesSummary) {
            return .notesSummarized
        }
        if types.contains(.prayerGeneration) {
            return .prayerAssisted
        }
        if types.contains(.scriptureSuggestion) {
            return .scriptureSuggested
        }
        if types.contains(.bereanInsert) {
            return .bereanAssisted
        }
        if types.contains(.toneCheck) {
            return .toneChecked
        }
        if types.contains(.altTextGeneration) {
            return .altTextAssisted
        }
        return nil
    }
}

// MARK: - ToneCheckSummary

struct ToneCheckSummary: Codable, Equatable {
    var kindnessScore: Double
    var clarityScore: Double
    var humilityScore: Double
    var peaceScore: Double
    var truthfulnessScore: Double
    var scriptureIntegrityScore: Double?
    var shameFlagged: Bool
    var encouragementScore: Double
    var manipulationRisk: Double
    var pastoralSensitivity: Double
}
