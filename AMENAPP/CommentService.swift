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
        
        // ✅ NEW: Fetch username BEFORE adding comment
        let authorUsername: String
        do {
            let userProfile = try await userService.fetchUserProfile(userId: userId)
            authorUsername = userProfile.username
            print("✅ Using username: @\(authorUsername)")
        } catch {
            print("⚠️ Failed to fetch username, generating fallback from userId")
            // Fallback: use first 8 chars of userId
            authorUsername = "user\(userId.prefix(8))"
        }
        
        // ✅ UPDATED: Pass username to PostInteractionsService
        let interactionsService = PostInteractionsService.shared
        let commentId = try await interactionsService.addComment(
            postId: postId,
            content: content,
            authorInitials: firebaseManager.currentUser?.displayName?.prefix(2).uppercased() ?? "??",
            authorUsername: authorUsername  // ← NEW PARAMETER
        )
        
        print("✅ Comment created with ID: \(commentId)")
        
        // Fetch the comment we just created
        let commentRef = ref.child("postInteractions").child(postId).child("comments").child(commentId)
        let snapshot = try await commentRef.getData()
        
        // Get comment data with fallback values
        let commentData = snapshot.value as? [String: Any] ?? [:]
        let currentUserName = firebaseManager.currentUser?.displayName ?? "Unknown User"
        let authorName = commentData["authorName"] as? String ?? currentUserName
        let authorInitials = commentData["authorInitials"] as? String ?? currentUserName.prefix(2).uppercased()
        let timestamp = commentData["timestamp"] as? Int64 ?? Int64(Date().timeIntervalSince1970 * 1000)
        
        // ✅ REMOVED: No longer need to fetch username here - we already have it
        
        // Verify we have the essential data
        if commentData.isEmpty {
            print("⚠️ Warning: Comment data is empty, using fallback values")
        }
        
        // Create Comment object
        let comment = Comment(
            id: commentId,
            postId: postId,
            authorId: userId,
            authorName: authorName,
            authorUsername: authorUsername,  // ✅ Use the username we already fetched
            authorInitials: String(authorInitials),
            authorProfileImageURL: nil,
            content: content,
            createdAt: Date(timeIntervalSince1970: Double(timestamp) / 1000.0),
            updatedAt: Date(timeIntervalSince1970: Double(timestamp) / 1000.0),
            amenCount: 0,
            replyCount: 0,
            amenUserIds: [],
            parentCommentId: nil,
            mentionedUserIds: mentionedUserIds
        )
        
        // Haptic feedback
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        
        // Update local cache
        if var postComments = comments[postId] {
            postComments.append(comment)
            comments[postId] = postComments.sorted { $0.createdAt < $1.createdAt }
        } else {
            comments[postId] = [comment]
        }
        
        print("✅ Comment added to local cache for post: \(postId)")
        print("📊 Current comment count: \(await interactionsService.getCommentCount(postId: postId))")
        
        return comment
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
        
        // Add comment first
        let comment = try await addComment(postId: postId, content: content, mentionedUserIds: mentionedUserIds)
        
        // Update to mark it as a reply
        let commentRef = ref.child("postInteractions").child(postId).child("comments").child(comment.id ?? "")
        try await commentRef.child("parentCommentId").setValue(parentCommentId)
        
        // Update local cache for replies
        var updatedComment = comment
        updatedComment.parentCommentId = parentCommentId
        
        if var replies = commentReplies[parentCommentId] {
            replies.append(updatedComment)
            commentReplies[parentCommentId] = replies.sorted { $0.createdAt < $1.createdAt }
        } else {
            commentReplies[parentCommentId] = [updatedComment]
        }
        
        print("✅ Reply added")
        
        // Haptic feedback
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
        
        return updatedComment
    }
    
    // MARK: - Fetch Comments
    
    /// Fetch all comments for a post from Realtime Database
    func fetchComments(for postId: String) async throws -> [Comment] {
        print("📥 Fetching comments for post: \(postId)")
        
        isLoading = true
        defer { isLoading = false }
        
        let interactionsService = PostInteractionsService.shared
        let realtimeComments = try await interactionsService.getComments(postId: postId)
        
        // Convert to Comment objects and filter out replies
        var fetchedComments: [Comment] = []
        
        for rtComment in realtimeComments {
            // ✅ NEW: Use username from RTDB if available, otherwise fetch or generate fallback
            let authorUsername: String
            if let storedUsername = rtComment.authorUsername, !storedUsername.isEmpty {
                authorUsername = storedUsername
                print("✅ Using stored username: @\(authorUsername)")
            } else {
                // Fallback: Try to fetch from Firestore for old comments
                do {
                    let user = try await userService.fetchUserProfile(userId: rtComment.authorId)
                    authorUsername = user.username
                    print("⚠️ Fetched username from Firestore (old comment): @\(authorUsername)")
                } catch {
                    print("⚠️ No stored username and fetch failed, using fallback")
                    authorUsername = "user\(rtComment.authorId.prefix(8))"
                }
            }
            
            let comment = Comment(
                id: rtComment.id,
                postId: postId,
                authorId: rtComment.authorId,
                authorName: rtComment.authorName,
                authorUsername: authorUsername,
                authorInitials: rtComment.authorInitials,
                authorProfileImageURL: nil,
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
        
        print("✅ Fetched \(fetchedComments.count) comments from Realtime DB")
        
        // Update local cache
        comments[postId] = fetchedComments
        
        return fetchedComments
    }
    
    /// Fetch replies for a specific comment
    func fetchReplies(for commentId: String) async throws -> [Comment] {
        print("📥 Fetching replies for comment: \(commentId)")
        
        // Get parent comment's post ID
        // Then filter comments with matching parentCommentId
        // For now, return cached replies
        return commentReplies[commentId] ?? []
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
        
        // Fetch top-level comments
        let topLevelComments = try await fetchComments(for: postId)
        
        // For each comment, fetch its replies
        var commentsWithReplies: [CommentWithReplies] = []
        
        for comment in topLevelComments {
            guard let commentId = comment.id else { continue }
            
            let replies = try await fetchReplies(for: commentId)
            let commentWithReplies = CommentWithReplies(comment: comment, replies: replies)
            commentsWithReplies.append(commentWithReplies)
        }
        
        print("✅ Fetched \(commentsWithReplies.count) comments with replies")
        
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
    func toggleAmen(commentId: String) async throws {
        print("🙏 Toggling Amen on comment: \(commentId)")
        
        guard let userId = firebaseManager.currentUser?.uid else {
            throw NSError(domain: "CommentService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        // Find the post ID for this comment (we need to search through our cache)
        var postId: String?
        for (pid, commentsArray) in comments {
            if commentsArray.contains(where: { $0.id == commentId }) {
                postId = pid
                break
            }
        }
        
        guard let postId = postId else {
            throw NSError(domain: "CommentService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Could not find post for comment"])
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
        print("🔊 Starting real-time listener for comments on post: \(postId)")
        
        let commentsRef = ref.child("postInteractions").child(postId).child("comments")
        
        let handle = commentsRef.observe(.value) { [weak self] snapshot in
            guard let self = self else { return }
            
            Task { @MainActor in
                var fetchedComments: [Comment] = []
                
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
                    
                    // Fetch username from user profile
                    let authorUsername: String
                    do {
                        // ✅ NEW: Check if username is already in RTDB
                        if let storedUsername = commentData["authorUsername"] as? String, !storedUsername.isEmpty {
                            authorUsername = storedUsername
                        } else {
                            // Fallback: Fetch from Firestore for old comments
                            let user = try await self.userService.fetchUserProfile(userId: authorId)
                            authorUsername = user.username
                        }
                    } catch {
                        print("⚠️ Failed to fetch user profile: \(error)")
                        authorUsername = "user\(authorId.prefix(8))"
                    }
                    
                    let comment = Comment(
                        id: childSnapshot.key,
                        postId: postId,
                        authorId: authorId,
                        authorName: authorName,
                        authorUsername: authorUsername,
                        authorInitials: authorInitials,
                        authorProfileImageURL: nil,
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
                
                // Update cache - separate top-level and replies
                self.comments[postId] = fetchedComments.filter { $0.parentCommentId == nil }
                
                // Group replies by parent
                for reply in fetchedComments.filter({ $0.parentCommentId != nil }) {
                    guard let parentId = reply.parentCommentId else { continue }
                    
                    if var replies = self.commentReplies[parentId] {
                        if !replies.contains(where: { $0.id == reply.id }) {
                            replies.append(reply)
                            self.commentReplies[parentId] = replies.sorted { $0.createdAt < $1.createdAt }
                        }
                    } else {
                        self.commentReplies[parentId] = [reply]
                    }
                }
                
                print("✅ Real-time update: \(self.comments[postId]?.count ?? 0) comments")
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
    func hasUserAmened(commentId: String) async -> Bool {
        guard let userId = firebaseManager.currentUser?.uid else { return false }
        
        // Find the post ID for this comment
        var postId: String?
        for (pid, commentsArray) in comments {
            if commentsArray.contains(where: { $0.id == commentId }) {
                postId = pid
                break
            }
        }
        
        guard let postId = postId else { return false }
        
        let userLikeRef = ref.child("postInteractions").child(postId).child("comments").child(commentId).child("likedBy").child(userId)
        
        do {
            let snapshot = try await userLikeRef.getData()
            return snapshot.exists()
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
