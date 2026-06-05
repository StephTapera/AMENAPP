// ObjectModel.swift
// AMEN App — Phase 0 Contract C1 Stubs
//
// FROZEN 2026-06-05. No implementations — stubs and protocol definitions only.
// See contracts/C1-object-model.md for the full specification.
//
// Phase 0 rules:
//   - No feature implementations; no Firestore I/O.
//   - All enums and structs are plain Codable value types.
//   - AmenTransformableObject protocol lives in AmenTransform.swift — not redefined here.
//   - OPEN: items mark unresolved design questions.
//
// Cross-reference: C1-object-model.md, C2-intent-taxonomy.md, C5-security-rules.md

import Foundation

// MARK: - AmenObjectType

/// Canonical object type registry. Every Firestore document belonging to
/// the Community OS object graph must declare one of these types.
///
/// C1 rule: the raw string value is persisted in Firestore as the `_type` field.
/// Do not rename raw values after the first production document is written.
enum AmenObjectType: String, Codable, CaseIterable, Identifiable {
    // Identity
    case user                   = "user"
    case organization           = "organization"
    case church                 = "church"
    case team                   = "team"
    case space                  = "space"

    // Content
    case post                   = "post"
    case prayer                 = "prayer"
    case discussion             = "discussion"
    case studyRoom              = "study_room"
    case prayerRoom             = "prayer_room"

    // Opportunity
    case event                  = "event"
    case volunteerOpportunity   = "volunteer_opportunity"
    case mentorship             = "mentorship"
    case job                    = "job"

    // Knowledge
    case churchNote             = "church_note"
    case bereanInsight          = "berean_insight"
    case mediaObject            = "media_object"
    case sermon                 = "sermon"

    // Private / ONE
    // OPEN: Whether `moment` should be unified under `post` with a contentType discriminator.
    case moment                 = "moment"
    case actionThread           = "action_thread"   // Do not replace existing ActionThread system

    var id: String { rawValue }

    /// The Firestore collection path prefix for this type.
    /// Nested collections (e.g. churchNotes under users/) use slash notation.
    var collectionPath: String {
        switch self {
        case .user:                 return "users"
        case .organization:         return "organizations"
        case .church:               return "churches"
        case .team:                 return "teams"
        case .space:                return "covenants"
        case .post:                 return "posts"
        case .prayer:               return "prayers"
        case .discussion:           return "discussions"
        case .studyRoom:            return "studyRooms"
        case .prayerRoom:           return "prayerRooms"
        case .event:                return "events"
        case .volunteerOpportunity: return "volunteerOpportunities"
        case .mentorship:           return "mentorships"
        case .job:                  return "jobs"
        case .churchNote:           return "users/{uid}/churchNotes"   // user-scoped
        case .bereanInsight:        return "users/{uid}/bereanInsights" // user-scoped
        case .mediaObject:          return "mediaObjects"
        case .sermon:               return "sermons"
        case .moment:               return "moments"
        case .actionThread:         return "actionThreads"
        }
    }
}

// MARK: - AmenCapability

/// Capabilities that objects can expose to the Action Pill (A18).
///
/// The resolved set for any (objectType × viewerRole × audience) triple
/// is computed by A18 at display time using the matrix in C1-object-model.md §2.
/// This enum is the canonical list — no capability outside this set may be added
/// without a C1 contract amendment.
enum AmenCapability: String, Codable, CaseIterable, Identifiable {
    case view       = "view"
    case discuss    = "discuss"
    case pray       = "pray"
    case study      = "study"
    case share      = "share"
    case save       = "save"
    case invite     = "invite"
    case followUp   = "follow_up"
    case volunteer  = "volunteer"
    case hire       = "hire"
    case mentor     = "mentor"
    case announce   = "announce"
    case broadcast  = "broadcast"
    case moderate   = "moderate"

    var id: String { rawValue }

    /// SF Symbol representing this capability in the Action Pill.
    var systemImage: String {
        switch self {
        case .view:      return "eye"
        case .discuss:   return "bubble.left.and.bubble.right"
        case .pray:      return "hands.sparkles"
        case .study:     return "book.closed"
        case .share:     return "square.and.arrow.up"
        case .save:      return "bookmark"
        case .invite:    return "person.badge.plus"
        case .followUp:  return "arrow.uturn.right.circle"
        case .volunteer: return "hands.and.sparkles"
        case .hire:      return "briefcase"
        case .mentor:    return "person.badge.key"
        case .announce:  return "megaphone"
        case .broadcast: return "dot.radiowaves.left.and.right"
        case .moderate:  return "shield.lefthalf.filled"
        }
    }
}

// MARK: - ObjectProvenance

/// Immutable provenance block embedded on every spawned Community OS object.
///
/// INVARIANT: Written once at object creation via a Firestore create-only transaction.
/// Never mutated after creation. Queried but never written by any Phase 1+ agent.
///
/// Unifies three fragmented provenance models in the existing codebase:
///   - ContentSourceReference (sourceId, sourceType, title, url, attribution)
///   - AmenAIProvenance (provider, model, runId, userApproved)
///   - ONEProvenanceLabel (C2PA image provenance — this struct is NOT a replacement
///     for ONEProvenanceLabel, which is image-level metadata)
///
/// C1 §3 rule: root-originated objects (no parent) set provenance to nil.
struct ObjectProvenance: Codable, Equatable {

    // MARK: Required fields

    /// ObjectType raw value of the originating object (e.g. "post", "berean_insight").
    let sourceType: String

    /// Firestore document path of the originating object (e.g. "posts/abc123").
    /// This is the hop-1 canonical link. Resharing a reshare sets this to the
    /// ORIGINAL source, not the intermediate.
    let sourceRef: String

    /// Firebase UID of the original object's author/owner.
    let sourceOwnerId: String

    /// Intent raw value that triggered the spawn (from C2). e.g. "discuss", "pray".
    let intent: String

    /// Server-authoritative timestamp. Never set from client clock.
    let createdAt: Date

    // MARK: Optional: AI provenance (present when AI-assisted/generated)

    /// Present when the object was generated or materially shaped by an AI model.
    let ai: AIProvenance?

    // MARK: - AIProvenance

    /// Embedded only when the object is AI-assisted or AI-generated.
    /// Replaces the fragmented AmenAIProvenance / AmenGeneratedDraft provenance chain
    /// for Community OS objects. Legacy AmenAIProvenance remains on pre-existing drafts.
    struct AIProvenance: Codable, Equatable {
        /// Adapter identifier — "anthropic" | "nvidia" | "openai" | "google"
        let provider: String

        /// Model version string (e.g. "claude-sonnet-4-6", "nvidia/llama-3.1-nemoguard-8b")
        let model: String

        /// Unique inference run ID for audit trail.
        let runId: String

        /// Task that produced this object — "draft" | "summary" | "translation" | "moderation"
        let taskType: String

        /// True if the user explicitly reviewed and accepted the AI output before publish.
        let userApproved: Bool

        /// True if the user modified the AI output before publishing.
        let userEdited: Bool
    }
}

// MARK: - EdgeType

/// Types of edges in the `/edges/{edgeId}` graph collection.
///
/// C1 §4 defines the read patterns and index requirements per edge type.
/// New edge types require a C1 contract amendment.
enum EdgeType: String, Codable, CaseIterable {
    /// Child object belongs to a parent context (e.g. churchNote → church, event → org).
    case belongsTo   = "belongsTo"

    /// Object was created via a transform operation (e.g. discussion ← post via Discuss intent).
    case spawnedFrom = "spawnedFrom"

    /// Contextual annotation link (e.g. bereanInsight ↔ scriptureRef, churchNote ↔ sermon).
    case links       = "links"

    /// User follows an org, church, space, or creator.
    case follows     = "follows"

    /// User or prayer room intercedes for a prayer request.
    case praysFor    = "praysFor"

    /// User mentors another user (established relationship, not a request).
    case mentors     = "mentors"

    /// User is a verified member of a space, church, or org.
    case memberOf    = "memberOf"
}

// MARK: - EdgeDocument

/// In-memory representation of an `/edges/{edgeId}` Firestore document.
///
/// Read pattern: query on `fromRef` + `edgeType` for outbound traversal,
/// or `toRef` + `edgeType` for inbound traversal. Both compound indexes are required.
///
/// Write rule: only the Community Graph service (A5) may write edges.
/// Edge deletions are soft-deletes (set `deletedAt`; never remove the document).
struct EdgeDocument: Codable, Equatable {
    let edgeId: String

    /// Firestore doc path of the originating node (e.g. "posts/abc").
    let fromRef: String
    let fromType: String    // AmenObjectType raw value

    /// Firestore doc path of the destination node.
    let toRef: String
    let toType: String      // AmenObjectType raw value

    let edgeType: String    // EdgeType raw value
    let createdBy: String   // Firebase UID
    let visibility: String  // VisibilityLevel raw value (from C1 §5)

    let createdAt: Date

    /// Nil = edge is active. Non-nil = edge is soft-deleted.
    let deletedAt: Date?
}

// MARK: - VisibilityLevel

/// Visibility tiers for objects and edges.
///
/// INVARIANT: An object's audience never automatically widens
/// during a transform operation. It may only narrow. See C2 §5.4.
enum VisibilityLevel: String, Codable, CaseIterable {
    case `private`      = "private"
    case trustedCircle  = "trusted_circle"
    case churchMembers  = "church_members"
    case spaceMembers   = "space_members"
    case mutuals        = "mutuals"
    case followers      = "followers"
    case `public`       = "public"

    /// Identity-shielded public visibility. Used by Prayer OS anonymous prayer mode.
    /// OPEN: Scope of identity shielding for public objects is an open Decision Register item.
    case anonymous      = "anonymous"

    /// Numeric rank for audience comparison. Higher = wider.
    var rank: Int {
        switch self {
        case .private:       return 0
        case .trustedCircle: return 1
        case .churchMembers: return 2
        case .spaceMembers:  return 3
        case .mutuals:       return 4
        case .followers:     return 5
        case .public:        return 6
        case .anonymous:     return 6  // same rank as public; differs only in identity exposure
        }
    }
}

// MARK: - AmenObjectNode (graph traversal helper)

/// A lightweight node descriptor for graph traversal queries.
/// Does NOT replace full object models — used only by the A5 graph service.
struct AmenObjectNode: Equatable {
    let ref: String              // Firestore doc path
    let type: AmenObjectType
    let capabilities: [AmenCapability]
    let visibility: VisibilityLevel
}

// MARK: - Denormalized counts rule

/// Denormalized counter fields on Community OS objects.
/// Managed exclusively by Cloud Function triggers (A1/A5 agents).
/// Never written by iOS client code.
///
/// Fields:
///   threadCount   — on Discussion; updated by thread create/delete CF
///   rsvpCount     — on Event; updated by RSVP edge create/delete CF
///   memberCount   — on Space; updated by memberOf edge create/delete CF
///
/// Anti-engagement invariant: none of these counters is ever shown
/// as a comparative metric between users. They are operational signals only.
enum DenormalizedCounter: String {
    case threadCount  = "threadCount"
    case rsvpCount    = "rsvpCount"
    case memberCount  = "memberCount"
}
