//
//  CacheManager.swift
//  AMENAPP
//
//  Manages caching for API responses - offline support
//

import Foundation

// MARK: - Cache Manager

class CacheManager {
    static let shared = CacheManager()
    
    private let userDefaults = UserDefaults.standard
    private let fileManager = FileManager.default
    
    private init() {}
    
    // MARK: - Cache Keys
    
    private enum CacheKey {
        static let dailyVerse = "cached_daily_verse"
        static let dailyVerseDate = "cached_daily_verse_date"
        static let bibleBooks = "cached_bible_books"
        static let bookmarkedArticles = "bookmarked_articles"
        static let bookmarkedBooks = "bookmarked_books"
    }
    
    // MARK: - Daily Verse Caching
    
    func saveDailyVerse(_ verse: DailyVerse) {
        if let encoded = try? JSONEncoder().encode(verse) {
            userDefaults.set(encoded, forKey: CacheKey.dailyVerse)
            userDefaults.set(Date(), forKey: CacheKey.dailyVerseDate)
        }
    }
    
    func loadCachedDailyVerse() -> DailyVerse? {
        // Check if we have a cached verse from today
        guard let date = userDefaults.object(forKey: CacheKey.dailyVerseDate) as? Date,
              Calendar.current.isDateInToday(date),
              let data = userDefaults.data(forKey: CacheKey.dailyVerse),
              let verse = try? JSONDecoder().decode(DailyVerse.self, from: data) else {
            return nil
        }
        return verse
    }
    
    func clearDailyVerseCache() {
        userDefaults.removeObject(forKey: CacheKey.dailyVerse)
        userDefaults.removeObject(forKey: CacheKey.dailyVerseDate)
    }
    
    // MARK: - Books Caching
    
    func saveBooks(_ books: [BookResult], forQuery query: String) {
        let cacheKey = "books_\(query.lowercased().replacingOccurrences(of: " ", with: "_"))"
        
        if let encoded = try? JSONEncoder().encode(books) {
            userDefaults.set(encoded, forKey: cacheKey)
            userDefaults.set(Date(), forKey: "\(cacheKey)_date")
        }
    }
    
    func loadCachedBooks(forQuery query: String) -> [BookResult]? {
        let cacheKey = "books_\(query.lowercased().replacingOccurrences(of: " ", with: "_"))"
        
        // Cache expires after 7 days
        guard let date = userDefaults.object(forKey: "\(cacheKey)_date") as? Date,
              Date().timeIntervalSince(date) < 7 * 24 * 60 * 60,
              let data = userDefaults.data(forKey: cacheKey),
              let books = try? JSONDecoder().decode([BookResult].self, from: data) else {
            return nil
        }
        return books
    }
    
    // MARK: - Bookmarks
    
    func saveBookmark(articleTitle: String) {
        var bookmarks = loadBookmarkedArticles()
        if !bookmarks.contains(articleTitle) {
            bookmarks.append(articleTitle)
            userDefaults.set(bookmarks, forKey: CacheKey.bookmarkedArticles)
        }
    }
    
    func removeBookmark(articleTitle: String) {
        var bookmarks = loadBookmarkedArticles()
        bookmarks.removeAll { $0 == articleTitle }
        userDefaults.set(bookmarks, forKey: CacheKey.bookmarkedArticles)
    }
    
    func loadBookmarkedArticles() -> [String] {
        userDefaults.stringArray(forKey: CacheKey.bookmarkedArticles) ?? []
    }
    
    func isArticleBookmarked(_ title: String) -> Bool {
        loadBookmarkedArticles().contains(title)
    }
    
    // MARK: - Book Bookmarks
    
    func saveBookBookmark(_ book: BookResult) {
        var bookmarks = loadBookmarkedBooks()
        if !bookmarks.contains(where: { $0.title == book.title }) {
            bookmarks.append(book)
            if let encoded = try? JSONEncoder().encode(bookmarks) {
                userDefaults.set(encoded, forKey: CacheKey.bookmarkedBooks)
            }
        }
    }
    
    func removeBookBookmark(_ bookTitle: String) {
        var bookmarks = loadBookmarkedBooks()
        bookmarks.removeAll { $0.title == bookTitle }
        if let encoded = try? JSONEncoder().encode(bookmarks) {
            userDefaults.set(encoded, forKey: CacheKey.bookmarkedBooks)
        }
    }
    
    func loadBookmarkedBooks() -> [BookResult] {
        guard let data = userDefaults.data(forKey: CacheKey.bookmarkedBooks),
              let books = try? JSONDecoder().decode([BookResult].self, from: data) else {
            return []
        }
        return books
    }
    
    func isBookBookmarked(_ title: String) -> Bool {
        loadBookmarkedBooks().contains(where: { $0.title == title })
    }
    
    // MARK: - Clear All Cache
    
    func clearAllCache() {
        clearDailyVerseCache()
        userDefaults.removeObject(forKey: CacheKey.bookmarkedArticles)
        userDefaults.removeObject(forKey: CacheKey.bookmarkedBooks)
    }
}

// MARK: - Make BookResult Codable

extension BookResult: Codable {
    enum CodingKeys: String, CodingKey {
        case title, authors, description, imageURL, purchaseLink
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try container.decode(String.self, forKey: .title)
        self.authors = try container.decode([String].self, forKey: .authors)
        self.description = try container.decode(String.self, forKey: .description)
        self.imageURL = try container.decodeIfPresent(String.self, forKey: .imageURL)
        self.purchaseLink = try container.decodeIfPresent(String.self, forKey: .purchaseLink)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.title, forKey: .title)
        try container.encode(self.authors, forKey: .authors)
        try container.encode(self.description, forKey: .description)
        try container.encodeIfPresent(self.imageURL, forKey: .imageURL)
        try container.encodeIfPresent(self.purchaseLink, forKey: .purchaseLink)
    }
}

// MARK: - Make DailyVerse Codable

extension DailyVerse: Codable {
    enum CodingKeys: String, CodingKey {
        case text, reference
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.text = try container.decode(String.self, forKey: .text)
        self.reference = try container.decode(String.self, forKey: .reference)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.text, forKey: .text)
        try container.encode(self.reference, forKey: .reference)
    }
}
