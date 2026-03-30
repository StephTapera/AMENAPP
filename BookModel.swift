//
//  BookModel.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//
//  Book data model for Essential Books feature
//

import Foundation
import SwiftUI
import FirebaseFirestore

/// Book model representing a Christian book resource
struct Book: Identifiable, Codable, Hashable {
    @DocumentID var id: String?
    var title: String
    var author: String
    var description: String
    var category: String
    var rating: Int
    var coverImageURL: String?
    var purchaseURL: String?
    var isbn: String?
    var publishedDate: Date?
    var pageCount: Int?
    var publisher: String?
    var isFeatured: Bool
    var isTrending: Bool
    var tags: [String]
    var savedCount: Int
    var viewCount: Int
    var createdAt: Date
    var updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case author
        case description
        case category
        case rating
        case coverImageURL
        case purchaseURL
        case isbn
        case publishedDate
        case pageCount
        case publisher
        case isFeatured
        case isTrending
        case tags
        case savedCount
        case viewCount
        case createdAt
        case updatedAt
    }
    
    // Computed property for cover colors (gradient fallback)
    var coverColors: [Color] {
        // If we have a cover image, use default gradient
        // In real app, you could analyze the image for dominant colors
        switch category {
        case "Apologetics":
            return [.blue, .indigo]
        case "Devotional":
            return [.green, .teal]
        case "New Believer":
            return [.orange, .red]
        case "Theology":
            return [.purple, .pink]
        case "Biography":
            return [.cyan, .blue]
        default:
            return [.gray, .blue]
        }
    }
    
    // Default initializer for creating new books
    init(
        id: String? = nil,
        title: String,
        author: String,
        description: String,
        category: String,
        rating: Int = 5,
        coverImageURL: String? = nil,
        purchaseURL: String? = nil,
        isbn: String? = nil,
        publishedDate: Date? = nil,
        pageCount: Int? = nil,
        publisher: String? = nil,
        isFeatured: Bool = false,
        isTrending: Bool = false,
        tags: [String] = [],
        savedCount: Int = 0,
        viewCount: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.description = description
        self.category = category
        self.rating = rating
        self.coverImageURL = coverImageURL
        self.purchaseURL = purchaseURL
        self.isbn = isbn
        self.publishedDate = publishedDate
        self.pageCount = pageCount
        self.publisher = publisher
        self.isFeatured = isFeatured
        self.isTrending = isTrending
        self.tags = tags
        self.savedCount = savedCount
        self.viewCount = viewCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Book category enum for filtering
enum BookCategory: String, CaseIterable {
    case all = "All"
    case newBeliever = "New Believer"
    case theology = "Theology"
    case devotional = "Devotional"
    case biography = "Biography"
    case apologetics = "Apologetics"
    
    var displayName: String {
        rawValue
    }
    
    var icon: String {
        switch self {
        case .all:
            return "books.vertical.fill"
        case .newBeliever:
            return "book.closed.fill"
        case .theology:
            return "graduationcap.fill"
        case .devotional:
            return "heart.text.square.fill"
        case .biography:
            return "person.text.rectangle.fill"
        case .apologetics:
            return "brain.head.profile"
        }
    }
}

/// User's saved book model
struct SavedBook: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var bookId: String
    var savedAt: Date
    var notes: String?
    var isRead: Bool
    var readingProgress: Double // 0.0 to 1.0
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case bookId
        case savedAt
        case notes
        case isRead
        case readingProgress
    }
    
    init(
        id: String? = nil,
        userId: String,
        bookId: String,
        savedAt: Date = Date(),
        notes: String? = nil,
        isRead: Bool = false,
        readingProgress: Double = 0.0
    ) {
        self.id = id
        self.userId = userId
        self.bookId = bookId
        self.savedAt = savedAt
        self.notes = notes
        self.isRead = isRead
        self.readingProgress = readingProgress
    }
}

/// Book review model
struct BookReview: Identifiable, Codable {
    @DocumentID var id: String?
    var bookId: String
    var userId: String
    var userName: String
    var userProfileImageURL: String?
    var rating: Int
    var reviewText: String
    var createdAt: Date
    var likesCount: Int
    
    enum CodingKeys: String, CodingKey {
        case id
        case bookId
        case userId
        case userName
        case userProfileImageURL
        case rating
        case reviewText
        case createdAt
        case likesCount
    }
}
