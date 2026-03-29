//
//  RepliesModels.swift
//  AMENAPP
//
//  Models and ViewModel for the Replies tab on user profiles
//  Shows posts that a user has commented on with their reply threaded below
//

import Foundation
import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - ReplyThread Model

/// Bundles an original post with the user's reply for display in the Replies tab
struct ReplyThread: Identifiable {
    let id: String  // Use comment ID as the unique identifier
    let originalPost: Post
    let userReply: Comment
    
    /// Sort by reply creation time (most recent first)
    var createdAt: Date {
        userReply.createdAt
    }
    
    init(originalPost: Post, userReply: Comment) {
        self.id = userReply.id ?? UUID().uuidString
        self.originalPost = originalPost
        self.userReply = userReply
    }
}

// MARK: - RepliesViewModel

@MainActor
class RepliesViewModel: ObservableObject {
    @Published var replyThreads: [ReplyThread] = []
    @Published var isLoading = false
    @Published var hasMoreData = true
    @Published var error: String?
    
    private let pageSize = 20
    private var lastDocument: DocumentSnapshot?
    private let db = Firestore.firestore()
    
    /// Fetch replies for a specific user
    func fetchReplies(for userId: String, isInitialLoad: Bool = false) async {
        guard !isLoading else { return }
        
        if isInitialLoad {
            replyThreads = []
            lastDocument = nil
            hasMoreData = true
        }
        
        guard hasMoreData else { return }
        
        isLoading = true
        error = nil
        
        do {
            // Query comments where authorId == userId
            var query = db.collectionGroup("comments")
                .whereField("authorId", isEqualTo: userId)
                .order(by: "createdAt", descending: true)
                .limit(to: pageSize)
            
            // Pagination support
            if let lastDoc = lastDocument {
                query = query.start(afterDocument: lastDoc)
            }
            
            let snapshot = try await query.getDocuments()
            
            // Update pagination state
            lastDocument = snapshot.documents.last
            hasMoreData = snapshot.documents.count == pageSize
            
            // Fetch parent posts for each comment
            var newThreads: [ReplyThread] = []
            
            for commentDoc in snapshot.documents {
                do {
                    let comment = try commentDoc.data(as: Comment.self)
                    
                    // Get the postId from the comment
                    guard let postId = comment.postId as String? else {
                        continue
                    }
                    
                    // Fetch the parent post
                    let postDoc = try await db.collection("posts").document(postId).getDocument()
                    
                    guard postDoc.exists,
                          let post = try? postDoc.data(as: Post.self) else {
                        continue
                    }
                    
                    // Create reply thread
                    let thread = ReplyThread(originalPost: post, userReply: comment)
                    newThreads.append(thread)
                    
                } catch {
                    print("⚠️ Failed to parse comment or fetch post: \(error)")
                    continue
                }
            }
            
            // Append new threads
            if isInitialLoad {
                replyThreads = newThreads
            } else {
                replyThreads.append(contentsOf: newThreads)
            }
            
            print("✅ Loaded \(newThreads.count) reply threads for user \(userId)")
            
        } catch {
            self.error = "Failed to load replies: \(error.localizedDescription)"
            print("❌ Error fetching replies: \(error)")
        }
        
        isLoading = false
    }
    
    /// Refresh replies (pull to refresh)
    func refreshReplies(for userId: String) async {
        await fetchReplies(for: userId, isInitialLoad: true)
    }
}
