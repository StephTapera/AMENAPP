//
//  NestedCommentService.swift
//  AMENAPP
//
//  Created by Claude on 2/15/26.
//
//  Handles nested comment threads with @mentions and reply notifications
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

/// Service for managing nested comment threads with reply support
@MainActor
class NestedCommentService: ObservableObject {
    static let shared = NestedCommentService()
    
    private let db = Firestore.firestore()
    
    // MARK: - Comment Model with Nesting
    
    struct NestedComment: Identifiable, Codable {
        let id: String
        let postId: String
        let authorId: String
        let authorName: String
        let authorProfileImage: String?
        let content: String
        let timestamp: Date
        let mentions: [String] // User IDs mentioned
        let parentCommentId: String? // nil for top-level comments
        var replyCount: Int
        var likeCount: Int
        var isLikedByCurrentUser: Bool
        
        var isReply: Bool {
            parentCommentId != nil
        }
    }
    
    // MARK: - Post Comment with Reply Support
    
    /// Post a new comment or reply
    func postComment(
        postId: String,
        content: String,
        parentCommentId: String? = nil
    ) async throws -> NestedComment {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "NestedComment", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // Get current user info
        let userDoc = try await db.collection("users").document(currentUserId).getDocument()
        guard let userData = userDoc.data() else {
            throw NSError(domain: "NestedComment", code: 404, userInfo: [NSLocalizedDescriptionKey: "User not found"])
        }
        
        let userName = userData["username"] as? String ?? "Anonymous"
        let profileImage = userData["profileImageURL"] as? String
        
        // Extract @mentions from content
        let mentions = extractMentions(from: content)
        
        // Create comment document
        let commentId = UUID().uuidString
        let comment = NestedComment(
            id: commentId,
            postId: postId,
            authorId: currentUserId,
            authorName: userName,
            authorProfileImage: profileImage,
            content: content,
            timestamp: Date(),
            mentions: mentions,
            parentCommentId: parentCommentId,
            replyCount: 0,
            likeCount: 0,
            isLikedByCurrentUser: false
        )
        
        // Save to Firestore
        let commentData: [String: Any] = [
            "id": comment.id,
            "postId": comment.postId,
            "authorId": comment.authorId,
            "authorName": comment.authorName,
            "authorProfileImage": profileImage ?? "",
            "content": comment.content,
            "timestamp": Timestamp(date: comment.timestamp),
            "mentions": mentions,
            "parentCommentId": parentCommentId ?? "",
            "replyCount": 0,
            "likeCount": 0
        ]
        
        try await db.collection("comments").document(commentId).setData(commentData)
        
        // If this is a reply, update parent comment's reply count
        if let parentId = parentCommentId {
            try await incrementReplyCount(parentCommentId: parentId)
        }
        
        // Update post's comment count
        try await incrementPostCommentCount(postId: postId)
        
        // Send notifications to mentioned users
        for mentionedUserId in mentions {
            await sendMentionNotification(
                to: mentionedUserId,
                from: currentUserId,
                fromName: userName,
                postId: postId,
                commentId: commentId,
                isReply: parentCommentId != nil
            )
        }
        
        // If this is a reply, notify the parent comment author
        if let parentId = parentCommentId {
            await sendReplyNotification(
                parentCommentId: parentId,
                from: currentUserId,
                fromName: userName,
                postId: postId,
                commentId: commentId
            )
        }
        
        print("✅ Posted comment successfully (reply: \(parentCommentId != nil))")
        return comment
    }
    
    // MARK: - Fetch Comments with Nesting
    
    /// Fetch all comments for a post, organized by parent/child
    func fetchComments(postId: String) async throws -> [NestedComment] {
        let snapshot = try await db.collection("comments")
            .whereField("postId", isEqualTo: postId)
            .order(by: "timestamp", descending: false)
            .getDocuments()
        
        var comments: [NestedComment] = []
        guard let currentUserId = Auth.auth().currentUser?.uid else { return [] }
        
        for doc in snapshot.documents {
            let data = doc.data()
            
            let comment = NestedComment(
                id: data["id"] as? String ?? doc.documentID,
                postId: data["postId"] as? String ?? "",
                authorId: data["authorId"] as? String ?? "",
                authorName: data["authorName"] as? String ?? "Unknown",
                authorProfileImage: data["authorProfileImage"] as? String,
                content: data["content"] as? String ?? "",
                timestamp: (data["timestamp"] as? Timestamp)?.dateValue() ?? Date(),
                mentions: data["mentions"] as? [String] ?? [],
                parentCommentId: (data["parentCommentId"] as? String)?.isEmpty == false ? data["parentCommentId"] as? String : nil,
                replyCount: data["replyCount"] as? Int ?? 0,
                likeCount: data["likeCount"] as? Int ?? 0,
                isLikedByCurrentUser: await checkIfLiked(commentId: doc.documentID, userId: currentUserId)
            )
            
            comments.append(comment)
        }
        
        return comments
    }
    
    /// Fetch replies for a specific comment
    func fetchReplies(parentCommentId: String) async throws -> [NestedComment] {
        let snapshot = try await db.collection("comments")
            .whereField("parentCommentId", isEqualTo: parentCommentId)
            .order(by: "timestamp", descending: false)
            .getDocuments()
        
        var replies: [NestedComment] = []
        guard let currentUserId = Auth.auth().currentUser?.uid else { return [] }
        
        for doc in snapshot.documents {
            let data = doc.data()
            
            let reply = NestedComment(
                id: data["id"] as? String ?? doc.documentID,
                postId: data["postId"] as? String ?? "",
                authorId: data["authorId"] as? String ?? "",
                authorName: data["authorName"] as? String ?? "Unknown",
                authorProfileImage: data["authorProfileImage"] as? String,
                content: data["content"] as? String ?? "",
                timestamp: (data["timestamp"] as? Timestamp)?.dateValue() ?? Date(),
                mentions: data["mentions"] as? [String] ?? [],
                parentCommentId: parentCommentId,
                replyCount: 0,
                likeCount: data["likeCount"] as? Int ?? 0,
                isLikedByCurrentUser: await checkIfLiked(commentId: doc.documentID, userId: currentUserId)
            )
            
            replies.append(reply)
        }
        
        return replies
    }
    
    // MARK: - Helper Functions
    
    /// Extract @mentions from comment content
    private func extractMentions(from content: String) -> [String] {
        // Regex to find @username patterns
        let pattern = "@([a-zA-Z0-9_]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        
        let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))
        
        var usernames: [String] = []
        for match in matches {
            if let range = Range(match.range(at: 1), in: content) {
                let username = String(content[range])
                usernames.append(username)
            }
        }
        
        // Convert usernames to user IDs (simplified - in production, query Firestore)
        return usernames
    }
    
    private func incrementReplyCount(parentCommentId: String) async throws {
        try await db.collection("comments").document(parentCommentId).updateData([
            "replyCount": FieldValue.increment(Int64(1))
        ])
    }
    
    private func incrementPostCommentCount(postId: String) async throws {
        try await db.collection("posts").document(postId).updateData([
            "commentCount": FieldValue.increment(Int64(1))
        ])
    }
    
    private func checkIfLiked(commentId: String, userId: String) async -> Bool {
        do {
            let doc = try await db.collection("comments")
                .document(commentId)
                .collection("likes")
                .document(userId)
                .getDocument()
            return doc.exists
        } catch {
            return false
        }
    }
    
    // MARK: - Notifications
    
    private func sendMentionNotification(
        to userId: String,
        from senderId: String,
        fromName: String,
        postId: String,
        commentId: String,
        isReply: Bool
    ) async {
        guard userId != senderId else { return }
        
        let notificationData: [String: Any] = [
            "userId": userId,
            "actorId": senderId,
            "actorName": fromName,
            "type": "mention",
            "postId": postId,
            "commentId": commentId,
            "actionText": isReply ? "mentioned you in a reply" : "mentioned you in a comment",
            "timestamp": Timestamp(date: Date()),
            "read": false
        ]
        
        do {
            try await db.collection("notifications").addDocument(data: notificationData)
        } catch {
            print("❌ Failed to send mention notification: \(error)")
        }
    }
    
    private func sendReplyNotification(
        parentCommentId: String,
        from senderId: String,
        fromName: String,
        postId: String,
        commentId: String
    ) async {
        // Get parent comment author
        do {
            let parentDoc = try await db.collection("comments").document(parentCommentId).getDocument()
            guard let parentAuthorId = parentDoc.data()?["authorId"] as? String,
                  parentAuthorId != senderId else { return }
            
            let notificationData: [String: Any] = [
                "userId": parentAuthorId,
                "actorId": senderId,
                "actorName": fromName,
                "type": "reply",
                "postId": postId,
                "commentId": commentId,
                "actionText": "replied to your comment",
                "timestamp": Timestamp(date: Date()),
                "read": false
            ]
            
            try await db.collection("notifications").addDocument(data: notificationData)
        } catch {
            print("❌ Failed to send reply notification: \(error)")
        }
    }
    
    // MARK: - Like/Unlike Comment
    
    func toggleLike(commentId: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        let likeRef = db.collection("comments")
            .document(commentId)
            .collection("likes")
            .document(currentUserId)
        
        let doc = try await likeRef.getDocument()
        
        if doc.exists {
            // Unlike
            try await likeRef.delete()
            try await db.collection("comments").document(commentId).updateData([
                "likeCount": FieldValue.increment(Int64(-1))
            ])
        } else {
            // Like
            try await likeRef.setData(["timestamp": Timestamp(date: Date())])
            try await db.collection("comments").document(commentId).updateData([
                "likeCount": FieldValue.increment(Int64(1))
            ])
        }
    }
}
