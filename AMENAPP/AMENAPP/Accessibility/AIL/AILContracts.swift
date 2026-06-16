// AILContracts.swift
// AMENAPP — Accessibility Intelligence Layer (AIL)
//
// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  WIRING CERTIFICATE — AIL Lane                                          ║
// ║  Generated: 2026-06-11 | Branch: safety-hardening                       ║
// ╠══════════════════════════════════════════════════════════════════════════╣
// ║  Surface                    Gate                            Status       ║
// ╠══════════════════════════════════════════════════════════════════════════╣
// ║  C10/C11 pre-send gate      PostDetailView (comment)        WIRED ✓     ║
// ║  C10/C11 pre-send gate      AmenUniversalComposerView(post) WIRED ✓     ║
// ║    (this commit)                                                         ║
// ║  C10/C11 pre-send gate      ONEMessageComposerView (DM)     WIRED ✓     ║
// ║    (this commit, isDirectMessage: true)                                  ║
// ║  C12 emotional safety blur  PostDetailView feed content     WIRED ✓     ║
// ║  C12 emotional safety blur  AmenSpaceDetailView             WIRED ✓     ║
// ║  A11y flag gate             AMENFeatureFlags.accessibilityIntelligenceEnabled WIRED ✓ ║
// ╠══════════════════════════════════════════════════════════════════════════╣
// ║  Dynamic Type audit                                                      ║
// ║    AILCaptionRenderer fontSize   user-chosen CaptionStyle.Size — OK ✓   ║
// ║    AILAccessibilitySettingsSection icon font  fixed→.body (this commit) ✓ ║
// ║    AILAccessibilitySetupView decorative icon  fixed 52pt — decorative OK ║
// ╠══════════════════════════════════════════════════════════════════════════╣
// ║  Iron rules verified:                                                    ║
// ║    • Pre-send gate is PROPOSAL-ONLY. Never blocks sends. User-driven only║
// ║    • Gate default OFF (AILPreSendInterceptor.shared.isEnabled = false)   ║
// ║    • Emotional safety filter FAILS OPEN (never hides on classify error)  ║
// ║    • Crisis-help content is NEVER blurred (isCrisisHelp bypass)          ║
// ║    • No tier checks anywhere in AIL. Free at every tier.                 ║
// ╚══════════════════════════════════════════════════════════════════════════╝
//
// FROZEN Swift mirror of functions/ail/ail.contracts.ts (Phase 1, 2026-06-09).
// Additive-only. Every AIL SwiftUI surface consumes these types — none may
// redefine them. Keep in sync with the TS contract when (rarely) it changes.
//
// Iron rules encoded here:
//  • Accessibility is free at every tier — there is NO tier field anywhere in AIL.
//  • Transforms FAIL OPEN to original (A11yTransformResult.failOpen).
//  • Every transform is labeled (provenance) and reversible (originalRef).
//  • Scripture is never re-leveled — EXPLAIN_SCRIPTURE renders alongside, labeled.

import Foundation

// MARK: - Tasks

/// The AIL capability surface, expressed as callModel tasks.
enum A11yTask: String, Codable, CaseIterable, Sendable {
    case translate
    case simplify
    case explainScripture = "explain_scripture"   // Claude-only, cite-or-refuse
    case toneHint = "tone_hint"
    case captionLive = "caption_live"             // SpeechProvider on-device
    case captionRecorded = "caption_recorded"     // SpeechProvider server ASR
    case describeImage = "describe_image"
    case summarizeAudio = "summarize_audio"
    case reentrySummary = "reentry_summary"
    case replyCareCheck = "reply_care_check"
    case cooldownRewrite = "cooldown_rewrite"
    case sensitivityClassify = "sensitivity_classify"

    /// Tasks that fail CLOSED (cite-or-refuse). All others fail OPEN to original.
    var failsOpen: Bool { self != .explainScripture }

    /// Tasks bound to the on-device/server SpeechProvider rather than callModel.
    var isSpeechAdapterTask: Bool { self == .captionLive || self == .captionRecorded }
}

// MARK: - Reading level (C2)

enum ReadingLevel: String, Codable, CaseIterable, Sendable {
    case original
    case simple
    case verySimple = "very_simple"
    case summary

    var displayName: String {
        switch self {
        case .original:   return "Original"
        case .simple:     return "Simple"
        case .verySimple: return "Very Simple"
        case .summary:    return "Summary"
        }
    }
}

// MARK: - Sensitivity topics (C12)

enum SensitivityTopic: String, Codable, CaseIterable, Sendable, Identifiable {
    case grief, conflict, politics, trauma, graphic
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

// MARK: - Provenance (net-new; same family as ONEProvenanceClass)

enum A11yProvenance: String, Codable, Sendable {
    case aiGenerated = "ai_generated"
    case aiHumanEdited = "ai_human_edited"
    case human

    /// One-tap label shown on every transform.
    var label: String {
        switch self {
        case .aiGenerated:   return "AI translation"
        case .aiHumanEdited: return "AI · edited by author"
        case .human:         return "Original"
        }
    }

    /// Maps onto the canonical media-provenance family (ONEProvenanceClass).
    var oneProvenanceClass: String {
        switch self {
        case .aiGenerated:   return "synthetic"
        case .aiHumanEdited: return "aiAssisted"
        case .human:         return "edited"
        }
    }
}

// MARK: - Value types

/// C1 idiom/slang/scripture-phrase tooltip attached to a translation.
struct CultureNote: Codable, Hashable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable { case idiom, slang, scripturePhrase = "scripture_phrase", cultural }
    var id: String { phrase }
    let phrase: String
    let note: String
    let kind: Kind
}

/// C4 caption rendering preferences (user-controlled, lives in A11yProfile).
struct CaptionStyle: Codable, Hashable, Sendable {
    enum Size: String, Codable, CaseIterable, Sendable { case small, medium, large, xl }
    enum Background: String, Codable, CaseIterable, Sendable { case none, dim, solid }
    enum Speed: String, Codable, CaseIterable, Sendable { case slow, normal, fast }
    enum Placement: String, Codable, CaseIterable, Sendable { case bottom, top }

    var size: Size = .medium
    var background: Background = .dim   // `.solid` is the Reduce-Transparency fallback
    var highContrast: Bool = false
    var speed: Speed = .normal
    var placement: Placement = .bottom
}

/// C4 recorded caption cue + track artifact.
struct CaptionCue: Codable, Hashable, Sendable, Identifiable {
    var id: String { "\(startMs)-\(endMs)" }
    let startMs: Int
    let endMs: Int
    let text: String
}

struct CaptionTrack: Codable, Hashable, Sendable {
    let mediaId: String
    let lang: String
    let cues: [CaptionCue]
    var provenance: A11yProvenance
    var moderationStatus: String      // pending | approved | flagged
    var createdAt: Double             // Unix epoch; mirrors TS `number`
    var updatedAt: Double
    var deletedAt: Double?            // nil when active; non-nil on soft-delete
}

/// C5 image description / alt text. Never names or identifies people (iron rule 6).
struct ImageDescription: Codable, Hashable, Sendable {
    let mediaId: String
    var text: String
    var provenance: A11yProvenance
    var confidence: A11yConfidence
    var flagged: Bool                 // true on degrade — fail open
}

enum A11yConfidence: String, Codable, Sendable { case high, medium, low }

// MARK: - Transform output union (TS: string | CaptionTrack | ImageDescription | null)

/// Mirrors the `output` field of the TS A11yTransformResult.
/// Discriminated by wire shape: strings → .text, objects with `cues` → .captionTrack,
/// objects with `flagged` → .imageDescription, JSON null → .none.
enum A11yTransformOutput: Sendable {
    case text(String)
    case captionTrack(CaptionTrack)
    case imageDescription(ImageDescription)
    case none

    /// String payload for text-only tasks. C4/C5 consumers must pattern-match `output` directly.
    var textValue: String? {
        if case .text(let s) = self { return s }
        return nil
    }
}

extension A11yTransformOutput: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .none; return }
        if let s = try? c.decode(String.self) { self = .text(s); return }
        // CaptionTrack has `cues`; ImageDescription has `flagged`. Try each in order.
        if let track = try? c.decode(CaptionTrack.self) { self = .captionTrack(track); return }
        if let desc  = try? c.decode(ImageDescription.self) { self = .imageDescription(desc); return }
        self = .none  // unrecognized shape — fail-open to none
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .text(let s):             try c.encode(s)
        case .captionTrack(let t):     try c.encode(t)
        case .imageDescription(let d): try c.encode(d)
        case .none:                    try c.encodeNil()
        }
    }
}

// MARK: - Transform result

/// Unified result of the ailTransform callable. On fail-open, `failOpen == true`
/// and the caller renders the ORIGINAL content with a quiet "unavailable" state.
struct A11yTransformResult: Codable, Sendable {
    let task: A11yTask
    var output: A11yTransformOutput   // TS: string | CaptionTrack | ImageDescription | null
    var provenance: A11yProvenance
    var sourceLang: String?
    var targetLang: String?
    var cultureNotes: [CultureNote]?
    var confidence: A11yConfidence
    let originalRef: String           // always resolvable — "View original"
    var failOpen: Bool                // true ⇒ render original + "unavailable"
    var crisisBypass: Bool            // produced under crisis-context bypass

    /// Backward-compatible accessor for text-only consumers (C1/C2/C3/C10/C11/C12/C14).
    /// C4/C5 consumers must pattern-match `output` to access CaptionTrack/ImageDescription.
    var text: String? { output.textValue }

    /// Fail-open sentinel the client returns when the callable errors or is unavailable.
    static func failedOpen(task: A11yTask, originalRef: String) -> A11yTransformResult {
        A11yTransformResult(
            task: task, output: .none, provenance: .human,
            sourceLang: nil, targetLang: nil, cultureNotes: nil,
            confidence: .low, originalRef: originalRef,
            failOpen: true, crisisBypass: false
        )
    }
}

// MARK: - Profile (users/{uid}/settings/a11yProfile)

/// Per-user accessibility profile. NO motor metrics, miss rates, input-timing, or
/// inferred conditions — those are forbidden fields (iron rule 5). Calibration is
/// on-device only; only the resulting target-size PREFERENCE is persisted.
struct A11yProfile: Codable, Sendable, Equatable {
    enum TouchTargets: String, Codable, CaseIterable, Sendable { case off, large, xl }

    var readingLevel: ReadingLevel = .original
    var autoTranslate: Bool = false
    var toneHintsEnabled: Bool = false          // opt-in (iron rule 7)
    var captionStyle: CaptionStyle = CaptionStyle()
    var calmMode: Bool = false                  // C13 — extends AmenSimpleModeService
    var largerTouchTargets: TouchTargets = .off // explicit; calibration on-device only
    var sensitivityFilters: [SensitivityTopic] = []
    var voiceNavEnabled: Bool = false

    static let `default` = A11yProfile()

    /// The ONLY keys ever written to Firestore. Anything else is a forbidden field.
    static let allowedKeys: Set<String> = [
        "readingLevel", "autoTranslate", "toneHintsEnabled", "captionStyle",
        "calmMode", "largerTouchTargets", "sensitivityFilters", "voiceNavEnabled",
    ]
}
