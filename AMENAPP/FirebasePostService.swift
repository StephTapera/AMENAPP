//
//  FirebasePostService.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//
//  Firestore implementation for posts functionality
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

// MARK: - Firestore Post Model

struct FirestorePost: Codable, Identifiable {
    @DocumentID var id: String?
    var authorId: String
    var authorName: String
    var authorUsername: String?
    var authorInitials: String
    var authorProfileImageURL: String?
    var content: String
    var category: String  // "openTable", "testimonies", "prayer"
    var topicTag: String?
    var visibility: String  // "everyone", "followers", "community"
    var allowComments: Bool
    var imageURLs: [String]?
    var linkURL: String?
    var createdAt: Date
    var updatedAt: Date?
    
    // Interaction counts
    var amenCount: Int
    var lightbulbCount: Int
    var commentCount: Int
    var repostCount: Int
    
    // Repost tracking
    var isRepost: Bool
    var originalPostId: String?
    var originalAuthorId: String?
    var originalAuthorName: String?
    
    // Lists of users who interacted
    var amenUserIds: [String]
    var lightbulbUserIds: [String]
    
    // Computed property for "time ago" display
    var timeAgo: String {
        FirestorePost.formatTimeAgo(from: createdAt)
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case authorId
        case authorName
        case authorUsername
        case authorInitials
        case authorProfileImageURL
        case content
        case category
        case topicTag
        case visibility
        case allowComments
        case imageURLs
        case linkURL
        case createdAt
        case updatedAt
        case amenCount
        case lightbulbCount
        case commentCount
        case repostCount
        case isRepost
        case originalPostId
        case originalAuthorId
        case originalAuthorName
        case amenUserIds
        case lightbulbUserIds
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decodeIfPresent(String.self, forKey: .id)
        authorId = try container.decode(String.self, forKey: .authorId)
        authorName = try container.decode(String.self, forKey: .authorName)
        authorUsername = try container.decodeIfPresent(String.self, forKey: .authorUsername)
        authorInitials = try container.decode(String.self, forKey: .authorInitials)
        authorProfileImageURL = try container.decodeIfPresent(String.self, forKey: .authorProfileImageURL)
        content = try container.decode(String.self, forKey: .content)
        category = try container.decode(String.self, forKey: .category)
        topicTag = try container.decodeIfPresent(String.self, forKey: .topicTag)
        visibility = try container.decode(String.self, forKey: .visibility)
        allowComments = try container.decode(Bool.self, forKey: .allowComments)
        imageURLs = try container.decodeIfPresent([String].self, forKey: .imageURLs)
        linkURL = try container.decodeIfPresent(String.self, forKey: .linkURL)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        amenCount = try container.decodeIfPresent(Int.self, forKey: .amenCount) ?? 0
        lightbulbCount = try container.decodeIfPresent(Int.self, forKey: .lightbulbCount) ?? 0
        commentCount = try container.decodeIfPresent(Int.self, forKey: .commentCount) ?? 0
        repostCount = try container.decodeIfPresent(Int.self, forKey: .repostCount) ?? 0
        isRepost = try container.decodeIfPresent(Bool.self, forKey: .isRepost) ?? false
        originalPostId = try container.decodeIfPresent(String.self, forKey: .originalPostId)
        originalAuthorId = try container.decodeIfPresent(String.self, forKey: .originalAuthorId)
        originalAuthorName = try container.decodeIfPresent(String.self, forKey: .originalAuthorName)
        amenUserIds = try container.decodeIfPresent([String].self, forKey: .amenUserIds) ?? []
        lightbulbUserIds = try container.decodeIfPresent([String].self, forKey: .lightbulbUserIds) ?? []
    }
    
    init(
        id: String? = nil,
        authorId: String,
        authorName: String,
        authorUsername: String? = nil,
        authorInitials: String,
        authorProfileImageURL: String? = nil,
        content: String,
        category: String,
        topicTag: String? = nil,
        visibility: String = "everyone",
        allowComments: Bool = true,
        imageURLs: [String]? = nil,
        linkURL: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        amenCount: Int = 0,
        lightbulbCount: Int = 0,
        commentCount: Int = 0,
        repostCount: Int = 0,
        isRepost: Bool = false,
        originalPostId: String? = nil,
        originalAuthorId: String? = nil,
        originalAuthorName: String? = nil,
        amenUserIds: [String] = [],
        lightbulbUserIds: [String] = []
    ) {
        self.id = id
        self.authorId = authorId
        self.authorName = authorName
        self.authorUsername = authorUsername
        self.authorInitials = authorInitials
        self.authorProfileImageURL = authorProfileImageURL
        self.content = content
        self.category = category
        self.topicTag = topicTag
        self.visibility = visibility
        self.allowComments = allowComments
        self.imageURLs = imageURLs
        self.linkURL = linkURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.amenCount = amenCount
        self.lightbulbCount = lightbulbCount
        self.commentCount = commentCount
        self.repostCount = repostCount
        self.isRepost = isRepost
        self.originalPostId = originalPostId
        self.originalAuthorId = originalAuthorId
        self.originalAuthorName = originalAuthorName
        self.amenUserIds = amenUserIds
        self.lightbulbUserIds = lightbulbUserIds
    }
    
    // Convert to local Post model
    func toPost() -> Post {
        let postCategory: Post.PostCategory = {
            switch category.lowercased() {
            case "opentable", "#opentable":
                return .openTable
            case "testimonies":
                return .testimonies
            case "prayer":
                return .prayer
            default:
                print("⚠️ Unknown category '\(category)', defaulting to openTable")
                return .openTable
            }
        }()
        
        let postVisibility: Post.PostVisibility = {
            switch visibility {
            case "everyone": return .everyone
            case "followers": return .followers
            case "community": return .community
            default: return .everyone
            }
        }()
        
        let timeAgo = FirestorePost.formatTimeAgo(from: createdAt)
        
        return Post(
            id: UUID(uuidString: id ?? UUID().uuidString) ?? UUID(),
            authorId: authorId,
            authorName: authorName,
            authorUsername: authorUsername,
            authorInitials: authorInitials,
            timeAgo: timeAgo,
            content: content,
            category: postCategory,
            topicTag: topicTag,
            visibility: postVisibility,
            allowComments: allowComments,
            imageURLs: imageURLs,
            linkURL: linkURL,
            createdAt: createdAt,
            amenCount: amenCount,
            lightbulbCount: lightbulbCount,
            commentCount: commentCount,
            repostCount: repostCount,
            isRepost: isRepost,
            originalAuthorName: originalAuthorName,
            originalAuthorId: originalAuthorId
        )
    }
    
    // Helper function to format time ago
    static func formatTimeAgo(from date: Date) -> String {
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.minute, .hour, .day, .weekOfYear, .month, .year], from: date, to: now)
        
        if let year = components.year, year > 0 {
            return "\(year)y"
        }
        if let month = components.month, month > 0 {
            return "\(month)mo"
        }
        if let week = components.weekOfYear, week > 0 {
            return "\(week)w"
        }
        if let day = components.day, day > 0 {
            return "\(day)d"
        }
        if let hour = components.hour, hour > 0 {
            return "\(hour)h"
        }
        if let minute = components.minute, minute > 0 {
            return "\(minute)m"
        }
        return "now"
    }
}

// MARK: - Firebase Post Service

@MainActor
class FirebasePostService: ObservableObject {
    static let shared = FirebasePostService()
    
    @Published var posts: [Post] = []
    @Published var openTablePosts: [Post] = []
    @Published var testimoniesPosts: [Post] = []
    @Published var prayerPosts: [Post] = []
    @Published var isLoading = false
    @Published var error: String?
    
    internal let firebaseManager = FirebaseManager.shared
    internal let db = Firestore.firestore()
    private let realtimeService = RealtimeDatabaseService.shared
    private var listeners: [ListenerRegistration] = []
    private var realtimePostsHandle: UInt?
    
    private init() {
        setupRealtimeFeed()
    }
    
    // MARK: - Realtime Feed Setup
    
    /// Setup real-time feed updates
    private func setupRealtimeFeed() {
        realtimeService.observeRecentPosts(limit: 100) { [weak self] postIds in
            guard let self = self else { return }
            
            Task { @MainActor in
                // Fetch full post data from Firestore for new posts
                await self.fetchPostsByIds(postIds)
            }
        }
    }
    
    /// Fetch posts by their IDs from Firestore
    private func fetchPostsByIds(_ postIds: [String]) async {
        guard !postIds.isEmpty else { return }
        
        do {
            // Firestore 'in' query limited to 10 items, so batch them
            let batches = postIds.chunked(into: 10)
            var allPosts: [Post] = []
            
            for batch in batches {
                let snapshot = try await db.collection(FirebaseManager.CollectionPath.posts)
                    .whereField(FieldPath.documentID(), in: batch)
                    .getDocuments()
                
                let batchPosts = try snapshot.documents.compactMap { doc in
                    try doc.data(as: FirestorePost.self)
                }.map { $0.toPost() }
                
                allPosts.append(contentsOf: batchPosts)
            }
            
            // Update posts maintaining order from realtime feed
            self.posts = postIds.compactMap { postId in
                allPosts.first { $0.id.uuidString == postId }
            }
            
            updateCategoryArrays()
            
        } catch {
            print("❌ Failed to fetch posts by IDs: \(error)")
        }
    }
    
    // MARK: - Create Post
    
    /// Create a new post in Firestore (OPTIMIZED FOR PERFORMANCE)
    func createPost(
        content: String,
        category: Post.PostCategory,
        topicTag: String? = nil,
        visibility: Post.PostVisibility = .everyone,
        allowComments: Bool = true,
        imageURLs: [String]? = nil,
        linkURL: String? = nil
    ) async throws {
        print("📝 Creating new post in Firestore (OPTIMIZED)...")
        
        guard let userId = firebaseManager.currentUser?.uid else {
            print("❌ No authenticated user")
            throw FirebaseError.unauthorized
        }
        
        // 🚀 OPTIMIZATION 1: Use cached user data instead of fetching
        let displayName: String
        let username: String
        let initials: String
        let profileImageURL: String?
        
        // Try to get from UserDefaults cache first (set during login/profile load)
        if let cachedName = UserDefaults.standard.string(forKey: "currentUserDisplayName"),
           let cachedUsername = UserDefaults.standard.string(forKey: "currentUserUsername"),
           let cachedInitials = UserDefaults.standard.string(forKey: "currentUserInitials") {
            displayName = cachedName
            username = cachedUsername
            initials = cachedInitials
            profileImageURL = UserDefaults.standard.string(forKey: "currentUserProfileImageURL")
            print("✅ Using cached user data (FAST)")
        } else {
            // Fallback: Fetch from Firestore (only if cache miss)
            print("⚠️ Cache miss - fetching user data from Firestore")
            let userDoc = try await db.collection(FirebaseManager.CollectionPath.users)
                .document(userId)
                .getDocument()
            
            guard let userData = userDoc.data() else {
                print("❌ User data not found")
                throw FirebaseError.documentNotFound
            }
            
            displayName = userData["displayName"] as? String ?? "Unknown User"
            username = userData["username"] as? String ?? "unknown"
            initials = userData["initials"] as? String ?? "??"
            profileImageURL = userData["profileImageURL"] as? String
            
            // Cache for next time
            UserDefaults.standard.set(displayName, forKey: "currentUserDisplayName")
            UserDefaults.standard.set(username, forKey: "currentUserUsername")
            UserDefaults.standard.set(initials, forKey: "currentUserInitials")
            if let imageURL = profileImageURL {
                UserDefaults.standard.set(imageURL, forKey: "currentUserProfileImageURL")
            }
        }
        
        let categoryString: String = {
            switch category {
            case .openTable: return "openTable"
            case .testimonies: return "testimonies"
            case .prayer: return "prayer"
            }
        }()
        
        let visibilityString: String = {
            switch visibility {
            case .everyone: return "everyone"
            case .followers: return "followers"
            case .community: return "community"
            }
        }()
        
        let newPost = FirestorePost(
            authorId: userId,
            authorName: displayName,
            authorUsername: username,
            authorInitials: initials,
            authorProfileImageURL: profileImageURL,
            content: content,
            category: categoryString,
            topicTag: topicTag,
            visibility: visibilityString,
            allowComments: allowComments,
            imageURLs: imageURLs,
            linkURL: linkURL
        )
        
        // 🚀 OPTIMIZATION 2: Generate local ID immediately for optimistic update
        let localPostId = UUID().uuidString
        let optimisticPost = newPost.toPost()
        
        // 🚀 OPTIMIZATION 3: Immediately post notification with optimistic post object
        await MainActor.run {
            NotificationCenter.default.post(
                name: .newPostCreated,
                object: nil,
                userInfo: [
                    "post": optimisticPost,
                    "category": categoryString,
                    "isOptimistic": true
                ]
            )
        }
        
        print("📤 Saving post to Firestore (async)...")
        
        // 🚀 OPTIMIZATION 4: Use Task detachment for non-blocking operations
        Task.detached(priority: .userInitiated) {
            do {
                let docRef = try await self.db.collection(FirebaseManager.CollectionPath.posts)
                    .addDocument(from: newPost)
                
                print("✅ Post created successfully with ID: \(docRef.documentID)")
                
                // Publish to Realtime Database for instant feed updates (background)
                try? await self.realtimeService.publishRealtimePost(
                    postId: docRef.documentID,
                    authorId: userId,
                    category: categoryString,
                    timestamp: Date()
                )
                
                print("✅ Post published to Realtime Database")
                
                // Update user's post count (background - no await)
                Task {
                    try? await self.db.collection(FirebaseManager.CollectionPath.users)
                        .document(userId)
                        .updateData([
                            "postsCount": FieldValue.increment(Int64(1)),
                            "updatedAt": Date()
                        ])
                }
                
                // Create mention notifications (background - no await)
                Task {
                    try? await self.createMentionNotifications(
                        postId: docRef.documentID,
                        postContent: content,
                        fromUserId: userId
                    )
                }
                
            } catch {
                print("❌ Failed to create post: \(error)")
                
                // Post failure notification
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: Notification.Name("postCreationFailed"),
                        object: nil,
                        userInfo: ["error": error]
                    )
                }
                
                throw error
            }
        }
        
        // Return immediately after starting async operations
        print("✅ Post creation initiated (returning immediately)")
    }
    
    // MARK: - Fetch Posts
    
    /// Fetch all posts (for main feed)
    func fetchAllPosts(limit: Int = 50) async throws {
        print("📥 Fetching all posts from Firestore...")
        isLoading = true
        defer { isLoading = false }
        
        do {
            let snapshot = try await db.collection(FirebaseManager.CollectionPath.posts)
                .order(by: "createdAt", descending: true)
                .limit(to: limit)
                .getDocuments()
            
            let firestorePosts = try snapshot.documents.compactMap { doc in
                try doc.data(as: FirestorePost.self)
            }
            
            self.posts = firestorePosts.map { $0.toPost() }
            print("✅ Fetched \(self.posts.count) posts")
            
            // Also update category-specific arrays
            updateCategoryArrays()
            
        } catch {
            print("❌ Failed to fetch posts: \(error)")
            self.error = error.localizedDescription
            throw error
        }
    }
    
    /// Fetch posts by category with filtering options
    func fetchPosts(
        for category: Post.PostCategory,
        filter: String = "all",
        topicTag: String? = nil,
        limit: Int = 50
    ) async throws -> [Post] {
        print("📥 Fetching \(category.rawValue) posts from Firestore (filter: \(filter))...")
        
        let categoryString: String = {
            switch category {
            case .openTable: return "openTable"
            case .testimonies: return "testimonies"
            case .prayer: return "prayer"
            }
        }()
        
        do {
            var query = db.collection(FirebaseManager.CollectionPath.posts)
                .whereField("category", isEqualTo: categoryString)
            
            // Apply topic tag filter if specified
            if let topicTag = topicTag, !topicTag.isEmpty {
                query = query.whereField("topicTag", isEqualTo: topicTag)
            }
            
            // Apply sorting based on filter
            switch filter.lowercased() {
            case "recent", "all":
                query = query.order(by: "createdAt", descending: true)
            case "popular":
                // For popular, we'll fetch and sort client-side since Firestore doesn't support
                // ordering by multiple calculated fields (amenCount + commentCount)
                query = query.order(by: "createdAt", descending: true)
            case "following":
                // For following, we need to filter by followed users
                // This requires getting followed user IDs first
                if let userId = firebaseManager.currentUser?.uid {
                    // Fetch following list
                    let userDoc = try await db.collection(FirebaseManager.CollectionPath.users)
                        .document(userId)
                        .getDocument()
                    
                    if let followingIds = userDoc.data()?["followingIds"] as? [String], !followingIds.isEmpty {
                        query = query.whereField("authorId", in: followingIds)
                            .order(by: "createdAt", descending: true)
                    } else {
                        // No following, return empty
                        print("✅ User not following anyone, returning empty array")
                        return []
                    }
                } else {
                    // Not authenticated, return empty
                    print("✅ User not authenticated, returning empty array")
                    return []
                }
            default:
                query = query.order(by: "createdAt", descending: true)
            }
            
            query = query.limit(to: limit)
            
            let snapshot = try await query.getDocuments()
            
            let firestorePosts = try snapshot.documents.compactMap { doc in
                try doc.data(as: FirestorePost.self)
            }
            
            var posts = firestorePosts.map { $0.toPost() }
            
            // Client-side sorting for "popular" filter
            if filter.lowercased() == "popular" {
                posts.sort { ($0.amenCount + $0.commentCount) > ($1.amenCount + $1.commentCount) }
            }
            
            print("✅ Fetched \(posts.count) \(category.rawValue) posts")
            
            return posts
            
        } catch {
            print("❌ Failed to fetch category posts: \(error)")
            throw error
        }
    }
    
    /// Fetch posts by specific user
    func fetchUserPosts(userId: String, limit: Int = 50) async throws -> [Post] {
        print("📥 Fetching posts for user: \(userId)")
        
        let snapshot = try await db.collection(FirebaseManager.CollectionPath.posts)
            .whereField("authorId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        
        let firestorePosts = try snapshot.documents.compactMap { doc in
            try doc.data(as: FirestorePost.self)
        }
        
        let posts = firestorePosts.map { $0.toPost() }
        print("✅ Fetched \(posts.count) user posts")
        
        return posts
    }
    
    /// Fetch a single post by its ID
    func fetchPostById(postId: String) async throws -> Post? {
        print("📥 Fetching post by ID: \(postId)")
        
        let document = try await db.collection(FirebaseManager.CollectionPath.posts)
            .document(postId)
            .getDocument()
        
        guard document.exists else {
            print("⚠️ Post not found: \(postId)")
            return nil
        }
        
        let firestorePost = try document.data(as: FirestorePost.self)
        let post = firestorePost.toPost()
        
        print("✅ Fetched post: \(postId)")
        return post
    }
    
    // MARK: - Real-time Listeners
    
    /// Start listening to posts in real-time
    func startListening(category: Post.PostCategory? = nil) {
        print("🔊 Starting real-time listener for posts...")
        
        // Check if user is authenticated
        guard firebaseManager.isAuthenticated else {
            print("⚠️ User not authenticated - skipping Firestore listener")
            self.error = "Please sign in to view posts"
            return
        }
        
        print("✅ User authenticated, setting up listener...")
        
        let query: Query
        
        if let category = category {
            let categoryString: String = {
                switch category {
                case .openTable: return "openTable"
                case .testimonies: return "testimonies"
                case .prayer: return "prayer"
                }
            }()
            
            query = db.collection(FirebaseManager.CollectionPath.posts)
                .whereField("category", isEqualTo: categoryString)
                .order(by: "createdAt", descending: true)
                .limit(to: 50)
        } else {
            query = db.collection(FirebaseManager.CollectionPath.posts)
                .order(by: "createdAt", descending: true)
                .limit(to: 100)
        }
        
        let listener = query.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            
            if let error = error {
                let nsError = error as NSError
                print("❌ Firestore listener error: \(error.localizedDescription)")
                print("   Error code: \(nsError.code), domain: \(nsError.domain)")
                
                // Check for specific error codes
                if nsError.code == 7 { // Permission denied
                    self.error = "Missing or insufficient permissions. Please check Firestore security rules."
                    print("⚠️ PERMISSION DENIED: Update your Firestore security rules to allow read access to the posts collection")
                } else {
                    self.error = error.localizedDescription
                }
                return
            }
            
            guard let snapshot = snapshot else {
                print("❌ No snapshot data")
                return
            }
            
            let firestorePosts = snapshot.documents.compactMap { doc -> FirestorePost? in
                try? doc.data(as: FirestorePost.self)
            }
            
            self.posts = firestorePosts.map { $0.toPost() }
            self.updateCategoryArrays()
            
            print("✅ Real-time update: \(self.posts.count) posts")
        }
        
        listeners.append(listener)
    }
    
    /// Stop all listeners
    func stopListening() {
        print("🔇 Stopping all listeners...")
        listeners.forEach { $0.remove() }
        listeners.removeAll()
    }
    
    // MARK: - Update Post
    
    /// Edit post content
    func editPost(postId: String, newContent: String) async throws {
        print("✏️ Editing post: \(postId)")
        
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        // Verify user owns the post
        let postDoc = try await db.collection(FirebaseManager.CollectionPath.posts)
            .document(postId)
            .getDocument()
        
        guard let postData = postDoc.data(),
              let authorId = postData["authorId"] as? String,
              authorId == userId else {
            print("❌ User does not own this post")
            throw FirebaseError.unauthorized
        }
        
        try await db.collection(FirebaseManager.CollectionPath.posts)
            .document(postId)
            .updateData([
                "content": newContent,
                "updatedAt": Date()
            ])
        
        print("✅ Post updated successfully")
        
        // Update local cache
        if let index = posts.firstIndex(where: { $0.id.uuidString == postId }) {
            var updatedPost = posts[index]
            updatedPost.content = newContent
            posts[index] = updatedPost
            updateCategoryArrays()
        }
    }
    
    /// Delete post
    func deletePost(postId: String) async throws {
        print("🗑️ Deleting post: \(postId)")
        
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        // Verify user owns the post
        let postDoc = try await db.collection(FirebaseManager.CollectionPath.posts)
            .document(postId)
            .getDocument()
        
        guard let postData = postDoc.data(),
              let authorId = postData["authorId"] as? String,
              authorId == userId else {
            print("❌ User does not own this post")
            throw FirebaseError.unauthorized
        }
        
        try await db.collection(FirebaseManager.CollectionPath.posts)
            .document(postId)
            .delete()
        
        print("✅ Post deleted successfully")
        
        // Update user's post count
        try await db.collection(FirebaseManager.CollectionPath.users)
            .document(userId)
            .updateData([
                "postsCount": FieldValue.increment(Int64(-1)),
                "updatedAt": Date()
            ])
        
        // Update local cache
        posts.removeAll { $0.id.uuidString == postId }
        updateCategoryArrays()
    }
    
    // MARK: - Interactions
    
    /// Toggle "Amen" on a post
    func toggleAmen(postId: String) async throws {
        print("🙏 Toggling Amen on post: \(postId)")
        
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        let postRef = db.collection(FirebaseManager.CollectionPath.posts).document(postId)
        let postDoc = try await postRef.getDocument()
        
        guard let data = postDoc.data(),
              var amenUserIds = data["amenUserIds"] as? [String] else {
            throw FirebaseError.invalidData
        }
        
        let hasAmened = amenUserIds.contains(userId)
        let postAuthorId = data["authorId"] as? String ?? ""
        
        if hasAmened {
            // Remove amen
            amenUserIds.removeAll { $0 == userId }
            try await postRef.updateData([
                "amenCount": FieldValue.increment(Int64(-1)),
                "amenUserIds": amenUserIds,
                "updatedAt": Date()
            ])
            print("✅ Amen removed")
        } else {
            // Add amen
            amenUserIds.append(userId)
            try await postRef.updateData([
                "amenCount": FieldValue.increment(Int64(1)),
                "amenUserIds": amenUserIds,
                "updatedAt": Date()
            ])
            print("✅ Amen added")
            
            // ✅ Create notification for post author
            try? await createAmenNotification(
                postId: postId,
                postAuthorId: postAuthorId,
                postContent: data["content"] as? String ?? "",
                fromUserId: userId
            )
        }
        
        // Haptic feedback
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
    }
    
    /// Increment comment count and create notification
    func incrementCommentCount(
        postId: String,
        commentText: String? = nil
    ) async throws {
        print("💬 Incrementing comment count for post: \(postId)")
        
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        // Get post data for notification
        let postDoc = try await db.collection(FirebaseManager.CollectionPath.posts)
            .document(postId)
            .getDocument()
        
        guard let postData = postDoc.data() else {
            throw FirebaseError.documentNotFound
        }
        
        // Update comment count
        try await db.collection(FirebaseManager.CollectionPath.posts)
            .document(postId)
            .updateData([
                "commentCount": FieldValue.increment(Int64(1)),
                "updatedAt": Date()
            ])
        
        print("✅ Comment count incremented")
        
        // ✅ Create notification if we have comment text
        if let commentText = commentText {
            try? await createCommentNotification(
                postId: postId,
                postAuthorId: postData["authorId"] as? String ?? "",
                postContent: postData["content"] as? String ?? "",
                commentText: commentText,
                fromUserId: userId
            )
        }
    }
    
    /// Repost to user's profile
    func repostToProfile(originalPostId: String) async throws {
        print("🔄 Reposting post: \(originalPostId)")
        
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        // Fetch original post
        let originalPostDoc = try await db.collection(FirebaseManager.CollectionPath.posts)
            .document(originalPostId)
            .getDocument()
        
        guard let originalPost = try? originalPostDoc.data(as: FirestorePost.self) else {
            throw FirebaseError.documentNotFound
        }
        
        // Fetch current user data
        let userDoc = try await db.collection(FirebaseManager.CollectionPath.users)
            .document(userId)
            .getDocument()
        
        guard let userData = userDoc.data() else {
            throw FirebaseError.documentNotFound
        }
        
        let displayName = userData["displayName"] as? String ?? "Unknown User"
        let username = userData["username"] as? String ?? "unknown"
        let initials = userData["initials"] as? String ?? "??"
        let profileImageURL = userData["profileImageURL"] as? String
        
        // Create repost
        let repost = FirestorePost(
            authorId: userId,
            authorName: displayName,
            authorUsername: username,
            authorInitials: initials,
            authorProfileImageURL: profileImageURL,
            content: originalPost.content,
            category: originalPost.category,
            topicTag: originalPost.topicTag,
            visibility: "everyone",
            allowComments: true,
            isRepost: true,
            originalPostId: originalPostId,
            originalAuthorId: originalPost.authorId,
            originalAuthorName: originalPost.authorName
        )
        
        _ = try db.collection(FirebaseManager.CollectionPath.posts).addDocument(from: repost)
        
        // Increment repost count on original
        try await db.collection(FirebaseManager.CollectionPath.posts)
            .document(originalPostId)
            .updateData([
                "repostCount": FieldValue.increment(Int64(1)),
                "updatedAt": Date()
            ])
        
        // Update user's post count
        try await db.collection(FirebaseManager.CollectionPath.users)
            .document(userId)
            .updateData([
                "postsCount": FieldValue.increment(Int64(1)),
                "updatedAt": Date()
            ])
        
        print("✅ Post reposted successfully")
        
        // Haptic feedback
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
    }
    
    // MARK: - Helper Methods
    
    /// Check if current user has interacted with a post
    func hasUserAmened(postId: String) async -> Bool {
        guard let userId = firebaseManager.currentUser?.uid else { return false }
        
        do {
            let postDoc = try await db.collection(FirebaseManager.CollectionPath.posts)
                .document(postId)
                .getDocument()
            
            guard let amenUserIds = postDoc.data()?["amenUserIds"] as? [String] else {
                return false
            }
            
            return amenUserIds.contains(userId)
        } catch {
            print("❌ Error checking amen status: \(error)")
            return false
        }
    }
    
    func hasUserLitLightbulb(postId: String) async -> Bool {
        guard let userId = firebaseManager.currentUser?.uid else { return false }
        
        do {
            let postDoc = try await db.collection(FirebaseManager.CollectionPath.posts)
                .document(postId)
                .getDocument()
            
            guard let lightbulbUserIds = postDoc.data()?["lightbulbUserIds"] as? [String] else {
                return false
            }
            
            return lightbulbUserIds.contains(userId)
        } catch {
            print("❌ Error checking lightbulb status: \(error)")
            return false
        }
    }
    
    /// Toggle lightbulb (like) on a post - FULL FIREBASE IMPLEMENTATION
    func toggleLightbulb(postId: String) async throws {
        print("💡 Toggling lightbulb on post: \(postId)")
        
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        let postRef = db.collection(FirebaseManager.CollectionPath.posts).document(postId)
        let postDoc = try await postRef.getDocument()
        
        guard let data = postDoc.data(),
              var lightbulbUserIds = data["lightbulbUserIds"] as? [String] else {
            throw FirebaseError.invalidData
        }
        
        let hasLit = lightbulbUserIds.contains(userId)
        
        if hasLit {
            // Remove lightbulb
            lightbulbUserIds.removeAll { $0 == userId }
            try await postRef.updateData([
                "lightbulbCount": FieldValue.increment(Int64(-1)),
                "lightbulbUserIds": lightbulbUserIds,
                "updatedAt": Date()
            ])
            print("💡 Lightbulb removed")
        } else {
            // Add lightbulb
            lightbulbUserIds.append(userId)
            try await postRef.updateData([
                "lightbulbCount": FieldValue.increment(Int64(1)),
                "lightbulbUserIds": lightbulbUserIds,
                "updatedAt": Date()
            ])
            print("💡 Lightbulb lit!")
        }
        
        // Haptic feedback
        let haptic = UIImpactFeedbackGenerator(style: hasLit ? .light : .medium)
        haptic.impactOccurred()
    }
    
    /// Update category-specific arrays from main posts array
    private func updateCategoryArrays() {
        openTablePosts = posts.filter { $0.category == .openTable }
        testimoniesPosts = posts.filter { $0.category == .testimonies }
        prayerPosts = posts.filter { $0.category == .prayer }
    }
    
    // MARK: - User-Specific Posts (for Profile View)
    
    /// Fetch original posts created by a specific user (excluding reposts)
    func fetchUserOriginalPosts(userId: String) async throws -> [Post] {
        print("📥 Fetching original posts for user: \(userId)")
        
        // ✅ Optimized query using composite index (authorId + isRepost + createdAt)
        let query = db.collection(FirebaseManager.CollectionPath.posts)
            .whereField("authorId", isEqualTo: userId)
            .whereField("isRepost", isEqualTo: false)
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
        
        let snapshot = try await query.getDocuments()
        let firestorePosts = try snapshot.documents.compactMap { try $0.data(as: FirestorePost.self) }
        let userPosts = firestorePosts.map { $0.toPost() }
        
        print("✅ Fetched \(userPosts.count) original posts for user")
        return userPosts
    }
    
    /// Fetch reposts by a specific user
    func fetchUserReposts(userId: String) async throws -> [Post] {
        print("📥 Fetching reposts for user: \(userId)")
        
        // ✅ Optimized query using composite index (authorId + isRepost + createdAt)
        let query = db.collection(FirebaseManager.CollectionPath.posts)
            .whereField("authorId", isEqualTo: userId)
            .whereField("isRepost", isEqualTo: true)
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
        
        let snapshot = try await query.getDocuments()
        let firestorePosts = try snapshot.documents.compactMap { try $0.data(as: FirestorePost.self) }
        let reposts = firestorePosts.map { $0.toPost() }
        
        print("✅ Fetched \(reposts.count) reposts for user")
        return reposts
    }
    
    /// Fetch saved posts for a specific user
    func fetchUserSavedPosts(userId: String) async throws -> [Post] {
        print("📥 Fetching saved posts for user: \(userId)")
        
        // First, get all saved post IDs
        let savedQuery = db.collection(FirebaseManager.CollectionPath.savedPosts)
            .whereField("userId", isEqualTo: userId)
            .order(by: "savedAt", descending: true)
            .limit(to: 50)
        
        let savedSnapshot = try await savedQuery.getDocuments()
        let savedPostIds = savedSnapshot.documents.compactMap { doc -> String? in
            doc.data()["postId"] as? String
        }
        
        guard !savedPostIds.isEmpty else {
            print("✅ No saved posts found")
            return []
        }
        
        // Fetch the actual posts
        // Note: Firestore has a limit of 10 items for 'in' queries, so we batch them
        var allSavedPosts: [Post] = []
        
        for batch in savedPostIds.chunked(into: 10) {
            let postsQuery = db.collection(FirebaseManager.CollectionPath.posts)
                .whereField(FieldPath.documentID(), in: batch)
            
            let postsSnapshot = try await postsQuery.getDocuments()
            let batchPosts = try postsSnapshot.documents.compactMap { try $0.data(as: FirestorePost.self) }
            allSavedPosts.append(contentsOf: batchPosts.map { $0.toPost() })
        }
        
        print("✅ Fetched \(allSavedPosts.count) saved posts for user")
        return allSavedPosts
    }
    
    /// Fetch comments/replies made by a specific user
    func fetchUserReplies(userId: String) async throws -> [Comment] {
        print("📥 Fetching replies for user: \(userId)")
        
        // ✅ Optimized query using composite index (authorId + createdAt)
        let query = db.collection(FirebaseManager.CollectionPath.comments)
            .whereField("authorId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
        
        let snapshot = try await query.getDocuments()
        let comments = try snapshot.documents.compactMap { try $0.data(as: Comment.self) }
        
        print("✅ Fetched \(comments.count) replies for user")
        return comments
    }
    
    // MARK: - Admin/Development Functions
    
    /// ⚠️ DANGER: Delete ALL posts from Firestore (for development/testing only)
    /// This will permanently delete all posts in the database
    func deleteAllPosts() async throws {
        print("🗑️ ⚠️ DELETING ALL POSTS FROM FIRESTORE...")
        
        let snapshot = try await db.collection(FirebaseManager.CollectionPath.posts).getDocuments()
        
        print("⚠️ Found \(snapshot.documents.count) posts to delete")
        
        // Delete in batches
        let batch = db.batch()
        var count = 0
        
        for document in snapshot.documents {
            batch.deleteDocument(document.reference)
            count += 1
            
            // Firestore batch limit is 500 operations
            if count >= 500 {
                try await batch.commit()
                count = 0
                print("✅ Deleted batch of 500 posts")
            }
        }
        
        // Commit remaining deletes
        if count > 0 {
            try await batch.commit()
            print("✅ Deleted final batch of \(count) posts")
        }
        
        print("✅ ALL POSTS DELETED")
        
        // Clear local cache
        await MainActor.run {
            self.posts = []
            self.openTablePosts = []
            self.testimoniesPosts = []
            self.prayerPosts = []
        }
    }
    
    /// Delete posts by specific author name (useful for removing fake data)
    func deletePostsByAuthorName(_ authorName: String) async throws {
        print("🗑️ Deleting posts by author: \(authorName)")
        
        let snapshot = try await db.collection(FirebaseManager.CollectionPath.posts)
            .whereField("authorName", isEqualTo: authorName)
            .getDocuments()
        
        print("⚠️ Found \(snapshot.documents.count) posts to delete for \(authorName)")
        
        let batch = db.batch()
        for document in snapshot.documents {
            batch.deleteDocument(document.reference)
        }
        
        try await batch.commit()
        print("✅ Deleted all posts by \(authorName)")
    }
    
    /// Delete multiple fake users' posts at once
    func deleteFakePosts() async throws {
        print("🗑️ Deleting all fake sample data posts...")
        
        let fakeNames = [
            "Sarah Chen",
            "Sarah Johnson",
            "David Chen",
            "Mike Chen",
            "Michael Chen",
            "Michael Thompson",
            "Emily Rodriguez",
            "James Parker",
            "Grace Thompson",
            "Daniel Park",
            "Rebecca Santos",
            "Sarah Mitchell",
            "Marcus Lee",
            "Jennifer Adams",
            "Emily Foster",
            "David & Rachel",
            "Patricia Moore",
            "George Thompson",
            "Angela Rivera",
            "Olivia Chen",
            "Nathan Parker",
            "Maria Santos",
            "Hannah Davis",
            "Jacob Williams",
            "Linda Martinez",
            "Rachel Kim",
            "David Martinez",
            "Anonymous"
        ]
        
        var totalDeleted = 0
        
        for fakeName in fakeNames {
            do {
                let snapshot = try await db.collection(FirebaseManager.CollectionPath.posts)
                    .whereField("authorName", isEqualTo: fakeName)
                    .getDocuments()
                
                if !snapshot.documents.isEmpty {
                    let batch = db.batch()
                    for document in snapshot.documents {
                        batch.deleteDocument(document.reference)
                    }
                    try await batch.commit()
                    
                    print("✅ Deleted \(snapshot.documents.count) posts by \(fakeName)")
                    totalDeleted += snapshot.documents.count
                }
            } catch {
                print("⚠️ Error deleting posts for \(fakeName): \(error)")
            }
        }
        
        print("✅ TOTAL FAKE POSTS DELETED: \(totalDeleted)")
        
        // Clear local cache and refresh
        await MainActor.run {
            self.posts = []
            self.openTablePosts = []
            self.testimoniesPosts = []
            self.prayerPosts = []
        }
        
        // Refresh posts from Firebase
        try await fetchAllPosts()
    }
    
    // MARK: - Notification Helpers
    
    /// Create notification when someone says Amen to a post
    private func createAmenNotification(
        postId: String,
        postAuthorId: String,
        postContent: String,
        fromUserId: String
    ) async throws {
        // Don't notify yourself
        guard fromUserId != postAuthorId else { return }
        
        // Get current user info
        let userDoc = try await db.collection(FirebaseManager.CollectionPath.users)
            .document(fromUserId)
            .getDocument()
        
        guard let userData = userDoc.data() else { return }
        
        let fromUserName = userData["displayName"] as? String ?? "Someone"
        let fromUsername = userData["username"] as? String ?? ""
        
        // Create notification document
        let notification: [String: Any] = [
            "userId": postAuthorId,
            "type": "amen",
            "fromUserId": fromUserId,
            "fromUserName": fromUserName,
            "fromUserUsername": fromUsername,
            "postId": postId,
            "message": "\(fromUserName) said Amen to your post",
            "postPreview": String(postContent.prefix(50)),
            "createdAt": Date(),
            "read": false
        ]
        
        try await db.collection("notifications").addDocument(data: notification)
        print("✅ Amen notification created")
    }
    
    /// Create notification when someone comments on a post
    private func createCommentNotification(
        postId: String,
        postAuthorId: String,
        postContent: String,
        commentText: String,
        fromUserId: String
    ) async throws {
        // Don't notify yourself
        guard fromUserId != postAuthorId else { return }
        
        // Get current user info
        let userDoc = try await db.collection(FirebaseManager.CollectionPath.users)
            .document(fromUserId)
            .getDocument()
        
        guard let userData = userDoc.data() else { return }
        
        let fromUserName = userData["displayName"] as? String ?? "Someone"
        let fromUsername = userData["username"] as? String ?? ""
        
        // Create notification document
        let notification: [String: Any] = [
            "userId": postAuthorId,
            "type": "comment",
            "fromUserId": fromUserId,
            "fromUserName": fromUserName,
            "fromUserUsername": fromUsername,
            "postId": postId,
            "message": "\(fromUserName) commented on your post",
            "postPreview": String(postContent.prefix(50)),
            "commentPreview": String(commentText.prefix(50)),
            "createdAt": Date(),
            "read": false
        ]
        
        try await db.collection("notifications").addDocument(data: notification)
        print("✅ Comment notification created")
    }
    
    /// Create notifications for mentioned users
    private func createMentionNotifications(
        postId: String,
        postContent: String,
        fromUserId: String
    ) async throws {
        // Detect mentions (@username)
        let mentions = detectMentions(in: postContent)
        
        guard !mentions.isEmpty else { return }
        
        // Get current user info
        let userDoc = try await db.collection(FirebaseManager.CollectionPath.users)
            .document(fromUserId)
            .getDocument()
        
        guard let userData = userDoc.data() else { return }
        
        let fromUserName = userData["displayName"] as? String ?? "Someone"
        let fromUsername = userData["username"] as? String ?? ""
        
        // Create notification for each mentioned user
        for mentionedUsername in mentions {
            // Find user by username
            let usersQuery = db.collection(FirebaseManager.CollectionPath.users)
                .whereField("username", isEqualTo: mentionedUsername)
                .limit(to: 1)
            
            let snapshot = try await usersQuery.getDocuments()
            
            guard let userDoc = snapshot.documents.first else { continue }
            let mentionedUserId = userDoc.documentID
            
            // Don't notify yourself
            guard mentionedUserId != fromUserId else { continue }
            
            // Create notification
            let notification: [String: Any] = [
                "userId": mentionedUserId,
                "type": "mention",
                "fromUserId": fromUserId,
                "fromUserName": fromUserName,
                "fromUserUsername": fromUsername,
                "postId": postId,
                "message": "\(fromUserName) mentioned you in a post",
                "postPreview": String(postContent.prefix(50)),
                "createdAt": Date(),
                "read": false
            ]
            
            try await db.collection("notifications").addDocument(data: notification)
            print("✅ Mention notification created for @\(mentionedUsername)")
        }
    }
    
    /// Detect @mentions in text
    private func detectMentions(in text: String) -> [String] {
        let pattern = "@([a-zA-Z0-9_]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        
        return matches.compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let usernameRange = match.range(at: 1)
            return nsText.substring(with: usernameRange)
        }
    }
}


