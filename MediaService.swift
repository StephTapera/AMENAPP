// MediaService.swift — Fetches Christian media from YouTube, RSS feeds

import Foundation

// MARK: - API Keys (never hardcoded)
private enum MediaAPIKeys {
    static var youtube: String {
        Bundle.main.object(forInfoDictionaryKey: "YOUTUBE_API_KEY") as? String ?? ""
    }
}

// MARK: - Channel Constants
private enum YouTubeChannels {
    static let elevation  = (id: "UCCzSSMYQXen9h8V0VEzx6_g", color: "#7C3AED") // Elevation Church
    static let hillsong   = (id: "UCNiGljFBDFETHwmrCp7voyg", color: "#2563EB") // Hillsong Church
    static let tdJakes    = (id: "UCZIGznXMSIiQEBGMnMFGxEQ", color: "#F59E0B") // TD Jakes
    static let passion    = (id: "UCGOAlKWAu_GKfJgWTJkWX-Q", color: "#0D9488") // Louie Giglio/Passion
    static let bibleProject = (id: "UCVfwlh9XpX2Y_tQfjeln9QA", color: "#16A34A") // Bible Project
}

// MARK: - YouTube Decodable Structs
private struct YTSearchResponse: Decodable {
    let items: [YTSearchItem]
}

private struct YTSearchItem: Decodable {
    let id: YTItemID
    let snippet: YTSnippet
}

private struct YTItemID: Decodable {
    let videoId: String?
}

private struct YTSnippet: Decodable {
    let title: String
    let description: String
    let channelTitle: String
    let publishedAt: String
    let thumbnails: YTThumbnails
}

private struct YTThumbnails: Decodable {
    let high: YTThumbnail?
}

private struct YTThumbnail: Decodable {
    let url: String
}

// MARK: - RSS Parser Delegate
private class RSSParserDelegate: NSObject, XMLParserDelegate {
    var items: [MediaItem] = []
    private var currentElement = ""
    private var currentTitle = ""
    private var currentDuration = ""
    private var currentEnclosureURL = ""
    private var currentPubDate = ""
    private var currentDescription = ""
    private var inItem = false

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        if elementName == "item" {
            inItem = true
            currentTitle = ""
            currentDuration = ""
            currentEnclosureURL = ""
            currentPubDate = ""
            currentDescription = ""
        }
        if elementName == "enclosure", inItem {
            currentEnclosureURL = attributeDict["url"] ?? ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, inItem else { return }
        switch currentElement {
        case "title": currentTitle += trimmed
        case "itunes:duration": currentDuration += trimmed
        case "pubDate": currentPubDate += trimmed
        case "description", "itunes:summary": currentDescription += trimmed
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item", inItem {
            inItem = false
            guard !currentEnclosureURL.isEmpty else { return }
            let parsedDate = parseRSSDate(currentPubDate)
            let item = MediaItem(
                id: "rss_\(currentEnclosureURL.hashValue)_\(currentTitle.hashValue)",
                title: currentTitle,
                author: "Fr. Mike Schmitz",
                channelOrShow: "Bible in a Year",
                type: .podcasts,
                duration: formattedDuration(currentDuration),
                thumbnailURL: "https://i.scdn.co/image/ab6765630000ba8a8c17c69df3fc1a8fb97f1fcf",
                contentURL: currentEnclosureURL,
                sourceType: .rss,
                scriptureRef: nil,
                publishedDate: parsedDate,
                isBookmarked: false,
                dominantColor: "#0F172A"
            )
            items.append(item)
        }
    }

    private func parseRSSDate(_ str: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "EEE, dd MMM yyyy HH:mm:ss Z"
        ]
        for fmt in formats {
            formatter.dateFormat = fmt
            if let date = formatter.date(from: str) { return date }
        }
        return Date()
    }

    private func formattedDuration(_ raw: String) -> String {
        // itunes:duration can be HH:MM:SS or MM:SS or just seconds
        let parts = raw.components(separatedBy: ":")
        if parts.count >= 2 { return raw }
        if let seconds = Int(raw) {
            let m = seconds / 60
            let s = seconds % 60
            return String(format: "%d:%02d", m, s)
        }
        return raw
    }
}

// MARK: - MediaService
final class MediaService {
    static let shared = MediaService()
    private init() {}

    private let session = URLSession.shared

    // MARK: - Public Fetch Methods

    func fetchSermons() async -> [MediaItem] {
        guard !MediaAPIKeys.youtube.isEmpty else {
            dlog("MediaService: No YouTube API key — returning sample sermons")
            return MediaItem.sampleItems.filter { $0.type == .sermons }
        }
        async let elevationItems = fetchChannel(
            YouTubeChannels.elevation.id,
            dominantColor: YouTubeChannels.elevation.color,
            type: .sermons
        )
        async let hillsongItems = fetchChannel(
            YouTubeChannels.hillsong.id,
            dominantColor: YouTubeChannels.hillsong.color,
            type: .sermons
        )
        async let tdJakesItems = fetchChannel(
            YouTubeChannels.tdJakes.id,
            dominantColor: YouTubeChannels.tdJakes.color,
            type: .sermons
        )
        async let passionItems = fetchChannel(
            YouTubeChannels.passion.id,
            dominantColor: YouTubeChannels.passion.color,
            type: .sermons
        )
        let results = await [elevationItems, hillsongItems, tdJakesItems, passionItems]
        return results.flatMap { $0 }
    }

    func fetchWorshipVideos() async -> [MediaItem] {
        guard !MediaAPIKeys.youtube.isEmpty else {
            dlog("MediaService: No YouTube API key — returning sample worship")
            return MediaItem.sampleItems.filter { $0.type == .worship }
        }
        async let bibleProjectItems = fetchChannel(
            YouTubeChannels.bibleProject.id,
            dominantColor: YouTubeChannels.bibleProject.color,
            type: .worship,
            maxResults: 5
        )
        async let elevationWorshipItems = fetchChannel(
            YouTubeChannels.elevation.id,
            dominantColor: YouTubeChannels.elevation.color,
            type: .worship,
            maxResults: 5
        )
        let results = await [bibleProjectItems, elevationWorshipItems]
        return results.flatMap { $0 }
    }

    func fetchPodcasts() async -> [MediaItem] {
        let feedURLs: [(url: String, author: String, show: String, color: String)] = [
            (
                "https://feeds.transistor.fm/bible-in-a-year-with-father-mike-schmitz",
                "Fr. Mike Schmitz",
                "Bible in a Year",
                "#0F172A"
            ),
            (
                "https://www.pray-as-you-go.org/podcast/feed/",
                "Pray as You Go",
                "Pray as You Go",
                "#1E3A5F"
            )
        ]

        var allPodcastItems: [MediaItem] = []

        await withTaskGroup(of: [MediaItem].self) { group in
            for feed in feedURLs {
                group.addTask {
                    await self.parsePodcastFeed(
                        urlString: feed.url,
                        author: feed.author,
                        show: feed.show,
                        dominantColor: feed.color
                    )
                }
            }
            for await items in group {
                allPodcastItems.append(contentsOf: items)
            }
        }

        if allPodcastItems.isEmpty {
            return MediaItem.sampleItems.filter { $0.type == .podcasts }
        }
        return allPodcastItems
    }

    func fetchDevotionals() async -> [MediaItem] {
        let devotionalVideoIDs: [(id: String, title: String, scripture: String, duration: String)] = [
            ("GDkqU9Oqy_8", "Intro to the Torah", "Genesis 1:1", "6:22"),
            ("7RoqnGcEjcs", "Intro to the Bible", "2 Timothy 3:16–17", "5:55"),
            ("ak06MSETeo4", "Shalom and the Kingdom of God", "Isaiah 9:6–7", "7:22"),
            ("xUM0fAv9_Jo", "The Story of the Bible", "John 1:1–14", "8:02"),
            ("H-54YSqm4aY", "The Image of God", "Genesis 1:26–27", "6:55"),
            ("ALsluAKBZ-c", "Sacrifice and Atonement", "Hebrews 9:22", "7:44"),
            ("fCFR8HsNrCM", "The Messiah Explained", "Isaiah 53", "9:11"),
            ("vD-E0gKKQvY", "The Kingdom of God", "Mark 1:15", "8:37")
        ]

        return devotionalVideoIDs.enumerated().map { index, item in
            MediaItem(
                id: "devotional_\(item.id)",
                title: item.title,
                author: "Bible Project",
                channelOrShow: "BibleProject",
                type: .devotionals,
                duration: item.duration,
                thumbnailURL: "https://i.ytimg.com/vi/\(item.id)/hqdefault.jpg",
                contentURL: "https://www.youtube.com/watch?v=\(item.id)",
                sourceType: .youtube,
                scriptureRef: item.scripture,
                publishedDate: Date(timeIntervalSinceNow: -86400 * Double(index * 7 + 30)),
                isBookmarked: false,
                dominantColor: "#16A34A"
            )
        }
    }

    func fetchAll() async -> [MediaItem] {
        async let sermons = fetchSermons()
        async let worship = fetchWorshipVideos()
        async let podcasts = fetchPodcasts()
        async let devotionals = fetchDevotionals()

        let allItems = await sermons + worship + podcasts + devotionals
        return allItems.sorted { $0.publishedDate > $1.publishedDate }
    }

    // MARK: - Cache

    func cacheItems(_ items: [MediaItem]) {
        do {
            let data = try JSONEncoder().encode(items)
            UserDefaults.standard.set(data, forKey: "cm_cached_items")
        } catch {
            dlog("MediaService: Failed to cache items — \(error.localizedDescription)")
        }
    }

    func cachedItems() -> [MediaItem]? {
        guard let data = UserDefaults.standard.data(forKey: "cm_cached_items") else { return nil }
        do {
            return try JSONDecoder().decode([MediaItem].self, from: data)
        } catch {
            dlog("MediaService: Failed to decode cached items — \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Private Helpers

    private func fetchChannel(
        _ channelId: String,
        dominantColor: String,
        type: MediaFilterType,
        maxResults: Int = 5
    ) async -> [MediaItem] {
        let apiKey = MediaAPIKeys.youtube
        guard !apiKey.isEmpty else {
            dlog("MediaService: YouTube API key missing for channel \(channelId)")
            return []
        }

        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/search")!
        components.queryItems = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "channelId", value: channelId),
            URLQueryItem(name: "maxResults", value: "\(maxResults)"),
            URLQueryItem(name: "order", value: "date"),
            URLQueryItem(name: "type", value: "video"),
            URLQueryItem(name: "key", value: apiKey)
        ]

        guard let url = components.url else {
            dlog("MediaService: Failed to build URL for channel \(channelId)")
            return []
        }

        do {
            let (data, response) = try await session.data(from: url)

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 403 {
                    dlog("MediaService: YouTube API rate limit (403) for channel \(channelId) — returning cached/sample items")
                    return cachedItems()?.filter { $0.type == type } ?? MediaItem.sampleItems.filter { $0.type == type }
                }
                guard httpResponse.statusCode == 200 else {
                    dlog("MediaService: Unexpected HTTP \(httpResponse.statusCode) for channel \(channelId)")
                    return []
                }
            }

            let decoded = try JSONDecoder().decode(YTSearchResponse.self, from: data)
            return decoded.items.compactMap { ytItem -> MediaItem? in
                guard let videoId = ytItem.id.videoId else { return nil }
                let thumbURL = ytItem.snippet.thumbnails.high?.url ?? ""
                let publishedDate = parseDate(ytItem.snippet.publishedAt)
                return MediaItem(
                    id: "yt_\(videoId)",
                    title: ytItem.snippet.title,
                    author: ytItem.snippet.channelTitle,
                    channelOrShow: ytItem.snippet.channelTitle,
                    type: type,
                    duration: "",
                    thumbnailURL: thumbURL,
                    contentURL: "https://www.youtube.com/watch?v=\(videoId)",
                    sourceType: .youtube,
                    scriptureRef: nil,
                    publishedDate: publishedDate,
                    isBookmarked: false,
                    dominantColor: dominantColor
                )
            }
        } catch {
            dlog("MediaService: Error fetching channel \(channelId) — \(error.localizedDescription)")
            return []
        }
    }

    private func parsePodcastFeed(
        urlString: String,
        author: String,
        show: String,
        dominantColor: String
    ) async -> [MediaItem] {
        guard let url = URL(string: urlString) else {
            dlog("MediaService: Invalid podcast feed URL — \(urlString)")
            return []
        }

        do {
            let (data, _) = try await session.data(from: url)

            return await withCheckedContinuation { continuation in
                let delegate = RSSParserDelegate()
                let parser = XMLParser(data: data)
                parser.delegate = delegate
                let success = parser.parse()
                if !success {
                    dlog("MediaService: RSS parse failed for \(urlString)")
                    continuation.resume(returning: [])
                    return
                }
                // Override author/show from feed metadata
                let items = delegate.items.prefix(10).map { item -> MediaItem in
                    var mutableItem = item
                    mutableItem.author = author
                    mutableItem.channelOrShow = show
                    mutableItem.dominantColor = dominantColor
                    return mutableItem
                }
                continuation.resume(returning: Array(items))
            }
        } catch {
            dlog("MediaService: Error fetching podcast feed \(urlString) — \(error.localizedDescription)")
            return []
        }
    }

    private func parseDate(_ str: String) -> Date {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: str) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd"
        ]
        for fmt in formats {
            formatter.dateFormat = fmt
            if let date = formatter.date(from: str) { return date }
        }
        dlog("MediaService: Could not parse date string: \(str)")
        return Date()
    }
}
