//
//  PostSearchView.swift
//  AMENAPP
//
//  Search for posts by caption, hashtags, location
//

import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth

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
                        } catch {
                            // Task.sleep throws CancellationError on cancel — expected, not an error
                        }
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
                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                        selectedTab = tab
                    }
                }) {
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.systemScaled(14, weight: .semibold))
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
                    .font(.systemScaled(40))
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

            if viewModel.recentSearches.isEmpty {
                Text("Start typing to search posts")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            } else {
                ForEach(viewModel.recentSearches, id: \.self) { term in
                    Button {
                        searchText = term
                        searchTask?.cancel()
                        searchTask = Task {
                            try? await Task.sleep(nanoseconds: 100_000_000)
                            guard !Task.isCancelled else { return }
                            await viewModel.searchPosts(query: term)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            Text(term)
                                .font(.custom("OpenSans-Regular", size: 15))
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                    }
                    Divider().padding(.leading, 52)
                }
                Button("Clear recent searches") {
                    Task { await viewModel.clearRecentSearches() }
                }
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
        .task { await viewModel.loadRecentSearches() }
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
                        .font(.systemScaled(10))
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
    @Published var recentSearches: [String] = []

    private let searchService = AlgoliaSearchService.shared
    private lazy var db = Firestore.firestore()
    private static let maxRecentSearches = 10

    // MARK: Recent Searches — Firestore-backed, anonymous-safe

    func loadRecentSearches() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            // Fall back to UserDefaults for unauthenticated users
            recentSearches = UserDefaults.standard.stringArray(forKey: "amen.recentSearches") ?? []
            return
        }
        do {
            let snap = try await db
                .collection("users").document(uid)
                .collection("recentSearches")
                .order(by: "searchedAt", descending: true)
                .limit(to: Self.maxRecentSearches)
                .getDocuments()
            recentSearches = snap.documents.compactMap { $0.data()["query"] as? String }
        } catch {
            recentSearches = UserDefaults.standard.stringArray(forKey: "amen.recentSearches") ?? []
        }
    }

    private func persistSearch(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // Update in-memory list — deduplicate and cap
        var updated = recentSearches.filter { $0.lowercased() != trimmed.lowercased() }
        updated.insert(trimmed, at: 0)
        if updated.count > Self.maxRecentSearches { updated = Array(updated.prefix(Self.maxRecentSearches)) }
        recentSearches = updated

        guard let uid = Auth.auth().currentUser?.uid else {
            UserDefaults.standard.set(recentSearches, forKey: "amen.recentSearches")
            return
        }
        let docId = trimmed.lowercased().replacingOccurrences(of: "/", with: "_")
        try? await db
            .collection("users").document(uid)
            .collection("recentSearches")
            .document(docId)
            .setData(["query": trimmed, "searchedAt": FieldValue.serverTimestamp()], merge: false)
    }

    func clearRecentSearches() async {
        recentSearches = []
        UserDefaults.standard.removeObject(forKey: "amen.recentSearches")
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let snap = try? await db
            .collection("users").document(uid)
            .collection("recentSearches")
            .getDocuments()
        let batch = db.batch()
        snap?.documents.forEach { batch.deleteDocument($0.reference) }
        try? await batch.commit()
    }

    // MARK: Search

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
            await persistSearch(query)

            #if DEBUG
            dlog("✅ Found \(posts.count) posts for query: \(query)")
            #endif
        } catch {
            self.error = "Search failed. Please try again."
            #if DEBUG
            dlog("❌ Post search failed: \(error)")
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
