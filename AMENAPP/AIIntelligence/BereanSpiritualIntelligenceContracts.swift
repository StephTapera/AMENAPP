// BereanSpiritualIntelligenceContracts.swift
// AMENAPP — Berean Spiritual Intelligence Layer
//
// Wave 0 Swift mirrors of src/berean/spiritualIntelligenceContracts.ts.
// TypeScript is source of truth. Keep in sync; add no behavior here.
//
// All flags default OFF / fail-closed. No flag flips in this build.
// BereanMode (ask/discern/build/guard/reflect) is defined in
// BereanMultilingualContracts.swift — do NOT redefine it here.

import Foundation

// MARK: - Privacy Core Zone

enum PrivacyCoreZone: String, Codable, CaseIterable, Sendable {
    case `public`   = "public"
    case functional = "functional"
    case preference = "preference"
    case behavioral = "behavioral"
    case sensitive  = "sensitive"
    /// AES-256-GCM encrypted at rest; prayer, crisis, confession. User-deletable.
    case high       = "high"
    case identity   = "identity"
}

// MARK: - Berean Depth (unified app-wide enum — single source of truth)

/// Orthogonal depth axis for Berean. Auto-selected by IntentSwitch; overridable
/// per-thread. Five stops support the depth-dial UI. Semantic names only;
/// display labels are in displayLabel and are configurable.
///
/// Prior 3-level mapping: Glance → quick, Study → study, Examine → deep/multiSource.
enum BereanDepth: String, Codable, CaseIterable, Identifiable, Sendable {
    case quick       = "quick"
    case study       = "study"
    case deep        = "deep"
    case multiSource = "multiSource"
    case research    = "research"

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .quick:       return "Quick Look"
        case .study:       return "Studying"
        case .deep:        return "Deep Study"
        case .multiSource: return "Multi-Source"
        case .research:    return "Full Research"
        }
    }

    var tokenCeiling: Int {
        switch self {
        case .quick:       return 2_000
        case .study:       return 6_000
        case .deep:        return 14_000
        case .multiSource: return 22_000
        case .research:    return 40_000
        }
    }

    var latencyBudgetMs: Int {
        switch self {
        case .quick:       return 3_000
        case .study:       return 8_000
        case .deep:        return 18_000
        case .multiSource: return 30_000
        case .research:    return 60_000
        }
    }
}

// MARK: - Intent Proposal

/// Auto-selected (mode × depth) pair. Proposed transparently via a small chip.
/// BereanMode is defined in BereanMultilingualContracts.swift.
struct IntentProposal: Codable, Sendable {
    /// Existing posture mode (ask/discern/build/guard/reflect)
    let mode: BereanMode
    let depth: BereanDepth
    /// Show chip only when confidence >= 0.7
    let confidence: Double
    /// Shown in the chip: "Romans 8 → Studying" style
    let rationale: String
    /// Always true from server; false when user-overridden
    let autoSelected: Bool
}

struct IntentOverride: Codable, Sendable {
    let mode: BereanMode?
    let depth: BereanDepth?
    let threadId: String
    let overriddenAt: TimeInterval
}

// MARK: - Scripture Connector

enum ConnectorTier: String, Codable, Sendable {
    case a = "A"  // Ships now: read-only scripture/study sources
    case b = "B"  // Stub: church/creator platforms (deferred)
    case c = "C"  // Stub: productivity OAuth (deferred to post-launch)
}

enum RedistributionKind: String, Codable, Sendable {
    case publicDomain = "public_domain"
    case cc           = "cc"
    case licensed     = "licensed"
    case restricted   = "restricted"
}

struct LicenseMetadata: Codable, Sendable {
    let name: String
    let redistribution: RedistributionKind
    let attributionRequired: Bool
    let attributionText: String?
    let cacheable: Bool
    let noFullBibleDump: Bool
}

enum ScriptureCapabilityKind: String, Codable, Sendable {
    case passageLookup    = "passage_lookup"
    case crossReferences  = "cross_references"
    case lexicon          = "lexicon"
    case commentary       = "commentary"
    case translatorNotes  = "translator_notes"
    case strongNumbers    = "strong_numbers"
    case morphology       = "morphology"
    case search           = "search"
}

struct ScriptureSource: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let tier: ConnectorTier
    /// Always false in this build — flags OFF, no flip
    let enabled: Bool
    let defaultTranslation: String?
    let availableTranslations: [String]
    let license: LicenseMetadata
    /// Key must stay server-side only when true; never in client bundle
    let requiresProxiedKey: Bool
    let capabilities: [ScriptureCapabilityKind]
}

// MARK: - Citation Verdict (GUARDIAN: Scripture Citation Integrity)

/// Every verse Berean emits is verified before display. Fail-closed.
/// If source unavailable → .unverifiable → treated identically to .fabricated.
enum CitationResult: String, Codable, Sendable {
    case verified     = "verified"
    case flagged      = "flagged"
    case fabricated   = "fabricated"
    case unverifiable = "unverifiable"  // Source down — fail-closed
    case paraphrase   = "paraphrase"    // Must be labeled
}

struct CitationVerdict: Codable, Sendable {
    let reference: String
    let quotation: String
    let result: CitationResult
    let sourceId: String
    let translation: String
    let actualText: String?
    let confidence: Double
    let checkedAt: TimeInterval
    let depth: BereanDepth

    /// True for any result that blocks or visibly flags the emission.
    var shouldBlock: Bool {
        switch result {
        case .verified, .paraphrase: return false
        case .flagged, .fabricated, .unverifiable: return true
        }
    }
}

// MARK: - Berean Memory Record

enum MemoryField: String, Codable, CaseIterable, Sendable {
    case preferredTranslation = "preferredTranslation"
    case studyStyle           = "studyStyle"
    case theologicalLean      = "theologicalLean"
    case denominationalLean   = "denominationalLean"
    case readingHabits        = "readingHabits"
    case prayerHistory        = "prayerHistory"  // zone: high — encrypted at rest

    var zone: PrivacyCoreZone {
        switch self {
        case .preferredTranslation: return .preference
        case .studyStyle:           return .preference
        case .theologicalLean:      return .sensitive
        case .denominationalLean:   return .sensitive
        case .readingHabits:        return .behavioral
        case .prayerHistory:        return .high
        }
    }

    /// Must be encrypted at rest using AES.GCM (via AMENEncryptionService) when true.
    var mustEncryptAtRest: Bool { zone == .high }
}

struct BereanMemoryRecord: Codable, Identifiable, Sendable {
    let id: String
    let uid: String
    let field: MemoryField
    let zone: PrivacyCoreZone
    /// AES-256-GCM encrypted blob when field.mustEncryptAtRest; plaintext otherwise
    let value: String
    let encryptedAtRest: Bool
    let createdAt: TimeInterval
    let updatedAt: TimeInterval
    /// Invariants — always true; inspect/delete UI must surface these
    let userCanInspect: Bool
    let userCanDelete: Bool
}
