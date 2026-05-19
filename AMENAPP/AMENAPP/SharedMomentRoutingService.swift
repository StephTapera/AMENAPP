import Foundation

@MainActor
final class SharedMomentRoutingService {
    static let shared = SharedMomentRoutingService()

    private init() {}

    func url(for target: SharedMomentTarget) -> URL? {
        var components = URLComponents()
        components.scheme = "amen"
        components.host = "media"
        components.path = "/\(target.postId)"

        var items: [URLQueryItem] = [
            URLQueryItem(name: "mediaIndex", value: String(target.mediaIndex))
        ]
        if let timestamp = target.timestamp {
            items.append(URLQueryItem(name: "moment", value: String(timestamp)))
        }
        if let frameIndex = target.frameIndex {
            items.append(URLQueryItem(name: "frame", value: String(frameIndex)))
        }
        if let momentId = target.momentId {
            items.append(URLQueryItem(name: "momentId", value: momentId))
        }
        if let mediaId = target.mediaId {
            items.append(URLQueryItem(name: "mediaId", value: mediaId))
        }
        components.queryItems = items
        return components.url
    }

    func parse(_ url: URL) -> SharedMomentTarget? {
        guard url.scheme == "amen", (url.host ?? "") == "media" else { return nil }
        let postId = url.pathComponents.filter { $0 != "/" }.first ?? ""
        guard !postId.isEmpty else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return SharedMomentTarget(
            postId: postId,
            mediaIndex: Int(items.first(where: { $0.name == "mediaIndex" })?.value ?? "") ?? 0,
            mediaId: items.first(where: { $0.name == "mediaId" })?.value,
            timestamp: Double(items.first(where: { $0.name == "moment" })?.value ?? ""),
            frameIndex: Int(items.first(where: { $0.name == "frame" })?.value ?? ""),
            momentId: items.first(where: { $0.name == "momentId" })?.value
        )
    }
}
