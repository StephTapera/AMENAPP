//
//  EssentialBooksView.swift
//  AMENAPP
//
//  Created by Steph on 1/17/26.
//
//  Smart book recommendations with personalized discovery - now with Firebase backend!
//

import SwiftUI

struct EssentialBooksView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = BooksViewModel()
    
    @State private var selectedCategory: BookCategory = .all
    @State private var searchText = ""
    @State private var showFilters = false
    @State private var viewMode: ViewMode = .grid
    @State private var sortOption: BookSortOption = .newest
    @State private var showSortOptions = false
    
    enum ViewMode {
        case list, grid
    }
    
    var filteredBooks: [Book] {
        let filtered = viewModel.filterBooks(viewModel.allBooks, by: selectedCategory, searchText: searchText)
        return viewModel.sortBooks(filtered, by: sortOption)
    }
    
    var recommendedBooks: [Book] {
        // Show category-specific recommendations
        if selectedCategory == .all {
            return viewModel.recommendedBooks
        } else {
            return viewModel.recommendedBooks.filter { $0.category == selectedCategory.rawValue }
        }
    }
    
    var trendingBooks: [Book] {
        // Filter trending by category
        if selectedCategory == .all {
            return viewModel.trendingBooks
        } else {
            return viewModel.trendingBooks.filter { $0.category == selectedCategory.rawValue }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Loading state
            if viewModel.isLoading {
                ProgressView("Loading books...")
                    .padding()
            }
            
            // Smart Search bar
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                
                TextField("Search books or authors", text: $searchText)
                    .font(.custom("OpenSans-Regular", size: 16))
                
                if !searchText.isEmpty {
                    Button {
                        withAnimation {
                            searchText = ""
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
            )
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            
            // Category filter + View mode
            HStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(BookCategory.allCases, id: \.self) { category in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedCategory = category
                                    let haptic = UIImpactFeedbackGenerator(style: .light)
                                    haptic.impactOccurred()
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: category.icon)
                                        .font(.system(size: 12))
                                    Text(category.rawValue)
                                        .font(.custom("OpenSans-SemiBold", size: 14))
                                }
                                .foregroundStyle(selectedCategory == category ? .white : .primary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(selectedCategory == category ? Color.black : Color(.systemGray6))
                                )
                            }
                        }
                    }
                    .padding(.leading, 20)
                }
                
                // Sort button
                Button {
                    showSortOptions.toggle()
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(Color(.systemGray6))
                        )
                }
                .padding(.trailing, 4)
                
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        viewMode = viewMode == .list ? .grid : .list
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                    }
                } label: {
                    Image(systemName: viewMode == .list ? "square.grid.2x2" : "list.bullet")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(Color(.systemGray6))
                        )
                }
                .padding(.trailing, 20)
            }
            .padding(.vertical, 12)
            
            ScrollView {
                VStack(spacing: 24) {
                    // For You Section - Smart Recommendations (only show if not searching)
                    if searchText.isEmpty && !recommendedBooks.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.blue)
                                Text(selectedCategory == .all ? "Recommended For You" : "Recommended \(selectedCategory.rawValue)")
                                    .font(.custom("OpenSans-Bold", size: 22))
                                
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(recommendedBooks) { book in
                                        ForYouBookCard(book: book)
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                    }
                    
                    // Trending Now (only show if not searching)
                    if searchText.isEmpty && !trendingBooks.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .foregroundStyle(.orange)
                                Text(selectedCategory == .all ? "Trending This Week" : "Trending in \(selectedCategory.rawValue)")
                                    .font(.custom("OpenSans-Bold", size: 22))
                                
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(trendingBooks) { book in
                                        TrendingBookCard(book: book)
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                    }
                    
                    // All Books Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(searchText.isEmpty ? (selectedCategory == .all ? "All Books" : selectedCategory.rawValue) : "Search Results")
                                .font(.custom("OpenSans-Bold", size: 22))
                            
                            Spacer()
                            
                            Text("\(filteredBooks.count)")
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Color(.systemGray6))
                                )
                        }
                        .padding(.horizontal, 20)
                        
                        if filteredBooks.isEmpty {
                            // Empty state
                            VStack(spacing: 16) {
                                Image(systemName: "books.vertical")
                                    .font(.system(size: 60))
                                    .foregroundStyle(.secondary)
                                
                                Text(searchText.isEmpty ? "No books in this category" : "No books found")
                                    .font(.custom("OpenSans-Bold", size: 18))
                                    .foregroundStyle(.primary)
                                
                                Text(searchText.isEmpty ? "Try selecting a different category" : "Try adjusting your search terms")
                                    .font(.custom("OpenSans-Regular", size: 14))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                        } else if viewMode == .list {
                            ForEach(filteredBooks) { book in
                                SmartBookCard(book: book)
                            }
                        } else {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                                ForEach(filteredBooks) { book in
                                    GridBookCard(book: book)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }
                .padding(.vertical, 20)
            }
        }
        .navigationTitle("Essential Books")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Book Card Components

struct ForYouBookCard: View {
    let book: Book
    @State private var isSaved = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: book.coverColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 140, height: 200)
                
                Image(systemName: "book.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.custom("OpenSans-Bold", size: 14))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                
                Text(book.author)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                HStack(spacing: 2) {
                    ForEach(0..<5) { index in
                        Image(systemName: index < book.rating ? "star.fill" : "star")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                    }
                }
            }
            .frame(width: 140, alignment: .leading)
        }
    }
}

struct TrendingBookCard: View {
    let book: Book
    @State private var isSaved = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: book.coverColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 160, height: 220)
                    
                    Image(systemName: "book.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.white.opacity(0.3))
                }
                
                // Trending badge
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 10))
                    Text("Trending")
                        .font(.custom("OpenSans-Bold", size: 10))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.orange)
                )
                .padding(8)
            }
            .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.custom("OpenSans-Bold", size: 15))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                
                Text(book.author)
                    .font(.custom("OpenSans-SemiBold", size: 12))
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 2) {
                    ForEach(0..<5) { index in
                        Image(systemName: index < book.rating ? "star.fill" : "star")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                    }
                }
            }
            .frame(width: 160, alignment: .leading)
        }
    }
}

struct SmartBookCard: View {
    let book: Book
    @State private var isSaved = false
    @State private var showDetail = false
    
    var body: some View {
        Button {
            showDetail = true
        } label: {
            HStack(spacing: 16) {
                // Book cover
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: book.coverColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 120)
                    
                    Image(systemName: "book.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(book.title)
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    Text("by \(book.author)")
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundStyle(.secondary)
                    
                    Text(book.description)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    
                    HStack(spacing: 8) {
                        // Rating
                        HStack(spacing: 2) {
                            ForEach(0..<5) { index in
                                Image(systemName: index < book.rating ? "star.fill" : "star")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.orange)
                            }
                        }
                        
                        Text(book.category)
                            .font(.custom("OpenSans-SemiBold", size: 11))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.blue.opacity(0.1))
                            )
                    }
                }
                
                Spacer()
                
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        isSaved.toggle()
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                    }
                } label: {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(isSaved ? .blue : .secondary)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
            )
            .padding(.horizontal, 20)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showDetail) {
            BookDetailView(book: book)
        }
    }
}

struct GridBookCard: View {
    let book: Book
    @State private var isSaved = false
    @State private var showDetail = false
    
    var body: some View {
        Button {
            showDetail = true
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: book.coverColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .aspectRatio(0.67, contentMode: .fit)
                        
                        Image(systemName: "book.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            isSaved.toggle()
                            let haptic = UIImpactFeedbackGenerator(style: .light)
                            haptic.impactOccurred()
                        }
                    } label: {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 18))
                            .foregroundStyle(isSaved ? .blue : .white)
                            .padding(8)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                            )
                    }
                    .padding(8)
                }
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(book.title)
                        .font(.custom("OpenSans-Bold", size: 14))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    
                    Text(book.author)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    HStack(spacing: 2) {
                        ForEach(0..<5) { index in
                            Image(systemName: index < book.rating ? "star.fill" : "star")
                                .font(.system(size: 9))
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showDetail) {
            BookDetailView(book: book)
        }
    }
}

// MARK: - Book Detail View

struct BookDetailView: View {
    @Environment(\.dismiss) var dismiss
    let book: Book
    @State private var isSaved = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Large book cover
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(
                                LinearGradient(
                                    colors: book.coverColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 200, height: 300)
                        
                        Image(systemName: "book.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
                    .padding(.top, 32)
                    
                    VStack(spacing: 12) {
                        Text(book.title)
                            .font(.custom("OpenSans-Bold", size: 26))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                        
                        Text("by \(book.author)")
                            .font(.custom("OpenSans-SemiBold", size: 18))
                            .foregroundStyle(.secondary)
                        
                        HStack(spacing: 16) {
                            HStack(spacing: 2) {
                                ForEach(0..<5) { index in
                                    Image(systemName: index < book.rating ? "star.fill" : "star")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.orange)
                                }
                            }
                            
                            Text(book.category)
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(Color.blue.opacity(0.1))
                                )
                        }
                    }
                    .padding(.horizontal, 32)
                    
                    // Action buttons
                    HStack(spacing: 12) {
                        Button {
                            // Purchase action
                        } label: {
                            Text("Get Book")
                                .font(.custom("OpenSans-Bold", size: 16))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.black)
                                )
                        }
                        
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                isSaved.toggle()
                                let haptic = UIImpactFeedbackGenerator(style: .light)
                                haptic.impactOccurred()
                            }
                        } label: {
                            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                                .font(.system(size: 18))
                                .foregroundStyle(isSaved ? .white : .primary)
                                .frame(width: 50, height: 50)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(isSaved ? Color.blue : Color(.systemGray6))
                                )
                        }
                        
                        Button {
                            // Share action
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 18))
                                .foregroundStyle(.primary)
                                .frame(width: 50, height: 50)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.systemGray6))
                                )
                        }
                    }
                    .padding(.horizontal, 32)
                    
                    // Description
                    VStack(alignment: .leading, spacing: 12) {
                        Text("About This Book")
                            .font(.custom("OpenSans-Bold", size: 20))
                        
                        Text(book.description)
                            .font(.custom("OpenSans-Regular", size: 16))
                            .foregroundStyle(.secondary)
                            .lineSpacing(6)
                        
                        Text("This essential book has transformed countless lives and continues to be a powerful resource for believers seeking to deepen their understanding and grow in their faith journey.")
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.secondary)
                            .lineSpacing(6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 32)
                    
                    Spacer(minLength: 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        EssentialBooksView()
    }
}
