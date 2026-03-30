//
//  SavedPostsView.swift
//  AMENAPP
//
//  Created by Steph on 1/29/26.
//
//  View for displaying and managing saved/bookmarked posts
//

import SwiftUI

// MARK: - Saved Folder

enum SavedFolder: String, CaseIterable, Identifiable {
    case all        = "All"
    case prayLater  = "Pray Later"
    case forSunday  = "For Sunday"
    case berean     = "Berean Research"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .all:       return "bookmark.fill"
        case .prayLater: return "hands.sparkles.fill"
        case .forSunday: return "sun.horizon.fill"
        case .berean:    return "book.fill"
        }
    }
    /// Topic tags associated with this folder (client-side filter).
    /// Posts whose topicTag (lowercased) contains any of these keywords land in the folder.
    var keywords: [String] {
        switch self {
        case .all:       return []
        case .prayLater: return ["prayer", "pray", "petition"]
        case .forSunday: return ["sermon", "church", "sunday", "worship"]
        case .berean:    return ["bible", "scripture", "verse", "berean", "study"]
        }
    }
}

struct SavedPostsView: View {
    @ObservedObject private var savedPostsService = RealtimeSavedPostsService.shared
    @ObservedObject private var postsService = RealtimePostService.shared

    @State private var savedPosts: [Post] = []
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var refreshTrigger = false
    @State private var selectedFolder: SavedFolder = .all
    
    private var displayedPosts: [Post] {
        guard selectedFolder != .all else { return savedPosts }
        return savedPosts.filter { post in
            let haystack = ((post.topicTag ?? "") + " " + post.content).lowercased()
            return selectedFolder.keywords.contains { haystack.contains($0) }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if isLoading && savedPosts.isEmpty {
                    // Initial loading
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Loading your saved posts...")
                            .font(AMENFont.regular(14))
                            .foregroundStyle(.secondary)
                    }
                } else if savedPosts.isEmpty {
                    // Empty state
                    emptyStateView
                } else {
                    // Posts list
                    postsListView
                }
            }
            .navigationTitle("Saved Posts")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            Task {
                                await refreshSavedPosts()
                            }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        
                        if !savedPosts.isEmpty {
                            Divider()
                            
                            Button(role: .destructive) {
                                showClearAllConfirmation()
                            } label: {
                                Label("Clear All Saved Posts", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 20))
                    }
                }
            }
            .task {
                await loadSavedPosts()
                setupRealtimeListener()
            }
            .onDisappear {
                // NOTE: Do NOT remove the saved posts listener here.
                // RealtimeSavedPostsService.shared is a global singleton; removing its
                // listener from this view breaks saved-post state and badges throughout
                // the app. The listener is only cleaned up on sign-out.
            }
            .refreshable {
                await refreshSavedPosts()
            }
            // Handle "Save to Folder" from PostCard options sheet
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("openSavedFolder"))) { notification in
                if let folderRaw = notification.userInfo?["folder"] as? String,
                   let folder = SavedFolder(rawValue: folderRaw) {
                    withAnimation(.easeOut(duration: 0.15)) {
                        selectedFolder = folder
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    // MARK: - Empty State View
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "bookmark.slash")
                .font(.system(size: 64))
                .foregroundStyle(.secondary.opacity(0.5))
            
            VStack(spacing: 8) {
                Text("No Saved Posts")
                    .font(AMENFont.bold(24))
                    .foregroundStyle(.primary)
                
                Text("Posts you bookmark will appear here.\nTap the bookmark icon on any post to save it.")
                    .font(AMENFont.regular(16))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            // Optional: Add a CTA to explore posts
            NavigationLink {
                // Link to main feed or explore
                Text("Feed")
            } label: {
                HStack {
                    Image(systemName: "arrow.right.circle.fill")
                    Text("Explore Posts")
                        .font(AMENFont.semiBold(16))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Posts List View
    
    private var postsListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Folder chip row — Liquid Glass filter bar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(SavedFolder.allCases) { folder in
                            let isSelected = selectedFolder == folder
                            Button {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    selectedFolder = folder
                                }
                                HapticManager.impact(style: .light)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: folder.icon)
                                        .font(.system(size: 11, weight: .semibold))
                                    Text(folder.rawValue)
                                        .font(AMENFont.semiBold(13))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background {
                                    if isSelected {
                                        Capsule()
                                            .fill(.regularMaterial)
                                            .overlay(
                                                Capsule().strokeBorder(
                                                    Color.black.opacity(0.08),
                                                    lineWidth: 0.5
                                                )
                                            )
                                            .shadow(color: .black.opacity(0.07), radius: 4, x: 0, y: 2)
                                    } else {
                                        Capsule()
                                            .fill(Color(.systemGray6))
                                    }
                                }
                                .foregroundStyle(isSelected ? Color.primary : Color.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }

                Divider()

                // Posts
                let posts = displayedPosts
                if posts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bookmark.slash")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary.opacity(0.4))
                        Text("No posts in \"\(selectedFolder.rawValue)\" yet")
                            .font(AMENFont.regular(14))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                } else {
                    ForEach(posts) { post in
                        PostCard(post: post)
                            .padding(.vertical, 8)

                        if post.id != posts.last?.id {
                            Divider()
                                .padding(.leading, 16)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Data Loading
    
    private func loadSavedPosts() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            dlog("📥 Loading saved posts...")
            
            // Fetch saved post IDs first
            let postIds = try await savedPostsService.fetchSavedPostIds()
            
            if postIds.isEmpty {
                savedPosts = []
                return
            }
            
            // Fetch full post objects
            var posts: [Post] = []
            
            for postId in postIds {
                do {
                    let post = try await postsService.fetchPost(postId: postId)
                    posts.append(post)
                } catch {
                    dlog("⚠️ Failed to fetch saved post \(postId): \(error)")
                    // Continue loading other posts even if one fails
                }
            }
            
            // Sort by creation date (most recent first)
            savedPosts = posts.sorted { $0.createdAt > $1.createdAt }
            
            dlog("✅ Loaded \(savedPosts.count) saved posts")
            
        } catch {
            dlog("❌ Error loading saved posts: \(error)")
            errorMessage = "Failed to load saved posts. Please try again."
            showError = true
        }
    }
    
    private func refreshSavedPosts() async {
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
        
        await loadSavedPosts()
        
        let successHaptic = UINotificationFeedbackGenerator()
        successHaptic.notificationOccurred(.success)
    }
    
    // MARK: - Real-time Updates

    private func setupRealtimeListener() {
        // Listen for individual unsave actions — remove the post locally without
        // replacing the entire array. Replacing the array destroys all PostCard
        // @State (isSaved, isSaveInFlight, etc.) making every card flash unsaved.
        NotificationCenter.default.addObserver(
            forName: Notification.Name("postUnsaved"),
            object: nil,
            queue: .main
        ) { [self] notification in
            guard let userInfo = notification.userInfo else { return }
            // PostCard posts "postId" as UUID; service posts as String — handle both.
            if let postId = userInfo["postId"] as? UUID {
                savedPosts.removeAll { $0.id == postId }
            } else if let postIdStr = userInfo["postId"] as? String {
                savedPosts.removeAll { $0.firestoreId == postIdStr }
            }
        }

        // Only do a full reload when a new post is added to saved
        // (count increased) — not on removal, which is handled above.
        savedPostsService.observeSavedPosts { [self] postIds in
            Task { @MainActor in
                if postIds.count > savedPosts.count {
                    dlog("🔄 New saved post detected, reloading...")
                    await loadSavedPosts()
                }
            }
        }
    }
    
    // MARK: - Clear All
    
    private func showClearAllConfirmation() {
        let alert = UIAlertController(
            title: "Clear All Saved Posts?",
            message: "This will remove all \(savedPosts.count) saved posts. This action cannot be undone.",
            preferredStyle: .actionSheet
        )
        
        alert.addAction(UIAlertAction(title: "Clear All", style: .destructive) { _ in
            Task {
                await clearAllSavedPosts()
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // Present alert
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(alert, animated: true)
        }
    }
    
    private func clearAllSavedPosts() async {
        isLoading = true
        
        let postsToRemove = savedPosts
        
        do {
            // Remove all saved posts one by one
            for post in postsToRemove {
                _ = try await savedPostsService.toggleSavePost(postId: post.id.uuidString)
            }
            
            savedPosts = []
            
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            
            dlog("✅ Cleared all saved posts")
            
        } catch {
            dlog("❌ Error clearing saved posts: \(error)")
            errorMessage = "Failed to clear saved posts. Please try again."
            showError = true
        }
        
        isLoading = false
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SavedPostsView()
    }
}

// MARK: - Compact Saved Posts List (for Profile)

/// A compact version for embedding in ProfileView
struct SavedPostsListCompact: View {
    @ObservedObject private var savedPostsService = RealtimeSavedPostsService.shared
    @State private var savedCount = 0
    
    var body: some View {
        NavigationLink {
            SavedPostsView()
        } label: {
            HStack {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.blue)
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Saved Posts")
                        .font(AMENFont.semiBold(16))
                        .foregroundStyle(.primary)
                    
                    if savedCount > 0 {
                        Text("\(savedCount) saved")
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No saved posts")
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .task {
            await loadCount()
        }
    }
    
    private func loadCount() async {
        do {
            savedCount = try await savedPostsService.getSavedPostsCount()
        } catch {
            dlog("❌ Error loading saved count: \(error)")
        }
    }
}

#Preview("Compact List") {
    SavedPostsListCompact()
        .padding()
}
