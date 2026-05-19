import Foundation
import FirebaseFunctions

@MainActor
final class AmenMediaGraphService {
    static let shared = AmenMediaGraphService()
    private let functions = Functions.functions()

    func saveToSelah(_ attachment: AmenSmartAttachment, sourcePostId: String?) async throws {
        try await save(attachment, sourcePostId: sourcePostId, context: "selah")
    }

    func addToChurchNotes(_ attachment: AmenSmartAttachment, sourcePostId: String?) async throws {
        try await save(attachment, sourcePostId: sourcePostId, context: "churchNotes")
    }

    func saveForLater(_ attachment: AmenSmartAttachment, sourcePostId: String?) async throws {
        try await save(attachment, sourcePostId: sourcePostId, context: "savedForLater")
    }

    func getRecentAttachments() async throws -> [String] {
        let result = try await functions.httpsCallable("getRecentMediaAttachments").call([:])
        let data = result.data as? [String: Any]
        return data?["ids"] as? [String] ?? []
    }

    func getSavedSongs() async throws -> [[String: Any]] {
        let result = try await functions.httpsCallable("getSavedMediaItems").call(["context": "songs"])
        let data = result.data as? [String: Any]
        return data?["items"] as? [[String: Any]] ?? []
    }

    private func save(_ attachment: AmenSmartAttachment, sourcePostId: String?, context: String) async throws {
        let item: [String: Any] = [
            "attachmentId": attachment.id,
            "provider": attachment.provider.rawValue,
            "providerId": attachment.providerId as Any,
            "type": attachment.type.rawValue,
            "title": attachment.title,
            "subtitle": attachment.subtitle as Any,
            "creatorName": attachment.creatorName as Any,
            "artworkUrl": attachment.artworkUrl as Any,
            "canonicalUrl": attachment.canonicalUrl,
            "sourcePostId": sourcePostId as Any,
            "savedContext": context,
            "safetyStatus": attachment.safetyStatus.rawValue,
            "visibility": "private"
        ]
        _ = try await functions.httpsCallable("saveMediaGraphItem").call(["item": item])
    }
}
