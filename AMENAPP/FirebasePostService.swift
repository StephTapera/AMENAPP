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
    var linkPreviewTitle: String?
    var linkPreviewDescription: String?
    var linkPreviewImageURL: String?
    var linkPreviewSiteName: String?
    var linkPreviewType: String?
    var verseReference: String?
    var verseText: String?
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
    
    // Content source label — set when user acknowledges pasted/AI content
    var contentSource: String?
    
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
        case linkPreviewTitle, linkPreviewDescription, linkPreviewImageURL, linkPreviewSiteName
        case linkPreviewType, verseReference, verseText
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
        case contentSource
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
        linkPreviewTitle = try container.decodeIfPresent(String.self, forKey: .linkPreviewTitle)
        linkPreviewDescription = try container.decodeIfPresent(String.self, forKey: .linkPreviewDescription)
        linkPreviewImageURL = try container.decodeIfPresent(String.self, forKey: .linkPreviewImageURL)
        linkPreviewSiteName = try container.decodeIfPresent(String.self, forKey: .linkPreviewSiteName)
        linkPreviewType = try container.decodeIfPresent(String.self, forKey: .linkPreviewType)
        verseReference = try container.decodeIfPresent(String.self, forKey: .verseReference)
        verseText = try container.decodeIfPresent(String.self, forKey: .verseText)
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
        contentSource = try container.decodeIfPresent(String.self, forKey: .contentSource)
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
        churchNoteId: String? = nil,
        contentSource: String? = nil
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
        self.contentSource = contentSource
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
            case "tip":
                return .tip
            case "funfact":
                return .funFact
            default:
                dlog("⚠️ Unknown category '\(category)', defaulting to openTable")
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
            linkPreviewTitle: linkPreviewTitle,
            linkPreviewDescription: linkPreviewDescription,
            linkPreviewImageURL: linkPreviewImageURL,
            linkPreviewSiteName: linkPreviewSiteName,
            linkPreviewType: linkPreviewType,
            verseReference: verseReference,
            verseText: verseText,
            createdAt: createdAt,
            amenCount: amenCount,
            lightbulbCount: lightbulbCount,
            commentCount: commentCount,
            repostCount: repostCount,
            isRepost: isRepost,
            originalAuthorName: originalAuthorName,
            originalAuthorId: originalAuthorId,
            churchNoteId: churchNoteId,
            contentSource: contentSource
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
    
    // P1-1: Pagination support
    @Published var hasMorePosts = true
    @Published var isLoadingMore = false
    private var lastDocuments: [String: DocumentSnapshot] = [:]  // Category -> last document
    private let pageSize = 25  // Load 25 posts per page
    
    internal let firebaseManager = FirebaseManager.shared
    internal let db = Firestore.firestore()
    private let realtimeService = RealtimeDatabaseService.shared
    private var listeners: [ListenerRegistration] = []
    private var realtimePostsHandle: UInt?
    private var activeListenerCategories: Set<String> = [] // ✅ Track active listeners per category
    private var profileImageCache: [String: String] = [:] // ✅ Cache user profile images (userId: imageURL)
    // P1-2: Per-category debounce tasks — coalesce rapid snapshot callbacks into a single update
    private var listenerDebounceTasks: [String: Task<Void, Never>] = [:]
    
    // FIX: Track known post IDs so RTDB-triggered re-fetches merge rather than replace.
    // Posts already in self.posts are updated in-place; confirmed Firebase posts are never
    // overwritten by stale optimistic entries, and vice versa.
    private var knownPostIds: Set<String> = []
    
    // P0 FIX: Map listeners to categories for proper cleanup
    private var categoryListeners: [String: ListenerRegistration] = [:]
    
    // P0 FIX: Add refresh flag for pull-to-refresh
    @Published var isRefreshing = false
    
    private init() {
        setupRealtimeFeed()
    }
    
    deinit {
        // Clean up all Firestore listeners
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        categoryListeners.values.forEach { $0.remove() }
        categoryListeners.removeAll()
        listenerDebounceTasks.values.forEach { $0.cancel() }
        listenerDebounceTasks.removeAll()

        #if DEBUG
        dlog("✅ FirebasePostService deinitialized - all listeners cleaned up")
        #endif
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
        // P0 FIX: Don't process empty post ID arrays from Realtime Database
        // This prevents overwriting cached Firestore posts with empty arrays
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
                } catch {
                    snapshot = try await db.collection(FirebaseManager.CollectionPath.posts)
                        .whereField(FieldPath.documentID(), in: batch)
                        .getDocuments(source: .cache)
                }
                
                let batchPosts = try snapshot.documents.compactMap { doc in
                    var firestorePost = try doc.data(as: FirestorePost.self)
                    firestorePost.id = doc.documentID  // ✅ FIX: Explicitly set the document ID
                    return firestorePost
                }.map { $0.toPost() }
                
                allPosts.append(contentsOf: batchPosts)
            }
            
            // FIX: Merge fetched posts into existing list instead of replacing.
            // This prevents optimistic posts (firebaseId == nil) from being dropped
            // when RTDB delivers a new snapshot before Firestore has confirmed the write.
            if !allPosts.isEmpty {
                // Build a lookup of confirmed posts by their Firestore document ID
                var updatedById: [String: Post] = [:]
                for post in allPosts {
                    if let fbId = post.firebaseId {
                        updatedById[fbId] = post
                        knownPostIds.insert(fbId)
                    }
                }

                // Update existing entries in-place; append genuinely new confirmed posts
                var merged = self.posts
                var mergedIds = Set(merged.compactMap { $0.firebaseId })
                for (fbId, newPost) in updatedById {
                    if let idx = merged.firstIndex(where: { $0.firebaseId == fbId }) {
                        merged[idx] = newPost  // update in-place (counts, etc.)
                    } else if !mergedIds.contains(fbId) {
                        merged.insert(newPost, at: 0)  // prepend new confirmed post
                        mergedIds.insert(fbId)
                    }
                }

                self.posts = merged
                updateCategoryArrays()
            }

        } catch {
            #if DEBUG
            dlog("❌ Failed to fetch posts by IDs: \(error)")
            #endif
        }
    }
    
    // MARK: - Create Post
    
    // P0: Track in-flight post submissions to prevent double-tap duplicates.
    // Keyed by idempotency key so rapid retries of the same post coalesce.
    @MainActor private var inflightPostCreations: [String: Task<Void, Error>] = [:]

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
        #if DEBUG
        dlog("📝 Creating new post with INSTANT optimistic update...")
        #endif

        guard let userId = firebaseManager.currentUser?.uid else {
            dlog("❌ No authenticated user")
            throw FirebaseError.unauthorized
        }

        // P0 IDEMPOTENCY: Derive a deterministic key from userId + content + truncated timestamp.
        // If the user taps Post twice in the same second, or the app is killed and relaunched
        // within 1 second, the second call coalesces onto the first Task and returns without
        // creating a duplicate document.
        let truncatedSecond = Int(Date().timeIntervalSince1970)
        let contentPrefix = String(content.prefix(64))
        let idempotencyKey = "\(userId)_\(category.rawValue)_\(contentPrefix)_\(truncatedSecond)".data(using: .utf8)
            .map { Data($0).base64EncodedString().prefix(40) }
            .map(String.init) ?? UUID().uuidString

        if let existingTask = inflightPostCreations[idempotencyKey] {
            dlog("⏭️ [Idempotency] Post creation already in progress for key: \(idempotencyKey.prefix(20))…, waiting")
            try await existingTask.value
            return
        }

        let creationTask = Task<Void, Error> { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor in
                    self.inflightPostCreations.removeValue(forKey: idempotencyKey)
                }
            }
            try await self._performCreatePost(
                userId: userId,
                idempotencyKey: idempotencyKey,
                content: content,
                category: category,
                topicTag: topicTag,
                visibility: visibility,
                allowComments: allowComments,
                imageURLs: imageURLs,
                linkURL: linkURL,
                churchNoteId: churchNoteId
            )
        }
        inflightPostCreations[idempotencyKey] = creationTask
        try await creationTask.value
    }

    /// Internal implementation — called only by createPost after idempotency gate.
    private func _performCreatePost(
        userId: String,
        idempotencyKey: String,
        content: String,
        category: Post.PostCategory,
        topicTag: String? = nil,
        visibility: Post.PostVisibility = .everyone,
        allowComments: Bool = true,
        imageURLs: [String]? = nil,
        linkURL: String? = nil,
        churchNoteId: String? = nil
    ) async throws {

        // Rate-limit check for new accounts
        let postRateLimit = await NewAccountRestrictionService.shared.canPost(userId: userId)
        guard postRateLimit.allowed else {
            throw NSError(
                domain: "RateLimit",
                code: 429,
                userInfo: [NSLocalizedDescriptionKey: postRateLimit.reason ?? "Daily post limit reached. Try again tomorrow."]
            )
        }

        // 🚀 STEP 1: Get cached user data (INSTANT - no network call)
        let displayName = UserDefaults.standard.string(forKey: "currentUserDisplayName") ?? "You"
        let username = UserDefaults.standard.string(forKey: "currentUserUsername") ?? "you"
        let initials = UserDefaults.standard.string(forKey: "currentUserInitials") ?? "ME"
        let profileImageURL = UserDefaults.standard.string(forKey: "currentUserProfileImageURL")
        
        // 🤖 STEP 1.5: Check for AI-generated content
        // Church-note shares are the user's own sermon notes — skip AI detection.
        if churchNoteId == nil {
            let aiDetectionResult = await AIContentDetectionService.shared.detectAIContent(content)

            if aiDetectionResult.isAIGenerated {

                // Notify user immediately
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: Notification.Name("aiContentDetected"),
                        object: nil,
                        userInfo: [
                            "confidence": aiDetectionResult.confidence,
                            "reason": aiDetectionResult.reason
                        ]
                    )
                }

                throw FirebaseError.invalidData
            }
        }
        

        
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
            dlog("⚡️ Post added to ProfileView INSTANTLY (optimistic)!")
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
        let _db = db
        let _idempotencyKey = idempotencyKey
        Task(priority: .userInitiated) { @MainActor in
            do {
                var postData = try Firestore.Encoder().encode(firestorePost)
                // P0 IDEMPOTENCY: Embed the key so Cloud Functions / security rules can
                // detect and reject replayed writes server-side.
                postData["idempotencyKey"] = _idempotencyKey
                let _writeToken = PerfBegin("createPost_write")
                let _traceToken = WriteOpTracer.begin("createPost", key: _idempotencyKey)
                Breadcrumb.record("createPost_write_start")
                let docRef = try await _db.collection(FirebaseManager.CollectionPath.posts)
                    .addDocument(data: postData)
                PerfEnd(_writeToken, threshold: 500)
                WriteOpTracer.succeed(_traceToken, docId: docRef.documentID)
                
                #if DEBUG
                dlog("✅ Post saved to Firestore: \(docRef.documentID)")
                #endif

                // Write moderation audit log entry (non-blocking)
                Task {
                    let allowDecision = ModerationDecision(
                        action: .allow,
                        confidence: 1.0,
                        reasons: [],
                        detectedBehaviors: [],
                        suggestedRevisions: nil,
                        reviewRequired: false,
                        appealable: false,
                        scores: ModerationScores(
                            toxicity: 0, spam: 0, aiSuspicion: 0,
                            duplicateMatch: 0, authenticity: 1, userRiskScore: 0
                        )
                    )
                    ModerationAuditLogService.shared.recordPostDecision(
                        userId: userId,
                        postId: docRef.documentID,
                        content: content,
                        decision: allowDecision
                    )
                }

                // Record action for rate-limit counter
                await NewAccountRestrictionService.shared.recordAction(.post, userId: userId)

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
                    dlog("📬 Sent newPostCreated notification for post: \(docRef.documentID)")
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
                dlog("❌ Failed to save post to Firestore: \(error)")
                WriteOpTracer.fail(WriteOpTracer.begin("createPost", key: tempId.uuidString), error: error)
                Breadcrumb.record("createPost_write_fail", meta: ["err": error.localizedDescription.prefix(60).description])

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
        
    }

    // MARK: - Fetch Posts
    
    /// Fetch all posts (for main feed)
    func fetchAllPosts(limit: Int = 50) async throws {
        // Skip fetching if user is not authenticated
        guard Auth.auth().currentUser != nil else {
            dlog("⏭️ Skipping fetchAllPosts - user not authenticated")
            return
        }

        let _perfToken = PerfBegin("feed_load")
        isLoading = true
        defer {
            isLoading = false
            PerfEnd(_perfToken)
        }

        do {
            // PERFORMANCE FIX: Load from cache first for instant display, then upgrade with server data
            var snapshot: QuerySnapshot

            do {
                snapshot = try await db.collection(FirebaseManager.CollectionPath.posts)
                    .order(by: "createdAt", descending: true)
                    .limit(to: limit)
                    .getDocuments(source: .cache)
            } catch {
                snapshot = try await db.collection(FirebaseManager.CollectionPath.posts)
                    .order(by: "createdAt", descending: true)
                    .limit(to: limit)
                    .getDocuments(source: .server)
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
            updateCategoryArrays()

        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }
    
    /// THREADS-STYLE: Synchronous cache preload during app splash screen
    /// This loads posts from Firestore cache BEFORE views appear
    @MainActor
    func preloadCacheSync() async {
        guard Auth.auth().currentUser != nil else { return }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        do {
            // Load OpenTable posts from cache synchronously (most important)
            let query = db.collection(FirebaseManager.CollectionPath.posts)
                .whereField("category", isEqualTo: "openTable")
                .order(by: "createdAt", descending: true)
                .limit(to: 50)
            
            let snapshot = try await query.getDocuments(source: .cache)
            
            let cachedPosts = snapshot.documents.compactMap { doc -> FirestorePost? in
                var firestorePost = try? doc.data(as: FirestorePost.self)
                firestorePost?.id = doc.documentID
                return firestorePost
            }.map { $0.toPost() }
            
            if !cachedPosts.isEmpty {
                self.openTablePosts = cachedPosts
                self.posts = cachedPosts
                
                let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                dlog("⚡️ PRELOAD: \(cachedPosts.count) posts loaded in \(String(format: "%.0f", elapsed))ms")
            }
        } catch {
            dlog("📱 No cache available - will load from server")
        }
    }
    
    /// Fetch posts by category with filtering options
    func fetchPosts(
        for category: Post.PostCategory,
        filter: String = "all",
        topicTag: String? = nil,
        limit: Int = 50
    ) async throws -> [Post] {
        dlog("📥 Fetching \(category.rawValue) posts from Firestore (filter: \(filter))...")
        
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
                        dlog("✅ User not following anyone, returning empty array")
                        return []
                    }
                } else {
                    // Not authenticated, return empty
                    dlog("✅ User not authenticated, returning empty array")
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
            
            dlog("✅ Fetched \(posts.count) \(category.rawValue) posts")
            
            return posts
            
        } catch {
            dlog("❌ Failed to fetch category posts: \(error)")
            throw error
        }
    }
    
    /// Fetch posts by specific user
    func fetchUserPosts(userId: String, limit: Int = 50, forceServerFetch: Bool = false) async throws -> [Post] {
        dlog("📥 Fetching posts for user: \(userId)")
        
        let query = db.collection(FirebaseManager.CollectionPath.posts)
            .whereField("authorId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
        let snapshot = try await (forceServerFetch
            ? query.getDocuments(source: .server)
            : query.getDocuments())
        
        let firestorePosts = try snapshot.documents.compactMap { doc in
            var firestorePost = try doc.data(as: FirestorePost.self)
            firestorePost.id = doc.documentID  // ✅ FIX: Explicitly set the document ID
            return firestorePost
        }
        
        let posts = firestorePosts.map { $0.toPost() }
        dlog("✅ Fetched \(posts.count) user posts")
        
        return posts
    }
    
    /// Fetch a single post by its ID
    func fetchPostById(postId: String) async throws -> Post? {
        dlog("📥 Fetching post by ID: \(postId)")
        
        let document = try await db.collection(FirebaseManager.CollectionPath.posts)
            .document(postId)
            .getDocument()
        
        guard document.exists else {
            dlog("⚠️ Post not found: \(postId)")
            return nil
        }
        
        var firestorePost = try document.data(as: FirestorePost.self)
        firestorePost.id = document.documentID  // ✅ FIX: Explicitly set the document ID
        let post = firestorePost.toPost()
        
        dlog("✅ Fetched post: \(postId)")
        return post
    }
    
    // MARK: - Real-time Listeners
    
    /// Start listening to posts in real-time
    func startListening(category: Post.PostCategory? = nil) {
        let categoryKey = category?.rawValue ?? "all"
        
        // ✅ If listeners array is empty but categories are marked active, clear the categories
        // This handles app restarts or cases where listeners were removed but categories weren't cleared
        if listeners.isEmpty && !activeListenerCategories.isEmpty {
            dlog("🔄 Clearing stale active categories (listeners were removed)")
            activeListenerCategories.removeAll()
        }
        
        // ✅ Prevent duplicate listeners for the same category
        guard !activeListenerCategories.contains(categoryKey) else {
            dlog("⏭️ Listener already active for category: \(categoryKey)")
            return
        }
        
        // Check if user is authenticated
        guard firebaseManager.isAuthenticated else {
            self.error = "Please sign in to view posts"
            dlog("❌ Cannot start listener - user not authenticated")
            return
        }
        
        dlog("🎧 Starting real-time listener for category: \(categoryKey)")
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
                    dlog("⚡️ INSTANT: Loaded \(cachedPosts.count) posts from cache")
                }
            } catch {
                dlog("📱 No cached posts available - will wait for server")
            }
        }
        
        let listener = query.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }

            // P1-2: Handle errors immediately (no debounce needed for error path)
            if let error = error {
                let nsError = error as NSError
                // Suppress permission errors when signed out — expected during auth transition
                if nsError.code == 7 && Auth.auth().currentUser == nil {
                    dlog("⏭️ Suppressed permission error (user signed out)")
                    return
                }
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    dlog("❌ Firestore listener error: \(error.localizedDescription)")
                    self.error = error.localizedDescription
                }
                return
            }

            guard let snapshot = snapshot else {
                dlog("❌ No snapshot data")
                return
            }

            // ✅ CRITICAL FIX: Skip empty cache snapshots (we already loaded from cache manually)
            let metadata = snapshot.metadata
            if snapshot.documents.isEmpty && metadata.isFromCache { return }

            // P1-2: Debounce rapid consecutive snapshot callbacks — coalesce into a single update
            // Cancel any pending debounce task for this category before scheduling a new one
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.listenerDebounceTasks[categoryKey]?.cancel()
                let debounceTask = Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    // 300ms debounce window — absorbs burst writes (e.g. multiple users posting simultaneously)
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }

                    let firestorePosts = snapshot.documents.compactMap { doc -> FirestorePost? in
                        var firestorePost = try? doc.data(as: FirestorePost.self)
                        firestorePost?.id = doc.documentID  // ✅ FIX: Explicitly set the document ID
                        return firestorePost
                    }

                    // P1-1: Store last document for pagination
                    if let lastDoc = snapshot.documents.last {
                        self.lastDocuments[categoryKey] = lastDoc
                    }

                    var newPosts = firestorePosts.map { $0.toPost() }

                    // P0 FIX: Deduplicate and sort posts
                    newPosts = self.deduplicateAndSort(newPosts)

                    // ✅ Update category-specific arrays IMMEDIATELY (non-blocking)
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

                        // P0 FIX: Deduplicate and sort combined posts
                        let combined = self.prayerPosts + self.testimoniesPosts + self.openTablePosts
                        self.posts = self.deduplicateAndSort(combined)

                        #if DEBUG
                        dlog("✅ Updated \(category.displayName): \(newPosts.count) posts (debounced+deduplicated)")
                        #endif
                    } else {
                        // No category filter - update all posts
                        self.posts = newPosts
                        self.updateCategoryArrays()
                    }

                    #if DEBUG
                    if metadata.isFromCache {
                        dlog("📦 Posts loaded from cache (offline mode)")
                    } else {
                        dlog("🌐 Posts loaded from server")
                    }
                    if metadata.hasPendingWrites {
                        dlog("⏳ Snapshot has pending writes")
                    }
                    #endif

                    // ✅ Enrich with profile images AFTER posts are displayed (non-blocking)
                    let postsToEnrich = newPosts
                    Task.detached(priority: .background) { [weak self] in
                        guard let self = self else { return }
                        var enrichedPosts = postsToEnrich
                        await self.enrichPostsWithProfileImages(&enrichedPosts)

                        // P0 FIX: Deduplicate enriched posts too
                        let sortedPosts = await self.deduplicateAndSort(enrichedPosts)

                        // Update posts again with profile images
                        await MainActor.run {
                            if let category = category {
                                switch category {
                                case .prayer:
                                    self.prayerPosts = sortedPosts
                                case .testimonies:
                                    self.testimoniesPosts = sortedPosts
                                case .openTable:
                                    self.openTablePosts = sortedPosts
                                case .tip, .funFact:
                                    break  // Tip and funFact posts stay in main feed only
                                }
                                // P0 FIX: Deduplicate combined posts
                                let combined = self.prayerPosts + self.testimoniesPosts + self.openTablePosts
                                self.posts = self.deduplicateAndSort(combined)
                            } else {
                                self.posts = sortedPosts
                                self.updateCategoryArrays()
                            }
                        }
                    }
                }
                self.listenerDebounceTasks[categoryKey] = debounceTask
            }
        }
        
        listeners.append(listener)
        categoryListeners[categoryKey] = listener  // ✅ FIX P0-1: store by key so stopListening(category:) can remove it
        #if DEBUG
        ListenerCounter.shared.attach("posts-\(categoryKey)")
        #endif
    }
    
    /// Stop all listeners
    func stopListening() {
        dlog("🔇 Stopping all listeners...")
        #if DEBUG
        activeListenerCategories.forEach { ListenerCounter.shared.detach("posts-\($0)") }
        #endif
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        categoryListeners.forEach { $0.value.remove() }
        categoryListeners.removeAll()
        activeListenerCategories.removeAll() // ✅ Clear all active categories
    }
    
    // P0 FIX: Stop listening for a specific category
    func stopListening(category: Post.PostCategory) {
        let categoryKey = category.rawValue
        
        if let listener = categoryListeners[categoryKey] {
            #if DEBUG
            dlog("🔇 Stopping listener for category: \(categoryKey)")
            ListenerCounter.shared.detach("posts-\(categoryKey)")
            #endif
            listener.remove()
            categoryListeners.removeValue(forKey: categoryKey)
            // Keep listeners array in sync so stopListening() (all) doesn't double-remove
            listeners.removeAll { $0 === listener }
            activeListenerCategories.remove(categoryKey)
        }
    }
    
    // MARK: - Pagination (P1-1)
    
    /// Load more posts for a specific category (pagination)
    func loadMorePosts(category: Post.PostCategory? = nil) async {
        let categoryKey = category?.rawValue ?? "all"
        
        guard hasMorePosts, !isLoadingMore else {
            dlog("⏭️ Skipping load more: hasMore=\(hasMorePosts), isLoading=\(isLoadingMore)")
            return
        }
        
        guard let lastDocument = lastDocuments[categoryKey] else {
            dlog("⚠️ No last document for pagination - use initial fetch instead")
            return
        }
        
        await MainActor.run {
            isLoadingMore = true
        }
        
        do {
            var query: Query
            
            if let category = category {
                let categoryString = category.rawValue
                query = db.collection(FirebaseManager.CollectionPath.posts)
                    .whereField("category", isEqualTo: categoryString)
                    .order(by: "createdAt", descending: true)
                    .start(afterDocument: lastDocument)
                    .limit(to: pageSize)
            } else {
                query = db.collection(FirebaseManager.CollectionPath.posts)
                    .order(by: "createdAt", descending: true)
                    .start(afterDocument: lastDocument)
                    .limit(to: pageSize)
            }
            
            let snapshot = try await query.getDocuments()
            
            guard !snapshot.documents.isEmpty else {
                await MainActor.run {
                    hasMorePosts = false
                    isLoadingMore = false
                }
                dlog("✅ No more posts to load")
                return
            }
            
            // Update last document for next pagination
            if let last = snapshot.documents.last {
                lastDocuments[categoryKey] = last
            }
            
            let firestorePosts = snapshot.documents.compactMap { doc -> FirestorePost? in
                var firestorePost = try? doc.data(as: FirestorePost.self)
                firestorePost?.id = doc.documentID
                return firestorePost
            }
            
            var newPosts = firestorePosts.map { $0.toPost() }
            
            // Enrich with profile images
            await enrichPostsWithProfileImages(&newPosts)
            
            await MainActor.run {
                if let category = category {
                    switch category {
                    case .prayer:
                        prayerPosts.append(contentsOf: newPosts)
                    case .testimonies:
                        testimoniesPosts.append(contentsOf: newPosts)
                    case .openTable:
                        openTablePosts.append(contentsOf: newPosts)
                    case .tip, .funFact:
                        break
                    }
                    posts = prayerPosts + testimoniesPosts + openTablePosts
                } else {
                    posts.append(contentsOf: newPosts)
                    updateCategoryArrays()
                }
                
                hasMorePosts = snapshot.documents.count == pageSize
                isLoadingMore = false
            }
            
            dlog("✅ Loaded \(newPosts.count) more posts (hasMore: \(hasMorePosts))")
            
        } catch {
            dlog("❌ Error loading more posts: \(error)")
            await MainActor.run {
                isLoadingMore = false
            }
        }
    }
    
    // MARK: - Update Post
    
    /// Edit post content
    func editPost(postId: String, newContent: String) async throws {
        dlog("✏️ Editing post: \(postId)")
        
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
            dlog("❌ User does not own this post")
            throw FirebaseError.unauthorized
        }
        
        try await db.collection(FirebaseManager.CollectionPath.posts)
            .document(postId)
            .updateData([
                "content": newContent,
                "updatedAt": Date()
            ])
        
        dlog("✅ Post updated successfully")
        
        // Update local cache — match on firebaseId (Firestore doc ID), not the local UUID
        if let index = posts.firstIndex(where: { $0.firebaseId == postId }) {
            var updatedPost = posts[index]
            updatedPost.content = newContent
            posts[index] = updatedPost
            updateCategoryArrays()
        }
    }
    
    /// Delete post
    func deletePost(postId: String) async throws {
        dlog("🗑️ Deleting post: \(postId)")
        
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
            dlog("❌ User does not own this post")
            throw FirebaseError.unauthorized
        }
        
        try await db.collection(FirebaseManager.CollectionPath.posts)
            .document(postId)
            .delete()
        
        dlog("✅ Post deleted successfully")
        
        // Update user's post count
        try await db.collection(FirebaseManager.CollectionPath.users)
            .document(userId)
            .updateData([
                "postsCount": FieldValue.increment(Int64(-1)),
                "updatedAt": Date()
            ])
        
        // Update local cache — match on firebaseId (Firestore doc ID), not the local UUID
        posts.removeAll { $0.firebaseId == postId }
        updateCategoryArrays()
    }
    
    // MARK: - Interactions (with Optimistic Updates)
    
    /// Toggle "Amen" on a post with INSTANT optimistic update
    func toggleAmen(postId: String) async throws {
        dlog("🙏 Toggling Amen on post (INSTANT): \(postId)")
        
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
                    dlog("✅ Amen added to Firestore")
                    
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
                    dlog("✅ Amen removed from Firestore")
                }
            } catch {
                dlog("❌ Failed to update amen in Firestore: \(error)")
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
        dlog("💬 Incrementing comment count (INSTANT) for post: \(postId)")
        
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
                
                dlog("✅ Comment count updated in Firestore")
                
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
                dlog("❌ Failed to update comment count: \(error)")
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
        dlog("🔄 Reposting post (INSTANT): \(originalPostId)")
        
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
        let _repostDb = db
        Task(priority: .userInitiated) { @MainActor in
            do {
                // Try to fetch original post from Firestore
                let originalPostDoc = try await _repostDb.collection(FirebaseManager.CollectionPath.posts)
                    .document(originalPostId)
                    .getDocument()
                
                guard originalPostDoc.exists,
                      let originalPost = try? originalPostDoc.data(as: FirestorePost.self) else {
                    dlog("⚠️ Original post not found: \(originalPostId)")
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
                
                _ = try _repostDb.collection(FirebaseManager.CollectionPath.posts).addDocument(from: repost)
                
                // Increment repost count on original
                try? await _repostDb.collection(FirebaseManager.CollectionPath.posts)
                    .document(originalPostId)
                    .updateData([
                        "repostCount": FieldValue.increment(Int64(1)),
                        "updatedAt": Date()
                    ])
                
                // Update user's post count
                try await _repostDb.collection(FirebaseManager.CollectionPath.users)
                    .document(userId)
                    .updateData([
                        "postsCount": FieldValue.increment(Int64(1)),
                        "updatedAt": Date()
                    ])
                
                dlog("✅ Post reposted successfully")
                
            } catch {
                dlog("❌ Failed to repost: \(error)")
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
            dlog("❌ Error checking amen status: \(error)")
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
            dlog("❌ Error checking lightbulb status: \(error)")
            return false
        }
    }
    
    /// Toggle lightbulb (like) on a post - FULL FIREBASE IMPLEMENTATION
    func toggleLightbulb(postId: String) async throws {
        dlog("💡 Toggling lightbulb on post: \(postId)")
        
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
            dlog("💡 Lightbulb removed")
        } else {
            // Add lightbulb
            lightbulbUserIds.append(userId)
            try await postRef.updateData([
                "lightbulbCount": FieldValue.increment(Int64(1)),
                "lightbulbUserIds": lightbulbUserIds,
                "updatedAt": Date()
            ])
            dlog("💡 Lightbulb lit!")
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
    
    // MARK: - P0 FIX: Deduplication & Sorting
    
    /// Deduplicate posts array using firebaseId or UUID
    private func deduplicatePosts(_ posts: [Post]) -> [Post] {
        var seen = Set<String>()
        return posts.filter { post in
            let key = post.firebaseId ?? post.id.uuidString
            let isNew = seen.insert(key).inserted
            if !isNew {
                dlog("⚠️ [DEDUP] Filtered duplicate post: \(key)")
            }
            return isNew
        }
    }
    
    /// Deduplicate and sort posts by createdAt (newest first)
    private func deduplicateAndSort(_ posts: [Post]) -> [Post] {
        let deduplicated = deduplicatePosts(posts)
        return deduplicated.sorted { $0.createdAt > $1.createdAt }
    }
    
    // MARK: - User-Specific Posts (for Profile View)
    
    /// Fetch original posts created by a specific user (excluding reposts)
    /// Supports fallback query if composite index is missing
    func fetchUserOriginalPosts(userId: String, useFallback: Bool = false) async throws -> [Post] {
        dlog("📥 Fetching original posts for user: \(userId)")
        
        do {
            let snapshot: QuerySnapshot
            
            if useFallback {
                // 🔄 FALLBACK: Simple query without isRepost filter (no composite index needed)
                dlog("⚠️ Using fallback query (filtering isRepost in memory)")
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
            dlog("📊 Firestore query returned \(snapshot.documents.count) documents")
            
            if snapshot.documents.isEmpty {
                dlog("⚠️ No documents found. Possible reasons:")
                dlog("   1. User hasn't created any posts")
                dlog("   2. All posts by this user are reposts (isRepost=true)")
                dlog("   3. Posts exist but authorId doesn't match '\(userId)'")
                if !useFallback {
                    dlog("   4. Firestore composite index not created (try useFallback=true)")
                }
            }
            
            // Debug: Log first few documents
            for (index, doc) in snapshot.documents.prefix(3).enumerated() {
                let data = doc.data()
                dlog("   📄 Document \(index + 1):")
                dlog("      - ID: \(doc.documentID)")
                dlog("      - authorId: \(data["authorId"] as? String ?? "nil")")
                dlog("      - category: \(data["category"] as? String ?? "nil")")
                dlog("      - isRepost: \(data["isRepost"] as? Bool ?? false)")
                dlog("      - content: \((data["content"] as? String ?? "").prefix(50))...")
            }
            
            var firestorePosts = try snapshot.documents.compactMap { try $0.data(as: FirestorePost.self) }
            
            // If using fallback, filter out reposts in memory
            if useFallback {
                let beforeFilter = firestorePosts.count
                firestorePosts = firestorePosts.filter { !$0.isRepost }
                dlog("🔄 Filtered \(beforeFilter - firestorePosts.count) reposts in memory")
            }
            
            let userPosts = firestorePosts.map { $0.toPost() }
            
            // Category breakdown
            let categoryBreakdown = userPosts.reduce(into: [Post.PostCategory: Int]()) { counts, post in
                counts[post.category, default: 0] += 1
            }
            
            dlog("✅ Fetched \(userPosts.count) original posts for user")
            if !categoryBreakdown.isEmpty {
                dlog("📊 Category breakdown:")
                categoryBreakdown.forEach { category, count in
                    dlog("   - \(category): \(count)")
                }
            }
            
            return userPosts
            
        } catch {
            dlog("❌ Error fetching user posts: \(error)")
            
            // Check if it's an index error
            if let firestoreError = error as NSError?,
               firestoreError.domain == "FIRFirestoreErrorDomain",
               firestoreError.code == 9 { // FAILED_PRECONDITION
                dlog("⚠️ FIRESTORE INDEX REQUIRED!")
                dlog("   Create a composite index for:")
                dlog("   Collection: posts")
                dlog("   Fields: authorId (Ascending), isRepost (Ascending), createdAt (Descending)")
                dlog("")
                dlog("   OR you can use the fallback query:")
                dlog("   try await fetchUserOriginalPosts(userId: userId, useFallback: true)")
                
                // Automatically retry with fallback if not already using it
                if !useFallback {
                    dlog("🔄 Automatically retrying with fallback query...")
                    return try await fetchUserOriginalPosts(userId: userId, useFallback: true)
                }
            }
            
            throw error
        }
    }
    
    /// Fetch reposts by a specific user
    func fetchUserReposts(userId: String) async throws -> [Post] {
        dlog("📥 Fetching reposts for user: \(userId)")
        
        // ✅ Optimized query using composite index (authorId + isRepost + createdAt)
        let query = db.collection(FirebaseManager.CollectionPath.posts)
            .whereField("authorId", isEqualTo: userId)
            .whereField("isRepost", isEqualTo: true)
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
        
        let snapshot = try await query.getDocuments()
        let firestorePosts = try snapshot.documents.compactMap { try $0.data(as: FirestorePost.self) }
        let reposts = firestorePosts.map { $0.toPost() }
        
        dlog("✅ Fetched \(reposts.count) reposts for user")
        return reposts
    }
    
    /// Fetch saved posts for a specific user
    func fetchUserSavedPosts(userId: String) async throws -> [Post] {
        dlog("📥 Fetching saved posts for user: \(userId)")
        
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
            dlog("✅ No saved posts found")
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
        
        dlog("✅ Fetched \(allSavedPosts.count) saved posts for user")
        return allSavedPosts
    }
    
    /// Fetch comments/replies made by a specific user
    func fetchUserReplies(userId: String) async throws -> [Comment] {
        dlog("📥 Fetching replies for user: \(userId)")
        
        // ✅ Optimized query using composite index (authorId + createdAt)
        let query = db.collection(FirebaseManager.CollectionPath.comments)
            .whereField("authorId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
        
        let snapshot = try await query.getDocuments()
        let comments = try snapshot.documents.compactMap { try $0.data(as: Comment.self) }
        
        dlog("✅ Fetched \(comments.count) replies for user")
        return comments
    }
    
    // MARK: - Admin/Development Functions
    
    /// ⚠️ DANGER: Delete ALL posts from Firestore (for development/testing only)
    /// This will permanently delete all posts in the database
    func deleteAllPosts() async throws {
        dlog("🗑️ ⚠️ DELETING ALL POSTS FROM FIRESTORE...")
        
        let snapshot = try await db.collection(FirebaseManager.CollectionPath.posts).getDocuments()
        
        dlog("⚠️ Found \(snapshot.documents.count) posts to delete")
        
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
                dlog("✅ Deleted batch of 500 posts")
            }
        }
        
        // Commit remaining deletes
        if count > 0 {
            try await batch.commit()
            dlog("✅ Deleted final batch of \(count) posts")
        }
        
        dlog("✅ ALL POSTS DELETED")
        
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
        dlog("🗑️ Deleting posts by author: \(authorName)")
        
        let snapshot = try await db.collection(FirebaseManager.CollectionPath.posts)
            .whereField("authorName", isEqualTo: authorName)
            .getDocuments()
        
        dlog("⚠️ Found \(snapshot.documents.count) posts to delete for \(authorName)")
        
        let batch = db.batch()
        for document in snapshot.documents {
            batch.deleteDocument(document.reference)
        }
        
        try await batch.commit()
        dlog("✅ Deleted all posts by \(authorName)")
    }
    
    /// Delete multiple fake users' posts at once
    func deleteFakePosts() async throws {
        dlog("🗑️ Deleting all fake sample data posts...")
        
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
                    
                    dlog("✅ Deleted \(snapshot.documents.count) posts by \(fakeName)")
                    totalDeleted += snapshot.documents.count
                }
            } catch {
                dlog("⚠️ Error deleting posts for \(fakeName): \(error)")
            }
        }
        
        dlog("✅ TOTAL FAKE POSTS DELETED: \(totalDeleted)")
        
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
        dlog("🔄 Starting migration to add profile images to all posts...")
        
        let db = Firestore.firestore()
        
        // Fetch all posts
        let snapshot = try await db.collection(FirebaseManager.CollectionPath.posts)
            .getDocuments()
        
        dlog("📊 Found \(snapshot.documents.count) posts to migrate")
        
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
                    dlog("⚠️ No profile image for user \(authorId), skipping \(posts.count) posts")
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
                
                dlog("✅ Updated \(posts.count) posts for user \(authorId)")
                
            } catch {
                dlog("⚠️ Failed to update posts for user \(authorId): \(error)")
                skipped += posts.count
            }
        }
        
        dlog("✅ Migration complete! Updated: \(updated), Skipped: \(skipped)")
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
        
        // Deterministic ID: amen_{postId}_{fromUserId} — overwrites on re-trigger
        let deterministicId = "amen_\(postId)_\(fromUserId)"
        try await db.collection("notifications").document(deterministicId).setData(notification, merge: false)
        dlog("✅ Amen notification created")
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
        
        // Deterministic ID: comment_{postId}_{fromUserId}
        // One notification per user per post; if they comment again the notification is refreshed
        // (keeping the feed clean) rather than adding duplicates.
        let deterministicId = "comment_\(postId)_\(fromUserId)"
        try await db.collection("notifications").document(deterministicId).setData(notification, merge: false)
        dlog("✅ Comment notification created")
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
            
            // Deterministic ID: mention_{postId}_{fromUserId}_{mentionedUserId}
            let deterministicId = "mention_\(postId)_\(fromUserId)_\(mentionedUserId)"
            try await db.collection("notifications").document(deterministicId).setData(notification, merge: false)
            dlog("✅ Mention notification created for @\(mentionedUsername)")
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


