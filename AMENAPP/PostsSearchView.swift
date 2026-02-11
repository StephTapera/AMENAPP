//
//  PostsSearchView.swift
//  AMENAPP
//
//  Production-ready Posts Search with Trending Highlights
//  Shown when user taps "Posts" in People Discovery
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Posts Search View

struct PostsSearchView: View {
    @StateObject private var viewModel = PostsSearchViewModel()
    @State private var searchText = ""
    @State private var selectedCategory: PostCategory = .trending
    @Environment(\.dismiss) var dismiss
    
    enum PostCategory: String, CaseIterable {
        case trending = "Trending"
        case recent = "Recent"
        case popular = "Popular"
        
        var icon: String {
            switch self {
            case .trending: return "flame.fill"
            case .recent: return "clock.fill"
            case .popular: return "heart.fill"
            }
        }
        
        var highlightColor: Color {
            switch self {
            case .trending: return Color(red: 0.8, green: 0.1, blue: 0.2) // Maroon/Red
            case .recent: return .blue
            case .popular: return .pink
            }
        }
    }
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color.black,
                    Color(red: 0.05, green: 0.05, blue: 0.08)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header with highlight
                headerWithHighlight
                
                // Search bar
                searchBarSection
                
                // Category chips
                categoryChipsSection
                
                // Posts content
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 16) {
                        if viewModel.isLoading && viewModel.posts.isEmpty {
                            loadingView
                        } else if viewModel.posts.isEmpty {
                            emptyStateView
                        } else {
                            ForEach(viewModel.posts) { post in
                                PostSearchCard(post: post, category: selectedCategory)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
                .refreshable {
                    await viewModel.refresh(category: selectedCategory, searchQuery: searchText)
                }
            }
        }
        .task {
            await viewModel.loadPosts(category: selectedCategory, searchQuery: searchText)
        }
        .onChange(of: selectedCategory) { oldValue, newValue in
            Task {
                await viewModel.loadPosts(category: newValue, searchQuery: searchText)
            }
        }
        .onChange(of: searchText) { oldValue, newValue in
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms debounce
                await viewModel.searchPosts(query: newValue, category: selectedCategory)
            }
        }
    }
    
    // MARK: - Header with Red/Maroon Highlight
    
    private var headerWithHighlight: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                // Back button
                Button {
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                    dismiss()
                } label: {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial.opacity(0.3))
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.3),
                                                Color.white.opacity(0.1)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                // Title with icon
                HStack(spacing: 10) {
                    Image(systemName: selectedCategory.icon)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    selectedCategory.highlightColor,
                                    selectedCategory.highlightColor.opacity(0.7)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text(selectedCategory.rawValue)
                        .font(.custom("OpenSans-Bold", size: 26))
                        .foregroundStyle(.white)
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            // Red/Maroon highlight bar (only for trending)
            if selectedCategory == .trending {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.9, green: 0.1, blue: 0.2),
                                Color(red: 0.7, green: 0.05, blue: 0.15)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 4)
                    .shadow(color: Color(red: 0.9, green: 0.1, blue: 0.2).opacity(0.5), radius: 8, y: 2)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedCategory)
    }
    
    // MARK: - Search Bar
    
    private var searchBarSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
            
            TextField("Search posts...", text: $searchText)
                .font(.custom("OpenSans-Regular", size: 16))
                .foregroundColor(.white)
                .placeholder(when: searchText.isEmpty) {
                    Text("Search posts...")
                        .font(.custom("OpenSans-Regular", size: 16))
                        .foregroundColor(.white.opacity(0.4))
                }
            
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.5))
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.3))
                
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.3),
                                Color.white.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
    
    // MARK: - Category Chips
    
    private var categoryChipsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(PostCategory.allCases, id: \.self) { category in
                    CategoryChip(
                        category: category,
                        isSelected: selectedCategory == category
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedCategory = category
                        }
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 16)
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.2)
            
            Text("Loading posts...")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(.white.opacity(0.3))
            
            Text("No posts found")
                .font(.custom("OpenSans-SemiBold", size: 18))
                .foregroundColor(.white)
            
            Text(searchText.isEmpty ? "Try a different category" : "Try a different search")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Category Chip

struct CategoryChip: View {
    let category: PostsSearchView.PostCategory
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(.system(size: 14, weight: .semibold))
                
                Text(category.rawValue)
                    .font(.custom("OpenSans-SemiBold", size: 15))
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.7))
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    if isSelected {
                        // Selected: Category highlight color
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(category.highlightColor)
                            .shadow(color: category.highlightColor.opacity(0.4), radius: 12, y: 6)
                    } else {
                        // Unselected: Liquid glass
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.ultraThinMaterial.opacity(0.2))
                        
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.2),
                                        Color.white.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                }
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Post Search Card

struct PostSearchCard: View {
    let post: Post
    let category: PostsSearchView.PostCategory
    @State private var showFullPost = false
    
    var body: some View {
        Button {
            showFullPost = true
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                // Author info
                HStack(spacing: 10) {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.blue, Color.purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                        .overlay(
                            Text(post.authorInitials ?? "?")
                                .font(.custom("OpenSans-Bold", size: 14))
                                .foregroundColor(.white)
                        )
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(post.authorDisplayName ?? "Unknown")
                            .font(.custom("OpenSans-Bold", size: 15))
                            .foregroundColor(.white)
                        
                        Text(post.timestamp?.timeAgoDisplay() ?? "")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    
                    Spacer()
                    
                    // Trending indicator
                    if category == .trending {
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 12))
                            Text("Hot")
                                .font(.custom("OpenSans-Bold", size: 11))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.9, green: 0.1, blue: 0.2),
                                            Color(red: 0.7, green: 0.05, blue: 0.15)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .shadow(color: Color(red: 0.9, green: 0.1, blue: 0.2).opacity(0.3), radius: 8, y: 2)
                        )
                    }
                }
                
                // Post content
                if let text = post.text, !text.isEmpty {
                    Text(text)
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                
                // Engagement stats
                HStack(spacing: 20) {
                    Label("\(post.likesCount)", systemImage: "heart.fill")
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundColor(.white.opacity(0.6))
                    
                    Label("\(post.commentsCount)", systemImage: "bubble.right.fill")
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundColor(.white.opacity(0.6))
                    
                    Label("\(post.repostsCount)", systemImage: "arrow.2.squarepath")
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .padding(16)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial.opacity(0.25))
                    
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.25),
                                    Color.white.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: .black.opacity(0.3), radius: 15, y: 8)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showFullPost) {
            NavigationView {
                // Integrate with existing PostDetailView or create new one
                Text("Post Detail View")
                    .font(.custom("OpenSans-Regular", size: 16))
            }
        }
    }
}

// MARK: - View Model

@MainActor
class PostsSearchViewModel: ObservableObject {
    @Published var posts: [Post] = []
    @Published var isLoading = false
    @Published var hasMore = true
    
    private let db = Firestore.firestore()
    private var lastDocument: DocumentSnapshot?
    private let pageSize = 20
    
    func loadPosts(category: PostsSearchView.PostCategory, searchQuery: String) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        
        do {
            var query: Query = db.collection("posts")
            
            // Apply category filter
            switch category {
            case .trending:
                // Posts with high engagement in last 24 hours
                let oneDayAgo = Date().addingTimeInterval(-24 * 60 * 60)
                query = query
                    .whereField("timestamp", isGreaterThan: Timestamp(date: oneDayAgo))
                    .order(by: "timestamp", descending: true)
                    .order(by: "likesCount", descending: true)
                
            case .recent:
                query = query.order(by: "timestamp", descending: true)
                
            case .popular:
                query = query.order(by: "likesCount", descending: true)
            }
            
            query = query.limit(to: pageSize)
            
            let snapshot = try await query.getDocuments()
            lastDocument = snapshot.documents.last
            
            let fetchedPosts = snapshot.documents.compactMap { doc -> Post? in
                try? doc.data(as: Post.self)
            }
            
            posts = fetchedPosts
            hasMore = snapshot.documents.count == pageSize
            
        } catch {
            print("❌ Error loading posts: \(error)")
            posts = []
        }
    }
    
    func searchPosts(query: String, category: PostsSearchView.PostCategory) async {
        guard !query.isEmpty else {
            await loadPosts(category: category, searchQuery: query)
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Simple text search - for production, use Algolia
            let snapshot = try await db.collection("posts")
                .order(by: "timestamp", descending: true)
                .limit(to: 50)
                .getDocuments()
            
            let allPosts = snapshot.documents.compactMap { doc -> Post? in
                try? doc.data(as: Post.self)
            }
            
            // Filter by search query
            posts = allPosts.filter { post in
                let searchLower = query.lowercased()
                let textMatch = post.text?.lowercased().contains(searchLower) ?? false
                let authorMatch = post.authorDisplayName?.lowercased().contains(searchLower) ?? false
                return textMatch || authorMatch
            }
            
        } catch {
            print("❌ Error searching posts: \(error)")
            posts = []
        }
    }
    
    func refresh(category: PostsSearchView.PostCategory, searchQuery: String) async {
        lastDocument = nil
        await loadPosts(category: category, searchQuery: searchQuery)
    }
}

// MARK: - TextField Placeholder Extension

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

// MARK: - Date Extension

extension Date {
    func timeAgoDisplay() -> String {
        let seconds = Date().timeIntervalSince(self)
        let minutes = seconds / 60
        let hours = minutes / 60
        let days = hours / 24
        
        if seconds < 60 {
            return "Just now"
        } else if minutes < 60 {
            return "\(Int(minutes))m"
        } else if hours < 24 {
            return "\(Int(hours))h"
        } else if days < 7 {
            return "\(Int(days))d"
        } else {
            return "\(Int(days / 7))w"
        }
    }
}
