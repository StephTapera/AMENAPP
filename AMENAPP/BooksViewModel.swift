//
//  BooksViewModel.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//
//  ViewModel for managing Essential Books state and interactions
//

import Foundation
import SwiftUI
import Combine
import FirebaseAuth

@MainActor
class BooksViewModel: ObservableObject {
    @Published var allBooks: [Book] = []
    @Published var featuredBooks: [Book] = []
    @Published var trendingBooks: [Book] = []
    @Published var recommendedBooks: [Book] = []
    @Published var savedBooks: [Book] = []
    @Published var savedBookIds: Set<String> = []
    
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let apiService = FirebaseBooksService.shared
    private var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }
    
    // MARK: - Initialization
    
    func loadInitialData() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchAllBooks() }
            group.addTask { await self.fetchFeaturedBooks() }
            group.addTask { await self.fetchTrendingBooks() }
            group.addTask { await self.fetchRecommendedBooks() }
            
            if self.currentUserId != nil {
                group.addTask { await self.loadSavedBooks() }
            }
        }
    }
    
    // MARK: - Fetch Books
    
    func fetchAllBooks() async {
        do {
            allBooks = try await apiService.fetchAllBooks()
        } catch {
            print("❌ Error fetching all books: \(error)")
            errorMessage = "Failed to load books"
        }
    }
    
    func fetchFeaturedBooks() async {
        do {
            featuredBooks = try await apiService.fetchFeaturedBooks(limit: 10)
        } catch {
            print("❌ Error fetching featured books: \(error)")
        }
    }
    
    func fetchTrendingBooks() async {
        do {
            trendingBooks = try await apiService.fetchTrendingBooks(limit: 10)
        } catch {
            print("❌ Error fetching trending books: \(error)")
        }
    }
    
    func fetchRecommendedBooks() async {
        guard let userId = currentUserId else {
            // If no user, show featured instead
            recommendedBooks = featuredBooks
            return
        }
        
        do {
            recommendedBooks = try await apiService.fetchRecommendedBooks(for: userId, limit: 10)
        } catch {
            print("❌ Error fetching recommended books: \(error)")
            // Fallback to featured books
            recommendedBooks = featuredBooks
        }
    }
    
    func fetchBooks(category: BookCategory) async -> [Book] {
        if category == .all {
            return allBooks
        }
        
        do {
            return try await apiService.fetchBooks(category: category.rawValue)
        } catch {
            print("❌ Error fetching books for category \(category.rawValue): \(error)")
            return []
        }
    }
    
    func searchBooks(query: String) async -> [Book] {
        guard !query.isEmpty else {
            return allBooks
        }
        
        do {
            return try await apiService.searchBooks(query: query)
        } catch {
            print("❌ Error searching books: \(error)")
            return []
        }
    }
    
    // MARK: - Save/Bookmark Operations
    
    func loadSavedBooks() async {
        guard let userId = currentUserId else { return }
        
        do {
            savedBooks = try await apiService.fetchSavedBooks(for: userId)
            savedBookIds = Set(savedBooks.compactMap { $0.id })
        } catch {
            print("❌ Error loading saved books: \(error)")
        }
    }
    
    func toggleSaveBook(_ book: Book) async {
        guard let bookId = book.id,
              let userId = currentUserId else {
            errorMessage = "Please sign in to save books"
            return
        }
        
        let isSaved = savedBookIds.contains(bookId)
        
        do {
            if isSaved {
                try await apiService.unsaveBook(bookId: bookId, userId: userId)
                savedBookIds.remove(bookId)
                savedBooks.removeAll { $0.id == bookId }
            } else {
                try await apiService.saveBook(bookId: bookId, userId: userId)
                savedBookIds.insert(bookId)
                savedBooks.append(book)
            }
        } catch {
            print("❌ Error toggling save book: \(error)")
            errorMessage = "Failed to save book"
        }
    }
    
    func isBookSaved(_ book: Book) -> Bool {
        guard let bookId = book.id else { return false }
        return savedBookIds.contains(bookId)
    }
    
    // MARK: - Book Interactions
    
    func viewBook(_ book: Book) async {
        guard let bookId = book.id else { return }
        
        do {
            try await apiService.incrementViewCount(bookId: bookId)
        } catch {
            print("❌ Error incrementing view count: \(error)")
        }
    }
    
    func updateReadingProgress(book: Book, progress: Double, isRead: Bool = false) async {
        guard let bookId = book.id,
              let userId = currentUserId else { return }
        
        do {
            try await apiService.updateReadingProgress(
                bookId: bookId,
                userId: userId,
                progress: progress,
                isRead: isRead
            )
        } catch {
            print("❌ Error updating reading progress: \(error)")
        }
    }
    
    // MARK: - Filtering & Sorting
    
    func filterBooks(_ books: [Book], by category: BookCategory, searchText: String) -> [Book] {
        var filtered = books
        
        // Filter by category
        if category != .all {
            filtered = filtered.filter { $0.category == category.rawValue }
        }
        
        // Filter by search text
        if !searchText.isEmpty {
            let lowercaseQuery = searchText.lowercased()
            filtered = filtered.filter {
                $0.title.lowercased().contains(lowercaseQuery) ||
                $0.author.lowercased().contains(lowercaseQuery) ||
                $0.description.lowercased().contains(lowercaseQuery) ||
                $0.tags.contains { $0.lowercased().contains(lowercaseQuery) }
            }
        }
        
        return filtered
    }
    
    func sortBooks(_ books: [Book], by sortOption: BookSortOption) -> [Book] {
        switch sortOption {
        case .titleAZ:
            return books.sorted { $0.title < $1.title }
        case .titleZA:
            return books.sorted { $0.title > $1.title }
        case .authorAZ:
            return books.sorted { $0.author < $1.author }
        case .ratingHighToLow:
            return books.sorted { $0.rating > $1.rating }
        case .mostSaved:
            return books.sorted { $0.savedCount > $1.savedCount }
        case .newest:
            return books.sorted { $0.createdAt > $1.createdAt }
        }
    }
}

// MARK: - Sort Options

enum BookSortOption: String, CaseIterable {
    case titleAZ = "Title (A-Z)"
    case titleZA = "Title (Z-A)"
    case authorAZ = "Author (A-Z)"
    case ratingHighToLow = "Highest Rated"
    case mostSaved = "Most Saved"
    case newest = "Newest"
    
    var icon: String {
        switch self {
        case .titleAZ, .titleZA:
            return "textformat"
        case .authorAZ:
            return "person.fill"
        case .ratingHighToLow:
            return "star.fill"
        case .mostSaved:
            return "bookmark.fill"
        case .newest:
            return "clock.fill"
        }
    }
}
