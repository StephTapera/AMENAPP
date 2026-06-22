// TrustSpineService.swift
// AMENAPP
//
// Phase 1 — System 35: Trust Spine.
// Single source of truth for backend-authoritative trust metadata
// (media provenance, AI disclosures, content reports).
//
// All trust metadata must be backend-written. The iOS client only requests
// records and reads results. Never write provenance/disclosure documents
// directly from this service — that is what Cloud Functions exist for.
//
// Non-negotiable contract:
//   - authenticityConfidence, syntheticMediaStatus, disclosureRequired,
//     disclosureSatisfied, and userVisibleLabel/Explanation are all
//     SERVER-DERIVED. The client surfaces them, never invents them.

import Foundation
import FirebaseFunctions

@MainActor
final class TrustSpineService: ObservableObject {

    static let shared = TrustSpineService()

    private let functions: Functions

    private init(functions: Functions = Functions.functions()) {
        self.functions = functions
    }

    // MARK: - Provenance

    /// Registers media provenance with the backend. The server derives
    /// authenticityConfidence + syntheticMediaStatus; the caller only
    /// provides raw capture/source/edit inputs.
    struct RegisterProvenanceInput {
        let postId: String
        let mediaId: String
        let capturedOnDevice: Bool
        let sourceType: MediaProvenance.MediaSourceType
        let contentCredentialsStatus: MediaProvenance.ContentCredentialsStatus
        let editEvents: [ProvenanceEditEvent]
        let aiEvents: [ProvenanceAIEvent]
    }

    struct RegisterProvenanceResult: Decodable {
        let provenanceId: String
        let authenticityConfidence: Double
        let syntheticMediaStatus: String
        let disclosureRequired: Bool
    }

    func registerMediaProvenance(_ input: RegisterProvenanceInput) async throws -> RegisterProvenanceResult {
        let payload: [String: Any] = [
            "postId": input.postId,
            "mediaId": input.mediaId,
            "capturedOnDevice": input.capturedOnDevice,
            "sourceType": input.sourceType.rawValue,
            "contentCredentialsStatus": input.contentCredentialsStatus.rawValue,
            "editEvents": input.editEvents.map { e in
                [
                    "editType": e.editType,
                    "tool": e.tool as Any,
                    "aiAssisted": e.aiAssisted,
                ]
            },
            "aiEvents": input.aiEvents.map { e in
                [
                    "actionType": e.actionType,
                    "provider": e.provider as Any,
                    "purpose": e.purpose,
                    "userApproved": e.userApproved,
                ]
            },
        ]

        let result = try await functions
            .httpsCallable("registerMediaProvenance")
            .call(payload)

        return try decode(RegisterProvenanceResult.self, from: result.data)
    }

    struct ProvenanceSummary: Decodable {
        let status: String
        let provenanceId: String?
        let postId: String?
        let mediaId: String?
        let ownerUid: String?
        let capturedOnDevice: Bool?
        let sourceType: String?
        let authenticityConfidence: Double?
        let contentCredentialsStatus: String?
        let syntheticMediaStatus: String?
        let disclosureRequired: Bool?
        let disclosureSatisfied: Bool?
        let moderationStatus: String?
    }

    func getPostProvenance(postId: String, mediaId: String) async throws -> ProvenanceSummary {
        let result = try await functions
            .httpsCallable("getPostProvenance")
            .call([
                "postId": postId,
                "mediaId": mediaId,
            ])
        return try decode(ProvenanceSummary.self, from: result.data)
    }

    // MARK: - AI Disclosures

    /// User-visible AI disclosure action types. The label + explanation
    /// shown in UI come from the SERVER, not from this enum — the enum
    /// only constrains what the client may request.
    enum AIDisclosureActionType: String {
        case aiAssisted = "ai_assisted"
        case aiEdited = "ai_edited"
        case aiGenerated = "ai_generated"
        case aiTranslated = "ai_translated"
        case aiSummarized = "ai_summarized"
        case aiEnhancedAudio = "ai_enhanced_audio"
        case aiEnhancedLighting = "ai_enhanced_lighting"
        case aiSuggestedCaption = "ai_suggested_caption"
        case aiSafetyReviewed = "ai_safety_reviewed"
        case aiAltText = "ai_alt_text"
    }

    struct RegisterAIDisclosureInput {
        let postId: String
        let mediaId: String
        let actionType: AIDisclosureActionType
        let modelProvider: String?
        let purpose: String
        let confidence: Double
    }

    struct RegisterAIDisclosureResult: Decodable {
        let disclosureId: String
        let userVisibleLabel: String
        let userVisibleExplanation: String
    }

    func registerAIDisclosure(_ input: RegisterAIDisclosureInput) async throws -> RegisterAIDisclosureResult {
        var payload: [String: Any] = [
            "postId": input.postId,
            "mediaId": input.mediaId,
            "actionType": input.actionType.rawValue,
            "purpose": input.purpose,
            "confidence": input.confidence,
        ]
        if let provider = input.modelProvider {
            payload["modelProvider"] = provider
        }

        let result = try await functions
            .httpsCallable("registerAIDisclosure")
            .call(payload)
        return try decode(RegisterAIDisclosureResult.self, from: result.data)
    }

    struct AIDisclosureFetchResult: Decodable {
        let records: [AIDisclosureRecord]
    }

    func getAIDisclosureDetails(postId: String, mediaId: String) async throws -> [AIDisclosureRecord] {
        let result = try await functions
            .httpsCallable("getAIDisclosureDetails")
            .call([
                "postId": postId,
                "mediaId": mediaId,
            ])
        return try decode(AIDisclosureFetchResult.self, from: result.data).records
    }

    // MARK: - Publish Trust Gate (Phase 2)

    struct PublishTrustGateResult: Decodable {
        let ok: Bool
        let postId: String
        let mediaCount: Int
    }

    /// Validates that provenance + AI disclosures exist for every media item
    /// in the post. If a gate fails the underlying Cloud Function throws an
    /// HttpsError("failed-precondition", "Trust gates failed", { failures }).
    /// The composer should surface failures to the user and BLOCK publish
    /// until they are resolved. This is enforcement, not a suggestion —
    /// the spec is explicit that publish must be blocked when AI disclosure
    /// is missing, provenance is missing, or moderation fails.
    func publishPostWithTrustGates(postId: String, mediaIds: [String]) async throws -> PublishTrustGateResult {
        do {
            let result = try await functions
                .httpsCallable("publishPostWithTrustGates")
                .call([
                    "postId": postId,
                    "mediaIds": mediaIds,
                ])
            let decoded = try decode(PublishTrustGateResult.self, from: result.data)
            TrustSpineAnalytics.track(.publishTrustGatePassed, params: [
                "post_id": postId,
                "media_count": decoded.mediaCount,
            ])
            return decoded
        } catch {
            TrustSpineAnalytics.track(.publishTrustGateFailed, params: [
                "post_id": postId,
                "media_count": mediaIds.count,
            ])
            throw error
        }
    }

    // MARK: - Discovery Transparency (Phase 4)

    /// One reason the ranker surfaced a post — server-derived. The client
    /// never invents these labels; they come from a static map on the
    /// backend, keyed by the code string. The icon name is an SF Symbol.
    struct DiscoveryReasonRow: Decodable, Identifiable {
        let code: String
        let label: String
        let explanation: String
        let icon: String
        let weight: Double

        var id: String { code }
    }

    struct DiscoveryReasonsResult: Decodable {
        let postId: String
        let reasons: [DiscoveryReasonRow]
    }

    /// Asks the backend why this post is in the caller's feed. Returns an
    /// ordered list of reasons (heaviest first). UI is responsible for
    /// rendering — but must show only what the server returned.
    func getDiscoveryReasons(postId: String) async throws -> DiscoveryReasonsResult {
        let result = try await functions
            .httpsCallable("getDiscoveryReasons")
            .call(["postId": postId])
        return try decode(DiscoveryReasonsResult.self, from: result.data)
    }

    // MARK: - Reports

    enum ReportTargetType: String {
        case post
        case comment
        case media
        case user
        case message
        case community
        case provenance
        case prayerRequest = "prayer_request"
        case ministryRoomMessage = "ministry_room_message"
    }

    enum ReportReason: String {
        case spam
        case harassment
        case scam
        case selfHarm = "self_harm"
        case hateSpeech = "hate_speech"
        case violence
        case sexualContent = "sexual_content"
        case minorSafety = "minor_safety"
        case misinformation
        case syntheticMedia = "synthetic_media"
        case aiUndisclosed = "ai_undisclosed"
        case intellectualProperty = "intellectual_property"
        case other
    }

    struct ReportResult: Decodable {
        let reportId: String
        let status: String
    }

    func reportContent(
        targetType: ReportTargetType,
        targetId: String,
        reason: ReportReason,
        details: String? = nil
    ) async throws -> ReportResult {
        var payload: [String: Any] = [
            "targetType": targetType.rawValue,
            "targetId": targetId,
            "reason": reason.rawValue,
        ]
        if let details, !details.isEmpty {
            payload["details"] = details
        }
        let result = try await functions
            .httpsCallable("reportContent")
            .call(payload)
        return try decode(ReportResult.self, from: result.data)
    }

    // MARK: - Decoding helper

    private func decode<T: Decodable>(_ type: T.Type, from data: Any?) throws -> T {
        guard let data else {
            throw TrustSpineError.emptyResponse
        }
        let json = try JSONSerialization.data(withJSONObject: data)
        return try JSONDecoder().decode(T.self, from: json)
    }

    // MARK: - Errors

    enum TrustSpineError: Error, LocalizedError {
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .emptyResponse:
                return "Trust Spine returned an empty response."
            }
        }
    }
}
