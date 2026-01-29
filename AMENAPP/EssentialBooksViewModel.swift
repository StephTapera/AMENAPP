//
//  EssentialBooksViewModel.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//
//  ViewModel for Essential Books feature - manages book data and user interactions
//

import Foundation
import SwiftUI
import Combine
import FirebaseAuth

@MainActor
class EssentialBooksViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var allBooks: [Book] = []
    @Published var featuredBooks: [Book] = []
    @Published var trendingBooks: [Book] = []
    @Published var recommendedBooks: [Book] = []
    @Published var savedBooks: [Book] = []
    
    @Published var selectedCategory: BookCategory = .all
    @Published var searchQuery: String = ""
    @Published var searchResults: [Book] = []
    
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    
    private let service = FirebaseBooksService.shared
    private var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }
    
    // MARK: - Computed Properties
    
    var displayedBooks: [Book] {
        if !searchQuery.isEmpty {
            return searchResults
        } else if selectedCategory == .all {
            return allBooks
        } else {
            return allBooks.filter { $0.category == selectedCategory.rawValue }
        }
    }
    
    // MARK: - Initialization
    
    init() {
        Task {
            await loadInitialData()
        }
    }
    
    // MARK: - Data Loading
    
    /// Load all initial data
    func loadInitialData() async {
        isLoading = true
        errorMessage = nil
        
        do {
            async let featured = service.fetchFeaturedBooks(limit: 5)
            async let trending = service.fetchTrendingBooks(limit: 10)
            async let all = service.fetchAllBooks()
            
            featuredBooks = try await featured
            trendingBooks = try await trending
            allBooks = try await all
            
            // Load user-specific data
            if let userId = currentUserId {
                async let recommended = service.fetchRecommendedBooks(for: userId, limit: 10)
                async let saved = service.fetchSavedBooks(for: userId)
                
                recommendedBooks = try await recommended
                savedBooks = try await saved
            }
            
            print("✅ Loaded all books data successfully")
        } catch {
            errorMessage = "Failed to load books: \(error.localizedDescription)"
            print("❌ Error loading books: \(error)")
        }
        
        isLoading = false
    }
    
    /// Refresh all data
    func refresh() async {
        await loadInitialData()
    }
    
    /// Load books by category
    func loadBooksByCategory(_ category: BookCategory) async {
        selectedCategory = category
        
        if category == .all {
            // Already loaded
            return
        }
        
        isLoading = true
        
        do {
            let books = try await service.fetchBooks(category: category.rawValue)
            allBooks = books
        } catch {
            errorMessage = "Failed to load books: \(error.localizedDescription)"
            print("❌ Error loading books by category: \(error)")
        }
        
        isLoading = false
    }
    
    /// Search books
    func searchBooks(query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        searchQuery = query
        isLoading = true
        
        do {
            searchResults = try await service.searchBooks(query: query)
        } catch {
            errorMessage = "Failed to search books: \(error.localizedDescription)"
            print("❌ Error searching books: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - User Interactions
    
    /// Save/bookmark a book
    func saveBook(_ book: Book) async {
        guard let userId = currentUserId, let bookId = book.id else {
            errorMessage = "You must be logged in to save books"
            return
        }
        
        do {
            try await service.saveBook(bookId: bookId, userId: userId)
            
            // Update local state
            if !savedBooks.contains(where: { $0.id == bookId }) {
                savedBooks.append(book)
            }
            
            print("✅ Book saved: \(book.title)")
        } catch {
            errorMessage = "Failed to save book: \(error.localizedDescription)"
            print("❌ Error saving book: \(error)")
        }
    }
    
    /// Unsave/unbookmark a book
    func unsaveBook(_ book: Book) async {
        guard let userId = currentUserId, let bookId = book.id else {
            return
        }
        
        do {
            try await service.unsaveBook(bookId: bookId, userId: userId)
            
            // Update local state
            savedBooks.removeAll { $0.id == bookId }
            
            print("✅ Book unsaved: \(book.title)")
        } catch {
            errorMessage = "Failed to unsave book: \(error.localizedDescription)"
            print("❌ Error unsaving book: \(error)")
        }
    }
    
    /// Check if a book is saved
    func isBookSaved(_ book: Book) -> Bool {
        guard let bookId = book.id else { return false }
        return savedBooks.contains { $0.id == bookId }
    }
    
    /// Increment view count when user opens a book
    func trackBookView(_ book: Book) async {
        guard let bookId = book.id else { return }
        
        do {
            try await service.incrementViewCount(bookId: bookId)
        } catch {
            print("⚠️ Failed to increment view count: \(error)")
            // Don't show error to user - this is a background operation
        }
    }
    
    /// Update reading progress
    func updateReadingProgress(for book: Book, progress: Double, isRead: Bool = false) async {
        guard let userId = currentUserId, let bookId = book.id else {
            return
        }
        
        do {
            try await service.updateReadingProgress(
                bookId: bookId,
                userId: userId,
                progress: progress,
                isRead: isRead
            )
            
            print("✅ Reading progress updated: \(progress * 100)%")
        } catch {
            errorMessage = "Failed to update reading progress: \(error.localizedDescription)"
            print("❌ Error updating reading progress: \(error)")
        }
    }
    
    // MARK: - Reviews
    
    /// Submit a review for a book
    func submitReview(
        for book: Book,
        rating: Int,
        reviewText: String
    ) async {
        guard let userId = currentUserId,
              let bookId = book.id,
              let currentUser = Auth.auth().currentUser else {
            errorMessage = "You must be logged in to submit reviews"
            return
        }
        
        do {
            // Get user profile data
            let userName = currentUser.displayName ?? "Anonymous"
            let userProfileImageURL = currentUser.photoURL?.absoluteString
            
            try await service.submitReview(
                bookId: bookId,
                userId: userId,
                userName: userName,
                userProfileImageURL: userProfileImageURL,
                rating: rating,
                reviewText: reviewText
            )
            
            print("✅ Review submitted for: \(book.title)")
        } catch {
            errorMessage = "Failed to submit review: \(error.localizedDescription)"
            print("❌ Error submitting review: \(error)")
        }
    }
    
    /// Fetch reviews for a book
    func fetchReviews(for book: Book) async -> [BookReview] {
        guard let bookId = book.id else { return [] }
        
        do {
            let reviews = try await service.fetchReviews(for: bookId)
            return reviews
        } catch {
            errorMessage = "Failed to load reviews: \(error.localizedDescription)"
            print("❌ Error fetching reviews: \(error)")
            return []
        }
    }
    
    // MARK: - Helper Methods
    
    /// Clear error message
    func clearError() {
        errorMessage = nil
    }
}

// MARK: - How to Use in SwiftUI View

/*
 
 Example usage in EssentialBooksView:
 
 ```swift
 import SwiftUI
 
 struct EssentialBooksView: View {
     @StateObject private var viewModel = EssentialBooksViewModel()
     
     var body: some View {
         ScrollView {
             VStack(spacing: 24) {
                 // Search Bar
                 SearchBar(text: $viewModel.searchQuery)
                     .onChange(of: viewModel.searchQuery) { _, newValue in
                         Task {
                             await viewModel.searchBooks(query: newValue)
                         }
                     }
                 
                 // Featured Books
                 if !viewModel.featuredBooks.isEmpty {
                     FeaturedBooksCarousel(books: viewModel.featuredBooks)
                 }
                 
                 // Recommended Books
                 if !viewModel.recommendedBooks.isEmpty {
                     RecommendedBooksSection(books: viewModel.recommendedBooks)
                 }
                 
                 // Category Filter
                 CategoryFilterView(selectedCategory: $viewModel.selectedCategory)
                     .onChange(of: viewModel.selectedCategory) { _, newCategory in
                         Task {
                             await viewModel.loadBooksByCategory(newCategory)
                         }
                     }
                 
                 // Books Grid
                 LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                     ForEach(viewModel.displayedBooks) { book in
                         BookCard(
                             book: book,
                             isSaved: viewModel.isBookSaved(book),
                             onSave: {
                                 Task {
                                     if viewModel.isBookSaved(book) {
                                         await viewModel.unsaveBook(book)
                                     } else {
                                         await viewModel.saveBook(book)
                                     }
                                 }
                             },
                             onTap: {
                                 // Navigate to book detail
                                 Task {
                                     await viewModel.trackBookView(book)
                                 }
                             }
                         )
                     }
                 }
                 .padding(.horizontal)
             }
         }
         .navigationTitle("Essential Books")
         .overlay {
             if viewModel.isLoading {
                 ProgressView()
             }
         }
         .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
             Button("OK") {
                 viewModel.clearError()
             }
         } message: {
             Text(viewModel.errorMessage ?? "")
         }
         .refreshable {
             await viewModel.refresh()
         }
     }
 }
 ```
 
 */
