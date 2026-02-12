//
//  RealtimeCommentsService.swift
//  AMENAPP
//
//  Created by Steph on 1/24/26.
//
//  Firebase Realtime Database implementation for comments/replies
//  Real-time updates and efficient nested comment structure
//

import Foundation
import FirebaseDatabase
import FirebaseAuth
import Combine

// Note: Comment model is defined in PostInteractionModels.swift

// MARK: - Realtime Comments Service

@MainActor
class RealtimeCommentsService: ObservableObject {
    static let shared = RealtimeCommentsService()
    
    private let database: DatabaseReference
    private var commentListeners: [String: DatabaseHandle] = [:]  // postId -> listener handle
    
    @Published var comments: [String: [Comment]] = [:]  // postId -> [comments]
    @Published var isLoading = false
    
    private init() {
        self.database = Database.database(url: "https://amen-5e359-default-rtdb.firebaseio.com").reference()
        print("🔥 RealtimeCommentsService initialized")
    }
    
    deinit {
        // Create a detached task to clean up listeners since deinit cannot be async
        Task { @MainActor [database, commentListeners] in
            for (postId, handle) in commentListeners {
                database.child("comments").child(postId).removeObserver(withHandle: handle)
            }
            print("🔇 All comment listeners removed in deinit")
        }
    }
    
    // MARK: - Database Structure
    /*
     /comments
       /{postId}
         /{commentId}
           - authorId: "userId"
           - authorName: "John Doe"
           - authorInitials: "JD"
           - authorProfileImageURL: "https://..."
           - content: "Great post!"
           - createdAt: timestamp
     
     /comment_stats
       /{commentId}
         - amenCount: 0
         - replyCount: 0
     
     /comment_interactions
       /{commentId}
         /amen
           /{userId}: timestamp
     
     /user_comments
       /{userId}
         /{commentId}: timestamp  // When commented
     */
    
    // MARK: - Create Comment
    
    func createComment(postId: String, content: String) async throws -> Comment {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "RealtimeCommentsService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let userId = currentUser.uid
        
        // Get cached user data
        let displayName = UserDefaults.standard.string(forKey: "currentUserDisplayName") ?? "User"
        let initials = UserDefaults.standard.string(forKey: "currentUserInitials") ?? "U"
        let profileImageURL = UserDefaults.standard.string(forKey: "currentUserProfileImageURL")
        
        // Generate comment ID
        let commentId = UUID().uuidString
        let timestamp = Date().timeIntervalSince1970
        
        // Create comment data
        let commentData: [String: Any] = [
            "authorId": userId,
            "authorName": displayName,
            "authorInitials": initials,
            "authorProfileImageURL": profileImageURL ?? "",
            "content": content,
            "createdAt": timestamp
        ]
        
        print("💬 Creating comment on post: \(postId)")
        
        // Multi-path update
        let updates: [String: Any] = [
            "/comments/\(postId)/\(commentId)": commentData,
            "/comment_stats/\(commentId)": [
                "amenCount": 0,
                "replyCount": 0
            ],
            "/user_comments/\(userId)/\(commentId)": timestamp
        ]
        
        try await database.updateChildValues(updates)
        
        // Increment post comment count
        try await RealtimeEngagementService.shared.incrementCommentCount(postId: postId)
        
        print("✅ Comment created successfully")
        
        // Create Comment object for return
        let comment = Comment(
            id: commentId,
            postId: postId,
            authorId: userId,
            authorName: displayName,
            authorUsername: "@\(displayName.lowercased().replacingOccurrences(of: " ", with: ""))",
            authorInitials: initials,
            authorProfileImageURL: profileImageURL,
            content: content,
            createdAt: Date(),
            updatedAt: Date(),
            amenCount: 0,
            replyCount: 0
        )
        
        // ✅ Send notification so ProfileView can update replies tab
        NotificationCenter.default.post(
            name: Notification.Name("newCommentCreated"),
            object: nil,
            userInfo: ["comment": comment]
        )
        print("📬 Sent newCommentCreated notification")
        
        return comment
    }
    
    // MARK: - Fetch Comments for Post
    
    func fetchComments(postId: String) async throws -> [Comment] {
        print("📥 Fetching comments for post: \(postId)")
        
        let snapshot = try await database.child("comments").child(postId).getData()
        
        guard snapshot.exists(), let commentsDict = snapshot.value as? [String: Any] else {
            print("⚠️ No comments found")
            return []
        }
        
        var comments: [Comment] = []
        
        for (commentId, value) in commentsDict {
            guard let commentData = value as? [String: Any] else { continue }
            
            let authorId = commentData["authorId"] as? String ?? ""
            let authorName = commentData["authorName"] as? String ?? "Unknown"
            let authorInitials = commentData["authorInitials"] as? String ?? "?"
            let authorProfileImageURL = commentData["authorProfileImageURL"] as? String
            let content = commentData["content"] as? String ?? ""
            let createdAtTimestamp = commentData["createdAt"] as? TimeInterval ?? 0
            
            // Fetch stats
            let statsSnapshot = try? await database.child("comment_stats").child(commentId).getData()
            var amenCount = 0
            var replyCount = 0
            
            if let statsSnapshot = statsSnapshot, statsSnapshot.exists(),
               let statsData = statsSnapshot.value as? [String: Any] {
                amenCount = statsData["amenCount"] as? Int ?? 0
                replyCount = statsData["replyCount"] as? Int ?? 0
            }
            
            let comment = Comment(
                id: commentId,
                postId: postId,
                authorId: authorId,
                authorName: authorName,
                authorUsername: "@\(authorName.lowercased().replacingOccurrences(of: " ", with: ""))",
                authorInitials: authorInitials,
                authorProfileImageURL: authorProfileImageURL,
                content: content,
                createdAt: Date(timeIntervalSince1970: createdAtTimestamp),
                updatedAt: Date(timeIntervalSince1970: createdAtTimestamp),
                amenCount: amenCount,
                replyCount: replyCount
            )
            
            comments.append(comment)
        }
        
        // Sort by creation date (oldest first for comments)
        comments.sort { $0.createdAt < $1.createdAt }
        
        print("✅ Fetched \(comments.count) comments")
        return comments
    }
    
    // MARK: - Fetch User Comments
    
    func fetchUserComments(userId: String) async throws -> [Comment] {
        print("📥 Fetching comments by user: \(userId)")
        
        let snapshot = try await database.child("user_comments").child(userId).getData()
        
        guard snapshot.exists(), let commentDict = snapshot.value as? [String: Any] else {
            print("⚠️ No comments found for user")
            return []
        }
        
        var comments: [Comment] = []
        
        // ✅ FIX: Properly fetch each comment with its data
        for (commentId, commentData) in commentDict {
            // If commentData contains postId, use it to fetch the full comment
            if let data = commentData as? [String: Any],
               let postId = data["postId"] as? String {
                
                // Fetch the full comment from the comments tree
                let commentSnapshot = try await database.child("comments").child(postId).child(commentId).getData()
                
                if commentSnapshot.exists(), let fullCommentData = commentSnapshot.value as? [String: Any] {
                    // Parse the comment
                    if let comment = parseComment(from: fullCommentData, commentId: commentId, postId: postId) {
                        comments.append(comment)
                    }
                }
            }
        }
        
        // Sort by timestamp (newest first)
        comments.sort { $0.createdAt > $1.createdAt }
        
        print("✅ Fetched \(comments.count) user comments")
        return comments
    }
    
    // MARK: - Fetch User Comment Interactions (Comments + Replies Received)
    
    /// Fetches ALL comments where user is involved:
    /// 1. Comments the user made (from user_comments)
    /// 2. Replies others made to the user's comments (by checking parentCommentId)
    func fetchUserCommentInteractions(userId: String) async throws -> [Comment] {
        print("📥 Fetching ALL comment interactions for user: \(userId)")
        
        var allComments: [Comment] = []
        var commentIds = Set<String>() // Track to avoid duplicates
        
        // 1. Fetch comments the user made
        let userComments = try await fetchUserComments(userId: userId)
        for comment in userComments {
            guard let commentId = comment.id else { continue }
            if !commentIds.contains(commentId) {
                allComments.append(comment)
                commentIds.insert(commentId)
            }
        }
        print("   ✅ User's own comments: \(userComments.count)")
        
        // 2. Fetch replies to the user's comments
        // For each comment the user made, check if there are replies to it
        for userComment in userComments {
            guard let userCommentId = userComment.id else { continue }
            
            // Get all comments on the same post
            let postCommentsSnapshot = try await database.child("comments").child(userComment.postId).getData()
            
            guard postCommentsSnapshot.exists(), 
                  let postCommentsDict = postCommentsSnapshot.value as? [String: Any] else {
                continue
            }
            
            // Find comments where parentCommentId matches this user's comment
            for (replyId, replyData) in postCommentsDict {
                guard let replyDict = replyData as? [String: Any],
                      let parentId = replyDict["parentCommentId"] as? String,
                      parentId == userCommentId else {
                    continue
                }
                
                // This is a reply to the user's comment
                if let reply = parseComment(from: replyDict, commentId: replyId, postId: userComment.postId),
                   let replyIdUnwrapped = reply.id,
                   !commentIds.contains(replyIdUnwrapped) {
                    allComments.append(reply)
                    commentIds.insert(replyIdUnwrapped)
                    print("   💬 Found reply from \(reply.authorName) to user's comment")
                }
            }
        }
        
        // Sort by newest first
        allComments.sort { $0.createdAt > $1.createdAt }
        
        print("✅ Fetched \(allComments.count) total comment interactions (\(userComments.count) own + \(allComments.count - userComments.count) replies received)")
        return allComments
    }
    
    /// Helper to parse comment data into Comment object
    private func parseComment(from data: [String: Any], commentId: String, postId: String) -> Comment? {
        guard let authorId = data["authorId"] as? String,
              let authorName = data["authorName"] as? String,
              let content = data["content"] as? String,
              let timestampDouble = data["createdAt"] as? Double else {
            print("⚠️ Invalid comment data for ID: \(commentId)")
            return nil
        }
        
        let authorInitials = data["authorInitials"] as? String ?? "?"
        let authorUsername = data["authorUsername"] as? String ?? ""
        let authorProfileImageURL = data["authorProfileImageURL"] as? String
        let amenCount = data["amenCount"] as? Int ?? 0
        let lightbulbCount = data["lightbulbCount"] as? Int ?? 0
        let replyCount = data["replyCount"] as? Int ?? 0
        let amenUserIds = data["amenUserIds"] as? [String] ?? []
        let parentCommentId = data["parentCommentId"] as? String
        let isEdited = data["isEdited"] as? Bool ?? false
        let createdAt = Date(timeIntervalSince1970: timestampDouble)
        
        let updatedAt: Date
        if let updatedTimestamp = data["updatedAt"] as? Double {
            updatedAt = Date(timeIntervalSince1970: updatedTimestamp)
        } else {
            updatedAt = createdAt
        }
        
        return Comment(
            id: commentId,
            postId: postId,
            authorId: authorId,
            authorName: authorName,
            authorUsername: authorUsername,
            authorInitials: authorInitials,
            authorProfileImageURL: authorProfileImageURL,
            content: content,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isEdited: isEdited,
            amenCount: amenCount,
            lightbulbCount: lightbulbCount,
            replyCount: replyCount,
            amenUserIds: amenUserIds,
            parentCommentId: parentCommentId
        )
    }
    
    // MARK: - Delete Comment
    
    func deleteComment(commentId: String, postId: String) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "RealtimeCommentsService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let userId = currentUser.uid
        
        print("🗑️ Deleting comment: \(commentId)")
        
        // Multi-path delete
        let updates: [String: Any?] = [
            "/comments/\(postId)/\(commentId)": nil,
            "/comment_stats/\(commentId)": nil,
            "/comment_interactions/\(commentId)": nil,
            "/user_comments/\(userId)/\(commentId)": nil
        ]
        
        try await database.updateChildValues(updates as [AnyHashable: Any])
        
        // Decrement post comment count
        try await RealtimeEngagementService.shared.decrementCommentCount(postId: postId)
        
        print("✅ Comment deleted successfully")
    }
    
    // MARK: - Toggle Comment Amen
    
    func toggleCommentAmen(commentId: String) async throws -> Bool {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "RealtimeCommentsService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let userId = currentUser.uid
        let interactionPath = "/comment_interactions/\(commentId)/amen/\(userId)"
        
        // Check if user already said amen
        let snapshot = try await database.child(interactionPath).getData()
        let hasAmen = snapshot.exists()
        
        if hasAmen {
            // Remove amen
            print("🙏 Removing amen from comment: \(commentId)")
            
            let updates: [String: Any?] = [
                interactionPath: nil
            ]
            
            try await database.updateChildValues(updates as [AnyHashable: Any])
            
            // Decrement count
            try await database.child("comment_stats").child(commentId).child("amenCount").runTransactionBlock { currentData in
                if var count = currentData.value as? Int, count > 0 {
                    count -= 1
                    currentData.value = count
                }
                return TransactionResult.success(withValue: currentData)
            }
            
            print("✅ Comment amen removed")
            return false
            
        } else {
            // Add amen
            print("🙏 Adding amen to comment: \(commentId)")
            
            let updates: [String: Any] = [
                interactionPath: Date().timeIntervalSince1970
            ]
            
            try await database.updateChildValues(updates)
            
            // Increment count
            try await database.child("comment_stats").child(commentId).child("amenCount").runTransactionBlock { currentData in
                var count = currentData.value as? Int ?? 0
                count += 1
                currentData.value = count
                return TransactionResult.success(withValue: currentData)
            }
            
            print("✅ Comment amen added")
            return true
        }
    }
    
    // MARK: - Real-time Listener for Comments
    
    func observeComments(postId: String, completion: @escaping ([Comment]) -> Void) {
        print("👂 Setting up real-time listener for comments on post: \(postId)")
        
        let handle = database.child("comments").child(postId).observe(.value) { [weak self] snapshot in
            guard let self = self else { return }
            
            Task {
                do {
                    guard snapshot.exists(), let commentsDict = snapshot.value as? [String: Any] else {
                        await MainActor.run {
                            self.comments[postId] = []
                            completion([])
                        }
                        return
                    }
                    
                    var comments: [Comment] = []
                    
                    for (commentId, value) in commentsDict {
                        guard let commentData = value as? [String: Any] else { continue }
                        
                        let authorId = commentData["authorId"] as? String ?? ""
                        let authorName = commentData["authorName"] as? String ?? "Unknown"
                        let authorInitials = commentData["authorInitials"] as? String ?? "?"
                        let authorProfileImageURL = commentData["authorProfileImageURL"] as? String
                        let content = commentData["content"] as? String ?? ""
                        let createdAtTimestamp = commentData["createdAt"] as? TimeInterval ?? 0
                        
                        // Fetch stats
                        let statsSnapshot = try? await self.database.child("comment_stats").child(commentId).getData()
                        var amenCount = 0
                        var replyCount = 0
                        
                        if let statsSnapshot = statsSnapshot, statsSnapshot.exists(),
                           let statsData = statsSnapshot.value as? [String: Any] {
                            amenCount = statsData["amenCount"] as? Int ?? 0
                            replyCount = statsData["replyCount"] as? Int ?? 0
                        }
                        
                        let comment = Comment(
                            id: commentId,
                            postId: postId,
                            authorId: authorId,
                            authorName: authorName,
                            authorUsername: "@\(authorName.lowercased().replacingOccurrences(of: " ", with: ""))",
                            authorInitials: authorInitials,
                            authorProfileImageURL: authorProfileImageURL,
                            content: content,
                            createdAt: Date(timeIntervalSince1970: createdAtTimestamp),
                            updatedAt: Date(timeIntervalSince1970: createdAtTimestamp),
                            amenCount: amenCount,
                            replyCount: replyCount
                        )
                        
                        comments.append(comment)
                    }
                    
                    // Sort by creation date
                    comments.sort { $0.createdAt < $1.createdAt }
                    
                    await MainActor.run {
                        self.comments[postId] = comments
                        print("🔄 Real-time update: \(comments.count) comments")
                        completion(comments)
                    }
                } catch {
                    print("❌ Error in comments listener: \(error)")
                }
            }
        }
        
        commentListeners[postId] = handle
    }
    
    func removeCommentsListener(postId: String) {
        if let handle = commentListeners[postId] {
            database.child("comments").child(postId).removeObserver(withHandle: handle)
            commentListeners.removeValue(forKey: postId)
            print("🔇 Removed comments listener for post: \(postId)")
        }
    }
    
    func removeAllListeners() {
        for (postId, handle) in commentListeners {
            database.child("comments").child(postId).removeObserver(withHandle: handle)
        }
        commentListeners.removeAll()
        print("🔇 All comment listeners removed")
    }
}
