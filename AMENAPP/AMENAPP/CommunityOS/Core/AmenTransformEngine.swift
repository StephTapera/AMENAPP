// AmenTransformEngine.swift
// AMEN App — CommunityOS / Core
//
// Phase 1 — Agent A1 (Core Platform Architecture)
// Full implementation of C2 Intent Taxonomy Contract — transform engine.
//
// Implements the (sourceType × intent) matrix from C2 §4.
// All matrix lookups are pure in-memory — no Firestore I/O in this class.
// See AmenObjectRepository for the write path that uses TransformConfig.

import Foundation
import FirebaseAuth

// MARK: - Intent

/// The 11 canonical intents a user can apply to any AmenObject.
/// Raw values are persisted to Firestore provenance records.
///
/// See contracts/C2-intent-taxonomy.md §2 for full semantics.
///
/// OPEN: Should a 12th intent `Challenge` (scholarly doctrinal rebuttal)
///       be added, or is `ask` sufficient? Decision deferred to product team.
enum Intent: String, Codable, CaseIterable, Identifiable, Sendable {
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

    /// Human-readable display label for UI.
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

    /// SF Symbol name for Liquid Glass chrome affordances.
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
}

// MARK: - ModerationTier

/// Review level applied to a transform output object.
/// Drives NeMo Guard / Vision LLM / human review pipeline selection.
///
/// OPEN: `severe` tier is defined but not assigned by the transform matrix.
///       Confirm whether it is reserved for Aegis pipeline inputs exclusively.
enum ModerationTier: String, Codable, Sendable {
    case low    = "low"
    case medium = "medium"
    case high   = "high"
    case severe = "severe"  // Reserved; not assigned by transform matrix currently.
}

// MARK: - TransformConfig

/// Per-cell configuration produced by the transform matrix lookup.
/// Returned from `AmenTransformEngine.transform()` alongside `SpawnProvenance`.
struct TransformConfig: Sendable {
    /// ObjectType raw value of the derived object (e.g., "discussion", "actionThread").
    let targetObjectType: String
    /// Default audience tier for the derived object per C2 §2.3.
    let defaultAudience: String
    /// Room type hint — non-nil only for Discuss intent outputs.
    let roomType: DiscussionRoomType?
    /// Moderation tier for the output object.
    let moderationTier: ModerationTier
    /// Allowed capability actions on the output.
    let allowedActions: [ObjectCapability]
}

// MARK: - TransformError

/// Errors thrown by AmenTransformEngine.transform(). All cases are hard failures;
/// callers must not silently swallow them.
enum TransformError: Error, Equatable {
    /// (sourceType × intent) is blocked (cell marked `–` in C2 matrix).
    case unsupportedCombination(sourceType: String, intent: Intent)
    /// Source object could not be resolved.
    case sourceObjectNotFound
    /// Firestore transaction to write provenance failed.
    case provenanceWriteFailed
    /// A required provenance field could not be resolved.
    case missingRequiredProvenance(field: String)
    /// Actor does not have the minimum role for this intent.
    case actorNotAuthorized(requiredRole: String)
    /// Feature flag is disabled for this intent/source combination.
    case featureFlagDisabled(flagName: String)
    /// Hire intent attempted without verified organization.
    case orgNotVerified
    /// Mentor intent: target mentor has not yet consented.
    case mentorConsentPending
}

// MARK: - AmenTransformEngine

/// Core transform engine. Implements the C2 transform matrix as an in-memory
/// static dictionary. No Firestore I/O — pure matrix lookup + provenance creation.
///
/// Usage:
///   ```swift
///   let (config, provenance) = try AmenTransformEngine().transform(
///       sourceType: .post,
///       sourceRef: "/posts/abc",
///       sourceOwnerId: "uid123",
///       intent: .discuss,
///       actorId: "uid456",
///       audience: nil
///   )
///   ```
///
/// The caller (AmenObjectRepository) is responsible for writing the derived object
/// and provenance to Firestore.
final class AmenTransformEngine {

    // MARK: - Matrix Key Helper

    /// Produces the dictionary key used to look up a matrix entry.
    static func matrixKey(source: ObjectType, intent: Intent) -> String {
        "\(source.rawValue)_\(intent.rawValue)"
    }

    // MARK: - Transform Matrix
    //
    // Keyed by "\(sourceType.rawValue)_\(intent.rawValue)".
    // Cells marked `–` in C2 §4.1 are absent from this dictionary.
    // Absent entries cause `transform()` to throw `.unsupportedCombination`.
    //
    // Coverage: Post × all intents, Prayer × (discuss|study|share|pray|ask|mentor),
    // BereanInsight × (share|discuss|pray|study|teach|ask|mentor|announce),
    // ChurchNote × (share|discuss|pray|study|teach|ask|announce),
    // Event × (share|discuss|pray|teach|ask|invite|volunteer|announce),
    // Job × (share|discuss|ask|hire|announce),
    // MediaObject × (share|discuss|pray|teach|ask|announce).
    // Remaining source types (Sermon, Message, SpaceObject, OrganizationObject,
    // ScriptureReference, MentorshipRequest) deferred to Phase 1 completion.
    //
    // OPEN: Full 13×11 matrix should be populated once all source types are modelled.

    // swiftlint:disable function_body_length
    static let matrix: [String: TransformConfig] = {
        var m = [String: TransformConfig]()

        // MARK: Post ×  all intents
        m["post_share"] = TransformConfig(
            targetObjectType: "post",
            defaultAudience: "source",
            roomType: nil,
            moderationTier: .medium,
            allowedActions: [.share, .save, .discuss, .pray]
        )
        m["post_discuss"] = TransformConfig(
            targetObjectType: "discussion",
            defaultAudience: "spaceMembers",
            roomType: .discussion,
            moderationTier: .medium,
            allowedActions: [.discuss, .pray, .save]
        )
        m["post_pray"] = TransformConfig(
            targetObjectType: "actionThread",
            defaultAudience: "private",
            roomType: nil,
            moderationTier: .low,
            allowedActions: [.pray, .followUp]
        )
        m["post_study"] = TransformConfig(
            targetObjectType: "study",
            defaultAudience: "private",
            roomType: nil,
            moderationTier: .low,
            allowedActions: [.study, .save, .share]
        )
        m["post_teach"] = TransformConfig(
            targetObjectType: "post",             // TeachingArtefact maps to post shape
            defaultAudience: "spaceMembers",
            roomType: nil,
            moderationTier: .high,
            allowedActions: [.share, .discuss]
        )
        m["post_ask"] = TransformConfig(
            targetObjectType: "actionThread",
            defaultAudience: "private",
            roomType: nil,
            moderationTier: .low,
            allowedActions: [.discuss, .followUp]
        )
        m["post_invite"] = TransformConfig(
            targetObjectType: "event",
            defaultAudience: "spaceMembers",
            roomType: nil,
            moderationTier: .low,
            allowedActions: [.invite, .share]
        )
        m["post_mentor"] = TransformConfig(
            targetObjectType: "mentorship",
            defaultAudience: "private",
            roomType: nil,
            moderationTier: .low,
            allowedActions: [.discuss, .followUp]
        )
        m["post_announce"] = TransformConfig(
            targetObjectType: "post",
            defaultAudience: "churchOnly",
            roomType: nil,
            moderationTier: .high,
            allowedActions: [.share, .discuss]
        )
        // post_volunteer is blocked (–) — no VolunteerSlot from a generic Post
        // post_hire is blocked (–) — hire requires an org object

        // MARK: Prayer × intents
        // prayer_share: BLOCKED — prayer content cannot be shared without creator approval.
        m["prayer_discuss"] = TransformConfig(
            targetObjectType: "discussion",
            defaultAudience: "trustedCircle",
            roomType: .prayer,
            moderationTier: .low,
            allowedActions: [.discuss, .pray]
        )
        m["prayer_pray"] = TransformConfig(
            targetObjectType: "actionThread",
            defaultAudience: "private",
            roomType: nil,
            moderationTier: .low,
            allowedActions: [.pray, .followUp]
        )
        m["prayer_ask"] = TransformConfig(
            targetObjectType: "actionThread",
            defaultAudience: "private",
            roomType: nil,
            moderationTier: .low,
            allowedActions: [.discuss, .followUp]
        )
        m["prayer_mentor"] = TransformConfig(
            targetObjectType: "mentorship",
            defaultAudience: "private",
            roomType: nil,
            moderationTier: .low,
            allowedActions: [.discuss, .followUp]
        )
        // prayer_announce: BLOCKED — prayer requests may not be announced.
        // OPEN: Should there be a "de-identified testimony" pathway that strips PII?

        // MARK: BereanInsight × intents
        m["bereanInsight_share"] = TransformConfig(
            targetObjectType: "post",
            defaultAudience: "source",
            roomType: nil,
            moderationTier: .medium,
            allowedActions: [.share, .save]
        )
        m["bereanInsight_discuss"] = TransformConfig(
            targetObjectType: "discussion",
            defaultAudience: "spaceMembers",
            roomType: .studyGroup,
            moderationTier: .medium,
            allowedActions: [.discuss, .pray]
        )
        m["bereanInsight_pray"] = TransformConfig(
            targetObjectType: "actionThread",
            defaultAudience: "private",
            roomType: nil,
            moderationTier: .low,
            allowedActions: [.pray]
        )
        m["bereanInsight_study"] = TransformConfig(
            targetObjectType: "study",
            defaultAudience: "private",
            roomType: nil,
            moderationTier: .low,
            allowedActions: [.study, .save, .share]
        )
        // OPEN: Should BereanInsight→Teach be allowed? Teaching from AI insight carries
        //       doctrinal risk. Current matrix allows it at High tier as compromise.
        m["bereanInsight_teach"] = TransformConfig(
            targetObjectType: "post",
            defaultAudience: "spaceMembers",
            roomType: nil,
            moderationTier: .high,
            allowedActions: [.share, .discuss]
        )
        m["bereanInsight_ask"] = TransformConfig(
            targetObjectType: "actionThread",
            defaultAudience: "private",
            roomType: nil,
            moderationTier: .low,
            allowedActions: [.discuss, .followUp]
        )
        m["bereanInsight_mentor"] = TransformConfig(
            targetObjectType: "mentorship",
            defaultAudience: "private",
            roomType: nil,
            moderationTier: .low,
            allowedActions: [.discuss, .followUp]
        )
        m["bereanInsight_announce"] = TransformConfig(
            targetObjectType: "post",
            defaultAudience: "churchOnly",
            roomType: nil,
            moderationTier: .high,
            allowedActions: [.share]
        )

        // MARK: ChurchNote × intents
        m["churchNote_share"] = TransformConfig(
            targetObjectType: "post",
            defaultAudience: "source",
            roomType: nil,
            moderationTier: .medium,
            allowedActions: [.share, .save, .pray]
        )
        m["churchNote_discuss"] = TransformConfig(
            targetObjectType: "discussion",
            defaultAudience: "spaceMembers",
            roomType: .studyGroup,
            moderationTier: .medium,
            allowedActions: [.discuss, .save]
        )
        m["churchNote_pray"] = TransformConfig(
            targetObjectType: "actionThread",
            defaultAudience: "private",
            roomType: nil,
            moderationTier: .low,
            allowedActions: [.pray, .followUp]
        )
        m["churchNote_study"] = TransformConfig(
            targetObjectType: "study",
            defaultAudience: "private",
            roomType: nil,
            moderationTier: .low,
            allowedActions: [.study, .save, .share, .discuss]
        )
        m["churchNote_teach"] = TransformConfig(
            targetObjectType: "post",
            defaultAudience: "spaceMembers",
            roomType: nil,
            moderationTier: .high,
            allowedActions: [.share, .discuss]
        )
        m["churchNote_ask"] = TransformConfig(
            targetObjectType: "actionThread",
            defaultAudience: "private",
            roomType: nil,
            moderationTier: .low,
            allowedActions: [.discuss, .followUp]
        )
        m["churchNote_announce"] = TransformConfig(
            targetObjectType: "post",
            defaultAudience: "churchOnly",
            roomType: nil,
            moderationTier: .high,
            allowedActions: [.share]
        )

        // MARK: Event × intents
        m["event_share"] = TransformConfig(
            targetObjectType: "post",
            defaultAudience: "spaceMembers",
            roomType: nil,
            moderationTier: .medium,
            allowedActions: [.share, .save, .invite]
        )
        m["event_discuss"] = TransformConfig(
            targetObjectType: "discussion",
            defaultAudience: "spaceMembers",
            roomType: .discussion,
            moderationTier: .medium,
            allowedActions: [.discuss]
        )
        m["event_pray"] = TransformConfig(
            targetObjectType: "actionThread",
            defaultAudience: "private",
            roomType: nil,
            moderationTier: .low,
            allowedActions: [.pray]
        )
        m["event_teach"] = TransformConfig(
            targetObjectType: "post",
            defaultAudience: "spaceMembers",
            roomType: nil,
            moderationTier: .high,
            allowedActions: [.share, .discuss]
        )
        m["event_ask"] = TransformConfig(
            targetObjectType: "actionThread",
            defaultAudience: "private",
            roomType: nil,
            moderationTier: .low,
            allowedActions: [.discuss]
        )
        m["event_invite"] = TransformConfig(
            targetObjectType: "event",
            defaultAudience: "spaceMembers",
            roomType: nil,
            moderationTier: .low,
            allowedActions: [.invite, .share]
        )
        m["event_volunteer"] = TransformConfig(
            targetObjectType: "volunteerOpportunity",
            defaultAudience: "spaceMembers",
            roomType: nil,
            moderationTier: .low,
            allowedActions: [.invite, .followUp]
        )
        m["event_announce"] = TransformConfig(
            targetObjectType: "post",
            defaultAudience: "churchOnly",
            roomType: nil,
            moderationTier: .high,
            allowedActions: [.share, .invite]
        )

        // MARK: Job × intents
        m["job_share"] = TransformConfig(
            targetObjectType: "post",
            defaultAudience: "publicFeed",
            roomType: nil,
            moderationTier: .medium,
            allowedActions: [.share, .save]
        )
        m["job_discuss"] = TransformConfig(
            targetObjectType: "discussion",
            defaultAudience: "spaceMembers",
            roomType: .discussion,
            moderationTier: .medium,
            allowedActions: [.discuss]
        )
        m["job_ask"] = TransformConfig(
            targetObjectType: "actionThread",
            defaultAudience: "private",
            roomType: nil,
            moderationTier: .low,
            allowedActions: [.discuss]
        )
        // OPEN: Hire intent for Job should be gated behind featureFlagDisabled until
        //       canonical JobPosting model is reviewed. Included here, gate at call site.
        m["job_hire"] = TransformConfig(
            targetObjectType: "job",
            defaultAudience: "publicFeed",
            roomType: nil,
            moderationTier: .medium,
            allowedActions: [.save, .share, .invite]
        )
        m["job_announce"] = TransformConfig(
            targetObjectType: "post",
            defaultAudience: "churchOnly",
            roomType: nil,
            moderationTier: .high,
            allowedActions: [.share, .invite]
        )

        // MARK: MediaObject × intents
        m["mediaObject_share"] = TransformConfig(
            targetObjectType: "post",
            defaultAudience: "source",
            roomType: nil,
            moderationTier: .medium,
            allowedActions: [.share, .save]
        )
        m["mediaObject_discuss"] = TransformConfig(
            targetObjectType: "discussion",
            defaultAudience: "spaceMembers",
            roomType: .discussion,
            moderationTier: .medium,
            allowedActions: [.discuss]
        )
        m["mediaObject_pray"] = TransformConfig(
            targetObjectType: "actionThread",
            defaultAudience: "private",
            roomType: nil,
            moderationTier: .low,
            allowedActions: [.pray]
        )
        m["mediaObject_teach"] = TransformConfig(
            targetObjectType: "post",
            defaultAudience: "spaceMembers",
            roomType: nil,
            moderationTier: .high,
            allowedActions: [.share]
        )
        m["mediaObject_ask"] = TransformConfig(
            targetObjectType: "actionThread",
            defaultAudience: "private",
            roomType: nil,
            moderationTier: .low,
            allowedActions: [.discuss]
        )
        m["mediaObject_announce"] = TransformConfig(
            targetObjectType: "post",
            defaultAudience: "churchOnly",
            roomType: nil,
            moderationTier: .high,
            allowedActions: [.share]
        )

        return m
    }()
    // swiftlint:enable function_body_length

    // MARK: - transform()

    /// Look up the transform matrix and create a `SpawnProvenance` record.
    ///
    /// - Parameters:
    ///   - sourceType: ObjectType of the originating object.
    ///   - sourceRef: Firestore document path, e.g. "/posts/abc123".
    ///   - sourceOwnerId: UID of the original object's owner.
    ///   - intent: One of the 11 canonical C2 intents.
    ///   - actorId: Firebase Auth UID of the user initiating the transform.
    ///   - audience: Optional caller-supplied audience override (not yet clamped here;
    ///               clamping is the caller's responsibility using `matrixKey` + config).
    /// - Returns: `(config, provenance)` pair. The caller writes both to Firestore.
    /// - Throws: `TransformError.unsupportedCombination` if the cell is blocked.
    ///           `TransformError.missingRequiredProvenance` if actorId is empty.
    func transform(
        sourceType: ObjectType,
        sourceRef: String,
        sourceOwnerId: String,
        intent: Intent,
        actorId: String,
        audience: String?
    ) throws -> (config: TransformConfig, provenance: SpawnProvenance) {
        // Guard: actor must be non-empty (caller should already validate Auth).
        guard !actorId.isEmpty else {
            throw TransformError.missingRequiredProvenance(field: "actorId")
        }

        let key = AmenTransformEngine.matrixKey(source: sourceType, intent: intent)
        guard let config = AmenTransformEngine.matrix[key] else {
            throw TransformError.unsupportedCombination(
                sourceType: sourceType.rawValue,
                intent: intent
            )
        }

        // Provenance: iOS client sets sourceRef, sourceType, intent, sourceOwnerId.
        // createdAt is always set server-side; we use Date() as a placeholder here —
        // the Firestore write in AmenObjectRepository uses FieldValue.serverTimestamp().
        let provenance = SpawnProvenance(
            sourceType: sourceType.rawValue,
            sourceRef: sourceRef.isEmpty ? nil : sourceRef,
            sourceOwnerId: sourceOwnerId.isEmpty ? nil : sourceOwnerId,
            intent: intent.rawValue,
            createdAt: Date()   // NOTE: overwritten by FieldValue.serverTimestamp() in repository
        )

        return (config, provenance)
    }

    // MARK: - isSupported()

    /// Returns `true` if the (sourceType × intent) combination is in the matrix.
    /// No Firestore I/O.
    func isSupported(sourceType: ObjectType, intent: Intent) -> Bool {
        let key = AmenTransformEngine.matrixKey(source: sourceType, intent: intent)
        return AmenTransformEngine.matrix[key] != nil
    }

    // MARK: - config(for:intent:)

    /// Returns the TransformConfig for a given combination, or nil if blocked.
    func config(for sourceType: ObjectType, intent: Intent) -> TransformConfig? {
        let key = AmenTransformEngine.matrixKey(source: sourceType, intent: intent)
        return AmenTransformEngine.matrix[key]
    }
}
