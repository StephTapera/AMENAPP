// AmenTransform.swift
// AMEN App — Phase 0 Contract C2 Stubs
//
// FROZEN — Do not implement logic in this file.
// All types are stubs only: no method bodies, no stored computed logic.
// See contracts/C2-intent-taxonomy.md for the full specification.
//
// Phase 0 rules:
//   - No feature implementations
//   - All functions are stubs (fatalError / protocol requirements only)
//   - OPEN: items mark unresolved design questions
//   - Provenance is a MANDATORY protocol requirement on TransformEngine
//
// Created: 2026-06-05

import Foundation

// MARK: - Intent

/// The 11 canonical intents a user can apply to any AmenObject.
/// Raw values are the Firestore-persisted string representations.
///
/// See C2-intent-taxonomy.md §2 for full semantics, privacy defaults,
/// and moderation tier per intent.
enum Intent: String, Codable, CaseIterable, Identifiable {
    case share      = "share"
    case discuss    = "discuss"
    case pray       = "pray"
    case study      = "study"
    case teach      = "teach"
    case ask        = "ask"
    case invite     = "invite"
    case volunteer  = "volunteer"
    case hire       = "hire"
    case mentor     = "mentor"
    case announce   = "announce"

    var id: String { rawValue }

    /// Human-readable display label.
    var displayLabel: String {
        switch self {
        case .share:     return "Share"
        case .discuss:   return "Discuss"
        case .pray:      return "Pray"
        case .study:     return "Study"
        case .teach:     return "Teach"
        case .ask:       return "Ask"
        case .invite:    return "Invite"
        case .volunteer: return "Volunteer"
        case .hire:      return "Hire"
        case .mentor:    return "Mentor"
        case .announce:  return "Announce"
        }
    }

    /// System image name for Liquid Glass chrome.
    var systemImage: String {
        switch self {
        case .share:     return "square.and.arrow.up"
        case .discuss:   return "bubble.left.and.bubble.right.fill"
        case .pray:      return "hands.sparkles.fill"
        case .study:     return "book.closed.fill"
        case .teach:     return "list.bullet.rectangle.fill"
        case .ask:       return "questionmark.bubble.fill"
        case .invite:    return "person.badge.plus"
        case .volunteer: return "hands.and.sparkles.fill"
        case .hire:      return "briefcase.fill"
        case .mentor:    return "person.badge.key.fill"
        case .announce:  return "megaphone.fill"
        }
    }

    /// Default moderation tier for the output object. See matrix §2.4.
    var defaultModerationTier: ModerationTier {
        switch self {
        case .share:     return .medium
        case .discuss:   return .medium
        case .pray:      return .low
        case .study:     return .low
        case .teach:     return .high
        case .ask:       return .low
        case .invite:    return .low
        case .volunteer: return .low
        case .hire:      return .medium
        case .mentor:    return .low
        case .announce:  return .high
        }
    }
}

// MARK: - AudienceConfig

/// Caller-supplied audience configuration for a transform operation.
/// The engine clamps this to the matrix ceiling if it is wider than allowed.
///
/// Maps to `ContentAudience` for persistence but carries an optional
/// explicit member list for private/directed transforms.
struct AudienceConfig: Codable, Equatable {

    /// Audience tier (maps 1:1 to `ContentAudience` raw values).
    let audienceType: AudienceTier

    /// Privacy strictness. Higher values require narrower audience.
    let privacyLevel: PrivacyLevel

    /// If non-nil, only these user IDs may access the output object.
    /// Only valid when `audienceType` is `.private` or `.trustedCircle`.
    let explicitMemberIds: [String]?

    // MARK: - Nested Types

    enum AudienceTier: String, Codable, CaseIterable {
        case `private`      = "private"
        case trustedCircle  = "trusted_circle"
        case smallGroup     = "small_group"
        case churchOnly     = "church_only"
        case spaceMembers   = "space_members"
        case paidMembers    = "paid_members"
        case publicFeed     = "public_feed"

        /// Numeric rank used for wideness comparison.
        /// Lower = narrower audience.
        var rank: Int {
            switch self {
            case .private:      return 0
            case .trustedCircle: return 1
            case .smallGroup:   return 2
            case .churchOnly:   return 3
            case .spaceMembers: return 4
            case .paidMembers:  return 5
            case .publicFeed:   return 6
            }
        }

        /// Returns true if self is wider (less restrictive) than `other`.
        func isWiderThan(_ other: AudienceTier) -> Bool { rank > other.rank }
    }

    enum PrivacyLevel: String, Codable, CaseIterable {
        case standard  = "standard"
        case elevated  = "elevated"
        case high      = "high"
        case critical  = "critical"
    }
}

// MARK: - TransformProvenance

/// Immutable provenance record written alongside every transform output.
///
/// PROTOCOL REQUIREMENT: This must always be fully populated. No field
/// may be nil for required fields. See C2-intent-taxonomy.md §5.3 and §6.
///
/// Written to Firestore at: transformedObjects/{newObjectId}/provenance
/// Uses a create-only transaction (fails if document already exists).
struct TransformProvenance: Codable, Equatable {

    // OPEN: Should transformedAt be a Firestore ServerTimestamp sentinel
    // rather than a Swift Date, to prevent client-clock skew?

    // Required fields — always present
    let sourceObjectId:    String
    let sourceObjectType:  String
    let sourceCreatorId:   String
    let sourceCreatedAt:   Date
    let transformActorId:  String
    let transformedAt:     Date        // Must be server timestamp in production
    let intentApplied:     String      // Intent.rawValue
    let originalAudience:  String      // AudienceConfig.AudienceTier.rawValue

    // Optional fields — set based on source type
    let sermonTimestamp:       TimeInterval?   // Sermon sources only
    let scriptureReference:    String?         // ScriptureReference sources only
    let scriptureTranslation:  String?         // ScriptureReference sources only
    let bereanActionId:        String?         // BereanInsight sources only
    let orgId:                 String?         // OrganizationObject, Job sources only
    let spaceId:               String?         // SpaceObject sources only
    let eventDate:             Date?           // Event sources only
}

// MARK: - TransformResult

/// The output of a successful `transform()` call.
/// All fields are non-optional unless semantically impossible for the operation.
struct TransformResult: Equatable {

    /// Firestore document ID of the newly-created derived object.
    let newObjectId: String

    /// Raw type string of the derived object (e.g. "discussion_room", "action_thread").
    let newObjectType: String

    /// Immutable provenance written to Firestore alongside the new object.
    /// NEVER nil. Protocol requires this field to always be set.
    let provenance: TransformProvenance

    /// The audience actually applied after clamping to matrix ceiling.
    let appliedAudience: AudienceConfig

    /// Permission set on the new object, keyed by capability name.
    /// Mirrors the `ActionThreadPermissionSet` pattern from ActionThreadModels.swift.
    let appliedPermissions: [String: Bool]

    /// Moderation tier resolved for this specific (sourceType × intent) combination.
    let moderationTier: ModerationTier

    /// Room ID — non-nil only for `Intent.discuss` output.
    /// Maps to `ObjectDiscussionRoom.id` in AmenObjectDiscussionModels.swift.
    let roomId: String?

    /// Action thread ID — non-nil only for `Intent.pray` output.
    /// Maps to `ActionThread.id` in ActionThreadModels.swift.
    let actionThreadId: String?

    /// Non-fatal advisory messages (e.g. audience was clamped).
    let warnings: [TransformWarning]
}

// MARK: - TransformWarning

/// A non-fatal advisory produced during a transform operation.
enum TransformWarning: Equatable {

    /// Caller-supplied audience was wider than the matrix ceiling; clamped.
    case audienceClamped(requested: AudienceConfig.AudienceTier, applied: AudienceConfig.AudienceTier)

    /// Source object has sensitive content; moderation review will be triggered.
    case sensitiveContentFlagged

    /// Provenance field could not be resolved from source; field omitted from record.
    case optionalProvenanceFieldMissing(field: String)

    /// The derived object type for this combination is provisional (not yet modelled).
    // OPEN: Remove this case once Job and MentorshipRequest are fully modelled.
    case targetTypeProvisional(type: String)
}

// MARK: - ModerationTier

/// Moderation review level applied to an output object.
/// Maps to the content moderation pipeline (NeMo Guard / Vision LLM / human review).
enum ModerationTier: String, Codable, CaseIterable {
    case low    = "low"
    case medium = "medium"
    case high   = "high"
    case severe = "severe"   // Reserved; not assigned by transform matrix currently.
    // OPEN: Severe tier is defined but unused in the transform matrix.
    // Confirm whether it applies to Aegis pipeline inputs exclusively
    // or can be returned here in future.
}

// MARK: - TransformError

/// Errors thrown by `TransformEngine.transform()`.
/// All cases are hard failures; callers must not silently swallow them.
enum TransformError: Error, Equatable {

    /// The (sourceType × intent) combination is blocked in the transform matrix.
    case unsupportedCombination(sourceType: String, intent: Intent)

    /// The actor does not have the role required to invoke this intent.
    case actorNotAuthorized(requiredRole: String)

    /// The source object could not be found in Firestore.
    case sourceObjectNotFound

    /// The Firestore transaction to write the provenance document failed.
    case provenanceWriteFailed

    /// Caller attempted to set an audience wider than the matrix ceiling.
    /// Distinct from the clamping warning — thrown when the policy is hard-block.
    case audienceCapExceeded(requested: AudienceConfig.AudienceTier, ceiling: AudienceConfig.AudienceTier)

    /// A required Remote Config feature flag is false.
    case featureFlagDisabled(flagName: String)

    /// Hire intent attempted without a verified organization.
    case orgNotVerified

    /// Mentor intent attempted; the target mentor has not yet consented.
    case mentorConsentPending

    /// A required provenance field could not be resolved.
    case missingRequiredProvenance(field: String)
}

// MARK: - AmenObject (Transform Source Protocol)

/// Minimum interface that any source object must expose to the transform engine.
/// Concrete models (Post, Sermon, ScriptureReference, etc.) must conform.
///
/// OPEN: Should this be a protocol on all domain models, or a
/// lightweight value-type wrapper that callers produce on demand?
protocol AmenTransformableObject {
    var objectId: String        { get }
    var objectType: String      { get }   // Must match one of the 13 canonical source types
    var creatorId: String       { get }
    var createdAt: Date         { get }
    var currentAudience: AudienceConfig.AudienceTier { get }
    var isAnonymous: Bool       { get }
    var hasPrayerContent: Bool  { get }
    var isDM: Bool              { get }
}

// MARK: - TransformEngine (Protocol)

/// The contract all transform engine implementations must fulfill.
///
/// PROVENANCE REQUIREMENT (mandatory):
///   Implementations MUST write a fully-populated `TransformProvenance` to
///   Firestore before returning a `TransformResult`. Returning a result
///   without confirmed provenance persistence is a protocol violation.
///   If provenance cannot be written, implementations MUST throw
///   `TransformError.provenanceWriteFailed` or
///   `TransformError.missingRequiredProvenance`.
///
/// AUDIENCE CLAMPING REQUIREMENT (mandatory):
///   Implementations MUST clamp `audience` to the matrix ceiling for the
///   given (sourceType × intent) combination. Silently widening audience
///   is a protocol violation.
protocol TransformEngine: AnyObject {

    /// Transform `source` by applying `intent`, creating a new derived object.
    ///
    /// - Parameters:
    ///   - source: The originating AmenObject. Must conform to AmenTransformableObject.
    ///   - intent: One of the 11 canonical intents.
    ///   - actorId: Firebase UID of the authenticated user initiating the transform.
    ///   - audience: Optional audience override; nil = use matrix default. Clamped to ceiling.
    /// - Returns: A `TransformResult` with a non-nil, Firestore-persisted provenance.
    /// - Throws: `TransformError` for all hard failures.
    func transform(
        source:   any AmenTransformableObject,
        intent:   Intent,
        actorId:  String,
        audience: AudienceConfig?
    ) async throws -> TransformResult

    /// Returns true if the given (sourceType × intent) combination is supported.
    /// Must not perform any Firestore I/O.
    func isSupported(sourceType: String, intent: Intent) -> Bool

    /// Returns the matrix-defined audience ceiling for a given combination.
    /// Returns nil for unsupported combinations.
    func audienceCeiling(sourceType: String, intent: Intent) -> AudienceConfig.AudienceTier?
}

// MARK: - TransformMatrix

/// Static lookup table encoding the transform matrix from C2-intent-taxonomy.md §4.
///
/// This is a pure configuration type — no network I/O, no Firestore access.
/// All entries are keyed by (sourceType raw string, Intent raw string).
///
/// Implementations should call `TransformMatrix.config(sourceType:intent:)` to
/// retrieve per-cell configuration rather than reimplementing the matrix inline.
///
/// OPEN: The matrix is currently expressed as a static dictionary.
/// A future Phase 1 task should evaluate whether a Firestore-backed remote
/// matrix is needed to allow hot-patching blocked combinations.
struct TransformMatrix {

    /// Per-cell configuration produced by the matrix lookup.
    struct CellConfig: Equatable {
        let targetObjectType: String
        let defaultAudience: AudienceConfig.AudienceTier
        let roomType: String?                 // nil unless Discuss intent
        let availableActions: [String]
        let moderationTier: ModerationTier
        let requiredProvenanceFields: [String]
    }

    /// Returns the cell configuration for the given combination,
    /// or nil if the combination is blocked (cell is `–` in the matrix).
    ///
    /// This method is the single authority for matrix lookups.
    /// No feature code should duplicate matrix logic.
    static func config(sourceType: String, intent: Intent) -> CellConfig? {
        // STUB — Implementation deferred to Phase 1
        // OPEN: The full 13×11 dictionary should be populated here in Phase 1.
        fatalError("TransformMatrix.config is a Phase 0 stub — not implemented")
    }

    /// Returns the set of intents that are supported for a given source type.
    static func supportedIntents(for sourceType: String) -> [Intent] {
        // STUB — Implementation deferred to Phase 1
        fatalError("TransformMatrix.supportedIntents is a Phase 0 stub — not implemented")
    }

    /// Returns the audience ceiling (widest permitted audience) for a given
    /// (sourceType × intent) combination. Returns nil for blocked combinations.
    static func audienceCeiling(sourceType: String, intent: Intent) -> AudienceConfig.AudienceTier? {
        // STUB — Implementation deferred to Phase 1
        fatalError("TransformMatrix.audienceCeiling is a Phase 0 stub — not implemented")
    }
}
