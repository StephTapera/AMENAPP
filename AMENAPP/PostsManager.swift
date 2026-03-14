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
    var authorProfileImageURL: String?  // Profile image URL (var for profile-refresh updates)
    let timeAgo: String
    var content: String  // Made mutable for editing
    let category: PostCategory
    let topicTag: String?
    let visibility: PostVisibility
    let allowComments: Bool
    var commentPermissions: CommentPermissions? // Who can comment
    let imageURLs: [String]?
    let linkURL: String?
    let linkPreviewTitle: String?      // Link preview title
    let linkPreviewDescription: String? // Link preview description
    let linkPreviewImageURL: String?   // Link preview image
    let linkPreviewSiteName: String?   // Link preview site name
    let linkPreviewType: String?       // "link" | "verse"
    let verseReference: String?        // e.g. "John 3:16"
    let verseText: String?             // verse body text (optional)
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
    var taggedUserIds: [String]? = nil // Users explicitly tagged in this post
    var tagStatusByUid: [String: String]? = nil // "approved" | "pending" per tagged user
    
    // Translation metadata
    var originalContent: String? = nil // Original content before translation
    var detectedLanguage: String? = nil // Detected source language (ISO 639-1 code)
    var isTranslated: Bool = false // Whether this post is currently showing translated content

    // Content source — set when user acknowledges the content is not fully their own
    // e.g. "ChatGPT", "External" — nil means organic/original
    var contentSource: String? = nil

    // Church tag — optional church the post is associated with
    var taggedChurchId: String? = nil
    var taggedChurchName: String? = nil

    // Moderation metadata (set by server-side onPostCreate trigger)
    var flaggedForReview: Bool = false // Post is under review by moderators
    var removed: Bool = false // Post was removed by automated moderation

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

        var displayName: String {
            switch self {
            case .everyone: return "Everyone"
            case .followers: return "Followers Only"
            case .community: return "Community Only"
            }
        }

        var icon: String {
            switch self {
            case .everyone: return "globe"
            case .followers: return "person.2.fill"
            case .community: return "building.columns.fill"
            }
        }

        var tintColor: Color {
            switch self {
            case .everyone: return .blue
            case .followers: return .green
            case .community: return .purple
            }
        }
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
        case imageURLs, linkURL, linkPreviewTitle, linkPreviewDescription, linkPreviewImageURL, linkPreviewSiteName
        case linkPreviewType, verseReference, verseText
        case createdAt
        case amenCount, lightbulbCount, commentCount, repostCount
        case isRepost, originalAuthorName, originalAuthorId, churchNoteId, mentions
        case taggedUserIds, tagStatusByUid
        case originalContent, detectedLanguage, isTranslated
        case contentSource
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
        linkPreviewType = try container.decodeIfPresent(String.self, forKey: .linkPreviewType)
        verseReference = try container.decodeIfPresent(String.self, forKey: .verseReference)
        verseText = try container.decodeIfPresent(String.self, forKey: .verseText)
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
        taggedUserIds = try container.decodeIfPresent([String].self, forKey: .taggedUserIds)
        tagStatusByUid = try container.decodeIfPresent([String: String].self, forKey: .tagStatusByUid)
        originalContent = try container.decodeIfPresent(String.self, forKey: .originalContent)
        detectedLanguage = try container.decodeIfPresent(String.self, forKey: .detectedLanguage)
        isTranslated = try container.decodeIfPresent(Bool.self, forKey: .isTranslated) ?? false
        contentSource = try container.decodeIfPresent(String.self, forKey: .contentSource)
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
        try container.encodeIfPresent(linkPreviewType, forKey: .linkPreviewType)
        try container.encodeIfPresent(verseReference, forKey: .verseReference)
        try container.encodeIfPresent(verseText, forKey: .verseText)
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
        try container.encodeIfPresent(taggedUserIds, forKey: .taggedUserIds)
        try container.encodeIfPresent(tagStatusByUid, forKey: .tagStatusByUid)
        try container.encodeIfPresent(originalContent, forKey: .originalContent)
        try container.encodeIfPresent(detectedLanguage, forKey: .detectedLanguage)
        try container.encode(isTranslated, forKey: .isTranslated)
        try container.encodeIfPresent(contentSource, forKey: .contentSource)
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
        linkPreviewType: String? = nil,
        verseReference: String? = nil,
        verseText: String? = nil,
        createdAt: Date = Date(),
        amenCount: Int = 0,
        lightbulbCount: Int = 0,
        commentCount: Int = 0,
        repostCount: Int = 0,
        isRepost: Bool = false,
        originalAuthorName: String? = nil,
        originalAuthorId: String? = nil,
        churchNoteId: String? = nil,
        contentSource: String? = nil
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
        self.linkPreviewType = linkPreviewType
        self.verseReference = verseReference
        self.verseText = verseText
        self.createdAt = createdAt
        self.amenCount = amenCount
        self.lightbulbCount = lightbulbCount
        self.commentCount = commentCount
        self.repostCount = repostCount
        self.isRepost = isRepost
        self.originalAuthorName = originalAuthorName
        self.originalAuthorId = originalAuthorId
        self.churchNoteId = churchNoteId
        self.contentSource = contentSource
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
    private var profileRefreshTask: Task<Void, Never>? // Batch profile refresh loop — must be cancelled on cleanup
    
    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Setup real-time sync with FirebasePostService using Combine.
        // Posts flow in via the Combine sink when FirebasePostService's listener delivers data
        // (started by AMENAPPApp.onAppear → FirebasePostService.startListening).
        // Do NOT call fetchAllPosts() here — that causes a duplicate Firestore round-trip
        // on startup, racing with preloadCacheSync() and the real-time listener.
        setupFirebaseSync()
        
        Task {
            // Start listening for profile picture updates (batch timer, not per-post listener)
            await startListeningForProfileUpdates()
        }
    }

    // ✅ Setup real-time sync with FirebasePostService using Combine publishers
    private func setupFirebaseSync() {
        // PERFORMANCE: Threads-style instant loading
        // - NO debounce on initial load (would delay by 50ms)
        // - Use removeDuplicates() instead to prevent redundant updates
        // - Debounce only after initial load for rapid server updates
        
        // Listen to prayer posts changes
        firebasePostService.$prayerPosts
            .removeDuplicates { $0.map { $0.firestoreId } == $1.map { $0.firestoreId } }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newPosts in
                guard let self = self else { return }
                // Keep only optimistic posts (firebaseId == nil) that have NOT been confirmed
                // by the server yet. Use nil-check directly — never use "" as a sentinel.
                let serverIds = Set(newPosts.compactMap { $0.firebaseId })
                let uniqueOptimistic = self.prayerPosts.filter { $0.firebaseId == nil }
                    .filter { post in
                        // Belt-and-suspenders: also skip any optimistic post whose UUID
                        // somehow matches a server ID string (should never happen).
                        !serverIds.contains(post.id.uuidString)
                    }
                self.prayerPosts = uniqueOptimistic + newPosts
                #if DEBUG
                dlog("🔄 Prayer posts updated: \(newPosts.count) posts")
                #endif
            }
            .store(in: &cancellables)

        // Listen to testimonies posts changes
        firebasePostService.$testimoniesPosts
            .removeDuplicates { $0.map { $0.firestoreId } == $1.map { $0.firestoreId } }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newPosts in
                guard let self = self else { return }
                let serverIds = Set(newPosts.compactMap { $0.firebaseId })
                let uniqueOptimistic = self.testimoniesPosts.filter { $0.firebaseId == nil }
                    .filter { !serverIds.contains($0.id.uuidString) }
                self.testimoniesPosts = uniqueOptimistic + newPosts
            }
            .store(in: &cancellables)

        // Listen to open table posts changes
        firebasePostService.$openTablePosts
            .removeDuplicates { $0.map { $0.firestoreId } == $1.map { $0.firestoreId } }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newPosts in
                guard let self = self else { return }
                // Preserve any optimistic (not-yet-confirmed) posts at the top that
                // are not yet in the server snapshot (firebaseId == nil means temp UUID post)
                let serverIds = Set(newPosts.compactMap { $0.firebaseId })
                let uniqueOptimistic = self.openTablePosts.filter { $0.firebaseId == nil }
                    .filter { !serverIds.contains($0.id.uuidString) }
                self.openTablePosts = uniqueOptimistic + newPosts
            }
            .store(in: &cancellables)

        // Listen to all posts changes
        firebasePostService.$posts
            .removeDuplicates { $0.map { $0.firestoreId } == $1.map { $0.firestoreId } }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newPosts in
                guard let self = self else { return }
                self.allPosts = newPosts
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Load from Firebase
    
    func loadPostsFromFirebase() async {
        // Skip loading if user is not authenticated
        guard Auth.auth().currentUser != nil else { return }

        do {
            try await firebasePostService.fetchAllPosts()
            
            // ✅ Don't start listener here - let individual views handle it with their category filters
            // This prevents listener conflicts
            
            // Update local arrays from FirebasePostService
            await MainActor.run {
                self.allPosts = firebasePostService.posts
                self.openTablePosts = firebasePostService.openTablePosts
                self.testimoniesPosts = firebasePostService.testimoniesPosts
                self.prayerPosts = firebasePostService.prayerPosts
                
                dlog("✅ Posts loaded: \(allPosts.count) total, \(prayerPosts.count) prayer, \(testimoniesPosts.count) testimonies, \(openTablePosts.count) openTable")
            }
        } catch {
            dlog("❌ Failed to load posts from Firebase: \(error)")
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
                
                // Real-time Combine publisher in setupFirebaseSync() will automatically
                // propagate the new post — no manual refresh needed.
                
                // Post notification for UI update
                NotificationCenter.default.post(
                    name: .newPostCreated,
                    object: nil,
                    userInfo: ["category": category.rawValue]
                )
                
            } catch {
                dlog("❌ Failed to create post: \(error)")
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
            dlog("📥 Fetching filtered posts: category=\(category.rawValue), filter=\(filter), topicTag=\(topicTag ?? "none")")
            
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
            
            dlog("✅ Updated \(category.rawValue) posts with \(finalPosts.count) items (personalized: \(filter == "For You"))")
            
        } catch {
            dlog("❌ Failed to fetch filtered posts: \(error)")
            self.error = error.localizedDescription
        }
    }
    
    // MARK: - Edit Post
    
    func editPost(postId: UUID, newContent: String) {
        Task { @MainActor in
            do {
                // Use firestoreId (Firestore document ID) — not the local UUID
                guard let post = allPosts.first(where: { $0.id == postId }) ?? openTablePosts.first(where: { $0.id == postId }) ?? testimoniesPosts.first(where: { $0.id == postId }) ?? prayerPosts.first(where: { $0.id == postId }),
                      let firestoreId = post.firebaseId else {
                    dlog("❌ editPost: post not found or missing firestoreId for \(postId)")
                    return
                }
                try await firebasePostService.editPost(postId: firestoreId, newContent: newContent)
                
                dlog("✅ Post edited successfully")
                
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
                dlog("❌ Failed to edit post: \(error)")
                self.error = error.localizedDescription
            }
        }
    }
    
    // MARK: - Delete Post
    
    func deletePost(postId: UUID) {
        Task {
            do {
                // Use firestoreId (Firestore document ID) — not the local UUID
                guard let post = allPosts.first(where: { $0.id == postId }) ?? openTablePosts.first(where: { $0.id == postId }) ?? testimoniesPosts.first(where: { $0.id == postId }) ?? prayerPosts.first(where: { $0.id == postId }),
                      let firestoreId = post.firebaseId else {
                    dlog("❌ deletePost: post not found or missing firestoreId for \(postId)")
                    return
                }
                try await firebasePostService.deletePost(postId: firestoreId)
                
                dlog("✅ Post deleted successfully")
                
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
                dlog("❌ Failed to delete post: \(error)")
                self.error = error.localizedDescription
            }
        }
    }
    
    // MARK: - Repost to Profile
    
    func repostToProfile(originalPost: Post, userInitials: String = "JD", userName: String = "John Disciple") {
        dlog("🔵 [POSTSMANAGER] repostToProfile() called for post: \(originalPost.firestoreId)")
        Task {
            do {
                dlog("🔵 [POSTSMANAGER] Calling RealtimeRepostsService.repostPost()...")
                // Use RealtimeRepostsService for reposts
                try await RealtimeRepostsService.shared.repostPost(postId: originalPost.id, originalPost: originalPost)

                dlog("✅ Post reposted successfully via RealtimeRepostsService")

                // Notification is already sent by RealtimeRepostsService
                // No need to send duplicate notification here

            } catch {
                dlog("❌ Failed to repost: \(error)")
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

                dlog("✅ Repost removed successfully via RealtimeRepostsService")

                // Remove from local cache
                allPosts.removeAll { $0.id == postId && $0.isRepost }
                openTablePosts.removeAll { $0.id == postId && $0.isRepost }
                testimoniesPosts.removeAll { $0.id == postId && $0.isRepost }
                prayerPosts.removeAll { $0.id == postId && $0.isRepost }

            } catch {
                dlog("❌ Failed to remove repost: \(error)")
                self.error = error.localizedDescription
            }
        }
    }
    
    // MARK: - Update Post Interactions
    
    func updateAmenCount(postId: UUID, increment: Bool) {
        Task { @MainActor in
            do {
                try await firebasePostService.toggleAmen(postId: postId.uuidString)
                
                // Update local cache
                updatePostInAllArrays(postId: postId) { post in
                    var updatedPost = post
                    updatedPost.amenCount += increment ? 1 : -1
                    return updatedPost
                }
            } catch {
                dlog("❌ Failed to update amen count: \(error)")
            }
        }
    }
    
    func updateLightbulbCount(postId: UUID, increment: Bool) {
        Task { @MainActor in
            do {
                try await firebasePostService.toggleLightbulb(postId: postId.uuidString)
                
                // Update local cache
                updatePostInAllArrays(postId: postId) { post in
                    var updatedPost = post
                    updatedPost.lightbulbCount += increment ? 1 : -1
                    return updatedPost
                }
            } catch {
                dlog("❌ Failed to update lightbulb count: \(error)")
            }
        }
    }
    
    func updateCommentCount(postId: UUID, increment: Bool) {
        Task { @MainActor in
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
                dlog("❌ Failed to update comment count: \(error)")
            }
        }
    }
    
    @MainActor
    func updateRepostCount(postId: UUID, increment: Bool) {
        // This is handled automatically by repostToProfile
        updatePostInAllArrays(postId: postId) { post in
            var updatedPost = post
            updatedPost.repostCount += increment ? 1 : -1
            return updatedPost
        }
    }
    
    // MARK: - Helper Methods
    
    @MainActor
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
        dlog("👂 [PERF FIX] Using batch profile updates instead of individual listeners")
        
        // Start a timer to refresh profile images every 5 minutes.
        // Stored so it can be cancelled when the manager is done.
        profileRefreshTask?.cancel()
        profileRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000_000) // 5 minutes
                guard !Task.isCancelled else { break }
                await refreshProfileImages()
            }
        }
        
        dlog("✅ Batch profile update timer started (5 min intervals)")
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
        
        dlog("🔄 Refreshing profile images for \(authorIds.count) authors...")
        
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
                dlog("⚠️ Failed to batch fetch profiles: \(error)")
            }
        }
    }
    
    // ✅ P0-1 FIX: Add cleanup method to remove all profile listeners
    /// Stop all profile picture listeners to prevent memory leaks
    /// Call this from view onDisappear blocks
    @MainActor
    func stopListeningForProfileUpdates() {
        dlog("🛑 Stopping \(profileUpdateListeners.count) profile picture listeners...")
        
        // Remove all Firestore listeners
        for (_, listener) in profileUpdateListeners {
            if let firestoreListener = listener as? ListenerRegistration {
                firestoreListener.remove()
            }
        }
        
        // Clear the dictionary
        profileUpdateListeners.removeAll()
        
        // Cancel the background refresh loop
        profileRefreshTask?.cancel()
        profileRefreshTask = nil
        
        dlog("✅ All profile listeners stopped")
    }
    
    /// Update all posts from a specific user with their new profile image
    private func updatePostsForUser(userId: String, newProfileImageURL: String) {
        // P2 PERF FIX: Single pass over allPosts, then derive category arrays —
        // replaces the previous 4× separate .map that iterated every array independently.
        var postsUpdated = 0

        allPosts = allPosts.map { post in
            guard post.authorId == userId else { return post }
            postsUpdated += 1
            var updated = post
            updated.authorProfileImageURL = newProfileImageURL
            return updated
        }

        // Derive category arrays from the already-updated allPosts (no extra iteration)
        openTablePosts  = allPosts.filter { $0.category == .openTable }
        testimoniesPosts = allPosts.filter { $0.category == .testimonies }
        prayerPosts     = allPosts.filter { $0.category == .prayer }

        #if DEBUG
        if postsUpdated > 0 {
            dlog("✅ Updated \(postsUpdated) posts with new profile picture for \(userId)")
        }
        #endif
    }
    
    /// Sync all posts with fresh user profile images from Firestore
    /// This ensures profile pictures are always up-to-date when the app opens
    func syncAllPostsWithUserProfiles() async {
        dlog("🔄 Syncing all posts with user profile images...")
        
        let db = Firestore.firestore()
        
        // Collect all unique author IDs from all posts
        var authorIds = Set<String>()
        
        await MainActor.run {
            for post in allPosts {
                authorIds.insert(post.authorId)
            }
        }
        
        guard !authorIds.isEmpty else {
            dlog("ℹ️ No posts to sync")
            return
        }
        
        dlog("📊 Found \(authorIds.count) unique authors to sync")
        
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
                dlog("⚠️ Failed to fetch profile for user \(authorId): \(error)")
            }
        }
        
        dlog("✅ Fetched \(profileImageMap.count) profile images")
        
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
            
            dlog("✅ Profile picture sync complete! Updated \(updatedAllPosts.count) posts")
        }
    }
}


