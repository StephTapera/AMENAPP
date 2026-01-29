//
//  BooksAPIService.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//
//  API service for Essential Books - handles all book-related Firebase operations
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

/// Service for managing book data and user interactions with books
@MainActor
final class FirebaseBooksService {
    static let shared = FirebaseBooksService()
    
    private let firestore = Firestore.firestore()
    private let auth = Auth.auth()
    
    // Collection references
    private var booksCollection: CollectionReference {
        firestore.collection("books")
    }
    
    private var savedBooksCollection: CollectionReference {
        firestore.collection("savedBooks")
    }
    
    private var bookReviewsCollection: CollectionReference {
        firestore.collection("bookReviews")
    }
    
    private init() {}
    
    // MARK: - Fetch Books
    
    /// Fetch all books from Firestore
    func fetchAllBooks() async throws -> [Book] {
        print("📚 Fetching all books from Firestore...")
        
        let snapshot = try await booksCollection
            .order(by: "createdAt", descending: true)
            .getDocuments()
        
        let books = try snapshot.documents.compactMap { doc -> Book? in
            try doc.data(as: Book.self)
        }
        
        print("✅ Fetched \(books.count) books")
        return books
    }
    
    /// Fetch books by category
    func fetchBooks(category: String) async throws -> [Book] {
        print("📚 Fetching books in category: \(category)")
        
        let snapshot = try await booksCollection
            .whereField("category", isEqualTo: category)
            .order(by: "createdAt", descending: true)
            .getDocuments()
        
        let books = try snapshot.documents.compactMap { doc -> Book? in
            try doc.data(as: Book.self)
        }
        
        print("✅ Fetched \(books.count) books in \(category)")
        return books
    }
    
    /// Fetch featured books
    func fetchFeaturedBooks(limit: Int = 10) async throws -> [Book] {
        print("⭐ Fetching featured books...")
        
        let snapshot = try await booksCollection
            .whereField("isFeatured", isEqualTo: true)
            .limit(to: limit)
            .getDocuments()
        
        let books = try snapshot.documents.compactMap { doc -> Book? in
            try doc.data(as: Book.self)
        }
        
        print("✅ Fetched \(books.count) featured books")
        return books
    }
    
    /// Fetch trending books
    func fetchTrendingBooks(limit: Int = 10) async throws -> [Book] {
        print("🔥 Fetching trending books...")
        
        let snapshot = try await booksCollection
            .whereField("isTrending", isEqualTo: true)
            .order(by: "viewCount", descending: true)
            .limit(to: limit)
            .getDocuments()
        
        let books = try snapshot.documents.compactMap { doc -> Book? in
            try doc.data(as: Book.self)
        }
        
        print("✅ Fetched \(books.count) trending books")
        return books
    }
    
    /// Fetch recommended books based on user interests (from onboarding)
    func fetchRecommendedBooks(for userId: String, limit: Int = 10) async throws -> [Book] {
        print("💡 Fetching recommended books for user: \(userId)")
        
        // Get user interests from their profile
        let userDoc = try await firestore.collection("users").document(userId).getDocument()
        guard let userData = userDoc.data(),
              let interests = userData["interests"] as? [String] else {
            print("⚠️ No user interests found, returning featured books")
            return try await fetchFeaturedBooks(limit: limit)
        }
        
        // Convert interests to book categories
        let categoryMapping: [String: String] = [
            "Bible Study": "Theology",
            "Prayer": "Devotional",
            "Worship": "Devotional",
            "Community": "Biography",
            "Devotionals": "Devotional",
            "Missions": "Biography",
            "Youth Ministry": "New Believer",
            "Theology": "Theology",
            "Evangelism": "Apologetics"
        ]
        
        var categories = Set<String>()
        for interest in interests {
            if let category = categoryMapping[interest] {
                categories.insert(category)
            }
        }
        
        if categories.isEmpty {
            return try await fetchFeaturedBooks(limit: limit)
        }
        
        // Fetch books from relevant categories
        let snapshot = try await booksCollection
            .whereField("category", in: Array(categories))
            .order(by: "rating", descending: true)
            .limit(to: limit)
            .getDocuments()
        
        let books = try snapshot.documents.compactMap { doc -> Book? in
            try doc.data(as: Book.self)
        }
        
        print("✅ Fetched \(books.count) recommended books")
        return books
    }
    
    /// Search books by title, author, or tags
    func searchBooks(query: String) async throws -> [Book] {
        print("🔍 Searching books with query: \(query)")
        
        let lowercaseQuery = query.lowercased()
        
        // Fetch all books and filter client-side (Firestore doesn't support full-text search)
        let allBooks = try await fetchAllBooks()
        
        let results = allBooks.filter { book in
            book.title.lowercased().contains(lowercaseQuery) ||
            book.author.lowercased().contains(lowercaseQuery) ||
            book.description.lowercased().contains(lowercaseQuery) ||
            book.tags.contains { $0.lowercased().contains(lowercaseQuery) }
        }
        
        print("✅ Found \(results.count) books matching query")
        return results
    }
    
    /// Fetch a single book by ID
    func fetchBook(id: String) async throws -> Book {
        print("📖 Fetching book with ID: \(id)")
        
        let doc = try await booksCollection.document(id).getDocument()
        guard let book = try? doc.data(as: Book.self) else {
            throw FirebaseBooksError.bookNotFound
        }
        
        print("✅ Fetched book: \(book.title)")
        return book
    }
    
    // MARK: - User Book Interactions
    
    /// Save/bookmark a book
    func saveBook(bookId: String, userId: String) async throws {
        print("💾 Saving book \(bookId) for user \(userId)")
        
        let savedBook = SavedBook(
            userId: userId,
            bookId: bookId,
            savedAt: Date()
        )
        
        let docRef = savedBooksCollection.document()
        try docRef.setData(from: savedBook)
        
        // Increment saved count on book
        try await booksCollection.document(bookId).updateData([
            "savedCount": FieldValue.increment(Int64(1))
        ])
        
        print("✅ Book saved successfully")
    }
    
    /// Unsave/unbookmark a book
    func unsaveBook(bookId: String, userId: String) async throws {
        print("🗑️ Unsaving book \(bookId) for user \(userId)")
        
        let snapshot = try await savedBooksCollection
            .whereField("userId", isEqualTo: userId)
            .whereField("bookId", isEqualTo: bookId)
            .getDocuments()
        
        for doc in snapshot.documents {
            try await doc.reference.delete()
        }
        
        // Decrement saved count on book
        try await booksCollection.document(bookId).updateData([
            "savedCount": FieldValue.increment(Int64(-1))
        ])
        
        print("✅ Book unsaved successfully")
    }
    
    /// Check if user has saved a book
    func isBookSaved(bookId: String, userId: String) async throws -> Bool {
        let snapshot = try await savedBooksCollection
            .whereField("userId", isEqualTo: userId)
            .whereField("bookId", isEqualTo: bookId)
            .limit(to: 1)
            .getDocuments()
        
        return !snapshot.documents.isEmpty
    }
    
    /// Fetch user's saved books
    func fetchSavedBooks(for userId: String) async throws -> [Book] {
        print("📚 Fetching saved books for user: \(userId)")
        
        let snapshot = try await savedBooksCollection
            .whereField("userId", isEqualTo: userId)
            .order(by: "savedAt", descending: true)
            .getDocuments()
        
        let bookIds = snapshot.documents.compactMap { doc -> String? in
            try? doc.data(as: SavedBook.self).bookId
        }
        
        if bookIds.isEmpty {
            return []
        }
        
        // Fetch books by IDs
        var books: [Book] = []
        for bookId in bookIds {
            if let book = try? await fetchBook(id: bookId) {
                books.append(book)
            }
        }
        
        print("✅ Fetched \(books.count) saved books")
        return books
    }
    
    /// Increment view count for a book
    func incrementViewCount(bookId: String) async throws {
        try await booksCollection.document(bookId).updateData([
            "viewCount": FieldValue.increment(Int64(1))
        ])
    }
    
    /// Update reading progress
    func updateReadingProgress(bookId: String, userId: String, progress: Double, isRead: Bool = false) async throws {
        print("📊 Updating reading progress for book \(bookId): \(progress * 100)%")
        
        let snapshot = try await savedBooksCollection
            .whereField("userId", isEqualTo: userId)
            .whereField("bookId", isEqualTo: bookId)
            .limit(to: 1)
            .getDocuments()
        
        guard let doc = snapshot.documents.first else {
            throw FirebaseBooksError.savedBookNotFound
        }
        
        try await doc.reference.updateData([
            "readingProgress": progress,
            "isRead": isRead
        ])
        
        print("✅ Reading progress updated")
    }
    
    // MARK: - Book Reviews
    
    /// Submit a review for a book
    func submitReview(
        bookId: String,
        userId: String,
        userName: String,
        userProfileImageURL: String?,
        rating: Int,
        reviewText: String
    ) async throws {
        print("⭐ Submitting review for book: \(bookId)")
        
        let review = BookReview(
            bookId: bookId,
            userId: userId,
            userName: userName,
            userProfileImageURL: userProfileImageURL,
            rating: rating,
            reviewText: reviewText,
            createdAt: Date(),
            likesCount: 0
        )
        
        let docRef = bookReviewsCollection.document()
        try docRef.setData(from: review)
        
        // Update book's average rating
        try await updateBookAverageRating(bookId: bookId)
        
        print("✅ Review submitted successfully")
    }
    
    /// Fetch reviews for a book
    func fetchReviews(for bookId: String) async throws -> [BookReview] {
        print("📝 Fetching reviews for book: \(bookId)")
        
        let snapshot = try await bookReviewsCollection
            .whereField("bookId", isEqualTo: bookId)
            .order(by: "createdAt", descending: true)
            .getDocuments()
        
        let reviews = try snapshot.documents.compactMap { doc -> BookReview? in
            try doc.data(as: BookReview.self)
        }
        
        print("✅ Fetched \(reviews.count) reviews")
        return reviews
    }
    
    /// Update book's average rating
    private func updateBookAverageRating(bookId: String) async throws {
        let reviews = try await fetchReviews(for: bookId)
        
        guard !reviews.isEmpty else { return }
        
        let totalRating = reviews.reduce(0) { $0 + $1.rating }
        let averageRating = Int(round(Double(totalRating) / Double(reviews.count)))
        
        try await booksCollection.document(bookId).updateData([
            "rating": averageRating
        ])
    }
    
    // MARK: - Admin Operations (for seeding data)
    
    /// Add a new book to Firestore (admin only)
    func addBook(_ book: Book) async throws -> String {
        print("➕ Adding new book: \(book.title)")
        
        let docRef = booksCollection.document()
        var newBook = book
        newBook.id = docRef.documentID
        
        try docRef.setData(from: newBook)
        
        print("✅ Book added with ID: \(docRef.documentID)")
        return docRef.documentID
    }
    
    /// Update an existing book
    func updateBook(_ book: Book) async throws {
        guard let bookId = book.id else {
            throw FirebaseBooksError.invalidBookId
        }
        
        print("✏️ Updating book: \(book.title)")
        
        try booksCollection.document(bookId).setData(from: book, merge: true)
        
        print("✅ Book updated successfully")
    }
    
    /// Delete a book
    func deleteBook(id: String) async throws {
        print("🗑️ Deleting book: \(id)")
        
        try await booksCollection.document(id).delete()
        
        // Also delete all saved references and reviews
        let savedSnapshot = try await savedBooksCollection
            .whereField("bookId", isEqualTo: id)
            .getDocuments()
        
        for doc in savedSnapshot.documents {
            try await doc.reference.delete()
        }
        
        let reviewsSnapshot = try await bookReviewsCollection
            .whereField("bookId", isEqualTo: id)
            .getDocuments()
        
        for doc in reviewsSnapshot.documents {
            try await doc.reference.delete()
        }
        
        print("✅ Book and related data deleted successfully")
    }
}

// MARK: - Errors

enum FirebaseBooksError: LocalizedError {
    case bookNotFound
    case savedBookNotFound
    case invalidBookId
    case unauthorized
    
    var errorDescription: String? {
        switch self {
        case .bookNotFound:
            return "Book not found"
        case .savedBookNotFound:
            return "Saved book record not found"
        case .invalidBookId:
            return "Invalid book ID"
        case .unauthorized:
            return "You are not authorized to perform this action"
        }
    }
}
