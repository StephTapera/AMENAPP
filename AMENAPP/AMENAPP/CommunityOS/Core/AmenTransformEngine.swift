// AmenTransformEngine.swift
// AMEN App — CommunityOS / Core
//
// Phase 1 — Agent A1 (Core Platform Architecture)
// In-process transform matrix engine implementing C2 §4.
//
// DISTINCT FROM:
//   FirebaseTransformEngine (TransformEngine.swift) — CF-backed async actor.
//   AmenTransform (TransformEngine.swift)            — static intent/tier helpers.
//
// This class is synchronous (no Firestore I/O) and provides:
//   1. TransformConfig — per-cell configuration returned by matrix lookup.
//   2. AmenTransformEngine — class with transform()/isSupported()/config(for:) API.
//
// SHARED TYPES (do NOT redefine here):
//   AmenObjectType, AmenIntent  →  CommunityObjectTypes.swift
//   ModerationTier, TransformError, SpawnProvenance  →  TransformEngine.swift / CommunityObjectTypes.swift
//   ObjectCapability  →  CommunityObjectTypes.swift

import Foundation
import FirebaseAuth

// MARK: - TransformConfig

/// Per-cell configuration produced by the transform matrix lookup.
/// Distinct from `TransformResult` (which is the full async CF response).
struct TransformConfig: Sendable {
    /// AmenObjectType raw value of the derived object (e.g. "discussion", "actionThread").
    let targetObjectType: String
    /// Default audience tier string per C2 §2.3.
    let defaultAudience: String
    /// Room type hint — non-nil only for Discuss intent outputs.
    let roomType: DiscussionRoomType?
    /// Moderation tier for the output per C2 §2.4.
    let moderationTier: ModerationTier
    /// Allowed capability actions on the output object.
    let allowedActions: [ObjectCapability]
}

// MARK: - AmenTransformEngine

/// In-process transform matrix engine. Implements the C2 §4 matrix as a static
/// dictionary keyed by "\(sourceType.rawValue)_\(intent.rawValue)".
///
/// No Firestore I/O — pure matrix lookup + provenance creation.
/// The Firestore write path lives in AmenObjectRepository.createSpawnedObject().
///
/// Usage:
/// ```swift
/// let engine = AmenTransformEngine()
/// let (config, provenance) = try engine.transform(
///     sourceType: .post, sourceRef: "/posts/abc",
///     sourceOwnerId: "uid", intent: .discuss, actorId: "uid2", audience: nil
/// )
/// ```
final class AmenTransformEngine {

    // MARK: - Matrix Key Helper

    /// Produces the dictionary key for a given (source, intent) pair.
    static func matrixKey(source: AmenObjectType, intent: AmenIntent) -> String {
        "\(source.rawValue)_\(intent.rawValue)"
    }

    // MARK: - Transform Matrix
    //
    // Cells marked `–` in C2 §4.1 are absent from this dictionary.
    // Missing entries cause transform() to throw TransformError.unsupportedCombination.
    //
    // Coverage in this build:
    //   Post × all non-blocked intents
    //   Prayer × (discuss | pray | ask | mentor)
    //   BereanInsight × (share | discuss | pray | study | teach | ask | mentor | announce)
    //   ChurchNote × (share | discuss | pray | study | teach | ask | announce)
    //   Event × (share | discuss | pray | teach | ask | invite | volunteer | announce)
    //   Job × (share | discuss | ask | hire | announce)
    //   MediaObject × (share | discuss | pray | teach | ask | announce)
    //
    // OPEN: Full 13×11 matrix — remaining source types (Sermon, Message, SpaceObject,
    //       OrganizationObject, ScriptureReference, MentorshipRequest) to be added
    //       once those models are fully authored.

    // swiftlint:disable function_body_length
    static let matrix: [String: TransformConfig] = {
        var m = [String: TransformConfig]()

        // MARK: Post × all intents
        m["post_share"] = TransformConfig(
            targetObjectType: "post",
            defaultAudience: "source",
            roomType: nil,
            moderationTier: .medium,
            allowedActions: [.share, .save, .discuss, .pray]
        )
        m["post_discuss"] = TransformConfig(
            targetObjectType: "discussion",
            defaultAudience: "space_members",
            roomType: .general,
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
            targetObjectType: "post",
            defaultAudience: "space_members",
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
            defaultAudience: "space_members",
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
            defaultAudience: "church_only",
            roomType: nil,
            moderationTier: .high,
            allowedActions: [.share, .discuss]
        )
        // post_volunteer: blocked (–)
        // post_hire: blocked (–)

        // MARK: Prayer × intents
        // prayer_share: BLOCKED — prayer content cannot be shared without creator approval
        m["prayer_discuss"] = TransformConfig(
            targetObjectType: "discussion",
            defaultAudience: "trusted_circle",
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
        // prayer_announce: BLOCKED — prayer requests may not be announced

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
            defaultAudience: "space_members",
            roomType: .bibleStudy,
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
        // OPEN: BereanInsight→Teach allowed at High tier as compromise for doctrinal risk.
        m["bereanInsight_teach"] = TransformConfig(
            targetObjectType: "post",
            defaultAudience: "space_members",
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
            defaultAudience: "church_only",
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
            defaultAudience: "space_members",
            roomType: .bibleStudy,
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
            defaultAudience: "space_members",
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
            defaultAudience: "church_only",
            roomType: nil,
            moderationTier: .high,
            allowedActions: [.share]
        )

        // MARK: Event × intents
        m["event_share"] = TransformConfig(
            targetObjectType: "post",
            defaultAudience: "space_members",
            roomType: nil,
            moderationTier: .medium,
            allowedActions: [.share, .save, .invite]
        )
        m["event_discuss"] = TransformConfig(
            targetObjectType: "discussion",
            defaultAudience: "space_members",
            roomType: .general,
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
            defaultAudience: "space_members",
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
            defaultAudience: "space_members",
            roomType: nil,
            moderationTier: .low,
            allowedActions: [.invite, .share]
        )
        m["event_volunteer"] = TransformConfig(
            targetObjectType: "volunteerOpportunity",
            defaultAudience: "space_members",
            roomType: nil,
            moderationTier: .low,
            allowedActions: [.invite, .followUp]
        )
        m["event_announce"] = TransformConfig(
            targetObjectType: "post",
            defaultAudience: "church_only",
            roomType: nil,
            moderationTier: .high,
            allowedActions: [.share, .invite]
        )

        // MARK: Job × intents
        m["job_share"] = TransformConfig(
            targetObjectType: "post",
            defaultAudience: "public_feed",
            roomType: nil,
            moderationTier: .medium,
            allowedActions: [.share, .save]
        )
        m["job_discuss"] = TransformConfig(
            targetObjectType: "discussion",
            defaultAudience: "space_members",
            roomType: .general,
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
        // OPEN: Job→Hire gated behind featureFlagDisabled until canonical JobPosting reviewed.
        m["job_hire"] = TransformConfig(
            targetObjectType: "job",
            defaultAudience: "public_feed",
            roomType: nil,
            moderationTier: .medium,
            allowedActions: [.save, .share, .invite]
        )
        m["job_announce"] = TransformConfig(
            targetObjectType: "post",
            defaultAudience: "church_only",
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
            defaultAudience: "space_members",
            roomType: .general,
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
            defaultAudience: "space_members",
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
            defaultAudience: "church_only",
            roomType: nil,
            moderationTier: .high,
            allowedActions: [.share]
        )

        return m
    }()
    // swiftlint:enable function_body_length

    // MARK: - transform()

    /// Looks up the matrix and creates a `SpawnProvenance` record.
    /// No Firestore I/O. The caller writes the derived object and provenance.
    ///
    /// - Parameters:
    ///   - sourceType: AmenObjectType of the originating object.
    ///   - sourceRef: Firestore document path, e.g. "/posts/abc123".
    ///   - sourceOwnerId: UID of the original object's owner.
    ///   - intent: One of the 11 canonical C2 intents.
    ///   - actorId: Firebase Auth UID of the initiating user.
    ///   - audience: Optional caller-supplied audience override (nil = use matrix default).
    /// - Returns: `(config, provenance)` pair. Caller writes both to Firestore.
    /// - Throws: `TransformError.unsupportedCombination` if the cell is blocked.
    ///           `TransformError.missingRequiredProvenance` if actorId is empty.
    func transform(
        sourceType: AmenObjectType,
        sourceRef: String,
        sourceOwnerId: String,
        intent: AmenIntent,
        actorId: String,
        audience: String?
    ) throws -> (config: TransformConfig, provenance: SpawnProvenance) {
        guard !actorId.isEmpty else {
            throw TransformError.missingRequiredProvenance(field: "actorId")
        }

        let key = AmenTransformEngine.matrixKey(source: sourceType, intent: intent)
        guard let config = AmenTransformEngine.matrix[key] else {
            throw TransformError.unsupportedCombination(
                sourceType: sourceType,
                intent: intent
            )
        }

        // Provenance: iOS sets source fields; createdAt placeholder is overwritten
        // by FieldValue.serverTimestamp() in AmenObjectRepository.
        let provenance = SpawnProvenance(
            sourceType: sourceType.rawValue,
            sourceRef: sourceRef.isEmpty ? nil : sourceRef,
            sourceOwnerId: sourceOwnerId.isEmpty ? nil : sourceOwnerId,
            intent: intent.rawValue,
            createdAt: Date()    // NOTE: overwritten by FieldValue.serverTimestamp() in repo
        )

        return (config, provenance)
    }

    // MARK: - isSupported()

    /// Returns true if the (sourceType × intent) combination is in the matrix.
    func isSupported(sourceType: AmenObjectType, intent: AmenIntent) -> Bool {
        AmenTransformEngine.matrix[matrixKey(source: sourceType, intent: intent)] != nil
    }

    // MARK: - config(for:intent:)

    /// Returns the TransformConfig for a combination, or nil if blocked.
    func config(for sourceType: AmenObjectType, intent: AmenIntent) -> TransformConfig? {
        AmenTransformEngine.matrix[AmenTransformEngine.matrixKey(source: sourceType, intent: intent)]
    }

    // MARK: - Private

    private func matrixKey(source: AmenObjectType, intent: AmenIntent) -> String {
        AmenTransformEngine.matrixKey(source: source, intent: intent)
    }
}
