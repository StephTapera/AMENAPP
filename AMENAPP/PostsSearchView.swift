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
import Combine

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
                .autocorrectionDisabled()
            
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
                            Text(post.authorInitials)
                                .font(.custom("OpenSans-Bold", size: 14))
                                .foregroundColor(.white)
                        )
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(post.authorName)
                            .font(.custom("OpenSans-Bold", size: 15))
                            .foregroundColor(.white)
                        
                        Text(post.timeAgo)
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
                if !post.content.isEmpty {
                    Text(post.content)
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                
                // Engagement stats
                HStack(spacing: 20) {
                    Label("\(post.amenCount)", systemImage: "heart.fill")
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundColor(.white.opacity(0.6))
                    
                    Label("\(post.commentCount)", systemImage: "bubble.right.fill")
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundColor(.white.opacity(0.6))
                    
                    Label("\(post.repostCount)", systemImage: "arrow.2.squarepath")
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
        
        // If there's a search query, use enhanced search
        if !searchQuery.isEmpty {
            await searchWithFirestore(query: searchQuery, category: category)
            return
        }
        
        // Otherwise, load from Firestore with category filter
        do {
            var query: Query = db.collection("posts")
            
            // Apply category filter with smart algorithms
            switch category {
            case .trending:
                // 🔥 TRENDING ALGORITHM: High engagement in last 24 hours
                // Score = (amenCount * 2 + commentCount * 3 + repostCount * 5) / hours_since_post
                let oneDayAgo = Date().addingTimeInterval(-24 * 60 * 60)
                query = query
                    .whereField("createdAt", isGreaterThan: Timestamp(date: oneDayAgo))
                    .order(by: "createdAt", descending: true)
                
            case .recent:
                // 🕐 RECENT ALGORITHM: Simple chronological order
                query = query.order(by: "createdAt", descending: true)
                
            case .popular:
                // ❤️ POPULAR ALGORITHM: All-time engagement
                // Score = amenCount + commentCount + repostCount
                query = query.order(by: "amenCount", descending: true)
            }
            
            query = query.limit(to: pageSize)
            
            let snapshot = try await query.getDocuments()
            lastDocument = snapshot.documents.last
            
            var fetchedPosts = snapshot.documents.compactMap { doc -> Post? in
                try? doc.data(as: Post.self)
            }
            
            // Apply trending score algorithm on client side for better ranking
            if category == .trending {
                fetchedPosts = rankTrendingPosts(fetchedPosts)
            }
            
            posts = fetchedPosts
            hasMore = snapshot.documents.count == pageSize
            
        } catch {
            print("❌ Error loading posts: \(error)")
            posts = []
        }
    }
    
    // 🔥 TRENDING RANKING ALGORITHM
    private func rankTrendingPosts(_ posts: [Post]) -> [Post] {
        return posts.sorted { post1, post2 in
            let score1 = calculateTrendingScore(post1)
            let score2 = calculateTrendingScore(post2)
            return score1 > score2
        }
    }
    
    private func calculateTrendingScore(_ post: Post) -> Double {
        let now = Date()
        let hoursSincePost = now.timeIntervalSince(post.createdAt) / 3600
        
        // Prevent division by zero
        guard hoursSincePost > 0 else { return 0 }
        
        // Weighted engagement score
        let amenWeight = 2.0
        let commentWeight = 3.0
        let repostWeight = 5.0
        
        let engagementScore = Double(post.amenCount) * amenWeight +
                             Double(post.commentCount) * commentWeight +
                             Double(post.repostCount) * repostWeight
        
        // Time decay: newer posts get bonus
        let timeDecay = 1.0 / (1.0 + hoursSincePost / 6.0) // Decay over 6 hours
        
        return engagementScore * timeDecay
    }
    
    // 🔍 ENHANCED FIRESTORE SEARCH: Search posts by content, author, verse, keywords, category
    func searchWithFirestore(query: String, category: PostsSearchView.PostCategory? = nil) async {
        do {
            // Fetch more posts for better search results (200 posts)
            let snapshot = try await db.collection("posts")
                .order(by: "createdAt", descending: true)
                .limit(to: 200)
                .getDocuments()
            
            let allPosts = snapshot.documents.compactMap { doc -> Post? in
                try? doc.data(as: Post.self)
            }
            
            // 🎯 SMART SEARCH ALGORITHM: Multi-field matching with relevance scoring
            let searchLower = query.lowercased()
            var scoredPosts: [(post: Post, score: Int)] = []
            
            for post in allPosts {
                var relevanceScore = 0
                
                // 🔍 Content matching (highest priority - 10 points)
                if post.content.lowercased().contains(searchLower) {
                    relevanceScore += 10
                    // Boost if it's an exact word match
                    let words = post.content.lowercased().split(separator: " ").map(String.init)
                    if words.contains(searchLower) {
                        relevanceScore += 5
                    }
                }
                
                // 👤 Author name matching (medium priority - 5 points)
                if post.authorName.lowercased().contains(searchLower) {
                    relevanceScore += 5
                }
                
                // 🏷️ Username matching (medium priority - 5 points)
                if let username = post.authorUsername, username.lowercased().contains(searchLower) {
                    relevanceScore += 5
                }
                
                // 📁 Category matching (low priority - 3 points)
                if post.category.rawValue.lowercased().contains(searchLower) {
                    relevanceScore += 3
                }
                
                // 🏷️ Topic tag matching (low priority - 3 points)
                if let topicTag = post.topicTag, topicTag.lowercased().contains(searchLower) {
                    relevanceScore += 3
                }
                
                // ✨ Engagement boost: Popular posts get priority
                let engagementBonus = (post.amenCount + post.commentCount + post.repostCount) / 10
                relevanceScore += min(engagementBonus, 10) // Cap at 10 bonus points
                
                // Only include posts with some relevance
                if relevanceScore > 0 {
                    scoredPosts.append((post: post, score: relevanceScore))
                }
            }
            
            // Sort by relevance score (highest first)
            scoredPosts.sort { $0.score > $1.score }
            
            // Extract posts and apply category filter if provided
            var searchResults = scoredPosts.map { $0.post }
            
            if let category = category {
                switch category {
                case .trending:
                    // Only posts from last 24 hours
                    let oneDayAgo = Date().addingTimeInterval(-24 * 60 * 60)
                    searchResults = searchResults.filter { $0.createdAt > oneDayAgo }
                    searchResults = rankTrendingPosts(searchResults)
                    
                case .recent:
                    // Already sorted by creation date in query
                    break
                    
                case .popular:
                    // Re-sort by engagement
                    searchResults.sort { post1, post2 in
                        let score1 = post1.amenCount + post1.commentCount + post1.repostCount
                        let score2 = post2.amenCount + post2.commentCount + post2.repostCount
                        return score1 > score2
                    }
                }
            }
            
            posts = Array(searchResults.prefix(pageSize))
            hasMore = searchResults.count > pageSize
            
            print("✅ Enhanced search: \(posts.count) results for '\(query)' (from \(scoredPosts.count) matches)")
            
        } catch {
            print("❌ Error in search: \(error)")
            posts = []
        }
    }
    
    func searchPosts(query: String, category: PostsSearchView.PostCategory) async {
        if query.isEmpty {
            await loadPosts(category: category, searchQuery: query)
        } else {
            await searchWithFirestore(query: query, category: category)
        }
    }
    
    func refresh(category: PostsSearchView.PostCategory, searchQuery: String) async {
        lastDocument = nil
        posts = []
        await loadPosts(category: category, searchQuery: searchQuery)
    }
}
