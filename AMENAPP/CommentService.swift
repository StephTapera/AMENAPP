//
//  CommentService.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//
//  Service for managing comments and replies on posts
//  Using Realtime Database for instant sync and accurate counts
//

import Foundation
import FirebaseDatabase
import FirebaseAuth
import FirebaseFirestore
import Combine
import UIKit

// MARK: - Comment Service

@MainActor
class CommentService: ObservableObject {
    static let shared = CommentService()
    
    @Published var comments: [String: [Comment]] = [:]  // postId -> comments
    @Published var commentReplies: [String: [Comment]] = [:]  // commentId -> replies
    @Published var isLoading = false
    @Published var error: String?
    
    private let firebaseManager = FirebaseManager.shared
    private let userService = UserService()
    private let database = Database.database()
    private var ref: DatabaseReference {
        database.reference()
    }
    private var listeners: [DatabaseHandle] = []
    private var listenerPaths: [String: DatabaseHandle] = [:]
    
    private init() {}
    
    // MARK: - Comment Permissions
    
    /// Check if user can comment on a post
    func canComment(postId: String, post: Post) async -> Bool {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return false
        }
        
        // Post author can always comment
        if post.authorId == currentUserId {
            return true
        }
        
        // Check comment permissions
        let permissions = post.commentPermissions ?? .everyone
        
        switch permissions {
        case .everyone:
            return true
            
        case .following:
            // Check if post author follows current user
            return await FollowService.shared.isFollowing(userId: post.authorId)
            
        case .mentioned:
            // Check if user is mentioned in the post
            // Extract mentions from post content
            let mentions = extractMentions(from: post.content)
            return mentions.contains { mention in
                mention.lowercased() == "@\(currentUserId.lowercased())"
            }
            
        case .off:
            return false
        }
    }
    
    private func extractMentions(from text: String) -> [String] {
        let pattern = "@[a-zA-Z0-9_]+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        
        return matches.compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range])
        }
    }
    
    // MARK: - Create Comment
    
    /// Add a comment to a post
    func addComment(
        postId: String,
        content: String,
        mentionedUserIds: [String]? = nil
    ) async throws -> Comment {
        print("💬 Adding comment to post: \(postId)")
        
        guard let userId = firebaseManager.currentUser?.uid else {
            throw NSError(domain: "CommentService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        // ============================================================================
        // ✅ STEP 1: AI CONTENT MODERATION
        // ============================================================================
        print("🛡️ Running AI moderation check for comment...")
        let moderationResult = try await ContentModerationService.shared.moderateContent(
            content,
            type: .comment,
            userId: userId
        )
        
        // Block comment if moderation fails
        if !moderationResult.isApproved {
            let reasons = moderationResult.flaggedReasons
            print("❌ Comment blocked by moderation: \(reasons.joined(separator: ", "))")
            
            // Show liquid glass toast notification
            await MainActor.run {
                ModerationToastManager.shared.show(reasons: reasons)
            }
            
            throw NSError(
                domain: "CommentService",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Content flagged"]
            )
        }
        
        print("✅ Comment passed moderation check")
        
        // ✅ Fetch user data (username AND profile image) BEFORE adding comment
        let authorUsername: String
        let authorProfileImageURL: String?
        do {
            let userProfile = try await userService.fetchUserProfile(userId: userId)
            authorUsername = userProfile.username
            authorProfileImageURL = userProfile.profileImageURL
            print("✅ Using username: @\(authorUsername)")
            print("✅ Profile image URL: \(authorProfileImageURL ?? "none")")
        } catch {
            print("⚠️ Failed to fetch user profile, generating fallback")
            authorUsername = "user\(userId.prefix(8))"
            authorProfileImageURL = nil
        }
        
        // ✅ Add comment to PostInteractionsService with profile image URL
        let interactionsService = PostInteractionsService.shared
        let commentId = try await interactionsService.addComment(
            postId: postId,
            content: content,
            authorInitials: firebaseManager.currentUser?.displayName?.prefix(2).uppercased() ?? "??",
            authorUsername: authorUsername,
            authorProfileImageURL: authorProfileImageURL  // ← NEW PARAMETER
        )
        
        print("✅ Comment created with ID: \(commentId)")
        
        // ✅ DON'T manually update local cache - let real-time listener handle it
        // This prevents duplicate comments in the UI
        
        // Haptic feedback
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        
        // Return a temporary comment object (won't be used by UI due to listener)
        let comment = Comment(
            id: commentId,
            postId: postId,
            authorId: userId,
            authorName: firebaseManager.currentUser?.displayName ?? "Unknown User",
            authorUsername: authorUsername,
            authorInitials: firebaseManager.currentUser?.displayName?.prefix(2).uppercased() ?? "??",
            authorProfileImageURL: authorProfileImageURL,
            content: content,
            createdAt: Date(),
            updatedAt: Date(),
            amenCount: 0,
            replyCount: 0,
            amenUserIds: [],
            parentCommentId: nil,
            mentionedUserIds: mentionedUserIds
        )
        
        print("✅ Comment will be added to UI via real-time listener")
        
        // 📧 Send mention notifications (extract mentions from content)
        let mentionUsernames = extractMentionUsernames(from: content)
        if !mentionUsernames.isEmpty {
            Task {
                var mentions: [MentionedUser] = []
                
                // Fetch user data for each mentioned username
                for username in mentionUsernames {
                    do {
                        let userQuery = try await firebaseManager.firestore
                            .collection("users")
                            .whereField("username", isEqualTo: username)
                            .limit(to: 1)
                            .getDocuments()
                        
                        if let userDoc = userQuery.documents.first {
                            let mentionUserId = userDoc.documentID
                            let displayName = userDoc.data()["displayName"] as? String ?? username
                            mentions.append(MentionedUser(
                                userId: mentionUserId,
                                username: username,
                                displayName: displayName
                            ))
                        }
                    } catch {
                        print("⚠️ Failed to resolve @\(username): \(error)")
                    }
                }
                
                // Send notifications
                if !mentions.isEmpty {
                    await NotificationService.shared.sendMentionNotifications(
                        mentions: mentions,
                        actorId: userId,
                        actorName: firebaseManager.currentUser?.displayName ?? "User",
                        actorUsername: authorUsername,
                        postId: postId,
                        contentType: "comment"
                    )
                }
            }
        }
        
        // ✅ Post notification so ProfileView can update Replies tab
        NotificationCenter.default.post(
            name: Notification.Name("newCommentCreated"),
            object: nil,
            userInfo: ["comment": comment]
        )
        print("📬 Posted newCommentCreated notification for ProfileView")
        
        return comment
    }
    
    // MARK: - Helper: Extract Mentions
    
    private func extractMentionUsernames(from text: String) -> [String] {
        let pattern = "@(\\w+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }
        
        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        
        return matches.compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let usernameRange = match.range(at: 1)
            return nsString.substring(with: usernameRange)
        }
    }
    
    // MARK: - Create Reply
    
    /// Add a reply to a comment (stored as a comment with parentCommentId in Realtime DB)
    func addReply(
        postId: String,
        parentCommentId: String,
        content: String,
        mentionedUserIds: [String]? = nil
    ) async throws -> Comment {
        print("↩️ Adding reply to comment: \(parentCommentId)")
        
        // ✅ Add comment first (moderation happens inside addComment)
        let comment = try await addComment(postId: postId, content: content, mentionedUserIds: mentionedUserIds)
        
        // Update to mark it as a reply
        let commentRef = ref.child("postInteractions").child(postId).child("comments").child(comment.id ?? "")
        try await commentRef.child("parentCommentId").setValue(parentCommentId)
        
        // ✅ Don't manually update reply cache; real-time listener will update
        var updatedComment = comment
        updatedComment.parentCommentId = parentCommentId
        
        print("✅ Reply added")
        
        // ✅ Post notification so ProfileView can update Replies tab
        NotificationCenter.default.post(
            name: Notification.Name("newCommentCreated"),
            object: nil,
            userInfo: ["comment": updatedComment]
        )
        print("📬 Posted newCommentCreated notification for reply")
        
        // Haptic feedback
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
        
        return updatedComment
    }
    
    // MARK: - Fetch Comments
    
    /// Fetch all comments for a post from Realtime Database
    func fetchComments(for postId: String) async throws -> [Comment] {
        print("📥 Fetching comments for post: \(postId)")
        print("🔍 [DEBUG] Querying path: postInteractions/\(postId)/comments")
        
        isLoading = true
        defer { isLoading = false }
        
        let interactionsService = PostInteractionsService.shared
        let realtimeComments = try await interactionsService.getComments(postId: postId)
        print("🔍 [DEBUG] Raw query returned \(realtimeComments.count) comments from RTDB")
        
        // Convert to Comment objects and filter out replies (only get top-level comments)
        var fetchedComments: [Comment] = []
        
        for rtComment in realtimeComments {
            // ✅ Skip replies (these are handled separately)
            guard rtComment.parentCommentId == nil else {
                print("⏭️ Skipping reply: \(rtComment.id)")
                continue
            }
            
            // ✅ Use stored username and profile image from RTDB
            let authorUsername: String
            let authorProfileImageURL: String?
            
            if let storedUsername = rtComment.authorUsername, !storedUsername.isEmpty {
                authorUsername = storedUsername
                print("✅ Using stored username: @\(authorUsername)")
            } else {
                print("⚠️ No stored username, using fallback")
                authorUsername = "user\(rtComment.authorId.prefix(8))"
            }
            
            // ✅ Get profile image URL from RTDB
            authorProfileImageURL = rtComment.authorProfileImageURL
            if let imageURL = authorProfileImageURL {
                print("✅ Profile image URL: \(imageURL)")
            }
            
            let comment = Comment(
                id: rtComment.id,
                postId: postId,
                authorId: rtComment.authorId,
                authorName: rtComment.authorName,
                authorUsername: authorUsername,
                authorInitials: rtComment.authorInitials,
                authorProfileImageURL: authorProfileImageURL,  // ✅ Now includes profile image
                content: rtComment.content,
                createdAt: rtComment.timestamp,
                updatedAt: rtComment.timestamp,
                amenCount: rtComment.likes,
                replyCount: 0,
                amenUserIds: [],
                parentCommentId: nil,
                mentionedUserIds: nil
            )
            
            fetchedComments.append(comment)
        }
        
        print("✅ Fetched \(fetchedComments.count) top-level comments from Realtime DB")
        
        // Update local cache
        comments[postId] = fetchedComments
        
        return fetchedComments
    }
    
    /// Fetch replies for a specific comment
    func fetchReplies(for commentId: String) async throws -> [Comment] {
        print("📥 Fetching replies for comment: \(commentId)")
        
        // ✅ FIXED: First check cache (populated by real-time listener)
        if let cachedReplies = commentReplies[commentId], !cachedReplies.isEmpty {
            print("✅ Returning \(cachedReplies.count) cached replies for comment: \(commentId)")
            return cachedReplies
        }
        
        // ✅ If cache is empty, fetch from database
        // This happens when the real-time listener hasn't populated the cache yet
        // or when loading historical data
        print("⚠️ No cached replies, fetching from database for comment: \(commentId)")
        
        // We need to find which post this comment belongs to
        // Search through all cached posts' comments to find the parent
        var parentPostId: String?
        for (postId, postComments) in comments {
            if postComments.contains(where: { $0.id == commentId }) {
                parentPostId = postId
                break
            }
        }
        
        guard let postId = parentPostId else {
            print("⚠️ Could not find post for comment: \(commentId)")
            return []
        }
        
        // Fetch all comments for the post and filter replies
        let interactionsService = PostInteractionsService.shared
        let allComments = try await interactionsService.getComments(postId: postId)
        
        var replies: [Comment] = []
        for rtComment in allComments {
            // Only get replies for this specific comment
            guard rtComment.parentCommentId == commentId else { continue }
            
            let authorUsername: String
            let authorProfileImageURL: String?
            
            if let storedUsername = rtComment.authorUsername, !storedUsername.isEmpty {
                authorUsername = storedUsername
            } else {
                authorUsername = "user\(rtComment.authorId.prefix(8))"
            }
            
            authorProfileImageURL = rtComment.authorProfileImageURL
            
            let reply = Comment(
                id: rtComment.id,
                postId: postId,
                authorId: rtComment.authorId,
                authorName: rtComment.authorName,
                authorUsername: authorUsername,
                authorInitials: rtComment.authorInitials,
                authorProfileImageURL: authorProfileImageURL,
                content: rtComment.content,
                createdAt: rtComment.timestamp,
                updatedAt: rtComment.timestamp,
                amenCount: rtComment.likes,
                replyCount: 0,
                amenUserIds: [],
                parentCommentId: rtComment.parentCommentId,
                mentionedUserIds: nil
            )
            
            replies.append(reply)
        }
        
        // Sort by timestamp
        replies.sort { $0.createdAt < $1.createdAt }
        
        // Update cache
        commentReplies[commentId] = replies
        
        print("✅ Fetched \(replies.count) replies from database for comment: \(commentId)")
        return replies
    }
    
    /// Fetch all comments by a specific user
    func fetchUserComments(userId: String, limit: Int = 50) async throws -> [Comment] {
        print("📥 Fetching comments for user: \(userId)")
        
        // Would need to query across all posts - not implemented yet
        return []
    }
    
    /// Fetch comments with nested replies
    func fetchCommentsWithReplies(for postId: String) async throws -> [CommentWithReplies] {
        print("📥 Fetching comments with replies for post: \(postId)")
        
        // ✅ IMPROVED: Check if real-time listener has already populated the cache
        if let cachedComments = comments[postId], !cachedComments.isEmpty {
            print("✅ Using cached comments from real-time listener (\(cachedComments.count) comments)")
            
            var commentsWithReplies: [CommentWithReplies] = []
            
            for comment in cachedComments {
                guard let commentId = comment.id else { continue }
                
                // Get replies from cache (populated by real-time listener)
                let replies = commentReplies[commentId] ?? []
                
                var updatedComment = comment
                updatedComment.replyCount = replies.count
                
                let commentWithReplies = CommentWithReplies(comment: updatedComment, replies: replies)
                commentsWithReplies.append(commentWithReplies)
            }
            
            print("✅ Built \(commentsWithReplies.count) comments with replies from cache")
            return commentsWithReplies
        }
        
        // ✅ If cache is empty, fetch from database (happens on initial load before listener fires)
        print("⚠️ Cache empty, fetching comments from database")
        
        // Fetch top-level comments
        let topLevelComments = try await fetchComments(for: postId)
        
        // For each comment, fetch its replies
        var commentsWithReplies: [CommentWithReplies] = []
        
        for comment in topLevelComments {
            guard let commentId = comment.id else { continue }
            
            let replies = try await fetchReplies(for: commentId)
            
            var updatedComment = comment
            updatedComment.replyCount = replies.count
            
            let commentWithReplies = CommentWithReplies(comment: updatedComment, replies: replies)
            commentsWithReplies.append(commentWithReplies)
        }
        
        print("✅ Fetched \(commentsWithReplies.count) comments with replies from database")
        
        return commentsWithReplies
    }
    
    // MARK: - Update Comment
    
    /// Edit comment content
    func editComment(commentId: String, postId: String, newContent: String) async throws {
        print("✏️ Editing comment: \(commentId)")
        
        guard !newContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "CommentService", code: -3, userInfo: [NSLocalizedDescriptionKey: "Comment cannot be empty"])
        }
        
        guard let userId = firebaseManager.currentUser?.uid else {
            throw NSError(domain: "CommentService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let commentRef = ref.child("postInteractions").child(postId).child("comments").child(commentId)
        
        // Verify ownership
        let snapshot = try await commentRef.getData()
        guard let commentData = snapshot.value as? [String: Any],
              let authorId = commentData["authorId"] as? String,
              authorId == userId else {
            throw NSError(domain: "CommentService", code: -4, userInfo: [NSLocalizedDescriptionKey: "You can only edit your own comments"])
        }
        
        // Update content and timestamp
        let updates: [String: Any] = [
            "content": newContent,
            "updatedAt": Int64(Date().timeIntervalSince1970 * 1000),
            "isEdited": true
        ]
        
        try await commentRef.updateChildValues(updates)
        
        print("✅ Comment edited successfully")
        
        // Update local cache
        if var postComments = comments[postId] {
            if let index = postComments.firstIndex(where: { $0.id == commentId }) {
                var updatedComment = postComments[index]
                updatedComment.content = newContent
                updatedComment.updatedAt = Date()
                postComments[index] = updatedComment
                comments[postId] = postComments
            }
        }
    }
    
    /// Delete comment
    func deleteComment(commentId: String, postId: String) async throws {
        print("🗑️ Deleting comment: \(commentId)")
        
        guard let userId = firebaseManager.currentUser?.uid else {
            throw NSError(domain: "CommentService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let commentRef = ref.child("postInteractions").child(postId).child("comments").child(commentId)
        
        // Verify ownership
        let snapshot = try await commentRef.getData()
        guard let commentData = snapshot.value as? [String: Any],
              let authorId = commentData["authorId"] as? String,
              authorId == userId else {
            throw NSError(domain: "CommentService", code: -4, userInfo: [NSLocalizedDescriptionKey: "You can only delete your own comments"])
        }
        
        // Remove the comment
        try await commentRef.removeValue()
        
        // Decrement comment count on the post
        let interactionsService = PostInteractionsService.shared
        let countRef = ref.child("postInteractions").child(postId).child("commentCount")
        try await countRef.runTransactionBlock { currentData in
            if let currentCount = currentData.value as? Int {
                currentData.value = max(0, currentCount - 1)
            } else {
                currentData.value = 0
            }
            return TransactionResult.success(withValue: currentData)
        }
        
        print("✅ Comment deleted successfully")
        
        // Update local cache
        if var postComments = comments[postId] {
            postComments.removeAll { $0.id == commentId }
            comments[postId] = postComments
        }
        
        // Also remove from replies cache
        commentReplies.removeValue(forKey: commentId)
    }
    
    // MARK: - Interactions
    
    /// Toggle "Amen" (or lightbulb) on a comment
    /// - Parameters:
    ///   - commentId: The comment ID to toggle
    ///   - postId: The post ID (required for direct Firebase access)
    func toggleAmen(commentId: String, postId: String) async throws {
        print("🙏 Toggling Amen on comment: \(commentId) in post: \(postId)")
        
        guard let userId = firebaseManager.currentUser?.uid else {
            throw NSError(domain: "CommentService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        // Reference to the comment's like status
        let commentRef = ref.child("postInteractions").child(postId).child("comments").child(commentId)
        let userLikeRef = commentRef.child("likedBy").child(userId)
        let likesCountRef = commentRef.child("likes")
        
        // Check current like status
        let snapshot = try await userLikeRef.getData()
        let hasLiked = snapshot.exists()
        
        // Toggle like status
        if hasLiked {
            // Remove like
            try await userLikeRef.removeValue()
            
            // Decrement count (use transaction for accuracy)
            try await likesCountRef.runTransactionBlock { currentData in
                if let currentCount = currentData.value as? Int {
                    currentData.value = max(0, currentCount - 1)
                } else {
                    currentData.value = 0
                }
                return TransactionResult.success(withValue: currentData)
            }
            
            print("✅ Removed amen from comment")
        } else {
            // Add like
            try await userLikeRef.setValue(true)
            
            // Increment count (use transaction for accuracy)
            try await likesCountRef.runTransactionBlock { currentData in
                if let currentCount = currentData.value as? Int {
                    currentData.value = currentCount + 1
                } else {
                    currentData.value = 1
                }
                return TransactionResult.success(withValue: currentData)
            }
            
            print("✅ Added amen to comment")
        }
        
        // Haptic feedback
        await MainActor.run {
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
        }
    }
    
    // MARK: - Real-time Listeners
    
    /// Start listening to comments for a post in Realtime Database
    func startListening(to postId: String) {
        // ✅ Prevent duplicate listeners
        if listenerPaths[postId] != nil {
            print("⚠️ Already listening to post: \(postId)")
            return
        }
        
        print("🔊 Starting real-time listener for comments on post: \(postId)")
        
        let commentsRef = ref.child("postInteractions").child(postId).child("comments")
        
        // ✅ CRITICAL FIX: Keep data synced locally even when app is offline
        // This ensures cached data persists across app restarts
        commentsRef.keepSynced(true)
        
        let handle = commentsRef.observe(.value) { [weak self] snapshot in
            guard let self = self else { return }
            
            Task { @MainActor in
                print("📥 [LISTENER] Real-time data received for post: \(postId)")
                print("   Snapshot exists: \(snapshot.exists())")
                print("   Children count: \(snapshot.childrenCount)")
                
                // ✅ Check if this data came from cache (offline) or server
                if let metadata = snapshot.value as? [String: Any] {
                    print("   Data source: \(metadata.keys.count) comment(s)")
                } else if snapshot.exists() {
                    print("   Data source: Has data but not a dictionary")
                } else {
                    print("   Data source: Empty snapshot (no comments)")
                }
                
                var fetchedComments: [Comment] = []
                var repliesMap: [String: [Comment]] = [:]
                
                for child in snapshot.children {
                    guard let childSnapshot = child as? DataSnapshot,
                          let commentData = childSnapshot.value as? [String: Any],
                          let authorId = commentData["authorId"] as? String,
                          let authorName = commentData["authorName"] as? String,
                          let authorInitials = commentData["authorInitials"] as? String,
                          let content = commentData["content"] as? String,
                          let timestamp = commentData["timestamp"] as? Int64 else {
                        continue
                    }
                    
                    // ✅ Get username and profile image from RTDB (stored during comment creation)
                    let authorUsername: String
                    let authorProfileImageURL: String?
                    
                    if let storedUsername = commentData["authorUsername"] as? String, !storedUsername.isEmpty {
                        authorUsername = storedUsername
                        print("✅ Using stored username: @\(authorUsername)")
                    } else {
                        // Fallback for old comments without username
                        authorUsername = "user\(authorId.prefix(8))"
                        print("⚠️ No stored username, using fallback: @\(authorUsername)")
                    }
                    
                    // ✅ Get profile image URL from RTDB
                    authorProfileImageURL = commentData["authorProfileImageURL"] as? String
                    if let imageURL = authorProfileImageURL {
                        print("✅ Profile image URL found: \(imageURL)")
                    }
                    
                    let comment = Comment(
                        id: childSnapshot.key,
                        postId: postId,
                        authorId: authorId,
                        authorName: authorName,
                        authorUsername: authorUsername,
                        authorInitials: authorInitials,
                        authorProfileImageURL: authorProfileImageURL,  // ✅ Now includes profile image
                        content: content,
                        createdAt: Date(timeIntervalSince1970: Double(timestamp) / 1000.0),
                        updatedAt: Date(timeIntervalSince1970: Double(timestamp) / 1000.0),
                        amenCount: commentData["likes"] as? Int ?? 0,
                        replyCount: 0,
                        amenUserIds: [],
                        parentCommentId: commentData["parentCommentId"] as? String,
                        mentionedUserIds: nil
                    )
                    
                    fetchedComments.append(comment)
                }
                
                // Sort by timestamp
                fetchedComments.sort { $0.createdAt < $1.createdAt }
                
                // ✅ Separate top-level comments and replies
                let topLevelComments = fetchedComments.filter { $0.parentCommentId == nil }
                let replies = fetchedComments.filter { $0.parentCommentId != nil }
                
                // ✅ Update cache ONCE with new data
                self.comments[postId] = topLevelComments
                
                // ✅ Clear and rebuild replies map
                for reply in replies {
                    guard let parentId = reply.parentCommentId else { continue }
                    
                    if repliesMap[parentId] != nil {
                        repliesMap[parentId]?.append(reply)
                    } else {
                        repliesMap[parentId] = [reply]
                    }
                }
                
                // ✅ Sort replies by timestamp within each parent
                for (parentId, var replies) in repliesMap {
                    replies.sort { $0.createdAt < $1.createdAt }
                    self.commentReplies[parentId] = replies
                }
                
                // ✅ Remove old replies that no longer exist
                let currentReplyParents = Set(replies.compactMap { $0.parentCommentId })
                let cachedReplyParents = Set(self.commentReplies.keys)
                for oldParent in cachedReplyParents where !currentReplyParents.contains(oldParent) {
                    self.commentReplies.removeValue(forKey: oldParent)
                }
                
                print("✅ Real-time update: \(topLevelComments.count) comments, \(replies.count) replies")
                
                // ✅ Post notification to immediately update UI
                NotificationCenter.default.post(
                    name: Notification.Name("commentsUpdated"),
                    object: nil,
                    userInfo: ["postId": postId]
                )
            }
        }
        
        listenerPaths[postId] = handle
    }
    
    /// Stop all listeners
    func stopListening() {
        print("🔇 Stopping all comment listeners...")
        
        for (postId, handle) in listenerPaths {
            ref.child("postInteractions").child(postId).child("comments").removeObserver(withHandle: handle)
        }
        
        listenerPaths.removeAll()
    }
    
    // MARK: - Helper Methods
    
    /// Check if user has amened a comment
    /// - Parameters:
    ///   - commentId: The comment ID to check
    ///   - postId: The post ID (required since cache might not be populated yet)
    func hasUserAmened(commentId: String, postId: String) async -> Bool {
        guard let userId = firebaseManager.currentUser?.uid else { return false }
        
        let userLikeRef = ref.child("postInteractions").child(postId).child("comments").child(commentId).child("likedBy").child(userId)
        
        do {
            let snapshot = try await userLikeRef.getData()
            let hasLiked = snapshot.exists()
            print("✅ hasUserAmened check - commentId: \(commentId), postId: \(postId), result: \(hasLiked)")
            return hasLiked
        } catch {
            print("❌ Error checking amen status: \(error)")
            return false
        }
    }
    
    // MARK: - Notifications (for compatibility)
    
    private func createCommentNotification(
        postId: String,
        commentId: String,
        postAuthorId: String,
        commenterName: String
    ) async throws {
        print("📬 Comment notification: skipped")
    }
    
    private func createReplyNotification(
        postId: String,
        commentId: String,
        replyId: String,
        parentAuthorId: String,
        replierName: String
    ) async throws {
        print("📬 Reply notification: skipped")
    }
    
    private func createMentionNotification(
        postId: String,
        commentId: String,
        mentionedUserId: String,
        mentionerName: String
    ) async throws {
        print("📬 Mention notification: skipped")
    }
}
