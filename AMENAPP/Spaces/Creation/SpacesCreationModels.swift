// SpacesCreationModels.swift
// AMENAPP — Spaces v2 Creation Wizard (Agent D)
//
// All model types that flow through the creation wizard.
// No "church" references anywhere in this file.

import Foundation

// MARK: - SpaceCreationIntent

/// Intent chosen in step 1 of the creation wizard.
/// Maps directly to `SpaceV2Type` for the resulting space document.
enum SpaceCreationIntent: String, CaseIterable, Identifiable {
    case discussion = "discussion"
    case study      = "study"
    case group      = "group"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .discussion: return "Discussion"
        case .study:      return "Study"
        case .group:      return "Group"
        }
    }

    var systemImageName: String {
        switch self {
        case .discussion: return "bubble.left.and.bubble.right"
        case .study:      return "book.closed.fill"
        case .group:      return "person.3.fill"
        }
    }

    var description: String {
        switch self {
        case .discussion: return "An open thread space for conversations and questions."
        case .study:      return "A structured passage-based study with discussion prompts."
        case .group:      return "A collaborative space for your community or team."
        }
    }

    var mapsToSpaceV2Type: SpaceV2Type {
        switch self {
        case .discussion: return .chat
        case .study:      return .bibleStudy
        case .group:      return .group
        }
    }
}

// MARK: - BereanScaffoldResponse

/// Berean's scaffold response — parsed from the accumulated SSE delta stream.
/// The backend is expected to return JSON matching this schema when
/// `scaffoldMode: true` is set in the POST body.
struct BereanScaffoldResponse: Codable {

    // Study intent
    /// e.g. ["Romans 8:1-17", "Romans 8:18-39"]
    var passageRefs: [String]
    /// e.g. "4 weeks, 2 sessions per week"
    var cadence: String?
    /// Up to 5 discussion prompts
    var discussionPrompts: [String]
    /// Draft blocks for the study template
    var blockDrafts: [ScaffoldBlock]

    // Discussion / Group intent
    /// Up to 5 seed thread starters
    var starterPrompts: [String]
    /// Suggested community norms / guidelines
    var suggestedNorms: [String]

    // MARK: Graceful fallback
    static let empty = BereanScaffoldResponse(
        passageRefs: [],
        cadence: nil,
        discussionPrompts: [],
        blockDrafts: [],
        starterPrompts: [],
        suggestedNorms: []
    )
}

// MARK: - ScaffoldBlock

/// A draft block produced by Berean for a study scaffold.
/// Maps 1-to-1 with `ChurchNoteBlock` when written to Firestore.
/// Field names are intentionally identical to `ChurchNoteBlock`'s CodingKeys.
struct ScaffoldBlock: Codable, Identifiable {
    var id: String
    /// "paragraph" | "scripture" | "reflection" | "prayer"
    var type: String
    var text: String

    // MARK: ChurchNoteBlock mapping helper
    /// Returns the `ChurchNoteBlockType` rawValue string, falling back to
    /// `.paragraph` if Berean returns an unrecognised type string.
    var resolvedBlockType: String {
        let valid = ["paragraph", "quote", "takeaway", "prayer", "action", "reflection", "scripture"]
        return valid.contains(type) ? type : "paragraph"
    }
}

// MARK: - SpacesPricingState

/// Live mutable state for step 3 (access & pricing).
struct SpacesPricingState {
    var policy: AccessPolicy = .free
    /// Amount in cents — $5.00 default
    var amountCents: Int = 500
    var currency: String = "usd"
    /// "month" | "year" | nil (one-time)
    var interval: String? = nil

    /// Returns a `PriceConfig` only when policy is not `.free`.
    var priceConfig: PriceConfig? {
        guard policy != .free else { return nil }
        return PriceConfig(amountCents: amountCents, currency: currency, interval: interval)
    }

    /// Validates the pricing state. Paid spaces require a minimum $0.50.
    var isValid: Bool {
        policy == .free || amountCents >= 50
    }
}

// MARK: - SpaceCreationDraft

/// The complete mutable state threaded through all wizard steps.
/// Agent F may inspect `scaffoldAccepted` and `scaffold` post-creation
/// to determine whether a Space was AI-scaffolded.
struct SpaceCreationDraft {
    var intent: SpaceCreationIntent? = nil
    var title: String = ""
    var description: String = ""
    var scaffold: BereanScaffoldResponse? = nil
    var scaffoldAccepted: Bool = false
    var pricingState: SpacesPricingState = SpacesPricingState()
    /// Set after `createSpace(...)` completes successfully.
    var createdSpaceId: String? = nil

    /// True once both title and intent have been selected.
    var canAdvanceFromIntent: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && intent != nil
    }
}
