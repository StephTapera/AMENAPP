//
//  PostSearchView.swift
//  AMENAPP
//
//  Search for posts by caption, hashtags, location
//

import SwiftUI
import Combine

// MARK: - Post Search View

struct PostSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = PostSearchViewModel()
    @State private var searchText = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var selectedTab: SearchTab = .posts
    
    enum SearchTab: String, CaseIterable {
        case posts = "Posts"
        case hashtags = "Hashtags"
        case locations = "Locations"
        
        var icon: String {
            switch self {
            case .posts: return "square.grid.2x2"
            case .hashtags: return "number"
            case .locations: return "mappin.and.ellipse"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search Bar
                searchBarView
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                
                // Tab Selector
                tabSelectorView
                    .padding(.top, 12)
                
                // Content
                ScrollView {
                    if viewModel.isLoading && viewModel.posts.isEmpty {
                        loadingView
                    } else if viewModel.posts.isEmpty && !searchText.isEmpty {
                        emptyStateView
                    } else if !viewModel.posts.isEmpty {
                        postsGridView
                    } else {
                        recentSearchesView
                    }
                }
            }
            .background(Color(white: 0.98))
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDisappear {
                searchTask?.cancel()
            }
        }
    }
    
    // MARK: - Search Bar
    
    private var searchBarView: some View {
        HStack(spacing: 12) {
            Group {
                if viewModel.isLoading && !searchText.isEmpty {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "magnifyingglass")
                }
            }
            .foregroundStyle(.secondary)
            .frame(width: 20)
            
            TextField("Search posts, hashtags...", text: $searchText)
                .font(.custom("OpenSans-Regular", size: 16))
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: searchText) {
                    // Cancel previous search
                    searchTask?.cancel()
                    
                    // Debounce by 400ms
                    searchTask = Task {
                        do {
                            try await Task.sleep(nanoseconds: 400_000_000)
                            guard !Task.isCancelled else { return }
                            await viewModel.searchPosts(query: searchText)
                        } catch {}
                    }
                }
            
            if !searchText.isEmpty {
                Button(action: {
                    searchTask?.cancel()
                    searchText = ""
                    viewModel.clearResults()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        )
    }
    
    // MARK: - Tab Selector
    
    private var tabSelectorView: some View {
        HStack(spacing: 0) {
            ForEach(SearchTab.allCases, id: \.self) { tab in
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = tab
                    }
                }) {
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 14, weight: .semibold))
                            Text(tab.rawValue)
                                .font(.custom("OpenSans-Bold", size: 14))
                        }
                        .foregroundStyle(selectedTab == tab ? .black : .secondary)
                        
                        if selectedTab == tab {
                            Rectangle()
                                .fill(Color.black)
                                .frame(height: 2)
                        } else {
                            Rectangle()
                                .fill(Color.clear)
                                .frame(height: 2)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .frame(maxWidth: .infinity)
            }
        }
        .background(
            Rectangle()
                .fill(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
    }
    
    // MARK: - Posts Grid
    
    private var postsGridView: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 2),
            GridItem(.flexible(), spacing: 2),
            GridItem(.flexible(), spacing: 2)
        ], spacing: 2) {
            ForEach(viewModel.posts) { post in
                PostThumbnailView(post: post)
            }
        }
        .padding(.top, 12)
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Searching...")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color(white: 0.95))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
            }
            
            Text("No posts found")
                .font(.custom("OpenSans-Bold", size: 18))
            
            Text("Try different keywords or hashtags")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
    
    // MARK: - Recent Searches
    
    private var recentSearchesView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Searches")
                .font(.custom("OpenSans-Bold", size: 18))
                .padding(.horizontal, 20)
                .padding(.top, 20)
            
            // TODO: Implement recent searches persistence
            Text("Start typing to search posts")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        }
    }
}

// MARK: - Post Thumbnail

struct PostThumbnailView: View {
    let post: AlgoliaPost
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                // Post image/video
                if let firstMedia = post.mediaURLs.first,
                   let url = URL(string: firstMedia) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                        case .failure(_):
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: geometry.size.width, height: geometry.size.height)
                        case .empty:
                            ZStack {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.2))
                                ProgressView()
                                    .tint(.gray)
                            }
                            .frame(width: geometry.size.width, height: geometry.size.height)
                        @unknown default:
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: geometry.size.width, height: geometry.size.height)
                        }
                    }
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
                
                // Engagement indicator
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10))
                    Text("\(post.likesCount)")
                        .font(.custom("OpenSans-Bold", size: 11))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.6))
                )
                .padding(8)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - View Model

@MainActor
class PostSearchViewModel: ObservableObject {
    @Published var posts: [AlgoliaPost] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let searchService = AlgoliaSearchService.shared
    
    func searchPosts(query: String) async {
        guard !query.isEmpty else {
            posts = []
            return
        }
        
        guard !isLoading else { return }
        
        isLoading = true
        error = nil
        
        do {
            posts = try await searchService.searchPosts(query: query, limit: 30)
            
            #if DEBUG
            print("✅ Found \(posts.count) posts for query: \(query)")
            #endif
        } catch {
            self.error = "Search failed. Please try again."
            #if DEBUG
            print("❌ Post search failed: \(error)")
            #endif
        }
        
        isLoading = false
    }
    
    func clearResults() {
        posts = []
        error = nil
    }
}

// MARK: - Preview

#Preview {
    PostSearchView()
}
