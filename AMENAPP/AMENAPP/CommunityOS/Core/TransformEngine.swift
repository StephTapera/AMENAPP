// TransformEngine.swift
// AMENAPP — CommunityOS / Core
//
// Phase 1 Core Spine: transform operation contract, result type,
// moderation tier, and the Firebase-backed stub implementation.
//
// Source contracts: C2 §5 "Transform Operation Contract"
//
// Usage is gated behind AMENFeatureFlags.shared.communityOSEnabled.

import Foundation
import FirebaseFunctions

// MARK: - ModerationTier

/// Moderation pipeline review level applied to transform output objects.
/// Source: C2 §2.4 "Moderation Tier per Intent".
enum ModerationTier: String, Codable, Sendable {
    case low    = "low"
    case medium = "medium"
    case high   = "high"
    case severe = "severe"
}

// MARK: - TransformError

/// Hard failures thrown (not returned as optionals) by any TransformEngine implementation.
/// Source: C2 §5.5 "Error Cases".
enum TransformError: Error, Sendable {
    /// The (sourceType × intent) cell in the transform matrix is blocked (`–`).
    case unsupportedCombination(sourceType: AmenObjectType, intent: AmenIntent)
    /// Actor lacks the minimum role required to trigger this intent.
    case actorNotAuthorized(requiredRole: AmenRole)
    /// The `sourceRef` document does not resolve in Firestore.
    case sourceObjectNotFound
    /// Firestore transaction to write the immutable provenance document failed.
    case provenanceWriteFailed
    /// Caller attempted to set audience wider than the matrix-defined ceiling.
    case audienceCapExceeded
    /// A required Remote Config flag is disabled.
    case featureFlagDisabled(flagName: String)
    /// Hire intent was attempted without a verified organization.
    case orgNotVerified
    /// Mentor intent was attempted; the mentor has not yet consented.
    case mentorConsentPending
    /// A required provenance field could not be resolved.
    case missingRequiredProvenance(field: String)
}

// MARK: - TransformResult

/// The outcome of a successful transform operation.
/// Source: C2 §5.2 "TransformResult".
///
/// A `TransformResult` with empty `provenance` must never be returned;
/// implementations that cannot guarantee provenance must throw
/// `TransformError.missingRequiredProvenance`. (C2 §6 Provenance Integrity Rule.)
struct TransformResult: Sendable {
    /// Firestore document ID of the newly created derived object.
    let newObjectId: String
    /// Type of the newly created derived object.
    let newObjectType: AmenObjectType
    /// Firestore document path of the newly created derived object.
    let newObjectRef: String
    /// Immutable provenance written to Firestore alongside the object.
    let provenance: SpawnProvenance
    /// The audience raw value actually applied after clamping to the matrix ceiling.
    let appliedAudience: String
    /// Moderation pipeline tier applied to the output.
    let moderationTier: ModerationTier
    /// Non-nil for `discuss` intent only — the ID of the created DiscussionRoom.
    let roomId: String?
    /// Non-nil for `pray` intent only — the ID of the created ActionThread.
    let actionThreadId: String?
    /// Non-fatal advisory messages (e.g., audience was clamped from wider request).
    let warnings: [String]
}

// MARK: - TransformEngine (Protocol)

/// Contract for all transform engine implementations.
///
/// Conforming types MUST enforce the provenance integrity rule (C2 §6):
/// a `TransformResult` with a nil or empty `provenance` must never be returned.
protocol TransformEngine: Actor {
    func transform(
        sourceRef: String,
        sourceType: AmenObjectType,
        intent: AmenIntent,
        actorId: String,
        audienceOverride: String?
    ) async throws -> TransformResult
}

// MARK: - FirebaseTransformEngine

/// Stub implementation of `TransformEngine` that calls the `transformObject`
/// Cloud Function via Firebase Callable Functions.
///
/// The `transformObject` CF does not yet exist in production — this stub is
/// wired to call it correctly once deployed. All calls gate on
/// `AMENFeatureFlags.shared.communityOSEnabled`.
actor FirebaseTransformEngine: TransformEngine {

    private let functions: Functions

    init(functions: Functions = Functions.functions()) {
        self.functions = functions
    }

    func transform(
        sourceRef: String,
        sourceType: AmenObjectType,
        intent: AmenIntent,
        actorId: String,
        audienceOverride: String?
    ) async throws -> TransformResult {

        guard await AMENFeatureFlags.shared.communityOSEnabled else {
            throw TransformError.featureFlagDisabled(flagName: "communityOSEnabled")
        }

        guard !actorId.isEmpty else {
            throw TransformError.actorNotAuthorized(requiredRole: .visitor)
        }

        var payload: [String: Any] = [
            "sourceRef": sourceRef,
            "sourceType": sourceType.rawValue,
            "intent": intent.rawValue,
            "actorId": actorId
        ]
        if let override = audienceOverride {
            payload["audienceOverride"] = override
        }

        let callable = functions.httpsCallable("transformObject")
        let result = try await callable.call(payload)

        guard let data = result.data as? [String: Any] else {
            throw TransformError.provenanceWriteFailed
        }

        return try TransformResult(from: data)
    }
}

// MARK: - TransformResult + Decoding helper

private extension TransformResult {
    init(from data: [String: Any]) throws {
        guard
            let newObjectId   = data["newObjectId"]   as? String,
            let newObjectTypeRaw = data["newObjectType"] as? String,
            let newObjectType = AmenObjectType(rawValue: newObjectTypeRaw),
            let newObjectRef  = data["newObjectRef"]  as? String,
            let appliedAudience = data["appliedAudience"] as? String,
            let moderationTierRaw = data["moderationTier"] as? String,
            let moderationTier = ModerationTier(rawValue: moderationTierRaw)
        else {
            throw TransformError.missingRequiredProvenance(field: "core_fields")
        }

        // Decode provenance sub-dictionary
        guard let provenanceDict = data["provenance"] as? [String: Any] else {
            throw TransformError.missingRequiredProvenance(field: "provenance")
        }
        guard
            let sourceType    = provenanceDict["sourceType"] as? String,
            let intent        = provenanceDict["intent"]     as? String
        else {
            throw TransformError.missingRequiredProvenance(field: "provenance.sourceType or provenance.intent")
        }

        // `createdAt` is server-set — decode from epoch seconds or use now as fallback
        let createdAt: Date
        if let epochSeconds = provenanceDict["createdAt"] as? TimeInterval {
            createdAt = Date(timeIntervalSince1970: epochSeconds)
        } else {
            createdAt = Date()
        }

        let provenance = SpawnProvenance(
            sourceType: sourceType,
            sourceRef: provenanceDict["sourceRef"] as? String,
            sourceOwnerId: provenanceDict["sourceOwnerId"] as? String,
            intent: intent,
            createdAt: createdAt
        )

        self.init(
            newObjectId: newObjectId,
            newObjectType: newObjectType,
            newObjectRef: newObjectRef,
            provenance: provenance,
            appliedAudience: appliedAudience,
            moderationTier: moderationTier,
            roomId: data["roomId"] as? String,
            actionThreadId: data["actionThreadId"] as? String,
            warnings: data["warnings"] as? [String] ?? []
        )
    }
}

// MARK: - AmenTransform (Static helpers)

/// Static helpers for working with the transform matrix (C2 §4).
enum AmenTransform {

    /// Returns the intents that are valid for a given source object type,
    /// based on the C2 §4 transform matrix. Cells marked `–` are excluded.
    static func availableIntents(for objectType: AmenObjectType) -> [AmenIntent] {
        switch objectType {
        case .churchNote:
            // Row: ChurchNote — blocked: volunteer, hire, mentor, invite
            return [.share, .discuss, .pray, .study, .teach, .ask, .announce]

        case .bereanInsight:
            // Row: BereanInsight — blocked: volunteer, hire, invite
            return [.share, .discuss, .pray, .study, .teach, .ask, .mentor, .announce]

        case .mediaObject:
            // Row: MediaObject — blocked: pray, study, volunteer, hire, mentor, invite
            return [.share, .discuss, .pray, .teach, .ask, .announce]

        case .post:
            // Row: Post — blocked: volunteer, hire
            return [.share, .discuss, .pray, .study, .teach, .ask, .invite, .mentor, .announce]

        case .prayer:
            // Row: PrayerRequest — blocked: share, study, teach, invite, volunteer, hire, announce
            return [.discuss, .pray, .ask, .mentor]

        case .event:
            // Row: Event — blocked: study, hire, mentor
            return [.share, .discuss, .pray, .teach, .ask, .invite, .volunteer, .announce]

        case .job:
            // Row: Job — blocked: pray, study, teach, volunteer, mentor
            return [.share, .discuss, .ask, .invite, .hire, .announce]

        case .mentorship:
            // Row: MentorshipRequest — blocked: share, discuss, teach, invite, volunteer, hire, announce
            return [.pray, .study, .ask, .mentor]

        case .moment:
            // Row: Message — blocked: share, study, teach, invite, volunteer, hire, announce
            return [.discuss, .pray, .ask, .mentor]

        case .space:
            // Row: SpaceObject — blocked: hire, mentor
            return [.share, .discuss, .pray, .study, .teach, .ask, .invite, .volunteer, .announce]

        case .organization, .church:
            // Row: OrganizationObject — blocked: mentor
            return [.share, .discuss, .pray, .study, .teach, .ask, .invite, .volunteer, .hire, .announce]

        case .discussion:
            // Row: DiscussionRoom as source — limited re-spawn surface
            return [.discuss, .pray, .ask]

        case .volunteerOpportunity:
            // Row: VolunteerOpportunity — blocked: hire, mentor
            return [.share, .discuss, .pray, .teach, .ask, .invite, .volunteer, .announce]

        case .study:
            // Study objects as source — same as BereanInsight shape
            return [.share, .discuss, .pray, .study, .teach, .ask, .mentor, .announce]

        case .actionThread:
            // ActionThread is a destination type; as a source it uses a subset
            return [.discuss, .pray, .ask]

        case .user, .team:
            // Users and teams are not primary transform sources in C2
            return [.share, .discuss, .pray, .invite, .mentor, .announce]
        }
    }

    /// Returns the default moderation tier for a given intent.
    /// Source: C2 §2.4 "Moderation Tier per Intent".
    static func moderationTier(for intent: AmenIntent) -> ModerationTier {
        switch intent {
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
