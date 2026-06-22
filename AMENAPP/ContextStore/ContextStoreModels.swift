// ContextStoreModels.swift
// AMEN Universal Migration & Context System — CANONICAL CONTRACT (Wave 0, FROZEN)
// FINALIZED TIER TABLE & SCHEMAS (Wave 0). See CONTRACTS.md for architecture.
//
// There is exactly ONE profile primitive: the ContextStore (facets + snapshots).
// IdentityBlueprint, PersonalOperatingManual, LifeCapsule, ContextQR, and the .amen
// export are PROJECTIONS over these facets — never separate stored models.
//
// Do not modify any type, enum case, or the tier table in this file without a
// contract amendment (halts all parallel wave work). See CONTRACTS.md.

import Foundation

// MARK: - Enumerations

/// The only categories a facet may belong to. Tier is derived from category via
/// `ContextTierTable` — never set per-facet by convention.
enum FacetCategory: String, Codable, CaseIterable {
    case interests
    case values
    case goals
    case skills
    case communities
    case relationships
    case communication
    case learning
    case faith_journey
    case current_focus
    case family
    case work
    case health
}

/// Who may see a facet. Default for every new facet is `.privateVisibility`.
enum Visibility: String, Codable, CaseIterable {
    case privateVisibility = "private"
    case friends
    case groups
    case church
    case publicVisibility = "public"
}

/// AMEN tiered encryption model.
/// - S: server-readable sensitive (encrypted at rest, system-processable)
/// - C: confidential, server-readable for declared features only (matching, feed, intros)
/// - P: private, NEVER server-readable; client-only projections, no CF payloads/logs/analytics
enum EncryptionTier: String, Codable {
    case s = "S"
    case c = "C"
    case p = "P"
}

enum FacetSource: String, Codable {
    case manual              // user typed it
    case interview           // Berean Migration Interview
    case extracted_paste     // universal paste box
    case extracted_file      // upload (resume, takeout, AI memory export)
    case derived             // inferred by AMEN systems post-onboarding
}

// MARK: - Structured facet values (tagged union)

/// Some facets carry structured data rather than a plain string/list.
/// Encoded as an internally-tagged union so it round-trips through Firestore and .amen.
enum StructuredFacetValue: Codable, Equatable {
    case text(String)
    case list([String])
    case faithJourney(FaithJourneyValue)
    case communicationStyle(CommunicationStyleValue)
    case relationshipCategory(RelationshipCategoryValue)

    private enum CodingKeys: String, CodingKey { case kind, payload }
    private enum Kind: String, Codable {
        case text, list, faithJourney, communicationStyle, relationshipCategory
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .text:                 self = .text(try c.decode(String.self, forKey: .payload))
        case .list:                 self = .list(try c.decode([String].self, forKey: .payload))
        case .faithJourney:         self = .faithJourney(try c.decode(FaithJourneyValue.self, forKey: .payload))
        case .communicationStyle:   self = .communicationStyle(try c.decode(CommunicationStyleValue.self, forKey: .payload))
        case .relationshipCategory: self = .relationshipCategory(try c.decode(RelationshipCategoryValue.self, forKey: .payload))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let v):                 try c.encode(Kind.text, forKey: .kind);                 try c.encode(v, forKey: .payload)
        case .list(let v):                 try c.encode(Kind.list, forKey: .kind);                 try c.encode(v, forKey: .payload)
        case .faithJourney(let v):         try c.encode(Kind.faithJourney, forKey: .kind);         try c.encode(v, forKey: .payload)
        case .communicationStyle(let v):   try c.encode(Kind.communicationStyle, forKey: .kind);   try c.encode(v, forKey: .payload)
        case .relationshipCategory(let v): try c.encode(Kind.relationshipCategory, forKey: .kind); try c.encode(v, forKey: .payload)
        }
    }

    /// Human-readable summary for previews/projections. Never used as a storage key.
    var displaySummary: String {
        switch self {
        case .text(let v): return v
        case .list(let v): return v.joined(separator: ", ")
        case .faithJourney(let v): return v.displaySummary
        case .communicationStyle(let v): return v.displaySummary
        case .relationshipCategory(let v): return v.displaySummary
        }
    }
}

/// Faith Journey structured value. NO scores, levels, comparisons, or rankings — by contract (§1.10).
struct FaithJourneyValue: Codable, Equatable {
    var currentChurchId: String?       // selected via Find a Church search, not matched here
    var currentChurchName: String?
    var currentStudy: String?
    var favoriteBooks: [String]        // books of the Bible
    var spiritualGoals: [String]       // may become Commitment Objects (Wave 4)
    var prayerHabits: [String]
    var areasOfGrowth: [String]
    /// MOST SENSITIVE. Always Tier P, client-only. Never server-readable.
    var areasNeedingSupport: [String]

    var displaySummary: String {
        var parts: [String] = []
        if let c = currentChurchName { parts.append("Church: \(c)") }
        if let s = currentStudy { parts.append("Study: \(s)") }
        if !favoriteBooks.isEmpty { parts.append("Books: \(favoriteBooks.joined(separator: ", "))") }
        return parts.joined(separator: " · ")
    }
}

struct CommunicationStyleValue: Codable, Equatable {
    var preferredTone: String?         // e.g. "direct", "warm", "reflective"
    var conversationStyles: [String]   // e.g. "async", "long-form", "voice"
    var frustratingBehaviors: [String] // online behaviors the user dislikes
    var meaningfulContentTypes: [String]

    var displaySummary: String {
        [preferredTone].compactMap { $0 }.joined() + (conversationStyles.isEmpty ? "" : " · " + conversationStyles.joined(separator: ", "))
    }
}

/// Relationship facets are CATEGORIES ONLY — never contacts/names. Always Tier P, client-only.
struct RelationshipCategoryValue: Codable, Equatable {
    enum Category: String, Codable, CaseIterable {
        case family, friends, mentors, colleagues, community, neighbors
    }
    var category: Category
    var note: String?                  // free-text, length-capped at extraction; never a contact

    var displaySummary: String { category.rawValue.capitalized }
}

// MARK: - Provenance

struct Provenance: Codable, Equatable {
    let source: FacetSource
    let sourceLabel: String?           // "LinkedIn export", "ChatGPT memory", etc.
    let extractedAt: Date?
    let confidence: Double?            // 0–1 extraction confidence
    var userApproved: Bool             // MUST be true before any Firestore write
    var userEdited: Bool               // user changed the AI's extraction
    let sanitizationPassId: String     // Aegis C59 sanitization receipt
}

// MARK: - ContextFacet (the only writable surface)

struct ContextFacet: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: String
    let category: FacetCategory
    let key: String                    // machine key, e.g. "interest.ai", "goal.launch_app"
    let label: String                  // human label
    var value: StructuredFacetValue
    var visibility: Visibility         // default .privateVisibility
    let tier: EncryptionTier           // MUST equal ContextTierTable.tier(for: category, key:)
    var provenance: Provenance
    let createdAt: Date
    var updatedAt: Date
    var schemaVersion: Int

    /// True iff the facet's tier matches the canonical table for its category/key.
    /// The client write path and the rules layer both enforce this — see ContextTierTable.
    var hasValidTier: Bool { tier == ContextTierTable.tier(for: category, key: key) }
}

// MARK: - ContextSnapshot (append-only time series)

struct ContextSnapshot: Codable, Identifiable, Equatable {
    enum Trigger: String, Codable { case manual, seasonal_prompt, major_edit }
    let id: UUID
    let userId: String
    let takenAt: Date
    let trigger: Trigger
    let facetStates: [ContextFacet]    // immutable copy at snapshot time
    var schemaVersion: Int
}

// MARK: - §3.3 TIER TABLE (law)

/// Single source of truth mapping facet category → encryption tier.
/// Server-side features may only read facets whose tier is `.c` (or `.s`).
/// Tier `.p` facets never leave the device through any server-readable path.
enum ContextTierTable {

    /// The canonical tier for a category. The `key` override exists only for the
    /// faith "areas needing support" facet, which is forced to Tier P regardless of
    /// the rest of faith_journey being Tier C.
    static func tier(for category: FacetCategory, key: String = "") -> EncryptionTier {
        // Faith "areas needing support" — most sensitive faith facet, always Tier P.
        if category == .faith_journey, key.hasSuffix(".areas_needing_support") {
            return .p
        }
        switch category {
        case .interests, .values, .goals, .skills, .communities,
             .communication, .learning, .current_focus, .work, .faith_journey:
            return .c
        case .relationships, .family, .health:
            return .p
        }
    }

    /// Whether a Cloud Function identity may read this facet at all.
    static func isServerReadable(_ tier: EncryptionTier) -> Bool {
        switch tier {
        case .s, .c: return true
        case .p:     return false
        }
    }

    /// Categories that require the dedicated faith consent screen before the first
    /// server-readable (Tier C) write. Declining keeps faith facets at Tier P.
    static let consentGatedCategories: Set<FacetCategory> = [.faith_journey]
}
