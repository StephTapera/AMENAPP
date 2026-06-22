import Foundation
import FirebaseFunctions

@MainActor
final class AmenDiscoverService {
    static let shared = AmenDiscoverService()

    private let functions = Functions.functions()

    func loadDiscoverFeed(cursor: String?, sessionId: String?, filter: String, query: String?) async throws -> AmenDiscoverFeedResponse {
        let callable = functions.httpsCallable("getAmenDiscoverFeed")
        var payload: [String: Any] = [
            "surface": "discover",
            "filters": ["topic": filter]
        ]
        payload["cursor"] = cursor
        payload["sessionId"] = sessionId
        if let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["intentQuery"] = query
        }

        let result = try await callable.call(payload)
        guard let data = result.data as? [String: Any] else {
            throw NSError(domain: "AmenDiscoverService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid feed response."])
        }

        let items = (data["items"] as? [[String: Any]] ?? []).compactMap(AmenDiscoverService.parseItem)
        let context = data["rankingContext"] as? [String: String] ?? [:]
        return AmenDiscoverFeedResponse(
            sessionId: data["sessionId"] as? String ?? sessionId ?? UUID().uuidString,
            items: items,
            nextCursor: data["nextCursor"] as? String,
            rankingContext: context
        )
    }

    func logDiscoverEvent(sessionId: String, itemId: String, event: String, visibleMs: Int? = nil) {
        let callable = functions.httpsCallable("logDiscoverEvent")
        var payload: [String: Any] = ["sessionId": sessionId, "itemId": itemId, "event": event]
        if let visibleMs { payload["visible_ms"] = visibleMs }
        Task { _ = try? await callable.call(payload) }
    }

    func submitDiscoverFeedback(itemId: String, sessionId: String, feedback: AmenDiscoverFeedbackType) async throws {
        let callable = functions.httpsCallable("submitDiscoverFeedback")
        _ = try await callable.call([
            "itemId": itemId,
            "sessionId": sessionId,
            "feedbackType": feedback.rawValue
        ])
    }

    func getDiscoverReason(itemId: String, sessionId: String) async throws -> AmenDiscoverReasonResponse {
        let callable = functions.httpsCallable("getDiscoverReason")
        let result = try await callable.call(["itemId": itemId, "sessionId": sessionId])
        let data = result.data as? [String: Any]
        return AmenDiscoverReasonResponse(
            itemId: itemId,
            reason: data?["reason"] as? String ?? "This was recommended based on your recent Amen activity and Discover settings."
        )
    }

    private static func parseItem(_ data: [String: Any]) -> AmenDiscoverItem? {
        guard
            let id = data["id"] as? String,
            let sourceId = data["sourceId"] as? String,
            let sourceType = data["sourceType"] as? String,
            let typeRaw = data["type"] as? String,
            let type = AmenDiscoverItemType(rawValue: typeRaw),
            let title = data["title"] as? String
        else {
            return nil
        }

        let mediaDict = data["media"] as? [String: Any] ?? [:]
        let media = AmenDiscoverMedia(
            thumbnailURL: mediaDict["thumbnailURL"] as? String,
            mediaURL: mediaDict["mediaURL"] as? String,
            durationSeconds: mediaDict["durationSeconds"] as? Int
        )

        func parseActor(_ key: String) -> AmenDiscoverActor? {
            guard let actor = data[key] as? [String: Any], let id = actor["id"] as? String, let name = actor["name"] as? String else {
                return nil
            }
            return AmenDiscoverActor(id: id, name: name, avatarURL: actor["avatarURL"] as? String)
        }

        let badges = Set((data["badges"] as? [String] ?? []).compactMap(AmenDiscoverBadge.init(rawValue:)))
        let createdAtSeconds = data["createdAtSeconds"] as? TimeInterval ?? Date().timeIntervalSince1970

        return AmenDiscoverItem(
            id: id,
            sourceId: sourceId,
            sourceType: sourceType,
            type: type,
            title: title,
            subtitle: data["subtitle"] as? String,
            caption: data["caption"] as? String,
            media: media,
            author: parseActor("author"),
            church: parseActor("church"),
            topics: data["topics"] as? [String] ?? [],
            scriptureRefs: data["scriptureRefs"] as? [String] ?? [],
            badges: badges,
            reasonPreview: data["reasonPreview"] as? String,
            createdAt: Date(timeIntervalSince1970: createdAtSeconds)
        )
    }
}
