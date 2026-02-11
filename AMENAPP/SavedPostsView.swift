//
//  SavedPostsView.swift
//  AMENAPP
//
//  Created by Steph on 1/29/26.
//
//  View for displaying and managing saved/bookmarked posts
//

import SwiftUI

struct SavedPostsView: View {
    @StateObject private var savedPostsService = RealtimeSavedPostsService.shared
    @StateObject private var postsService = RealtimePostService.shared
    
    @State private var savedPosts: [Post] = []
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var refreshTrigger = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                if isLoading && savedPosts.isEmpty {
                    // Initial loading
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Loading your saved posts...")
                            .font(.custom("OpenSans-Regular", size: 14))
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
                savedPostsService.removeSavedPostsListener()
            }
            .refreshable {
                await refreshSavedPosts()
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
                    .font(.custom("OpenSans-Bold", size: 24))
                    .foregroundStyle(.primary)
                
                Text("Posts you bookmark will appear here.\nTap the bookmark icon on any post to save it.")
                    .font(.custom("OpenSans-Regular", size: 16))
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
                        .font(.custom("OpenSans-SemiBold", size: 16))
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
                // Header with count
                HStack {
                    Image(systemName: "bookmark.fill")
                        .foregroundStyle(.blue)
                    Text("\(savedPosts.count) saved post\(savedPosts.count == 1 ? "" : "s")")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
                
                Divider()
                
                // Posts
                ForEach(savedPosts) { post in
                    PostCard(post: post)
                        .padding(.vertical, 8)
                    
                    if post.id != savedPosts.last?.id {
                        Divider()
                            .padding(.leading, 16)
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
            print("📥 Loading saved posts...")
            
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
                    print("⚠️ Failed to fetch saved post \(postId): \(error)")
                    // Continue loading other posts even if one fails
                }
            }
            
            // Sort by creation date (most recent first)
            savedPosts = posts.sorted { $0.createdAt > $1.createdAt }
            
            print("✅ Loaded \(savedPosts.count) saved posts")
            
        } catch {
            print("❌ Error loading saved posts: \(error)")
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
        savedPostsService.observeSavedPosts { postIds in
            Task { @MainActor in
                // Only reload if the count changed (post was added/removed)
                if postIds.count != self.savedPosts.count {
                    print("🔄 Saved posts changed, reloading...")
                    await self.loadSavedPosts()
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
                try await savedPostsService.toggleSavePost(postId: post.firestoreId)
            }
            
            savedPosts = []
            
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            
            print("✅ Cleared all saved posts")
            
        } catch {
            print("❌ Error clearing saved posts: \(error)")
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
    @StateObject private var savedPostsService = RealtimeSavedPostsService.shared
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
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .foregroundStyle(.primary)
                    
                    if savedCount > 0 {
                        Text("\(savedCount) saved")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No saved posts")
                            .font(.custom("OpenSans-Regular", size: 13))
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
            print("❌ Error loading saved count: \(error)")
        }
    }
}

#Preview("Compact List") {
    SavedPostsListCompact()
        .padding()
}
