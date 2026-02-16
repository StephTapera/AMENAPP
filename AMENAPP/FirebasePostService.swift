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
    
    // Church note reference
    var churchNoteId: String?
    
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
        case churchNoteId
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
        churchNoteId = try container.decodeIfPresent(String.self, forKey: .churchNoteId)
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
        lightbulbUserIds: [String] = [],
        churchNoteId: String? = nil
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
        self.churchNoteId = churchNoteId
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
            firebaseId: id,
            authorId: authorId,
            authorName: authorName,
            authorUsername: authorUsername,
            authorInitials: authorInitials,
            authorProfileImageURL: authorProfileImageURL,  // ✅ FIX: Added profile image URL
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
            originalAuthorId: originalAuthorId,
            churchNoteId: churchNoteId
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
    private var activeListenerCategories: Set<String> = [] // ✅ Track active listeners per category
    private var profileImageCache: [String: String] = [:] // ✅ Cache user profile images (userId: imageURL)
    
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
        
        // Skip fetching if user is not authenticated
        guard Auth.auth().currentUser != nil else {
            return
        }
        
        do {
            // Firestore 'in' query limited to 10 items, so batch them
            let batches = postIds.chunked(into: 10)
            var allPosts: [Post] = []
            
            for batch in batches {
                // ✅ Try server first, then fall back to cache if offline
                var snapshot: QuerySnapshot
                do {
                    snapshot = try await db.collection(FirebaseManager.CollectionPath.posts)
                        .whereField(FieldPath.documentID(), in: batch)
                        .getDocuments(source: .server)
                    print("🌐 Fetched \(snapshot.documents.count) posts from server")
                } catch {
                    print("⚠️ Server unavailable, loading from cache...")
                    snapshot = try await db.collection(FirebaseManager.CollectionPath.posts)
                        .whereField(FieldPath.documentID(), in: batch)
                        .getDocuments(source: .cache)
                    print("📦 Loaded \(snapshot.documents.count) posts from cache")
                }
                
                let batchPosts = try snapshot.documents.compactMap { doc in
                    var firestorePost = try doc.data(as: FirestorePost.self)
                    firestorePost.id = doc.documentID  // ✅ FIX: Explicitly set the document ID
                    return firestorePost
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
    
    /// Create a new post in Firestore with INSTANT optimistic updates (like Threads)
    func createPost(
        content: String,
        category: Post.PostCategory,
        topicTag: String? = nil,
        visibility: Post.PostVisibility = .everyone,
        allowComments: Bool = true,
        imageURLs: [String]? = nil,
        linkURL: String? = nil,
        churchNoteId: String? = nil
    ) async throws {
        print("📝 Creating new post with INSTANT optimistic update...")
        
        guard let userId = firebaseManager.currentUser?.uid else {
            print("❌ No authenticated user")
            throw FirebaseError.unauthorized
        }
        
        // 🚀 STEP 1: Get cached user data (INSTANT - no network call)
        let displayName = UserDefaults.standard.string(forKey: "currentUserDisplayName") ?? "You"
        let username = UserDefaults.standard.string(forKey: "currentUserUsername") ?? "you"
        let initials = UserDefaults.standard.string(forKey: "currentUserInitials") ?? "ME"
        let profileImageURL = UserDefaults.standard.string(forKey: "currentUserProfileImageURL")
        
        print("✅ Using cached user data (INSTANT)")
        
        let categoryString: String = {
            switch category {
            case .openTable: return "openTable"
            case .testimonies: return "testimonies"
            case .prayer: return "prayer"
            case .tip: return "tip"
            case .funFact: return "funFact"
            }
        }()
        
        let visibilityString: String = {
            switch visibility {
            case .everyone: return "everyone"
            case .followers: return "followers"
            case .community: return "community"
            }
        }()
        
        // 🚀 STEP 2: Create optimistic post object with temporary ID
        let tempId = UUID()
        let optimisticPost = Post(
            id: tempId,
            firebaseId: nil, // Will be set when Firebase confirms
            authorId: userId,
            authorName: displayName,
            authorUsername: username,
            authorInitials: initials,
            authorProfileImageURL: profileImageURL,
            timeAgo: "Just now",
            content: content,
            category: category,
            topicTag: topicTag,
            visibility: visibility,
            allowComments: allowComments,
            imageURLs: imageURLs,
            linkURL: linkURL,
            createdAt: Date(),
            amenCount: 0,
            lightbulbCount: 0,
            commentCount: 0,
            repostCount: 0,
            isRepost: false,
            originalAuthorName: nil,
            originalAuthorId: nil,
            churchNoteId: churchNoteId
        )
        
        // 🚀 STEP 3: INSTANTLY notify ProfileView (UI updates IMMEDIATELY)
        await MainActor.run {
            NotificationCenter.default.post(
                name: .newPostCreated,
                object: nil,
                userInfo: [
                    "post": optimisticPost,
                    "isOptimistic": true
                ]
            )
            print("⚡️ Post added to ProfileView INSTANTLY (optimistic)!")
        }
        
        // 🚀 STEP 4: Save to Firestore in background (non-blocking)
        let firestorePost = FirestorePost(
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
            linkURL: linkURL,
            churchNoteId: churchNoteId
        )
        
        // Background save - don't wait for it
        Task.detached(priority: .userInitiated) {
            do {
                let docRef = try await self.db.collection(FirebaseManager.CollectionPath.posts)
                    .addDocument(from: firestorePost)
                
                print("✅ Post saved to Firestore with ID: \(docRef.documentID)")
                
                // ✅ Notify ProfileView that post was created successfully
                await MainActor.run {
                    // Create confirmed post with Firebase ID
                    let confirmedPost = Post(
                        id: tempId,
                        firebaseId: docRef.documentID,
                        authorId: userId,
                        authorName: displayName,
                        authorUsername: username,
                        authorInitials: initials,
                        authorProfileImageURL: profileImageURL,
                        timeAgo: "Just now",
                        content: content,
                        category: category,
                        topicTag: topicTag,
                        visibility: visibility,
                        allowComments: allowComments,
                        imageURLs: imageURLs,
                        linkURL: linkURL,
                        createdAt: Date(),
                        amenCount: 0,
                        lightbulbCount: 0,
                        commentCount: 0,
                        repostCount: 0,
                        isRepost: false,
                        originalAuthorName: nil,
                        originalAuthorId: nil,
                        churchNoteId: churchNoteId
                    )
                    
                    NotificationCenter.default.post(
                        name: .newPostCreated,
                        object: nil,
                        userInfo: [
                            "post": confirmedPost,
                            "isOptimistic": false
                        ]
                    )
                    print("📬 Sent newPostCreated notification for post: \(docRef.documentID)")
                }
                
                // Update user's post count (background)
                Task {
                    try? await self.db.collection(FirebaseManager.CollectionPath.users)
                        .document(userId)
                        .updateData([
                            "postsCount": FieldValue.increment(Int64(1)),
                            "updatedAt": Date()
                        ])
                }
                
                // Create mention notifications (background)
                Task {
                    try? await self.createMentionNotifications(
                        postId: docRef.documentID,
                        postContent: content,
                        fromUserId: userId
                    )
                }
                
            } catch {
                print("❌ Failed to save post to Firestore: \(error)")
                
                // Post failure notification - rollback optimistic update
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: Notification.Name("postCreationFailed"),
                        object: nil,
                        userInfo: [
                            "error": error,
                            "postId": tempId.uuidString
                        ]
                    )
                }
            }
        }
        
        print("✅ Post creation complete - UI updated INSTANTLY, saving in background")
    }
    
    // MARK: - Fetch Posts
    
    /// Fetch all posts (for main feed)
    func fetchAllPosts(limit: Int = 50) async throws {
        // Skip fetching if user is not authenticated
        guard Auth.auth().currentUser != nil else {
            print("⏭️ Skipping fetchAllPosts - user not authenticated")
            return
        }
        
        print("📥 Fetching all posts from Firestore...")
        isLoading = true
        defer { isLoading = false }
        
        do {
            // ✅ Try server first, then fall back to cache if offline
            var snapshot: QuerySnapshot
            do {
                snapshot = try await db.collection(FirebaseManager.CollectionPath.posts)
                    .order(by: "createdAt", descending: true)
                    .limit(to: limit)
                    .getDocuments(source: .server)
                print("🌐 Fetched \(snapshot.documents.count) posts from server")
            } catch {
                print("⚠️ Server unavailable, loading from cache...")
                snapshot = try await db.collection(FirebaseManager.CollectionPath.posts)
                    .order(by: "createdAt", descending: true)
                    .limit(to: limit)
                    .getDocuments(source: .cache)
                print("📦 Loaded \(snapshot.documents.count) posts from cache")
            }
            
            let firestorePosts = try snapshot.documents.compactMap { doc in
                var firestorePost = try doc.data(as: FirestorePost.self)
                firestorePost.id = doc.documentID  // ✅ FIX: Explicitly set the document ID
                return firestorePost
            }
            
            var posts = firestorePosts.map { $0.toPost() }
            
            // ✅ Automatically enrich posts with profile images if missing
            await enrichPostsWithProfileImages(&posts)
            
            self.posts = posts
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
            case .tip: return "tip"
            case .funFact: return "funFact"
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
                var firestorePost = try doc.data(as: FirestorePost.self)
                firestorePost.id = doc.documentID  // ✅ FIX: Explicitly set the document ID
                return firestorePost
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
            var firestorePost = try doc.data(as: FirestorePost.self)
            firestorePost.id = doc.documentID  // ✅ FIX: Explicitly set the document ID
            return firestorePost
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
        
        var firestorePost = try document.data(as: FirestorePost.self)
        firestorePost.id = document.documentID  // ✅ FIX: Explicitly set the document ID
        let post = firestorePost.toPost()
        
        print("✅ Fetched post: \(postId)")
        return post
    }
    
    // MARK: - Real-time Listeners
    
    /// Start listening to posts in real-time
    func startListening(category: Post.PostCategory? = nil) {
        let categoryKey = category?.rawValue ?? "all"
        
        // ✅ If listeners array is empty but categories are marked active, clear the categories
        // This handles app restarts or cases where listeners were removed but categories weren't cleared
        if listeners.isEmpty && !activeListenerCategories.isEmpty {
            activeListenerCategories.removeAll()
        }
        
        // ✅ Prevent duplicate listeners for the same category
        guard !activeListenerCategories.contains(categoryKey) else {
            return
        }
        
        // Check if user is authenticated
        guard firebaseManager.isAuthenticated else {
            self.error = "Please sign in to view posts"
            return
        }
        
        activeListenerCategories.insert(categoryKey) // ✅ Mark this category as active
        
        let query: Query
        
        if let category = category {
            let categoryString: String = {
                switch category {
                case .openTable: return "openTable"
                case .testimonies: return "testimonies"
                case .prayer: return "prayer"
                case .tip: return "tip"
                case .funFact: return "funFact"
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
        
        // ✅ INSTANT LOAD: Load from cache immediately before starting listener
        Task { @MainActor in
            do {
                let cacheSnapshot = try await query.getDocuments(source: .cache)
                let cachedPosts = cacheSnapshot.documents.compactMap { doc -> FirestorePost? in
                    var firestorePost = try? doc.data(as: FirestorePost.self)
                    firestorePost?.id = doc.documentID  // ✅ FIX: Explicitly set the document ID
                    return firestorePost
                }.map { $0.toPost() }
                
                if !cachedPosts.isEmpty {
                    if let category = category {
                        switch category {
                        case .prayer:
                            self.prayerPosts = cachedPosts
                        case .testimonies:
                            self.testimoniesPosts = cachedPosts
                        case .openTable:
                            self.openTablePosts = cachedPosts
                        case .tip, .funFact:
                            break  // Tip and funFact posts stay in main feed only
                        }
                        self.posts = self.prayerPosts + self.testimoniesPosts + self.openTablePosts
                    } else {
                        self.posts = cachedPosts
                        self.updateCategoryArrays()
                    }
                    print("⚡️ INSTANT: Loaded \(cachedPosts.count) posts from cache")
                }
            } catch {
                print("📱 No cached posts available - will wait for server")
            }
        }
        
        let listener = query.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            
            Task { @MainActor in
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
                
                // ✅ CRITICAL FIX: Skip empty cache snapshots (we already loaded from cache manually)
                let metadata = snapshot.metadata
                if snapshot.documents.isEmpty && metadata.isFromCache {
                    print("⏭️ Skipping empty cache snapshot (already loaded from cache)")
                    return
                }
                
                let firestorePosts = snapshot.documents.compactMap { doc -> FirestorePost? in
                    var firestorePost = try? doc.data(as: FirestorePost.self)
                    firestorePost?.id = doc.documentID  // ✅ FIX: Explicitly set the document ID
                    return firestorePost
                }
                
                var newPosts = firestorePosts.map { $0.toPost() }

                // ✅ Update category-specific arrays IMMEDIATELY (non-blocking)
                await MainActor.run {
                    if let category = category {
                        switch category {
                        case .prayer:
                            self.prayerPosts = newPosts
                        case .testimonies:
                            self.testimoniesPosts = newPosts
                        case .openTable:
                            self.openTablePosts = newPosts
                        case .tip, .funFact:
                            break  // Tip and funFact posts stay in main feed only
                        }

                        // Update the main posts array by combining all categories
                        self.posts = self.prayerPosts + self.testimoniesPosts + self.openTablePosts

                        print("✅ Updated \(category.displayName): \(newPosts.count) posts with profile images")
                    } else {
                        // No category filter - update all posts
                        self.posts = newPosts
                        self.updateCategoryArrays()
                    }
                }
                
                // Log metadata for debugging
                if metadata.isFromCache {
                    print("📦 Posts loaded from cache (offline mode)")
                } else {
                    print("🌐 Posts loaded from server")
                }
                
                if metadata.hasPendingWrites {
                    print("⏳ Snapshot has pending writes")
                }
                
                // ✅ Enrich with profile images AFTER posts are displayed (non-blocking)
                Task.detached(priority: .background) { [weak self] in
                    guard let self = self else { return }
                    var enrichedPosts = newPosts
                    await self.enrichPostsWithProfileImages(&enrichedPosts)
                    
                    // Update posts again with profile images
                    await MainActor.run {
                        if let category = category {
                            switch category {
                            case .prayer:
                                self.prayerPosts = enrichedPosts
                            case .testimonies:
                                self.testimoniesPosts = enrichedPosts
                            case .openTable:
                                self.openTablePosts = enrichedPosts
                            case .tip, .funFact:
                                break  // Tip and funFact posts stay in main feed only
                            }
                            self.posts = self.prayerPosts + self.testimoniesPosts + self.openTablePosts
                        } else {
                            self.posts = enrichedPosts
                            self.updateCategoryArrays()
                        }
                    }
                }
            }
        }
        
        listeners.append(listener)
    }
    
    /// Stop all listeners
    func stopListening() {
        print("🔇 Stopping all listeners...")
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        activeListenerCategories.removeAll() // ✅ Clear all active categories
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
    
    // MARK: - Interactions (with Optimistic Updates)
    
    /// Toggle "Amen" on a post with INSTANT optimistic update
    func toggleAmen(postId: String) async throws {
        print("🙏 Toggling Amen on post (INSTANT): \(postId)")
        
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        // 🚀 STEP 1: Check current state locally
        let postRef = db.collection(FirebaseManager.CollectionPath.posts).document(postId)
        let postDoc = try await postRef.getDocument()
        
        guard let data = postDoc.data(),
              var amenUserIds = data["amenUserIds"] as? [String] else {
            throw FirebaseError.invalidData
        }
        
        let hasAmened = amenUserIds.contains(userId)
        let willAdd = !hasAmened
        let postAuthorId = data["authorId"] as? String ?? ""
        
        // 🚀 STEP 2: Update UI INSTANTLY via RealtimePostService
        // Note: Optimistic updates temporarily disabled
        // await MainActor.run {
        //     RealtimePostService.shared.updateReactionOptimistically(
        //         postId: postId,
        //         reactionType: .amen,
        //         increment: willAdd
        //     )
        // }
        
        // 🚀 STEP 3: Update Firestore in background (non-blocking)
        Task.detached(priority: .userInitiated) {
            do {
                if willAdd {
                    // Add amen
                    amenUserIds.append(userId)
                    try await postRef.updateData([
                        "amenCount": FieldValue.increment(Int64(1)),
                        "amenUserIds": amenUserIds,
                        "updatedAt": Date()
                    ])
                    print("✅ Amen added to Firestore")
                    
                    // Create notification for post author (background)
                    try? await self.createAmenNotification(
                        postId: postId,
                        postAuthorId: postAuthorId,
                        postContent: data["content"] as? String ?? "",
                        fromUserId: userId
                    )
                } else {
                    // Remove amen
                    amenUserIds.removeAll { $0 == userId }
                    try await postRef.updateData([
                        "amenCount": FieldValue.increment(Int64(-1)),
                        "amenUserIds": amenUserIds,
                        "updatedAt": Date()
                    ])
                    print("✅ Amen removed from Firestore")
                }
            } catch {
                print("❌ Failed to update amen in Firestore: \(error)")
                // Rollback optimistic update
                // Note: Optimistic updates temporarily disabled
                // await MainActor.run {
                //     RealtimePostService.shared.updateReactionOptimistically(
                //         postId: postId,
                //         reactionType: .amen,
                //         increment: !willAdd // Reverse the action
                //     )
                // }
            }
        }
        
        // Haptic feedback
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
    }
    
    /// Increment comment count with INSTANT optimistic update
    func incrementCommentCount(
        postId: String,
        commentText: String? = nil
    ) async throws {
        print("💬 Incrementing comment count (INSTANT) for post: \(postId)")
        
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        // 🚀 STEP 1: Update UI INSTANTLY
        // Note: Optimistic updates temporarily disabled
        // await MainActor.run {
        //     RealtimePostService.shared.updateCommentCountOptimistically(postId: postId, increment: true)
        // }
        
        // 🚀 STEP 2: Update Firestore in background
        Task.detached(priority: .userInitiated) {
            do {
                // Get post data for notification
                let postDoc = try await self.db.collection(FirebaseManager.CollectionPath.posts)
                    .document(postId)
                    .getDocument()
                
                guard let postData = postDoc.data() else {
                    throw FirebaseError.documentNotFound
                }
                
                // Update comment count
                try await self.db.collection(FirebaseManager.CollectionPath.posts)
                    .document(postId)
                    .updateData([
                        "commentCount": FieldValue.increment(Int64(1)),
                        "updatedAt": Date()
                    ])
                
                print("✅ Comment count updated in Firestore")
                
                // Create notification if we have comment text (background)
                if let commentText = commentText {
                    try? await self.createCommentNotification(
                        postId: postId,
                        postAuthorId: postData["authorId"] as? String ?? "",
                        postContent: postData["content"] as? String ?? "",
                        commentText: commentText,
                        fromUserId: userId
                    )
                }
            } catch {
                print("❌ Failed to update comment count: \(error)")
                // Rollback optimistic update
                // Note: Optimistic updates temporarily disabled
                // await MainActor.run {
                //     RealtimePostService.shared.updateCommentCountOptimistically(postId: postId, increment: false)
                // }
            }
        }
    }
    
    /// Repost to user's profile with INSTANT optimistic update
    func repostToProfile(originalPostId: String) async throws {
        print("🔄 Reposting post (INSTANT): \(originalPostId)")
        
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        // 🚀 STEP 1: Update UI INSTANTLY
        // Note: Optimistic updates temporarily disabled
        // await MainActor.run {
        //     RealtimePostService.shared.updateReactionOptimistically(
        //         postId: originalPostId,
        //         reactionType: .repost,
        //         increment: true
        //     )
        // }
        
        // 🚀 STEP 2: Create repost in background
        Task.detached(priority: .userInitiated) {
            do {
                // Try to fetch original post from Firestore
                let originalPostDoc = try await self.db.collection(FirebaseManager.CollectionPath.posts)
                    .document(originalPostId)
                    .getDocument()
                
                guard originalPostDoc.exists,
                      let originalPost = try? originalPostDoc.data(as: FirestorePost.self) else {
                    print("⚠️ Original post not found: \(originalPostId)")
                    throw FirebaseError.documentNotFound
                }
                
                // Use cached user data
                let displayName = UserDefaults.standard.string(forKey: "currentUserDisplayName") ?? "Unknown User"
                let username = UserDefaults.standard.string(forKey: "currentUserUsername") ?? "unknown"
                let initials = UserDefaults.standard.string(forKey: "currentUserInitials") ?? "??"
                let profileImageURL = UserDefaults.standard.string(forKey: "currentUserProfileImageURL")
                
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
                
                _ = try self.db.collection(FirebaseManager.CollectionPath.posts).addDocument(from: repost)
                
                // Increment repost count on original
                try? await self.db.collection(FirebaseManager.CollectionPath.posts)
                    .document(originalPostId)
                    .updateData([
                        "repostCount": FieldValue.increment(Int64(1)),
                        "updatedAt": Date()
                    ])
                
                // Update user's post count
                try await self.db.collection(FirebaseManager.CollectionPath.users)
                    .document(userId)
                    .updateData([
                        "postsCount": FieldValue.increment(Int64(1)),
                        "updatedAt": Date()
                    ])
                
                print("✅ Post reposted successfully")
                
            } catch {
                print("❌ Failed to repost: \(error)")
                // Rollback optimistic update
                // Note: Optimistic updates temporarily disabled
                // await MainActor.run {
                //     RealtimePostService.shared.updateReactionOptimistically(
                //         postId: originalPostId,
                //         reactionType: .repost,
                //         increment: false
                //     )
                // }
                throw error
            }
        }
        
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
    /// Supports fallback query if composite index is missing
    func fetchUserOriginalPosts(userId: String, useFallback: Bool = false) async throws -> [Post] {
        print("📥 Fetching original posts for user: \(userId)")
        
        do {
            let snapshot: QuerySnapshot
            
            if useFallback {
                // 🔄 FALLBACK: Simple query without isRepost filter (no composite index needed)
                print("⚠️ Using fallback query (filtering isRepost in memory)")
                let query = db.collection(FirebaseManager.CollectionPath.posts)
                    .whereField("authorId", isEqualTo: userId)
                    .order(by: "createdAt", descending: true)
                    .limit(to: 100) // Fetch more since we'll filter in memory
                
                snapshot = try await query.getDocuments()
            } else {
                // ✅ PREFERRED: Optimized query using composite index (authorId + isRepost + createdAt)
                let query = db.collection(FirebaseManager.CollectionPath.posts)
                    .whereField("authorId", isEqualTo: userId)
                    .whereField("isRepost", isEqualTo: false)
                    .order(by: "createdAt", descending: true)
                    .limit(to: 50)
                
                snapshot = try await query.getDocuments()
            }
            
            // 🐛 DEBUG: Log raw Firestore data
            print("📊 Firestore query returned \(snapshot.documents.count) documents")
            
            if snapshot.documents.isEmpty {
                print("⚠️ No documents found. Possible reasons:")
                print("   1. User hasn't created any posts")
                print("   2. All posts by this user are reposts (isRepost=true)")
                print("   3. Posts exist but authorId doesn't match '\(userId)'")
                if !useFallback {
                    print("   4. Firestore composite index not created (try useFallback=true)")
                }
            }
            
            // Debug: Log first few documents
            for (index, doc) in snapshot.documents.prefix(3).enumerated() {
                let data = doc.data()
                print("   📄 Document \(index + 1):")
                print("      - ID: \(doc.documentID)")
                print("      - authorId: \(data["authorId"] as? String ?? "nil")")
                print("      - category: \(data["category"] as? String ?? "nil")")
                print("      - isRepost: \(data["isRepost"] as? Bool ?? false)")
                print("      - content: \((data["content"] as? String ?? "").prefix(50))...")
            }
            
            var firestorePosts = try snapshot.documents.compactMap { try $0.data(as: FirestorePost.self) }
            
            // If using fallback, filter out reposts in memory
            if useFallback {
                let beforeFilter = firestorePosts.count
                firestorePosts = firestorePosts.filter { !$0.isRepost }
                print("🔄 Filtered \(beforeFilter - firestorePosts.count) reposts in memory")
            }
            
            let userPosts = firestorePosts.map { $0.toPost() }
            
            // Category breakdown
            let categoryBreakdown = userPosts.reduce(into: [Post.PostCategory: Int]()) { counts, post in
                counts[post.category, default: 0] += 1
            }
            
            print("✅ Fetched \(userPosts.count) original posts for user")
            if !categoryBreakdown.isEmpty {
                print("📊 Category breakdown:")
                categoryBreakdown.forEach { category, count in
                    print("   - \(category): \(count)")
                }
            }
            
            return userPosts
            
        } catch {
            print("❌ Error fetching user posts: \(error)")
            
            // Check if it's an index error
            if let firestoreError = error as NSError?,
               firestoreError.domain == "FIRFirestoreErrorDomain",
               firestoreError.code == 9 { // FAILED_PRECONDITION
                print("⚠️ FIRESTORE INDEX REQUIRED!")
                print("   Create a composite index for:")
                print("   Collection: posts")
                print("   Fields: authorId (Ascending), isRepost (Ascending), createdAt (Descending)")
                print("")
                print("   OR you can use the fallback query:")
                print("   try await fetchUserOriginalPosts(userId: userId, useFallback: true)")
                
                // Automatically retry with fallback if not already using it
                if !useFallback {
                    print("🔄 Automatically retrying with fallback query...")
                    return try await fetchUserOriginalPosts(userId: userId, useFallback: true)
                }
            }
            
            throw error
        }
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
    
    // MARK: - Profile Image Enrichment
    
    /// Automatically enrich posts with profile images if they're missing
    /// This runs transparently when posts are loaded from Firestore
    private func enrichPostsWithProfileImages(_ posts: inout [Post]) async {
        // Find posts without profile images
        let postsNeedingImages = posts.filter { $0.authorProfileImageURL == nil || $0.authorProfileImageURL?.isEmpty == true }
        
        guard !postsNeedingImages.isEmpty else { return }
        
        // Group by author to batch fetch profile images
        var authorIds = Set<String>()
        for post in postsNeedingImages {
            authorIds.insert(post.authorId)
        }
        
        // Filter out authorIds already in cache
        let authorIdsToFetch = authorIds.filter { profileImageCache[$0] == nil }
        
        // Fetch profile images for uncached authors only (in parallel)
        await withTaskGroup(of: (String, String?).self) { group in
            for authorId in authorIdsToFetch {
                group.addTask {
                    do {
                        let userDoc = try await self.db.collection("users").document(authorId).getDocument()
                        let profileImageURL = userDoc.data()?["profileImageURL"] as? String
                        return (authorId, profileImageURL)
                    } catch {
                        return (authorId, nil)
                    }
                }
            }
            
            for await (authorId, profileImageURL) in group {
                if let url = profileImageURL, !url.isEmpty {
                    await MainActor.run {
                        self.profileImageCache[authorId] = url
                    }
                }
            }
        }
        
        // Update posts with profile images from cache (create new Post instances since it's a struct)
        posts = posts.map { post in
            if post.authorProfileImageURL == nil || post.authorProfileImageURL?.isEmpty == true {
                if let profileImageURL = profileImageCache[post.authorId] {
                    return Post(
                        id: post.id,
                        firebaseId: post.firebaseId,
                        authorId: post.authorId,
                        authorName: post.authorName,
                        authorUsername: post.authorUsername,
                        authorInitials: post.authorInitials,
                        authorProfileImageURL: profileImageURL,
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
            }
            return post
        }
    }
    
    // MARK: - Migration Helpers
    
    /// One-time migration to add authorProfileImageURL to all existing posts
    func migrateAllPostsWithProfileImages() async throws {
        print("🔄 Starting migration to add profile images to all posts...")
        
        let db = Firestore.firestore()
        
        // Fetch all posts
        let snapshot = try await db.collection(FirebaseManager.CollectionPath.posts)
            .getDocuments()
        
        print("📊 Found \(snapshot.documents.count) posts to migrate")
        
        var updated = 0
        var skipped = 0
        
        // Group posts by author
        var postsByAuthor: [String: [QueryDocumentSnapshot]] = [:]
        for doc in snapshot.documents {
            if let authorId = doc.data()["authorId"] as? String {
                postsByAuthor[authorId, default: []].append(doc)
            }
        }
        
        // Fetch each author's profile and update their posts
        for (authorId, posts) in postsByAuthor {
            do {
                let userDoc = try await db.collection("users").document(authorId).getDocument()
                
                guard let userData = userDoc.data(),
                      let profileImageURL = userData["profileImageURL"] as? String,
                      !profileImageURL.isEmpty else {
                    print("⚠️ No profile image for user \(authorId), skipping \(posts.count) posts")
                    skipped += posts.count
                    continue
                }
                
                // Update all posts by this author
                for postDoc in posts {
                    // Check if already has profileImageURL
                    if let existing = postDoc.data()["authorProfileImageURL"] as? String, !existing.isEmpty {
                        skipped += 1
                        continue
                    }
                    
                    try await postDoc.reference.updateData([
                        "authorProfileImageURL": profileImageURL
                    ])
                    updated += 1
                }
                
                print("✅ Updated \(posts.count) posts for user \(authorId)")
                
            } catch {
                print("⚠️ Failed to update posts for user \(authorId): \(error)")
                skipped += posts.count
            }
        }
        
        print("✅ Migration complete! Updated: \(updated), Skipped: \(skipped)")
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


