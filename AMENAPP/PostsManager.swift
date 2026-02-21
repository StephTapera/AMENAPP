//
//  PostsManager.swift
//  AMENAPP
//
//  Created by Steph on 1/17/26.
//

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Post Model

/// Represents a user mention reference in post content
struct MentionedUser: Codable, Equatable, Hashable {
    let userId: String
    let username: String
    let displayName: String
}

struct Post: Identifiable, Codable, Equatable {
    let id: UUID
    let firebaseId: String?
    let authorId: String  // Firebase user ID of the post author
    let authorName: String
    let authorUsername: String?  // Optional username (e.g., @johndoe)
    let authorInitials: String
    let authorProfileImageURL: String?  // Profile image URL
    let timeAgo: String
    var content: String  // Made mutable for editing
    let category: PostCategory
    let topicTag: String?
    let visibility: PostVisibility
    let allowComments: Bool
    var commentPermissions: CommentPermissions? // Who can comment
    let imageURLs: [String]?
    let linkURL: String?
    let linkPreviewTitle: String?  // Link preview title
    let linkPreviewDescription: String?  // Link preview description
    let linkPreviewImageURL: String?  // Link preview image
    let linkPreviewSiteName: String?  // Link preview site name
    let createdAt: Date
    var amenCount: Int
    var lightbulbCount: Int
    var commentCount: Int
    var repostCount: Int
    var isRepost: Bool = false  // Track if this is a repost
    var originalAuthorName: String? = nil // Track original author if repost
    var originalAuthorId: String? = nil // Track original author ID if repost
    var churchNoteId: String? = nil // Optional church note ID if post contains a shared note
    var mentions: [MentionedUser]? = nil // User mentions in this post
    
    // Translation metadata
    var originalContent: String? = nil // Original content before translation
    var detectedLanguage: String? = nil // Detected source language (ISO 639-1 code)
    var isTranslated: Bool = false // Whether this post is currently showing translated content

    enum PostCategory: String, Codable, CaseIterable {
        case openTable = "openTable"      // ✅ Firebase-safe (no special chars)
        case testimonies = "testimonies"  // ✅ Firebase-safe (lowercase)
        case prayer = "prayer"            // ✅ Firebase-safe (lowercase)
        case tip = "tip"                  // ✅ NEW: Tips category
        case funFact = "funFact"          // ✅ NEW: Fun Facts category
        
        /// Display name for UI (with special formatting)
        var displayName: String {
            switch self {
            case .openTable: return "#OPENTABLE"
            case .testimonies: return "Testimonies"
            case .prayer: return "Prayer"
            case .tip: return "Tip"
            case .funFact: return "Fun Fact"
            }
        }
        
        /// Whether this category should show its badge on post cards
        var showCategoryBadge: Bool {
            switch self {
            case .openTable, .testimonies, .prayer:
                return true
            case .tip, .funFact:
                return false  // Hide category badge for Tips and Fun Facts
            }
        }
        
        var cardCategory: PostCard.PostCardCategory {
            switch self {
            case .openTable: return .openTable
            case .testimonies: return .testimonies
            case .prayer: return .prayer
            case .tip: return .openTable  // Use openTable style for now
            case .funFact: return .openTable  // Use openTable style for now
            }
        }
    }
    
    enum PostVisibility: String, Codable {
        case everyone = "Everyone"
        case followers = "Followers"
        case community = "Community Only"
    }
    
    enum CommentPermissions: String, Codable, CaseIterable {
        case everyone = "Everyone"
        case following = "People I follow"
        case mentioned = "Mentioned only"
        case off = "Comments off"
        
        var icon: String {
            switch self {
            case .everyone: return "globe"
            case .following: return "person.2.fill"
            case .mentioned: return "at"
            case .off: return "bubble.left.and.bubble.right.fill"
            }
        }
    }
    
    // MARK: - Custom Decoding (Handle Missing Fields)
    
    enum CodingKeys: String, CodingKey {
        case id, firebaseId, authorId, authorName, authorUsername, authorInitials, authorProfileImageURL, timeAgo
        case content, category, topicTag, visibility, allowComments, commentPermissions
        case imageURLs, linkURL, linkPreviewTitle, linkPreviewDescription, linkPreviewImageURL, linkPreviewSiteName, createdAt
        case amenCount, lightbulbCount, commentCount, repostCount
        case isRepost, originalAuthorName, originalAuthorId, churchNoteId, mentions
        case originalContent, detectedLanguage, isTranslated
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        firebaseId = try container.decodeIfPresent(String.self, forKey: .firebaseId)
        authorId = try container.decode(String.self, forKey: .authorId)
        authorName = try container.decode(String.self, forKey: .authorName)
        
        // ✅ Gracefully handle missing authorUsername (for backward compatibility)
        authorUsername = try container.decodeIfPresent(String.self, forKey: .authorUsername)
        
        authorInitials = try container.decode(String.self, forKey: .authorInitials)
        
        // ✅ Gracefully handle missing authorProfileImageURL (for backward compatibility)
        authorProfileImageURL = try container.decodeIfPresent(String.self, forKey: .authorProfileImageURL)
        
        timeAgo = try container.decode(String.self, forKey: .timeAgo)
        content = try container.decode(String.self, forKey: .content)
        category = try container.decode(PostCategory.self, forKey: .category)
        topicTag = try container.decodeIfPresent(String.self, forKey: .topicTag)
        visibility = try container.decode(PostVisibility.self, forKey: .visibility)
        allowComments = try container.decode(Bool.self, forKey: .allowComments)
        commentPermissions = try container.decodeIfPresent(CommentPermissions.self, forKey: .commentPermissions)
        imageURLs = try container.decodeIfPresent([String].self, forKey: .imageURLs)
        linkURL = try container.decodeIfPresent(String.self, forKey: .linkURL)
        linkPreviewTitle = try container.decodeIfPresent(String.self, forKey: .linkPreviewTitle)
        linkPreviewDescription = try container.decodeIfPresent(String.self, forKey: .linkPreviewDescription)
        linkPreviewImageURL = try container.decodeIfPresent(String.self, forKey: .linkPreviewImageURL)
        linkPreviewSiteName = try container.decodeIfPresent(String.self, forKey: .linkPreviewSiteName)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        amenCount = try container.decode(Int.self, forKey: .amenCount)
        lightbulbCount = try container.decode(Int.self, forKey: .lightbulbCount)
        commentCount = try container.decode(Int.self, forKey: .commentCount)
        repostCount = try container.decode(Int.self, forKey: .repostCount)
        isRepost = try container.decodeIfPresent(Bool.self, forKey: .isRepost) ?? false
        originalAuthorName = try container.decodeIfPresent(String.self, forKey: .originalAuthorName)
        originalAuthorId = try container.decodeIfPresent(String.self, forKey: .originalAuthorId)
        churchNoteId = try container.decodeIfPresent(String.self, forKey: .churchNoteId)
        mentions = try container.decodeIfPresent([MentionedUser].self, forKey: .mentions)
        originalContent = try container.decodeIfPresent(String.self, forKey: .originalContent)
        detectedLanguage = try container.decodeIfPresent(String.self, forKey: .detectedLanguage)
        isTranslated = try container.decodeIfPresent(Bool.self, forKey: .isTranslated) ?? false
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(firebaseId, forKey: .firebaseId)
        try container.encode(authorId, forKey: .authorId)
        try container.encode(authorName, forKey: .authorName)
        try container.encodeIfPresent(authorUsername, forKey: .authorUsername)
        try container.encode(authorInitials, forKey: .authorInitials)
        try container.encodeIfPresent(authorProfileImageURL, forKey: .authorProfileImageURL)
        try container.encode(timeAgo, forKey: .timeAgo)
        try container.encode(content, forKey: .content)
        try container.encode(category, forKey: .category)
        try container.encodeIfPresent(topicTag, forKey: .topicTag)
        try container.encode(visibility, forKey: .visibility)
        try container.encode(allowComments, forKey: .allowComments)
        try container.encodeIfPresent(commentPermissions, forKey: .commentPermissions)
        try container.encodeIfPresent(imageURLs, forKey: .imageURLs)
        try container.encodeIfPresent(linkURL, forKey: .linkURL)
        try container.encodeIfPresent(linkPreviewTitle, forKey: .linkPreviewTitle)
        try container.encodeIfPresent(linkPreviewDescription, forKey: .linkPreviewDescription)
        try container.encodeIfPresent(linkPreviewImageURL, forKey: .linkPreviewImageURL)
        try container.encodeIfPresent(linkPreviewSiteName, forKey: .linkPreviewSiteName)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(amenCount, forKey: .amenCount)
        try container.encode(lightbulbCount, forKey: .lightbulbCount)
        try container.encode(commentCount, forKey: .commentCount)
        try container.encode(repostCount, forKey: .repostCount)
        try container.encode(isRepost, forKey: .isRepost)
        try container.encodeIfPresent(originalAuthorName, forKey: .originalAuthorName)
        try container.encodeIfPresent(originalAuthorId, forKey: .originalAuthorId)
        try container.encodeIfPresent(churchNoteId, forKey: .churchNoteId)
        try container.encodeIfPresent(mentions, forKey: .mentions)
        try container.encodeIfPresent(originalContent, forKey: .originalContent)
        try container.encodeIfPresent(detectedLanguage, forKey: .detectedLanguage)
        try container.encode(isTranslated, forKey: .isTranslated)
    }
    
    init(
        id: UUID = UUID(),
        firebaseId: String? = nil,
        authorId: String = "",
        authorName: String,
        authorUsername: String? = nil,
        authorInitials: String,
        authorProfileImageURL: String? = nil,
        timeAgo: String = "Just now",
        content: String,
        category: PostCategory,
        topicTag: String? = nil,
        visibility: PostVisibility = .everyone,
        allowComments: Bool = true,
        commentPermissions: CommentPermissions? = .everyone,
        imageURLs: [String]? = nil,
        linkURL: String? = nil,
        linkPreviewTitle: String? = nil,
        linkPreviewDescription: String? = nil,
        linkPreviewImageURL: String? = nil,
        linkPreviewSiteName: String? = nil,
        createdAt: Date = Date(),
        amenCount: Int = 0,
        lightbulbCount: Int = 0,
        commentCount: Int = 0,
        repostCount: Int = 0,
        isRepost: Bool = false,
        originalAuthorName: String? = nil,
        originalAuthorId: String? = nil,
        churchNoteId: String? = nil
    ) {
        self.id = id
        self.firebaseId = firebaseId
        self.authorId = authorId
        self.authorName = authorName
        self.authorUsername = authorUsername
        self.authorInitials = authorInitials
        self.authorProfileImageURL = authorProfileImageURL
        self.timeAgo = timeAgo
        self.content = content
        self.category = category
        self.topicTag = topicTag
        self.visibility = visibility
        self.allowComments = allowComments
        self.commentPermissions = commentPermissions
        self.imageURLs = imageURLs
        self.linkURL = linkURL
        self.linkPreviewTitle = linkPreviewTitle
        self.linkPreviewDescription = linkPreviewDescription
        self.linkPreviewImageURL = linkPreviewImageURL
        self.linkPreviewSiteName = linkPreviewSiteName
        self.createdAt = createdAt
        self.amenCount = amenCount
        self.lightbulbCount = lightbulbCount
        self.commentCount = commentCount
        self.repostCount = repostCount
        self.isRepost = isRepost
        self.originalAuthorName = originalAuthorName
        self.originalAuthorId = originalAuthorId
        self.churchNoteId = churchNoteId
    }

    var backendId: String {
        firebaseId ?? id.uuidString
    }
}

// MARK: - Posts Manager

class PostsManager: ObservableObject {
    @MainActor static let shared = PostsManager()
    
    @Published var openTablePosts: [Post] = []
    @Published var testimoniesPosts: [Post] = []
    @Published var prayerPosts: [Post] = []
    @Published var allPosts: [Post] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let firebasePostService = FirebasePostService.shared
    private let personalizationService = PersonalizationService.shared
    private var profileUpdateListeners: [String: Any] = [:] // Store Firestore listeners
    
    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Setup real-time sync with FirebasePostService using Combine
        setupFirebaseSync()

        // Load posts from Firebase
        Task {
            await loadPostsFromFirebase()
            // Start listening for profile picture updates
            await startListeningForProfileUpdates()
        }
    }

    // ✅ Setup real-time sync with FirebasePostService using Combine publishers
    private func setupFirebaseSync() {
        // P0 FIX: Add debouncing to reduce cascade re-renders from 4x to 1x
        // Listen to prayer posts changes
        firebasePostService.$prayerPosts
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newPosts in
                guard let self = self else { return }
                // P0-4: Removed objectWillChange.send() - @Published already triggers updates
                self.prayerPosts = newPosts
                print("🔄 Prayer posts updated: \(newPosts.count) posts")
            }
            .store(in: &cancellables)

        // Listen to testimonies posts changes
        firebasePostService.$testimoniesPosts
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newPosts in
                guard let self = self else { return }
                // P0-4: Removed objectWillChange.send() - @Published already triggers updates
                self.testimoniesPosts = newPosts
                print("🔄 Testimonies posts updated: \(newPosts.count) posts")
            }
            .store(in: &cancellables)

        // Listen to open table posts changes
        firebasePostService.$openTablePosts
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newPosts in
                guard let self = self else { return }
                // P0-4: Removed objectWillChange.send() - @Published already triggers updates
                self.openTablePosts = newPosts
                print("🔄 OpenTable posts updated: \(newPosts.count) posts (with profile images)")
            }
            .store(in: &cancellables)

        // Listen to all posts changes
        firebasePostService.$posts
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newPosts in
                guard let self = self else { return }
                // P0-4: Removed objectWillChange.send() - @Published already triggers updates
                self.allPosts = newPosts
                print("🔄 All posts updated: \(newPosts.count) posts")
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Load from Firebase
    
    func loadPostsFromFirebase() async {
        // Skip loading if user is not authenticated
        guard Auth.auth().currentUser != nil else {
            print("⏭️ Skipping post load - user not authenticated")
            return
        }
        
        do {
            print("📥 Loading posts from Firebase...")
            try await firebasePostService.fetchAllPosts()
            
            // ✅ Don't start listener here - let individual views handle it with their category filters
            // This prevents listener conflicts
            
            // Update local arrays from FirebasePostService
            await MainActor.run {
                self.allPosts = firebasePostService.posts
                self.openTablePosts = firebasePostService.openTablePosts
                self.testimoniesPosts = firebasePostService.testimoniesPosts
                self.prayerPosts = firebasePostService.prayerPosts
                
                print("✅ Posts loaded: \(allPosts.count) total, \(prayerPosts.count) prayer, \(testimoniesPosts.count) testimonies, \(openTablePosts.count) openTable")
            }
        } catch {
            print("❌ Failed to load posts from Firebase: \(error)")
            self.error = error.localizedDescription
        }
    }
    
    func refreshPosts() async {
        await loadPostsFromFirebase()
    }
    
    // MARK: - Create Post
    
    func createPost(
        content: String,
        category: Post.PostCategory,
        topicTag: String? = nil,
        visibility: Post.PostVisibility = .everyone,
        allowComments: Bool = true,
        imageURLs: [String]? = nil,
        linkURL: String? = nil,
        churchNoteId: String? = nil
    ) {
        Task {
            do {
                // Use Firebase service to create post
                try await firebasePostService.createPost(
                    content: content,
                    category: category,
                    topicTag: topicTag,
                    visibility: visibility,
                    allowComments: allowComments,
                    imageURLs: imageURLs,
                    linkURL: linkURL,
                    churchNoteId: churchNoteId
                )
                
                print("✅ Post created successfully")
                
                // Real-time listener will automatically update the UI
                // But we can manually refresh if needed
                await refreshPosts()
                
                // Post notification for UI update
                NotificationCenter.default.post(
                    name: .newPostCreated,
                    object: nil,
                    userInfo: ["category": category.rawValue]
                )
                
            } catch {
                print("❌ Failed to create post: \(error)")
                self.error = error.localizedDescription
            }
        }
    }
    
    // MARK: - Get Posts by Category
    
    func getPosts(for category: Post.PostCategory) -> [Post] {
        switch category {
        case .openTable:
            return openTablePosts
        case .testimonies:
            return testimoniesPosts
        case .prayer:
            return prayerPosts
        case .tip, .funFact:
            return allPosts.filter { $0.category == category }
        }
    }
    
    // MARK: - Fetch Filtered Posts
    
    /// Fetch posts with filter and category applied (backend-connected)
    func fetchFilteredPosts(
        for category: Post.PostCategory,
        filter: String,
        topicTag: String? = nil
    ) async {
        do {
            print("📥 Fetching filtered posts: category=\(category.rawValue), filter=\(filter), topicTag=\(topicTag ?? "none")")
            
            let posts = try await firebasePostService.fetchPosts(
                for: category,
                filter: filter,
                topicTag: topicTag
            )
            
            // Apply personalization if "For You" filter
            let finalPosts: [Post]
            if filter == "For You" {
                // Use the new PersonalizationService for better algorithm
                finalPosts = personalizationService.personalizePostsFeed(posts, category: category)
            } else {
                finalPosts = posts
            }
            
            // Update the appropriate category array
            switch category {
            case .openTable:
                self.openTablePosts = finalPosts
            case .testimonies:
                self.testimoniesPosts = finalPosts
            case .prayer:
                self.prayerPosts = finalPosts
            case .tip, .funFact:
                // Tip and funFact posts are shown in the main feed, not separate arrays
                break
            }
            
            print("✅ Updated \(category.rawValue) posts with \(finalPosts.count) items (personalized: \(filter == "For You"))")
            
        } catch {
            print("❌ Failed to fetch filtered posts: \(error)")
            self.error = error.localizedDescription
        }
    }
    
    // MARK: - Edit Post
    
    func editPost(postId: UUID, newContent: String) {
        Task {
            do {
                try await firebasePostService.editPost(postId: postId.uuidString, newContent: newContent)
                
                print("✅ Post edited successfully")
                
                // Update local cache
                updatePostInAllArrays(postId: postId) { post in
                    var updatedPost = post
                    updatedPost.content = newContent
                    return updatedPost
                }
                
                // Post notification for UI update
                NotificationCenter.default.post(
                    name: .postEdited,
                    object: nil,
                    userInfo: ["postId": postId]
                )
                
                // Haptic feedback
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
                
            } catch {
                print("❌ Failed to edit post: \(error)")
                self.error = error.localizedDescription
            }
        }
    }
    
    // MARK: - Delete Post
    
    func deletePost(postId: UUID) {
        Task {
            do {
                try await firebasePostService.deletePost(postId: postId.uuidString)
                
                print("✅ Post deleted successfully")
                
                // Remove from local arrays
                allPosts.removeAll { $0.id == postId }
                openTablePosts.removeAll { $0.id == postId }
                testimoniesPosts.removeAll { $0.id == postId }
                prayerPosts.removeAll { $0.id == postId }
                
                // Post notification for UI update
                NotificationCenter.default.post(
                    name: .postDeleted,
                    object: nil,
                    userInfo: ["postId": postId]
                )
                
                // Haptic feedback
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.warning)
                
            } catch {
                print("❌ Failed to delete post: \(error)")
                self.error = error.localizedDescription
            }
        }
    }
    
    // MARK: - Repost to Profile
    
    func repostToProfile(originalPost: Post, userInitials: String = "JD", userName: String = "John Disciple") {
        print("🔵 [POSTSMANAGER] repostToProfile() called for post: \(originalPost.firestoreId)")
        Task {
            do {
                print("🔵 [POSTSMANAGER] Calling RealtimeRepostsService.repostPost()...")
                // Use RealtimeRepostsService for reposts
                try await RealtimeRepostsService.shared.repostPost(postId: originalPost.id, originalPost: originalPost)

                print("✅ Post reposted successfully via RealtimeRepostsService")

                // Notification is already sent by RealtimeRepostsService
                // No need to send duplicate notification here

            } catch {
                print("❌ Failed to repost: \(error)")
                self.error = error.localizedDescription
            }
        }
    }

    /// Remove a repost from the user's profile
    func removeRepost(postId: UUID, firestoreId: String) {
        Task {
            do {
                // Use RealtimeRepostsService to remove the repost
                // ✅ Pass Firestore ID instead of UUID
                try await RealtimeRepostsService.shared.undoRepost(firestoreId: firestoreId)

                print("✅ Repost removed successfully via RealtimeRepostsService")

                // Remove from local cache
                allPosts.removeAll { $0.id == postId && $0.isRepost }
                openTablePosts.removeAll { $0.id == postId && $0.isRepost }
                testimoniesPosts.removeAll { $0.id == postId && $0.isRepost }
                prayerPosts.removeAll { $0.id == postId && $0.isRepost }

            } catch {
                print("❌ Failed to remove repost: \(error)")
                self.error = error.localizedDescription
            }
        }
    }
    
    // MARK: - Update Post Interactions
    
    func updateAmenCount(postId: UUID, increment: Bool) {
        Task {
            do {
                try await firebasePostService.toggleAmen(postId: postId.uuidString)
                
                // Update local cache
                updatePostInAllArrays(postId: postId) { post in
                    var updatedPost = post
                    updatedPost.amenCount += increment ? 1 : -1
                    return updatedPost
                }
            } catch {
                print("❌ Failed to update amen count: \(error)")
            }
        }
    }
    
    func updateLightbulbCount(postId: UUID, increment: Bool) {
        Task {
            do {
                try await firebasePostService.toggleLightbulb(postId: postId.uuidString)
                
                // Update local cache
                updatePostInAllArrays(postId: postId) { post in
                    var updatedPost = post
                    updatedPost.lightbulbCount += increment ? 1 : -1
                    return updatedPost
                }
            } catch {
                print("❌ Failed to update lightbulb count: \(error)")
            }
        }
    }
    
    func updateCommentCount(postId: UUID, increment: Bool) {
        Task {
            do {
                if increment {
                    try await firebasePostService.incrementCommentCount(postId: postId.uuidString)
                }
                
                // Update local cache
                updatePostInAllArrays(postId: postId) { post in
                    var updatedPost = post
                    updatedPost.commentCount += increment ? 1 : -1
                    return updatedPost
                }
            } catch {
                print("❌ Failed to update comment count: \(error)")
            }
        }
    }
    
    func updateRepostCount(postId: UUID, increment: Bool) {
        // This is handled automatically by repostToProfile
        updatePostInAllArrays(postId: postId) { post in
            var updatedPost = post
            updatedPost.repostCount += increment ? 1 : -1
            return updatedPost
        }
    }
    
    // MARK: - Helper Methods
    
    private func updatePostInAllArrays(postId: UUID, update: (Post) -> Post) {
        // Update in all posts
        if let index = allPosts.firstIndex(where: { $0.id == postId }) {
            allPosts[index] = update(allPosts[index])
        }
        
        // Update in category-specific arrays
        if let index = openTablePosts.firstIndex(where: { $0.id == postId }) {
            openTablePosts[index] = update(openTablePosts[index])
        }
        
        if let index = testimoniesPosts.firstIndex(where: { $0.id == postId }) {
            testimoniesPosts[index] = update(testimoniesPosts[index])
        }
        
        if let index = prayerPosts.firstIndex(where: { $0.id == postId }) {
            prayerPosts[index] = update(prayerPosts[index])
        }
    }
    
    // MARK: - Profile Picture Sync
    
    /// P0 FIX: Replace N+1 real-time listeners with periodic batch updates
    /// Instead of 50-100 listeners, use a single timer to refresh profile images every 5 minutes
    private func startListeningForProfileUpdates() async {
        print("👂 [PERF FIX] Using batch profile updates instead of individual listeners")
        
        // Start a timer to refresh profile images every 5 minutes
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000_000) // 5 minutes
                await refreshProfileImages()
            }
        }
        
        print("✅ Batch profile update timer started (5 min intervals)")
    }
    
    /// Batch refresh profile images for all unique authors
    private func refreshProfileImages() async {
        let db = Firestore.firestore()
        
        // Get unique author IDs
        var authorIds = Set<String>()
        await MainActor.run {
            for post in allPosts {
                authorIds.insert(post.authorId)
            }
        }
        
        guard !authorIds.isEmpty else { return }
        
        print("🔄 Refreshing profile images for \(authorIds.count) authors...")
        
        // Batch fetch user profiles (10 at a time due to Firestore 'in' limit)
        let authorIdArray = Array(authorIds)
        for i in stride(from: 0, to: authorIdArray.count, by: 10) {
            let batch = Array(authorIdArray[i..<min(i + 10, authorIdArray.count)])
            
            do {
                let snapshot = try await db.collection("users")
                    .whereField(FieldPath.documentID(), in: batch)
                    .getDocuments()
                
                for document in snapshot.documents {
                    if let profileImageURL = document.data()["profileImageURL"] as? String {
                        await MainActor.run {
                            self.updatePostsForUser(userId: document.documentID, newProfileImageURL: profileImageURL)
                        }
                    }
                }
            } catch {
                print("⚠️ Failed to batch fetch profiles: \(error)")
            }
        }
    }
    
    // ✅ P0-1 FIX: Add cleanup method to remove all profile listeners
    /// Stop all profile picture listeners to prevent memory leaks
    /// Call this from view onDisappear blocks
    @MainActor
    func stopListeningForProfileUpdates() {
        print("🛑 Stopping \(profileUpdateListeners.count) profile picture listeners...")
        
        // Remove all Firestore listeners
        for (authorId, listener) in profileUpdateListeners {
            if let firestoreListener = listener as? ListenerRegistration {
                firestoreListener.remove()
            }
        }
        
        // Clear the dictionary
        profileUpdateListeners.removeAll()
        
        print("✅ All profile listeners stopped")
    }
    
    /// Update all posts from a specific user with their new profile image
    private func updatePostsForUser(userId: String, newProfileImageURL: String) {
        print("🔄 Updating posts for user \(userId) with new profile picture")
        
        var postsUpdated = 0
        
        // Update all posts arrays
        allPosts = allPosts.map { post in
            guard post.authorId == userId else { return post }
            postsUpdated += 1
            return Post(
                id: post.id,
                firebaseId: post.firebaseId,
                authorId: post.authorId,
                authorName: post.authorName,
                authorUsername: post.authorUsername,
                authorInitials: post.authorInitials,
                authorProfileImageURL: newProfileImageURL,
                timeAgo: post.timeAgo,
                content: post.content,
                category: post.category,
                topicTag: post.topicTag,
                visibility: post.visibility,
                allowComments: post.allowComments,
                imageURLs: post.imageURLs,
                linkURL: post.linkURL,
                createdAt: post.createdAt,
                amenCount: post.amenCount,
                lightbulbCount: post.lightbulbCount,
                commentCount: post.commentCount,
                repostCount: post.repostCount,
                isRepost: post.isRepost,
                originalAuthorName: post.originalAuthorName,
                originalAuthorId: post.originalAuthorId
            )
        }
        
        openTablePosts = openTablePosts.map { post in
            guard post.authorId == userId else { return post }
            return Post(
                id: post.id,
                firebaseId: post.firebaseId,
                authorId: post.authorId,
                authorName: post.authorName,
                authorUsername: post.authorUsername,
                authorInitials: post.authorInitials,
                authorProfileImageURL: newProfileImageURL,
                timeAgo: post.timeAgo,
                content: post.content,
                category: post.category,
                topicTag: post.topicTag,
                visibility: post.visibility,
                allowComments: post.allowComments,
                imageURLs: post.imageURLs,
                linkURL: post.linkURL,
                createdAt: post.createdAt,
                amenCount: post.amenCount,
                lightbulbCount: post.lightbulbCount,
                commentCount: post.commentCount,
                repostCount: post.repostCount,
                isRepost: post.isRepost,
                originalAuthorName: post.originalAuthorName,
                originalAuthorId: post.originalAuthorId
            )
        }
        
        testimoniesPosts = testimoniesPosts.map { post in
            guard post.authorId == userId else { return post }
            return Post(
                id: post.id,
                firebaseId: post.firebaseId,
                authorId: post.authorId,
                authorName: post.authorName,
                authorUsername: post.authorUsername,
                authorInitials: post.authorInitials,
                authorProfileImageURL: newProfileImageURL,
                timeAgo: post.timeAgo,
                content: post.content,
                category: post.category,
                topicTag: post.topicTag,
                visibility: post.visibility,
                allowComments: post.allowComments,
                imageURLs: post.imageURLs,
                linkURL: post.linkURL,
                createdAt: post.createdAt,
                amenCount: post.amenCount,
                lightbulbCount: post.lightbulbCount,
                commentCount: post.commentCount,
                repostCount: post.repostCount,
                isRepost: post.isRepost,
                originalAuthorName: post.originalAuthorName,
                originalAuthorId: post.originalAuthorId
            )
        }
        
        prayerPosts = prayerPosts.map { post in
            guard post.authorId == userId else { return post }
            return Post(
                id: post.id,
                firebaseId: post.firebaseId,
                authorId: post.authorId,
                authorName: post.authorName,
                authorUsername: post.authorUsername,
                authorInitials: post.authorInitials,
                authorProfileImageURL: newProfileImageURL,
                timeAgo: post.timeAgo,
                content: post.content,
                category: post.category,
                topicTag: post.topicTag,
                visibility: post.visibility,
                allowComments: post.allowComments,
                imageURLs: post.imageURLs,
                linkURL: post.linkURL,
                createdAt: post.createdAt,
                amenCount: post.amenCount,
                lightbulbCount: post.lightbulbCount,
                commentCount: post.commentCount,
                repostCount: post.repostCount,
                isRepost: post.isRepost,
                originalAuthorName: post.originalAuthorName,
                originalAuthorId: post.originalAuthorId
            )
        }
        
        print("✅ Updated \(postsUpdated) posts with new profile picture")
    }
    
    /// Sync all posts with fresh user profile images from Firestore
    /// This ensures profile pictures are always up-to-date when the app opens
    func syncAllPostsWithUserProfiles() async {
        print("🔄 Syncing all posts with user profile images...")
        
        let db = Firestore.firestore()
        
        // Collect all unique author IDs from all posts
        var authorIds = Set<String>()
        
        await MainActor.run {
            for post in allPosts {
                authorIds.insert(post.authorId)
            }
        }
        
        guard !authorIds.isEmpty else {
            print("ℹ️ No posts to sync")
            return
        }
        
        print("📊 Found \(authorIds.count) unique authors to sync")
        
        // Fetch fresh profile data for all authors
        var profileImageMap: [String: String] = [:]
        
        for authorId in authorIds {
            do {
                let userDoc = try await db.collection("users").document(authorId).getDocument()
                
                if let userData = userDoc.data(),
                   let profileImageURL = userData["profileImageURL"] as? String,
                   !profileImageURL.isEmpty {
                    profileImageMap[authorId] = profileImageURL
                }
            } catch {
                print("⚠️ Failed to fetch profile for user \(authorId): \(error)")
            }
        }
        
        print("✅ Fetched \(profileImageMap.count) profile images")
        
        // Update all posts with fresh profile images
        await MainActor.run {
            // Create updated posts
            var updatedAllPosts: [Post] = []
            var updatedOpenTablePosts: [Post] = []
            var updatedTestimoniesPosts: [Post] = []
            var updatedPrayerPosts: [Post] = []
            
            for post in allPosts {
                let profileImageURL = profileImageMap[post.authorId]
                let updatedPost = Post(
                    id: post.id,
                    firebaseId: post.firebaseId,
                    authorId: post.authorId,
                    authorName: post.authorName,
                    authorUsername: post.authorUsername,
                    authorInitials: post.authorInitials,
                    authorProfileImageURL: profileImageURL, // Updated!
                    timeAgo: post.timeAgo,
                    content: post.content,
                    category: post.category,
                    topicTag: post.topicTag,
                    visibility: post.visibility,
                    allowComments: post.allowComments,
                    imageURLs: post.imageURLs,
                    linkURL: post.linkURL,
                    createdAt: post.createdAt,
                    amenCount: post.amenCount,
                    lightbulbCount: post.lightbulbCount,
                    commentCount: post.commentCount,
                    repostCount: post.repostCount,
                    isRepost: post.isRepost,
                    originalAuthorName: post.originalAuthorName,
                    originalAuthorId: post.originalAuthorId
                )
                
                updatedAllPosts.append(updatedPost)
                
                // Also update category-specific arrays
                switch post.category {
                case .openTable:
                    updatedOpenTablePosts.append(updatedPost)
                case .testimonies:
                    updatedTestimoniesPosts.append(updatedPost)
                case .prayer:
                    updatedPrayerPosts.append(updatedPost)
                case .tip, .funFact:
                    // Tip and funFact posts stay in allPosts only
                    break
                }
            }
            
            // Replace all posts with updated versions
            self.allPosts = updatedAllPosts
            self.openTablePosts = updatedOpenTablePosts
            self.testimoniesPosts = updatedTestimoniesPosts
            self.prayerPosts = updatedPrayerPosts
            
            print("✅ Profile picture sync complete! Updated \(updatedAllPosts.count) posts")
        }
    }
}


