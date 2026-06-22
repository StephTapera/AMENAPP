// SermonMediaTransformService.swift — AMEN IntegrationOS
// Actor that calls the `moderateMediaTransform` Cloud Function.

import Foundation
import FirebaseFunctions
import FirebaseRemoteConfig

actor SermonMediaTransformService {
    static let shared = SermonMediaTransformService()
    private init() {}

    private let functions = Functions.functions()
    private let remoteConfig = RemoteConfig.remoteConfig()
    private var isEnabled: Bool { remoteConfig.configValue(forKey: "integration_media_transform_enabled").boolValue }

    func transform(sermonId: String, mediaURL: String, title: String) async throws -> SermonStudyPacket {
        guard isEnabled else { throw IntegrationOSError.providerUnavailable("moderateMediaTransform") }

        let payload: [String: Any] = [
            "sermonId": sermonId,
            "mediaURL": mediaURL,
            "title": title
        ]

        let result = try await functions.httpsCallable("moderateMediaTransform").call(payload)
        guard let data = result.data as? [String: Any] else {
            throw IntegrationOSError.providerUnavailable("moderateMediaTransform")
        }

        return try parsePacket(from: data, sermonId: sermonId, title: title, mediaURL: mediaURL)
    }

    private func parsePacket(
        from data: [String: Any],
        sermonId: String,
        title: String,
        mediaURL: String
    ) throws -> SermonStudyPacket {
        let outline = (data["outline"] as? [[String: Any]] ?? []).enumerated().map { idx, pt in
            SermonOutlinePoint(
                order: idx,
                heading: pt["heading"] as? String ?? "",
                body: pt["body"] as? String ?? "",
                scripture: pt["scripture"] as? String
            )
        }

        return SermonStudyPacketBuilder()
            .sermonId(sermonId)
            .title(data["title"] as? String ?? title)
            .preacher(data["preacher"] as? String)
            .church(data["churchName"] as? String)
            .scripture(data["scripture"] as? [String] ?? [])
            .outline(outline)
            .themes(data["keyThemes"] as? [String] ?? [])
            .questions(data["discussionQuestions"] as? [String] ?? [])
            .prayerPoints(data["prayerPoints"] as? [String] ?? [])
            .mediaURL(mediaURL)
            .build()
    }
}
