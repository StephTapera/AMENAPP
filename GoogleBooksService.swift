// GoogleBooksService.swift
// AMENAPP
//
// Fetches book metadata from the free Google Books API.
// No API key required for basic search (up to ~1000 queries/day).
// For higher limits add GOOGLE_BOOKS_API_KEY to Config.xcconfig.

import Foundation
import SwiftUI
import Combine

// MARK: - Config

enum GoogleBooksConfig {
    static let apiKey: String = Bundle.main.object(
        forInfoDictionaryKey: "GOOGLE_BOOKS_API_KEY") as? String ?? ""
    static let baseURL = "https://www.googleapis.com/books/v1"
}

// MARK: - Service

// Not @MainActor — network calls must run off the main thread so parallel
// task group fetches in fetchCuratedShelves() don't deadlock each other.
// Cache is protected by a private actor to satisfy Swift 6 concurrency rules.

private actor BookSearchCache {
    private var store: [String: [WLBook]] = [:]
    func get(_ key: String) -> [WLBook]? { store[key] }
    func set(_ key: String, _ books: [WLBook]) { store[key] = books }
    func clear() { store.removeAll() }
}

final class GoogleBooksService: @unchecked Sendable {
    static let shared = GoogleBooksService()

    private let cache = BookSearchCache()

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: cfg)
    }()

    private init() {}

    // MARK: - Search

    func search(query: String, maxResults: Int = 20, startIndex: Int = 0) async throws -> [WLBook] {
        let key = "\(query)_\(startIndex)"

        if let cached = await cache.get(key) { return cached }

        var components = URLComponents(string: "\(GoogleBooksConfig.baseURL)/volumes")!
        var items: [URLQueryItem] = [
            .init(name: "q",           value: query),
            .init(name: "maxResults",  value: "\(min(maxResults, 40))"),
            .init(name: "startIndex",  value: "\(startIndex)"),
            .init(name: "printType",   value: "books"),
            .init(name: "langRestrict",value: "en"),
            .init(name: "orderBy",     value: "relevance")
        ]
        if !GoogleBooksConfig.apiKey.isEmpty {
            items.append(.init(name: "key", value: GoogleBooksConfig.apiKey))
        }
        components.queryItems = items

        guard let url = components.url else { throw WLBookServiceError.invalidURL }
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw WLBookServiceError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let result = try JSONDecoder().decode(GBListResponse.self, from: data)
        let books = (result.items ?? []).compactMap { WLBook(fromAPI: $0) }

        await cache.set(key, books)
        return books
    }

    // MARK: - Curated Shelves

    func fetchCuratedShelves() async -> [WLBookShelf] {
        typealias ShelfSpec = (title: String, sub: String?, query: String,
                               color: SwiftUI.Color, icon: String?, premium: Bool)
        let specs: [ShelfSpec] = [
            ("Theology Essentials",   "Foundations of the faith", "reformed theology classics",             .indigo, "scroll",           false),
            ("Prayer & Devotion",     "Deepen your walk",         "christian prayer devotional",            .purple, "hands.sparkles",   false),
            ("Discipleship",          "Follow Jesus daily",       "christian discipleship",                 .blue,   "figure.walk",      false),
            ("Women of Faith",        "Voices for every season",  "Jackie Hill Perry Kristin Hannah christian women faith", .pink, "person.crop.circle.badge.checkmark", false),
            ("Marriage & Family",     "For couples & parents",    "christian marriage family Keller",       .red,    "heart.circle",     true),
            ("Leadership",            "For pastors & leaders",    "christian leadership church",            .orange, "person.3",         true),
            ("Spiritual Disciplines", "Habits of the soul",       "spiritual disciplines foster Willard",   .teal,   "sparkles",         true),
            ("Christian Classics",    "Timeless works",           "christian classics Bonhoeffer Lewis Tozer", .brown, "crown",          false),
            ("Apologetics",           "Defend the faith",         "christian apologetics Lewis Keller",     .green,  "shield",           false),
            ("Mental Health & Hope",  "Healing through faith",    "christian mental health anxiety hope faith", Color(red: 0.4, green: 0.6, blue: 0.8), "brain.head.profile", false),
        ]

        // Capture service reference strongly — no weak self needed outside @MainActor
        let service = self
        var shelves: [WLBookShelf] = []
        await withTaskGroup(of: WLBookShelf?.self) { group in
            for spec in specs {
                group.addTask {
                    guard let books = try? await service.search(query: spec.query, maxResults: 12),
                          !books.isEmpty else { return nil }
                    return WLBookShelf(
                        id: spec.query, title: spec.title, subtitle: spec.sub,
                        books: books, isPremium: spec.premium,
                        accentColor: spec.color, icon: spec.icon
                    )
                }
            }
            for await shelf in group {
                if let s = shelf { shelves.append(s) }
            }
        }
        return shelves.sorted { !$0.isPremium && $1.isPremium }
    }

    func clearCache() {
        Task { await cache.clear() }
    }

    // MARK: - Static Fallback Catalog
    // Used when the Google Books API is unavailable or returns empty results.
    // Each entry mirrors the WLBook structure so the UI always has content.

    static let fallbackCatalog: [WLBook] = [
        WLBook(id: "jackie-gay-bar", title: "Gay Girl, Good God",
               subtitle: "The Story of Who I Was and Who God Has Always Been",
               authors: ["Jackie Hill Perry"], description: "Jackie Hill Perry shares her personal story of walking away from homosexuality and into a life with God, offering biblical insights on identity, sexuality, and grace.",
               categories: ["Christian Living"], isbn13: "9781433560866", isbn10: nil,
               publishedDate: "2018", publisher: "B&H Publishing", pageCount: 176,
               language: "en", thumbnailURL: nil, highResThumbnailURL: nil,
               previewLink: nil, averageRating: 4.8, ratingsCount: 3200,
               isFeatured: true, recommendationReason: "A powerful testimony of identity and redemption.",
               curatedTags: ["Testimony", "Identity", "Faith"]),

        WLBook(id: "jackie-holier-than-thou", title: "Holier Than Thou",
               subtitle: "How God's Holiness Helps Us",
               authors: ["Jackie Hill Perry"], description: "Jackie Hill Perry explores the holiness of God and how understanding it transforms our lives and relationship with Christ.",
               categories: ["Theology"], isbn13: "9781535992312", isbn10: nil,
               publishedDate: "2021", publisher: "B&H Publishing", pageCount: 192,
               language: "en", thumbnailURL: nil, highResThumbnailURL: nil,
               previewLink: nil, averageRating: 4.9, ratingsCount: 1800,
               isFeatured: true, recommendationReason: "Essential reading on the holiness of God.",
               curatedTags: ["Theology", "Holiness"]),

        WLBook(id: "jackie-jude", title: "Jude: Contending for the Faith in Today's Culture",
               subtitle: nil,
               authors: ["Jackie Hill Perry"], description: "A verse-by-verse study of the book of Jude, calling believers to contend for the faith in an age of false teaching.",
               categories: ["Bible Study"], isbn13: "9781087752211", isbn10: nil,
               publishedDate: "2022", publisher: "LifeWay Press", pageCount: 192,
               language: "en", thumbnailURL: nil, highResThumbnailURL: nil,
               previewLink: nil, averageRating: 4.7, ratingsCount: 980,
               isFeatured: false, recommendationReason: nil,
               curatedTags: ["Bible Study", "Apologetics"]),

        WLBook(id: "keller-reason-for-god", title: "The Reason for God",
               subtitle: "Belief in an Age of Skepticism",
               authors: ["Timothy Keller"], description: "Timothy Keller addresses the most common doubts and objections to Christianity, making a compelling case for the truth of the faith.",
               categories: ["Apologetics"], isbn13: "9781594483493", isbn10: nil,
               publishedDate: "2008", publisher: "Dutton", pageCount: 320,
               language: "en", thumbnailURL: nil, highResThumbnailURL: nil,
               previewLink: nil, averageRating: 4.8, ratingsCount: 12000,
               isFeatured: true, recommendationReason: "The definitive modern apologetics primer.",
               curatedTags: ["Apologetics", "Theology"]),

        WLBook(id: "keller-prayer", title: "Prayer",
               subtitle: "Experiencing Awe and Intimacy with God",
               authors: ["Timothy Keller"], description: "Drawing on the wisdom of John Calvin, Martin Luther, and others, Keller shows readers how to cultivate a rich and meaningful prayer life.",
               categories: ["Prayer"], isbn13: "9780525952930", isbn10: nil,
               publishedDate: "2014", publisher: "Dutton", pageCount: 320,
               language: "en", thumbnailURL: nil, highResThumbnailURL: nil,
               previewLink: nil, averageRating: 4.7, ratingsCount: 6500,
               isFeatured: true, recommendationReason: "A masterclass on prayer for every believer.",
               curatedTags: ["Prayer", "Spiritual Growth"]),

        WLBook(id: "cs-lewis-screwtape", title: "The Screwtape Letters",
               subtitle: nil,
               authors: ["C.S. Lewis"], description: "A brilliant satirical masterpiece by C.S. Lewis, told through the correspondence of a senior demon and his nephew, revealing the tactics of spiritual warfare.",
               categories: ["Christian Classics"], isbn13: "9780060652937", isbn10: nil,
               publishedDate: "1942", publisher: "HarperOne", pageCount: 225,
               language: "en", thumbnailURL: nil, highResThumbnailURL: nil,
               previewLink: nil, averageRating: 4.9, ratingsCount: 48000,
               isFeatured: true, recommendationReason: "One of the greatest works of Christian literature.",
               curatedTags: ["Classics", "Spiritual Warfare"]),

        WLBook(id: "cs-lewis-mere-christianity", title: "Mere Christianity",
               subtitle: nil,
               authors: ["C.S. Lewis"], description: "C.S. Lewis argues for the reasonableness of Christianity and presents the core of what it means to be Christian, accessible to believers and skeptics alike.",
               categories: ["Apologetics"], isbn13: "9780060652920", isbn10: nil,
               publishedDate: "1952", publisher: "HarperOne", pageCount: 240,
               language: "en", thumbnailURL: nil, highResThumbnailURL: nil,
               previewLink: nil, averageRating: 4.9, ratingsCount: 65000,
               isFeatured: true, recommendationReason: "The most-read Christian apologetics book of the 20th century.",
               curatedTags: ["Apologetics", "Classics"]),

        WLBook(id: "foster-celebration-discipline", title: "Celebration of Discipline",
               subtitle: "The Path to Spiritual Growth",
               authors: ["Richard J. Foster"], description: "The classic guide to the inward, outward, and corporate disciplines of the Christian faith, encouraging believers toward deeper spirituality.",
               categories: ["Spiritual Disciplines"], isbn13: "9780060628284", isbn10: nil,
               publishedDate: "1978", publisher: "HarperOne", pageCount: 256,
               language: "en", thumbnailURL: nil, highResThumbnailURL: nil,
               previewLink: nil, averageRating: 4.7, ratingsCount: 14000,
               isFeatured: false, recommendationReason: "The foundational book on spiritual disciplines.",
               curatedTags: ["Spiritual Disciplines", "Classics"]),

        WLBook(id: "bonhoeffer-cost-of-discipleship", title: "The Cost of Discipleship",
               subtitle: nil,
               authors: ["Dietrich Bonhoeffer"], description: "Bonhoeffer's landmark work on what it truly means to follow Jesus, contrasting cheap grace with costly grace.",
               categories: ["Discipleship"], isbn13: "9780684815008", isbn10: nil,
               publishedDate: "1937", publisher: "Touchstone", pageCount: 320,
               language: "en", thumbnailURL: nil, highResThumbnailURL: nil,
               previewLink: nil, averageRating: 4.8, ratingsCount: 22000,
               isFeatured: true, recommendationReason: "A timeless call to radical discipleship.",
               curatedTags: ["Discipleship", "Classics"]),

        WLBook(id: "tozer-pursuit-of-god", title: "The Pursuit of God",
               subtitle: nil,
               authors: ["A.W. Tozer"], description: "Tozer's devotional classic that calls readers to press deeper into intimacy with God, emphasizing the heart of true worship and spiritual hunger.",
               categories: ["Devotional"], isbn13: "9781600660269", isbn10: nil,
               publishedDate: "1948", publisher: "Christian Publications", pageCount: 128,
               language: "en", thumbnailURL: nil, highResThumbnailURL: nil,
               previewLink: nil, averageRating: 4.9, ratingsCount: 28000,
               isFeatured: true, recommendationReason: "A devotional essential for every believer's library.",
               curatedTags: ["Devotional", "Classics", "Prayer"]),

        WLBook(id: "sarah-jakes-lost-and-found", title: "Lost and Found",
               subtitle: "Finding Hope in the Detours of Life",
               authors: ["Sarah Jakes Roberts"], description: "Sarah Jakes Roberts shares her personal journey of faith, restoration, and discovering purpose through life's unexpected detours.",
               categories: ["Christian Living"], isbn13: "9780764212451", isbn10: nil,
               publishedDate: "2014", publisher: "Bethany House", pageCount: 208,
               language: "en", thumbnailURL: nil, highResThumbnailURL: nil,
               previewLink: nil, averageRating: 4.6, ratingsCount: 3100,
               isFeatured: false, recommendationReason: nil,
               curatedTags: ["Women of Faith", "Testimony"]),

        WLBook(id: "priscilla-shirer-fervent", title: "Fervent",
               subtitle: "A Woman's Battle Plan to Serious, Specific and Strategic Prayer",
               authors: ["Priscilla Shirer"], description: "Priscilla Shirer presents a battle plan for prayer, exposing the enemy's specific strategies against women and equipping readers with targeted prayers.",
               categories: ["Prayer"], isbn13: "9781433688546", isbn10: nil,
               publishedDate: "2015", publisher: "B&H Publishing", pageCount: 240,
               language: "en", thumbnailURL: nil, highResThumbnailURL: nil,
               previewLink: nil, averageRating: 4.8, ratingsCount: 8200,
               isFeatured: true, recommendationReason: "A strategic prayer guide for women of faith.",
               curatedTags: ["Prayer", "Women of Faith"]),

        WLBook(id: "maverick-city-music-book", title: "Talking to God",
               subtitle: "What to Say When You Don't Know What to Pray",
               authors: ["Adam Weber"], description: "A refreshing and honest guide to prayer that strips away all the formality and helps believers simply talk to God as they are.",
               categories: ["Prayer"], isbn13: "9780593193037", isbn10: nil,
               publishedDate: "2021", publisher: "WaterBrook", pageCount: 240,
               language: "en", thumbnailURL: nil, highResThumbnailURL: nil,
               previewLink: nil, averageRating: 4.7, ratingsCount: 1200,
               isFeatured: false, recommendationReason: nil,
               curatedTags: ["Prayer"]),

        WLBook(id: "francis-chan-crazy-love", title: "Crazy Love",
               subtitle: "Overwhelmed by a Relentless God",
               authors: ["Francis Chan"], description: "Francis Chan challenges readers to stop engaging in a watered-down, no-cost discipleship and start living with a radical, sold-out love for God.",
               categories: ["Christian Living"], isbn13: "9781434703521", isbn10: nil,
               publishedDate: "2008", publisher: "David C Cook", pageCount: 224,
               language: "en", thumbnailURL: nil, highResThumbnailURL: nil,
               previewLink: nil, averageRating: 4.7, ratingsCount: 21000,
               isFeatured: true, recommendationReason: "A life-changing call to radical Christianity.",
               curatedTags: ["Discipleship", "Christian Living"]),

        WLBook(id: "louie-giglio-dont-give-enemy-seat", title: "Don't Give the Enemy a Seat at Your Table",
               subtitle: "It's Time to Win the Battle of Your Mind",
               authors: ["Louie Giglio"], description: "Louie Giglio takes readers through Psalm 23, revealing that God prepares a table before us in the presence of our enemies — and we must not invite the enemy to sit down.",
               categories: ["Spiritual Growth"], isbn13: "9781400228034", isbn10: nil,
               publishedDate: "2021", publisher: "Thomas Nelson", pageCount: 224,
               language: "en", thumbnailURL: nil, highResThumbnailURL: nil,
               previewLink: nil, averageRating: 4.8, ratingsCount: 9400,
               isFeatured: true, recommendationReason: "Essential for winning the battle of the mind.",
               curatedTags: ["Spiritual Warfare", "Mental Health"]),
    ]
}

// MARK: - Errors

enum WLBookServiceError: LocalizedError {
    case invalidURL, httpError(Int), noData

    var errorDescription: String? {
        switch self {
        case .invalidURL:       return "Invalid request URL."
        case .httpError(let c): return "Server error (\(c))."
        case .noData:           return "No book data returned."
        }
    }
}

// MARK: - API Response types (private)

private struct GBListResponse: Decodable {
    let totalItems: Int?
    let items: [GBItem]?
}

struct GBItem: Decodable {
    let id: String
    let volumeInfo: VolumeInfo?

    struct VolumeInfo: Decodable {
        let title: String?
        let subtitle: String?
        let authors: [String]?
        let description: String?
        let categories: [String]?
        let publishedDate: String?
        let publisher: String?
        let pageCount: Int?
        let language: String?
        let imageLinks: ImageLinks?
        let averageRating: Double?
        let ratingsCount: Int?
        let previewLink: String?
        let industryIdentifiers: [ISBN]?

        struct ImageLinks: Decodable {
            let smallThumbnail: String?
            let thumbnail: String?
            let small: String?
            let medium: String?
            let large: String?
        }
        struct ISBN: Decodable {
            let type: String
            let identifier: String
        }
    }
}

// MARK: - WLBook init from API

extension WLBook {
    init?(fromAPI item: GBItem) {
        guard let info = item.volumeInfo,
              let title = info.title, !title.isEmpty else { return nil }

        self.id    = item.id
        self.title = title
        self.subtitle = info.subtitle
        self.authors  = info.authors ?? []
        self.description  = info.description
        self.categories   = info.categories ?? []
        self.publishedDate = info.publishedDate
        self.publisher    = info.publisher
        self.pageCount    = info.pageCount
        self.language     = info.language
        self.previewLink  = info.previewLink
        self.averageRating = info.averageRating
        self.ratingsCount  = info.ratingsCount

        let rawThumb = info.imageLinks?.thumbnail ?? info.imageLinks?.smallThumbnail
        self.thumbnailURL = rawThumb?.replacingOccurrences(of: "http://", with: "https://")
        let rawHigh = info.imageLinks?.large ?? info.imageLinks?.medium ?? info.imageLinks?.small ?? rawThumb
        self.highResThumbnailURL = rawHigh?.replacingOccurrences(of: "http://", with: "https://")

        let ids = info.industryIdentifiers ?? []
        self.isbn13 = ids.first(where: { $0.type == "ISBN_13" })?.identifier
        self.isbn10 = ids.first(where: { $0.type == "ISBN_10" })?.identifier
    }
}
