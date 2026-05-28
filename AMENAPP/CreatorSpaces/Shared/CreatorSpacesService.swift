import Foundation
import FirebaseFirestore
import FirebaseFunctions
import FirebaseStorage

@MainActor
final class CreatorSpacesService: ObservableObject {
    static let shared = CreatorSpacesService()

    private lazy var functions = Functions.functions()

    private init() {}

    func processMediaUpload(_ draft: CreatorMediaAssetDraft) async throws -> CreatorMediaUploadResult {
        let result = try await functions.httpsCallable("processMediaUpload").call(draft.payload)
        guard let data = result.data as? [String: Any],
              let assetId = data["assetId"] as? String,
              let labelId = data["labelId"] as? String else {
            throw CreatorSpacesServiceError.invalidResponse
        }
        return CreatorMediaUploadResult(assetId: assetId, labelId: labelId)
    }

    func getDailyPortion(cursor: String? = nil) async throws -> CreatorDailyPortionResponse {
        var payload: [String: Any] = [:]
        if let cursor { payload["cursor"] = cursor }

        let result = try await functions.httpsCallable("getDailyPortion").call(payload)
        guard let data = result.data as? [String: Any] else {
            throw CreatorSpacesServiceError.invalidResponse
        }
        return CreatorDailyPortionResponse(
            items: data["items"] as? [String] ?? [],
            exhausted: data["exhausted"] as? Bool ?? true,
            nextCursor: data["nextCursor"] as? String
        )
    }

    func fetchRenderableMediaAssets(ids: [String]) async throws -> [CreatorRenderableMediaAsset] {
        guard !ids.isEmpty else { return [] }

        var assets: [CreatorRenderableMediaAsset] = []
        for assetId in ids {
            let document = try await Firestore.firestore().collection("mediaAssets").document(assetId).getDocument()
            guard let data = document.data(),
                  let frames = data["frames"] as? [String: Any],
                  let media = try await renderableMedia(from: frames, assetId: assetId) else {
                continue
            }

            let type = data["type"] as? String ?? CreatorMediaAssetType.presence.rawValue
            let moderation = data["moderation"] as? [String: Any]
            let moderationStatus = moderation?["status"] as? String ?? CreatorMediaModerationStatus.pending.rawValue
            assets.append(CreatorRenderableMediaAsset(
                assetId: assetId,
                type: type,
                moderationStatus: moderationStatus,
                media: media
            ))
        }
        return assets
    }

    func recordEditEvent(assetId: String, tool: String, aiInvolved: Bool) async throws {
        _ = try await functions.httpsCallable("recordEditEvent").call([
            "assetId": assetId,
            "tool": tool,
            "aiInvolved": aiInvolved
        ])
    }

    func runSafetyCheck(_ draft: CreatorMediaAssetDraft) async throws -> CreatorSpacesSafetyCheckResult {
        let result = try await functions.httpsCallable("runSafetyCheck").call(draft.payload)
        guard let data = result.data as? [String: Any],
              let decision = data["decision"] as? String else {
            throw CreatorSpacesServiceError.invalidResponse
        }
        return CreatorSpacesSafetyCheckResult(
            decision: decision,
            reasons: data["reasons"] as? [String] ?? []
        )
    }

    func queryMemoryGraph(_ naturalLanguage: String) async throws -> [String] {
        let result = try await functions.httpsCallable("queryMemoryGraph").call([
            "naturalLanguage": naturalLanguage
        ])
        guard let data = result.data as? [String: Any] else {
            throw CreatorSpacesServiceError.invalidResponse
        }
        return data["nodeIds"] as? [String] ?? []
    }

    func createPaidListing(_ input: CreatorSpacePaidListingInput) async throws -> String {
        let result = try await functions.httpsCallable("createCreatorSpacePaidListing").call([
            "spaceId": input.spaceId,
            "title": input.title,
            "description": input.description,
            "kind": input.kind.rawValue,
            "stripePriceId": input.stripePriceId,
            "visibility": input.visibility
        ])
        guard let data = result.data as? [String: Any],
              let listingId = data["listingId"] as? String else {
            throw CreatorSpacesServiceError.invalidResponse
        }
        return listingId
    }

    func createCheckoutSession(spaceId: String, listingId: String) async throws -> CreatorSpaceCheckoutResult {
        let result = try await functions.httpsCallable("createCreatorSpaceCheckoutSession").call([
            "spaceId": spaceId,
            "listingId": listingId
        ])
        guard let data = result.data as? [String: Any],
              let checkoutId = data["checkoutId"] as? String else {
            throw CreatorSpacesServiceError.invalidResponse
        }
        let urlString = data["url"] as? String
        return CreatorSpaceCheckoutResult(checkoutId: checkoutId, url: urlString.flatMap(URL.init(string:)))
    }

    func checkEntitlement(spaceId: String, listingId: String) async throws -> CreatorSpaceEntitlementStatus {
        let result = try await functions.httpsCallable("checkCreatorSpaceEntitlement").call([
            "spaceId": spaceId,
            "listingId": listingId
        ])
        guard let data = result.data as? [String: Any] else {
            throw CreatorSpacesServiceError.invalidResponse
        }
        return CreatorSpaceEntitlementStatus(
            accessGranted: data["accessGranted"] as? Bool ?? false,
            status: data["status"] as? String ?? "none"
        )
    }

    private func renderableMedia(from frames: [String: Any], assetId: String) async throws -> PostMediaContainer? {
        let preferredFrame = (frames["composite"] as? [String: Any])
            ?? (frames["back"] as? [String: Any])
            ?? (frames["front"] as? [String: Any])

        guard let frame = preferredFrame,
              let storagePath = frame["storagePath"] as? String else {
            return nil
        }

        let downloadURL = try await downloadURL(for: storagePath)
        let width = frame["width"] as? Int
        let height = frame["height"] as? Int
        let item = PostMediaItem(
            id: "\(assetId)_creator_spaces",
            type: .image,
            url: downloadURL.absoluteString,
            order: 0,
            width: width,
            height: height
        )
        return PostMediaContainer(items: [item])
    }

    private func downloadURL(for storagePath: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            Storage.storage().reference(withPath: storagePath).downloadURL { url, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: CreatorSpacesServiceError.invalidResponse)
                }
            }
        }
    }
}

struct CreatorMediaAssetDraft: Sendable {
    var type: CreatorMediaAssetType
    var frames: CreatorMediaFrames
    var context: CreatorMediaContext?
    var distribution: CreatorFeedDistribution
    var sourceCamera: String
    var capturedOnDevice: Bool
    var editedWithAI: Bool

    var payload: [String: Any] {
        var framePayload: [String: Any] = ["layout": frames.layout.rawValue]
        if let back = frames.back {
            framePayload["back"] = ["storagePath": back.storagePath, "width": back.width, "height": back.height]
        }
        if let front = frames.front {
            framePayload["front"] = ["storagePath": front.storagePath, "width": front.width, "height": front.height]
        }
        if let composite = frames.composite {
            framePayload["composite"] = ["storagePath": composite.storagePath, "width": composite.width, "height": composite.height]
        }
        if let audio = frames.audio {
            framePayload["audio"] = ["storagePath": audio.storagePath, "spatial": audio.spatial]
        }

        var payload: [String: Any] = [
            "type": type.rawValue,
            "frames": framePayload,
            "feed": ["distribution": distribution.rawValue],
            "provenance": [
                "capturedOnDevice": capturedOnDevice,
                "sourceCamera": sourceCamera,
                "editedWithAI": editedWithAI
            ]
        ]

        if let context {
            payload["context"] = [
                "location": context.location as Any,
                "emotionTags": context.emotionTags,
                "ambientSignals": context.ambientSignals
            ]
        }

        return payload
    }
}

struct CreatorSpacesSafetyCheckResult: Equatable, Sendable {
    var decision: String
    var reasons: [String]
}

enum CreatorSpacesServiceError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Creator Spaces returned an invalid response."
        }
    }
}
