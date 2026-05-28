import Foundation
import FirebaseAuth

@MainActor
final class AmenUniversalContentService: ObservableObject {
    static let shared = AmenUniversalContentService()

    private let functions = CloudFunctionsService.shared
    private let decoder: JSONDecoder

    private init() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func fetchFeed(limit: Int = 20) async throws -> [ContentNode] {
        try await fetchContentList(functionName: "getUniversalContentFeed", payload: ["limit": limit])
    }

    func fetchProfileContent(ownerId: String, limit: Int = 20) async throws -> [ContentNode] {
        try await fetchContentList(functionName: "getProfileContent", payload: [
            "ownerId": ownerId,
            "limit": limit
        ])
    }

    func keywordSearch(_ query: String, limit: Int = 20) async throws -> [ContentNode] {
        try await fetchContentList(functionName: "keywordSearchContent", payload: [
            "query": query,
            "limit": limit
        ])
    }

    func reviewModeration(contentId: String, decision: ModerationStatus, reason: String? = nil) async throws {
        var payload: [String: Any] = [
            "contentId": contentId,
            "decision": decision.rawValue
        ]
        if let reason {
            payload["reason"] = reason
        }
        _ = try await functions.call("reviewContentNodeModeration", data: payload)
    }

    func createMediaUploadSession(type: String) async throws -> [String: Any] {
        try await callDictionary("createMediaUploadSession", payload: ["type": type])
    }

    func finalizeMediaUpload(mediaId: String, width: Double? = nil, height: Double? = nil, duration: Double? = nil) async throws {
        var payload: [String: Any] = ["mediaId": mediaId]
        if let width { payload["width"] = width }
        if let height { payload["height"] = height }
        if let duration { payload["duration"] = duration }
        _ = try await functions.call("finalizeMediaUpload", data: payload)
    }

    func processUploadedMedia(mediaId: String) async throws {
        _ = try await functions.call("processUploadedMedia", data: ["mediaId": mediaId])
    }

    func generateVideoTranscript(mediaId: String) async throws {
        _ = try await functions.call("generateVideoTranscript", data: ["mediaId": mediaId])
    }

    func generateCaptions(mediaId: String) async throws {
        _ = try await functions.call("generateCaptions", data: ["mediaId": mediaId])
    }

    func generateVideoChapters(mediaId: String) async throws {
        _ = try await functions.call("generateVideoChapters", data: ["mediaId": mediaId])
    }

    func generateMediaSummary(mediaId: String) async throws -> String {
        let response = try await callDictionary("generateMediaSummary", payload: ["mediaId": mediaId])
        return response["summary"] as? String ?? ""
    }

    func createNote(title: String) async throws -> String {
        let response = try await callDictionary("createNote", payload: ["title": title])
        return response["noteId"] as? String ?? ""
    }

    func updateNoteBlock(noteId: String, blockId: String? = nil, type: String, text: String, order: Int) async throws -> String {
        var payload: [String: Any] = [
            "noteId": noteId,
            "type": type,
            "text": text,
            "order": order
        ]
        if let blockId { payload["blockId"] = blockId }
        let response = try await callDictionary("updateNoteBlock", payload: payload)
        return response["blockId"] as? String ?? ""
    }

    func convertNoteToPost(noteId: String) async throws -> String {
        let response = try await callDictionary("convertNoteToPost", payload: ["noteId": noteId])
        return response["draftId"] as? String ?? ""
    }

    func saveDesignProject(designId: String? = nil, title: String, templateId: String?, payload: [String: Any]) async throws -> String {
        var request: [String: Any] = ["title": title, "payload": payload]
        if let designId { request["designId"] = designId }
        if let templateId { request["templateId"] = templateId }
        let response = try await callDictionary("saveDesignProject", payload: request)
        return response["designId"] as? String ?? ""
    }

    func exportDesignImageMetadata(designId: String, storagePath: String, width: Int, height: Int) async throws -> String {
        let response = try await callDictionary("exportDesignImageMetadata", payload: [
            "designId": designId,
            "storagePath": storagePath,
            "width": width,
            "height": height
        ])
        return response["storagePath"] as? String ?? storagePath
    }

    func createCommunity(name: String, type: String, isPrivate: Bool, description: String = "") async throws -> String {
        let response = try await callDictionary("createCommunity", payload: [
            "name": name,
            "type": type,
            "isPrivate": isPrivate,
            "description": description
        ])
        return response["communityId"] as? String ?? ""
    }

    func createCommunityPost(communityId: String, text: String, title: String? = nil) async throws -> String {
        var payload: [String: Any] = ["communityId": communityId, "text": text]
        if let title { payload["title"] = title }
        let response = try await callDictionary("createCommunityPost", payload: payload)
        return response["contentId"] as? String ?? ""
    }

    func createReply(contentId: String, body: String, parentReplyId: String? = nil) async throws -> String {
        var payload: [String: Any] = ["contentId": contentId, "body": body]
        if let parentReplyId { payload["parentReplyId"] = parentReplyId }
        let response = try await callDictionary("createReply", payload: payload)
        return response["replyId"] as? String ?? ""
    }

    func summarizeThread(contentId: String) async throws -> String {
        let response = try await callDictionary("summarizeThread", payload: ["contentId": contentId])
        return response["summary"] as? String ?? ""
    }

    func saveThreadToNote(contentId: String, summary: String? = nil) async throws -> String {
        var payload: [String: Any] = ["contentId": contentId]
        if let summary, !summary.isEmpty {
            payload["summary"] = summary
        }
        let response = try await callDictionary("saveThreadToNote", payload: payload)
        return response["noteId"] as? String ?? ""
    }

    func scheduleContent(contentId: String, at date: Date) async throws -> String {
        let encoder = ISO8601DateFormatter()
        let response = try await callDictionary("scheduleContent", payload: [
            "contentId": contentId,
            "scheduledAt": encoder.string(from: date)
        ])
        return response["scheduleId"] as? String ?? ""
    }

    func publishScheduledContent(scheduleId: String) async throws {
        _ = try await functions.call("publishScheduledContent", data: ["scheduleId": scheduleId])
    }

    func indexContentNode(contentId: String) async throws {
        _ = try await functions.call("indexContentNode", data: ["contentId": contentId])
    }

    func requestAIRewrite(text: String) async throws -> [String: Any] {
        try await callDictionary("rewriteContent", payload: ["text": text])
    }

    private func callDictionary(_ functionName: String, payload: [String: Any]) async throws -> [String: Any] {
        guard Auth.auth().currentUser != nil else { return [:] }
        return try await functions.call(functionName, data: payload) as? [String: Any] ?? [:]
    }

    private func fetchContentList(functionName: String, payload: [String: Any]) async throws -> [ContentNode] {
        guard AMENFeatureFlags.shared.universalContentModelEnabled else {
            return []
        }

        guard Auth.auth().currentUser != nil else {
            return []
        }

        let response = try await functions.call(functionName, data: payload)
        guard let dictionary = response as? [String: Any],
              let items = dictionary["items"] as? [[String: Any]] else {
            return []
        }

        return items.compactMap(decodeContentNode)
    }

    private func decodeContentNode(_ dictionary: [String: Any]) -> ContentNode? {
        guard JSONSerialization.isValidJSONObject(dictionary),
              let data = try? JSONSerialization.data(withJSONObject: dictionary) else {
            return nil
        }
        return try? decoder.decode(ContentNode.self, from: data)
    }
}
