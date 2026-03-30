// BookModels.swift
// AMENAPP
//
// Core data models for the AMEN Wisdom Library feature.
// Prefixed with "WL" (WisdomLibrary) to avoid conflict with
// the existing BookModel.swift (EssentialBooks feature).

import Foundation
import SwiftUI

// MARK: - WLBook (Google Books-sourced)

struct WLBook: Identifiable, Codable, Hashable {
    let id: String                      // Google volume ID
    let title: String
    let subtitle: String?
    let authors: [String]
    let description: String?
    let categories: [String]
    let isbn13: String?
    let isbn10: String?
    let publishedDate: String?
    let publisher: String?
    let pageCount: Int?
    let language: String?
    let thumbnailURL: String?
    let highResThumbnailURL: String?
    let previewLink: String?
    let averageRating: Double?
    let ratingsCount: Int?

    // Affiliate routing
    var amazonAffiliateURL: String?
    var appleBooksURL: String?

    // AMEN metadata
    var isFeatured: Bool = false
    var recommendationReason: String?
    var curatedTags: [String] = []

    var primaryAuthor: String { authors.first ?? "Unknown Author" }

    var authorDisplayString: String {
        switch authors.count {
        case 0: return "Unknown Author"
        case 1: return authors[0]
        case 2: return "\(authors[0]) & \(authors[1])"
        default: return "\(authors[0]) et al."
        }
    }

    var shortDescription: String? {
        guard let desc = description else { return nil }
        let cleaned = desc.replacingOccurrences(of: "<[^>]+>", with: "",
                                                options: .regularExpression)
        return cleaned.isEmpty ? nil : cleaned
    }

    var primaryCategory: String? { categories.first }

    var coverColor: Color {
        let hash = abs(title.hashValue)
        let colors: [Color] = [.blue, .purple, .orange, .green, .pink, .indigo, .teal]
        return colors[hash % colors.count]
    }

    static var placeholder: WLBook {
        WLBook(id: UUID().uuidString, title: "Loading…", subtitle: nil,
               authors: ["Author"], description: nil, categories: [],
               isbn13: nil, isbn10: nil, publishedDate: nil, publisher: nil,
               pageCount: nil, language: nil, thumbnailURL: nil,
               highResThumbnailURL: nil, previewLink: nil,
               averageRating: nil, ratingsCount: nil)
    }
}

// MARK: - WLBookShelf

struct WLBookShelf: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let books: [WLBook]
    let isPremium: Bool
    let accentColor: Color
    let icon: String?
}

// MARK: - WLBookCategory

enum WLBookCategory: String, CaseIterable, Identifiable {
    case all          = "All"
    case womenOfFaith = "Women of Faith"
    case theology     = "Theology"
    case discipleship = "Discipleship"
    case prayer       = "Prayer"
    case marriage     = "Marriage"
    case leadership   = "Leadership"
    case history      = "Church History"
    case missions     = "Missions"
    case devotional   = "Devotional"
    case apologetics  = "Apologetics"
    case spiritual    = "Spiritual Formation"
    case classics     = "Classics"

    var id: String { rawValue }

    var googleQuery: String {
        switch self {
        case .all:          return "christian"
        case .womenOfFaith: return "Jackie Hill Perry christian women faith"
        case .theology:     return "christian theology"
        case .discipleship: return "christian discipleship"
        case .prayer:       return "christian prayer book"
        case .marriage:     return "christian marriage"
        case .leadership:   return "christian leadership"
        case .history:      return "church history"
        case .missions:     return "christian missions"
        case .devotional:   return "christian devotional"
        case .apologetics:  return "christian apologetics"
        case .spiritual:    return "spiritual disciplines christian"
        case .classics:     return "christian classics theology"
        }
    }

    var icon: String {
        switch self {
        case .all:          return "books.vertical"
        case .womenOfFaith: return "person.crop.circle.badge.checkmark"
        case .theology:     return "scroll"
        case .discipleship: return "figure.walk"
        case .prayer:       return "hands.sparkles"
        case .marriage:     return "heart.circle"
        case .leadership:   return "person.3"
        case .history:      return "clock"
        case .missions:     return "globe"
        case .devotional:   return "sun.max"
        case .apologetics:  return "shield"
        case .spiritual:    return "sparkles"
        case .classics:     return "crown"
        }
    }
}

// MARK: - WLSavedBook

struct WLSavedBook: Identifiable, Codable {
    var id: String
    let userId: String
    let bookId: String
    let title: String
    let author: String
    let thumbnailURL: String?
    let savedAt: Date
    var collectionIds: [String]

    init(book: WLBook, userId: String) {
        self.id = book.id
        self.userId = userId
        self.bookId = book.id
        self.title = book.title
        self.author = book.primaryAuthor
        self.thumbnailURL = book.thumbnailURL
        self.savedAt = Date()
        self.collectionIds = []
    }
}

// MARK: - WLReadingStats

struct WLReadingStats {
    let streakDays: Int
    let booksThisMonth: Int
    let totalSaved: Int
    static let empty = WLReadingStats(streakDays: 0, booksThisMonth: 0, totalSaved: 0)
}
