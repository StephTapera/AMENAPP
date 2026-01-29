//
//  EnhancedPostCard.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//
//  Enhanced PostCard with full social features integration:
//  - Comments and replies
//  - Save posts
//  - Reposts with quote option
//

import SwiftUI

struct EnhancedPostCard: View {
    let post: Post
    var isUserPost: Bool = false
    
    @StateObject private var savedPostsService = SavedPostsService.shared
    @StateObject private var repostService = RepostService.shared
    @StateObject private var commentService = CommentService.shared
    @StateObject private var postsManager = PostsManager.shared
    @EnvironmentObject var userService: UserService
    
    @State private var showComments = false
    @State private var showQuoteRepost = false
    @State private var showSaveToCollection = false
    @State private var showEditSheet = false
    @State private var showDeleteAlert = false
    @State private var showUserProfile = false
    @State private var hasLitLightbulb = false
    @State private var hasSaidAmen = false
    @State private var isSaved = false
    @State private var hasReposted = false
    
    private var category: PostCard.PostCardCategory {
        post.category.cardCategory
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // MARK: - Header
            HStack(spacing: 12) {
                // Avatar (tappable)
                Button {
                    showUserProfile = true
                } label: {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [category.color.opacity(0.2), category.color.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .overlay(
                            Text(post.authorInitials)
                                .font(.custom("OpenSans-Bold", size: 16))
                                .foregroundStyle(category.color)
                        )
                }
                .buttonStyle(.plain)
                
                // Name and info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(post.authorName)
                            .font(.custom("OpenSans-Bold", size: 15))
                            .foregroundStyle(.primary)
                        
                        if category != .openTable {
                            HStack(spacing: 4) {
                                Image(systemName: category.icon)
                                    .font(.system(size: 10, weight: .semibold))
                                Text(category.displayName)
                                    .font(.custom("OpenSans-Bold", size: 11))
                            }
                            .foregroundStyle(category.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(category.color.opacity(0.15)))
                        }
                    }
                    
                    HStack(spacing: 6) {
                        Text(post.timeAgo)
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                        
                        if let tag = post.topicTag {
                            Text("•")
                                .foregroundStyle(.secondary)
                            Text(tag)
                                .font(.custom("OpenSans-SemiBold", size: 12))
                                .foregroundStyle(category.color)
                        }
                    }
                }
                
                Spacer()
                
                // Menu
                Menu {
                    if isUserPost {
                        Button {
                            showEditSheet = true
                        } label: {
                            Label("Edit Post", systemImage: "pencil")
                        }
                        
                        Button(role: .destructive) {
                            showDeleteAlert = true
                        } label: {
                            Label("Delete Post", systemImage: "trash")
                        }
                        
                        Divider()
                    }
                    
                    Menu {
                        Button {
                            Task {
                                try await repostService.repost(postId: post.id.uuidString)
                            }
                        } label: {
                            Label("Repost", systemImage: "arrow.2.squarepath")
                        }
                        
                        Button {
                            showQuoteRepost = true
                        } label: {
                            Label("Quote Repost", systemImage: "quote.bubble")
                        }
                    } label: {
                        Label("Repost Options", systemImage: "arrow.triangle.2.circlepath")
                    }
                    
                    Menu {
                        Button {
                            Task {
                                try await savedPostsService.savePost(postId: post.id.uuidString)
                            }
                        } label: {
                            Label("Save to All", systemImage: "bookmark")
                        }
                        
                        ForEach(savedPostsService.collections.filter { $0 != "All" }, id: \.self) { collection in
                            Button {
                                Task {
                                    try await savedPostsService.savePost(
                                        postId: post.id.uuidString,
                                        collection: collection
                                    )
                                }
                            } label: {
                                Label("Save to \(collection)", systemImage: "folder")
                            }
                        }
                        
                        Divider()
                        
                        Button {
                            showSaveToCollection = true
                        } label: {
                            Label("New Collection...", systemImage: "folder.badge.plus")
                        }
                    } label: {
                        Label("Save Options", systemImage: "bookmark")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.6))
                        .frame(width: 32, height: 32)
                }
            }
            
            // MARK: - Content
            Text(post.content)
                .font(.custom("OpenSans-Regular", size: 16))
                .foregroundStyle(.primary)
                .lineSpacing(6)
            
            // Repost indicator
            if post.isRepost, let originalAuthor = post.originalAuthorName {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Reposted from \(originalAuthor)")
                        .font(.custom("OpenSans-SemiBold", size: 13))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color(.systemGray6)))
            }
            
            // MARK: - Action Buttons
            HStack(spacing: 8) {
                // Amen/Lightbulb
                if category == .openTable {
                    Button {
                        toggleLightbulb()
                    } label: {
                        ActionButton(
                            icon: hasLitLightbulb ? "lightbulb.fill" : "lightbulb",
                            count: post.lightbulbCount,
                            isActive: hasLitLightbulb,
                            activeColor: .yellow
                        )
                    }
                    .symbolEffect(.bounce, value: hasLitLightbulb)
                } else {
                    Button {
                        toggleAmen()
                    } label: {
                        ActionButton(
                            icon: hasSaidAmen ? "hands.clap.fill" : "hands.clap",
                            count: post.amenCount,
                            isActive: hasSaidAmen,
                            activeColor: .black
                        )
                    }
                    .symbolEffect(.bounce, value: hasSaidAmen)
                }
                
                // Comments
                Button {
                    showComments = true
                } label: {
                    ActionButton(
                        icon: "bubble.left.fill",
                        count: post.commentCount,
                        isActive: false
                    )
                }
                
                // Reposts
                Menu {
                    Button {
                        Task {
                            if hasReposted {
                                try await repostService.unrepost(postId: post.id.uuidString)
                            } else {
                                try await repostService.repost(postId: post.id.uuidString)
                            }
                        }
                    } label: {
                        Label(hasReposted ? "Unrepost" : "Repost", 
                              systemImage: "arrow.2.squarepath")
                    }
                    
                    Button {
                        showQuoteRepost = true
                    } label: {
                        Label("Quote Repost", systemImage: "quote.bubble")
                    }
                    
                    Divider()
                    
                    Button {
                        // Show who reposted
                    } label: {
                        Label("See who reposted", systemImage: "person.2")
                    }
                } label: {
                    ActionButton(
                        icon: "arrow.2.squarepath",
                        count: post.repostCount,
                        isActive: hasReposted,
                        activeColor: .green
                    )
                }
                
                Spacer()
                
                // Save
                Button {
                    Task {
                        try await savedPostsService.toggleSave(postId: post.id.uuidString)
                    }
                } label: {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSaved ? .blue : .black.opacity(0.5))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(isSaved ? Color.blue.opacity(0.1) : Color.black.opacity(0.05))
                        )
                        .overlay(
                            Capsule()
                                .stroke(isSaved ? Color.blue.opacity(0.3) : Color.black.opacity(0.1), lineWidth: 1)
                        )
                }
                .symbolEffect(.bounce, value: isSaved)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        )
        .task {
            await loadInteractionStates()
        }
        .sheet(isPresented: $showComments) {
            CommentsView(post: post)
                .environmentObject(userService)
        }
        .sheet(isPresented: $showQuoteRepost) {
            QuoteRepostView(post: post)
        }
        .sheet(isPresented: $showSaveToCollection) {
            CreateCollectionView(postId: post.id.uuidString)
        }
        .sheet(isPresented: $showEditSheet) {
            EditPostSheet(post: post)
        }
        .alert("Delete Post", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deletePost()
            }
        } message: {
            Text("Are you sure you want to delete this post? This action cannot be undone.")
        }
        .onChange(of: savedPostsService.savedPostIds) { _, _ in
            updateSavedState()
        }
        .onChange(of: repostService.repostedPostIds) { _, _ in
            updateRepostState()
        }
    }
    
    // MARK: - Actions
    
    private func loadInteractionStates() async {
        // Check saved status
        isSaved = await savedPostsService.isPostSaved(postId: post.id.uuidString)
        
        // Check repost status
        hasReposted = await repostService.hasReposted(postId: post.id.uuidString)
        
        // Check amen/lightbulb status (would need to add to FirebasePostService)
        // For now, using local state
    }
    
    private func updateSavedState() {
        isSaved = savedPostsService.savedPostIds.contains(post.id.uuidString)
    }
    
    private func updateRepostState() {
        hasReposted = repostService.repostedPostIds.contains(post.id.uuidString)
    }
    
    private func toggleLightbulb() {
        hasLitLightbulb.toggle()
        postsManager.updateLightbulbCount(postId: post.id, increment: hasLitLightbulb)
        
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
    }
    
    private func toggleAmen() {
        hasSaidAmen.toggle()
        postsManager.updateAmenCount(postId: post.id, increment: hasSaidAmen)
        
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
    }
    
    private func deletePost() {
        postsManager.deletePost(postId: post.id)
    }
}

// MARK: - Action Button Component

private struct ActionButton: View {
    let icon: String
    let count: Int
    var isActive: Bool = false
    var activeColor: Color = .blue
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
            
            if count > 0 {
                Text("\(count)")
                    .font(.custom("OpenSans-SemiBold", size: 11))
                    .contentTransition(.numericText())
            }
        }
        .foregroundStyle(isActive ? activeColor : Color.black.opacity(0.5))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(isActive ? activeColor.opacity(0.15) : Color.black.opacity(0.05))
        )
        .overlay(
            Capsule()
                .stroke(isActive ? activeColor.opacity(0.3) : Color.black.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Quote Repost View

struct QuoteRepostView: View {
    let post: Post
    
    @StateObject private var repostService = RepostService.shared
    @State private var comment = ""
    @State private var isPosting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Input area
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add your thoughts")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.secondary)
                    
                    TextEditor(text: $comment)
                        .font(.custom("OpenSans-Regular", size: 16))
                        .frame(height: 120)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemGray6))
                        )
                }
                .padding(.horizontal)
                
                // Original post preview
                VStack(alignment: .leading, spacing: 12) {
                    Text("Reposting")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                    
                    EnhancedPostCard(post: post)
                        .opacity(0.8)
                        .padding(.horizontal)
                }
                
                Spacer()
            }
            .navigationTitle("Quote Repost")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        submitQuoteRepost()
                    } label: {
                        if isPosting {
                            ProgressView()
                        } else {
                            Text("Repost")
                                .font(.custom("OpenSans-SemiBold", size: 16))
                        }
                    }
                    .disabled(comment.isEmpty || isPosting)
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func submitQuoteRepost() {
        isPosting = true
        
        Task {
            do {
                try await repostService.repost(
                    postId: post.id.uuidString,
                    withComment: comment
                )
                
                dismiss()
                
                // Haptic feedback
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            
            isPosting = false
        }
    }
}

// MARK: - Create Collection View

struct CreateCollectionView: View {
    let postId: String
    
    @StateObject private var savedPostsService = SavedPostsService.shared
    @State private var collectionName = ""
    @State private var isCreating = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                TextField("Collection Name", text: $collectionName)
                    .font(.custom("OpenSans-Regular", size: 16))
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray6))
                    )
                    .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("New Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        createCollection()
                    } label: {
                        if isCreating {
                            ProgressView()
                        } else {
                            Text("Create")
                        }
                    }
                    .disabled(collectionName.isEmpty || isCreating)
                }
            }
        }
    }
    
    private func createCollection() {
        isCreating = true
        
        Task {
            do {
                try await savedPostsService.createCollection(name: collectionName)
                try await savedPostsService.savePost(postId: postId, collection: collectionName)
                dismiss()
            } catch {
                print("Error creating collection: \(error)")
            }
            
            isCreating = false
        }
    }
}

#Preview {
    EnhancedPostCard(
        post: Post(
            authorName: "John Disciple",
            authorInitials: "JD",
            content: "This is a test post with all the new social features!",
            category: .openTable,
            topicTag: "Tech & Faith"
        )
    )
    .environmentObject(UserService())
}
