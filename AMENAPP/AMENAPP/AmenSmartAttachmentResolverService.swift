import Foundation
import FirebaseFunctions

@MainActor
final class AmenSmartAttachmentResolverService: ObservableObject {
    static let shared = AmenSmartAttachmentResolverService()

    private let functions = Functions.functions()
    private var inFlightTask: Task<AmenSmartAttachment, Error>?
    private var lastResolvedURL: URL?

    func detectSupportedURL(in text: String) -> URL? {
        extractSupportedURLs(from: text).first
    }

    func extractSupportedURLs(from text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var urls: [URL] = []
        var seen = Set<String>()
        for match in detector.matches(in: text, options: [], range: range) {
            guard let r = Range(match.range, in: text),
                  let url = URL(string: String(text[r])),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "https" else {
                continue
            }
            let key = url.absoluteString.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                urls.append(url)
            }
        }
        return urls
    }

    func resolve(url: URL, source: String) async throws -> AmenSmartAttachment {
        if let lastResolvedURL, lastResolvedURL == url, let inFlightTask {
            return try await inFlightTask.value
        }

        inFlightTask?.cancel()
        let task = Task<AmenSmartAttachment, Error> {
            let payload: [String: Any] = ["url": url.absoluteString, "source": source]
            let result = try await functions.httpsCallable("resolveSmartAttachment").call(payload)
            guard let data = result.data as? [String: Any] else {
                throw AmenAttachmentError.resolveFailed
            }
            return try Self.parseAttachment(data)
        }
        inFlightTask = task
        lastResolvedURL = url

        do {
            let attachment = try await task.value
            inFlightTask = nil
            return attachment
        } catch {
            inFlightTask = nil
            throw error
        }
    }

    static func parseAttachment(_ data: [String: Any]) throws -> AmenSmartAttachment {
        func string(_ key: String) -> String? { data[key] as? String }
        func bool(_ key: String) -> Bool { (data[key] as? Bool) ?? false }
        func int(_ key: String) -> Int? { data[key] as? Int }

        guard
            let id = string("attachmentId"),
            let providerRaw = string("provider"),
            let provider = AmenAttachmentProvider(rawValue: providerRaw),
            let typeRaw = string("type"),
            let type = AmenAttachmentType(rawValue: typeRaw),
            let title = string("title"),
            let canonicalUrl = string("canonicalUrl"),
            let attributionText = string("attributionText"),
            let playbackRaw = string("playbackPolicy"),
            let playback = AmenAttachmentPlaybackPolicy(rawValue: playbackRaw),
            let safetyRaw = string("safetyStatus"),
            let safety = AmenAttachmentSafetyStatus(rawValue: safetyRaw)
        else {
            throw AmenAttachmentError.resolveFailed
        }

        let actionsRaw = (data["smartActions"] as? [String]) ?? []
        let actions = actionsRaw.compactMap(AmenSmartAttachmentAction.init(rawValue:))

        return AmenSmartAttachment(
            id: id,
            postId: string("postId"),
            provider: provider,
            type: type,
            providerId: string("providerId"),
            title: title,
            subtitle: string("subtitle"),
            creatorName: string("creatorName"),
            description: string("description"),
            artworkUrl: string("artworkUrl"),
            canonicalUrl: canonicalUrl,
            originalUrl: string("originalUrl"),
            durationMs: int("durationMs"),
            previewUrl: string("previewUrl"),
            attributionText: attributionText,
            sourceLogoRequired: bool("sourceLogoRequired"),
            playbackPolicy: playback,
            safetyStatus: safety,
            intelligenceState: string("intelligenceState").flatMap(AmenUniversalLinkState.init(rawValue:)),
            sourcePlatformLabel: string("sourcePlatformLabel"),
            publishedAtISO8601: string("publishedAtISO8601"),
            transcriptStatus: string("transcriptStatus"),
            aiContextStatus: string("aiContextStatus"),
            summary: string("summary"),
            scriptureReferences: data["scriptureReferences"] as? [String],
            extractedLinks: (data["extractedLinks"] as? [[String: Any]])?.compactMap { item in
                guard
                    let id = item["id"] as? String,
                    let url = item["url"] as? String,
                    let raw = item["category"] as? String,
                    let category = AmenExtractedLinkCategory(rawValue: raw)
                else { return nil }
                return AmenExtractedLink(id: id, url: url, title: item["title"] as? String, category: category)
            },
            smartActions: actions,
            soundtrackEnabled: bool("soundtrackEnabled"),
            createdAt: nil,
            updatedAt: nil
        )
    }
}
