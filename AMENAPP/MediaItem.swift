// MediaItem.swift — Core media item model for Christian Media feature

import Foundation
import SwiftUI

struct MediaItem: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var author: String
    var channelOrShow: String
    var type: MediaFilterType
    var duration: String
    var thumbnailURL: String
    var contentURL: String
    var sourceType: MediaSource
    var scriptureRef: String?
    var publishedDate: Date
    var isBookmarked: Bool = false
    var dominantColor: String

    // MARK: - Computed

    var youtubeVideoID: String? {
        guard sourceType == .youtube else { return nil }
        // Try v= param first
        if let url = URL(string: contentURL),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let vParam = components.queryItems?.first(where: { $0.name == "v" })?.value {
            return vParam
        }
        // Try youtu.be short links
        if let url = URL(string: contentURL), url.host == "youtu.be" {
            return url.pathComponents.dropFirst().first
        }
        // Try embed URL pattern
        if contentURL.contains("/embed/") {
            let parts = contentURL.components(separatedBy: "/embed/")
            if parts.count > 1 {
                return parts[1].components(separatedBy: "?").first
            }
        }
        return nil
    }

    var youtubeEmbedURL: URL? {
        guard let videoID = youtubeVideoID else { return nil }
        let urlString = "https://www.youtube.com/embed/\(videoID)?autoplay=1&playsinline=1&rel=0&modestbranding=1"
        return URL(string: urlString)
    }

    // MARK: - Sample Items

    static let sampleItems: [MediaItem] = [
        MediaItem(
            id: "sample_sermon_1",
            title: "Wholeness: When God Fills the Gaps",
            author: "Steven Furtick",
            channelOrShow: "Elevation Church",
            type: .sermons,
            duration: "38:24",
            thumbnailURL: "https://i.ytimg.com/vi/L1o_Zz9sPl4/hqdefault.jpg",
            contentURL: "https://www.youtube.com/watch?v=L1o_Zz9sPl4",
            sourceType: .youtube,
            scriptureRef: "Philippians 4:11–13",
            publishedDate: Date(timeIntervalSinceNow: -86400 * 3),
            isBookmarked: false,
            dominantColor: "#7C3AED"
        ),
        MediaItem(
            id: "sample_sermon_2",
            title: "The Grave Couldn't Hold Him",
            author: "TD Jakes",
            channelOrShow: "T.D. Jakes Ministries",
            type: .sermons,
            duration: "54:12",
            thumbnailURL: "https://i.ytimg.com/vi/vRKPBbMDPF0/hqdefault.jpg",
            contentURL: "https://www.youtube.com/watch?v=vRKPBbMDPF0",
            sourceType: .youtube,
            scriptureRef: "John 11:25",
            publishedDate: Date(timeIntervalSinceNow: -86400 * 5),
            isBookmarked: false,
            dominantColor: "#F59E0B"
        ),
        MediaItem(
            id: "sample_worship_1",
            title: "What A Beautiful Name",
            author: "Hillsong Worship",
            channelOrShow: "Hillsong Church",
            type: .worship,
            duration: "5:41",
            thumbnailURL: "https://i.ytimg.com/vi/nQWFzMvCfLE/hqdefault.jpg",
            contentURL: "https://www.youtube.com/watch?v=nQWFzMvCfLE",
            sourceType: .youtube,
            scriptureRef: "Philippians 2:9–11",
            publishedDate: Date(timeIntervalSinceNow: -86400 * 7),
            isBookmarked: true,
            dominantColor: "#2563EB"
        ),
        MediaItem(
            id: "sample_worship_2",
            title: "Graves Into Gardens",
            author: "Elevation Worship",
            channelOrShow: "Elevation Church",
            type: .worship,
            duration: "6:03",
            thumbnailURL: "https://i.ytimg.com/vi/aBMFoH-t_Hs/hqdefault.jpg",
            contentURL: "https://www.youtube.com/watch?v=aBMFoH-t_Hs",
            sourceType: .youtube,
            scriptureRef: "Ezekiel 37:1–14",
            publishedDate: Date(timeIntervalSinceNow: -86400 * 10),
            isBookmarked: false,
            dominantColor: "#7C3AED"
        ),
        MediaItem(
            id: "sample_devotional_1",
            title: "The Image of God Explained",
            author: "Bible Project",
            channelOrShow: "BibleProject",
            type: .devotionals,
            duration: "6:55",
            thumbnailURL: "https://i.ytimg.com/vi/H-54YSqm4aY/hqdefault.jpg",
            contentURL: "https://www.youtube.com/watch?v=H-54YSqm4aY",
            sourceType: .youtube,
            scriptureRef: "Genesis 1:26–27",
            publishedDate: Date(timeIntervalSinceNow: -86400 * 14),
            isBookmarked: false,
            dominantColor: "#16A34A"
        ),
        MediaItem(
            id: "sample_devotional_2",
            title: "Shalom and the Kingdom of God",
            author: "Bible Project",
            channelOrShow: "BibleProject",
            type: .devotionals,
            duration: "7:22",
            thumbnailURL: "https://i.ytimg.com/vi/ak06MSETeo4/hqdefault.jpg",
            contentURL: "https://www.youtube.com/watch?v=ak06MSETeo4",
            sourceType: .youtube,
            scriptureRef: "Isaiah 9:6–7",
            publishedDate: Date(timeIntervalSinceNow: -86400 * 16),
            isBookmarked: false,
            dominantColor: "#16A34A"
        ),
        MediaItem(
            id: "sample_podcast_1",
            title: "Day 1: Genesis — The Beginning",
            author: "Fr. Mike Schmitz",
            channelOrShow: "Bible in a Year",
            type: .podcasts,
            duration: "29:15",
            thumbnailURL: "https://i.scdn.co/image/ab6765630000ba8a8c17c69df3fc1a8fb97f1fcf",
            contentURL: "https://feeds.transistor.fm/bible-in-a-year-with-father-mike-schmitz",
            sourceType: .rss,
            scriptureRef: "Genesis 1–2",
            publishedDate: Date(timeIntervalSinceNow: -86400 * 2),
            isBookmarked: false,
            dominantColor: "#0F172A"
        ),
        MediaItem(
            id: "sample_sermon_3",
            title: "How to Survive Your Own Story",
            author: "Louie Giglio",
            channelOrShow: "Passion City Church",
            type: .sermons,
            duration: "44:18",
            thumbnailURL: "https://i.ytimg.com/vi/I8K2RKjXzRk/hqdefault.jpg",
            contentURL: "https://www.youtube.com/watch?v=I8K2RKjXzRk",
            sourceType: .youtube,
            scriptureRef: "Romans 8:28",
            publishedDate: Date(timeIntervalSinceNow: -86400 * 8),
            isBookmarked: false,
            dominantColor: "#0D9488"
        )
    ]
}

