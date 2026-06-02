//
//  RepliesModels.swift
//  AMENAPP
//
//  Models and ViewModel for the Replies tab on user profiles
//  Shows posts that a user has commented on with their reply threaded below
//

import Foundation
import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth
import FirebaseDatabase

// MARK: - ReplyThread Model

enum ReplyContextType: CaseIterable, Equatable {
    case post
    case prayer
    case verseDiscussion
    case churchNote
    case berean

    var label: String? {
        switch self {
        case .post: return nil
        case .prayer: return "Prayer"
        case .verseDiscussion: return "Verse"
        case .churchNote: return "Church Note"
        case .berean: return "Berean"
        }
    }

    var icon: String? {
        switch self {
        case .post: return nil
        case .prayer: return "hands.sparkles"
        case .verseDiscussion: return "book"
        case .churchNote: return "note.text"
        case .berean: return "sparkles"
        }
    }
}

enum ReplyVisibilityState: Equatable {
    case visible
    case pendingApproval
    case hidden
    case parentDeleted
    case parentUnavailable

    var bannerText: String? {
        switch self {
        case .visible: return nil
        case .pendingApproval: return "Pending approval"
        case .hidden: return "Hidden reply"
        case .parentDeleted: return "Original post was deleted"
        case .parentUnavailable: return "Original post unavailable"
        }
    }

    var bannerIcon: String? {
        switch self {
        case .visible: return nil
        case .pendingApproval: return "clock"
        case .hidden: return "eye.slash"
        case .parentDeleted: return "trash"
        case .parentUnavailable: return "exclamationmark.triangle"
        }
    }
}

enum ReplyFilter: CaseIterable, Equatable {
    case all
    case verse
    case prayer
    case notes

    func matches(_ thread: ReplyThread) -> Bool {
        switch self {
        case .all:
            return true
        case .verse:
            return thread.contextType == .verseDiscussion
        case .prayer:
            return thread.contextType == .prayer
        case .notes:
            return thread.contextType == .churchNote
        }
    }
}

/// Bundles an original post with the user's reply for display in the Replies tab
struct ReplyThread: Identifiable {
    let id: String  // Use comment ID as the unique identifier
    let originalPost: Post
    let userReply: Comment
    let contextType: ReplyContextType
    let visibilityState: ReplyVisibilityState
    let parentCommentId: String?
    let parentAuthorName: String?
    let parentAuthorUsername: String?
    let parentPreviewText: String?
    private let originalPostAvailable: Bool
    
    /// Sort by reply creation time (most recent first)
    var createdAt: Date {
        userReply.createdAt
    }
    
    init(originalPost: Post, userReply: Comment) {
        self.id = userReply.id ?? UUID().uuidString
        self.originalPost = originalPost
        self.userReply = userReply
        self.contextType = .post
        self.visibilityState = .visible
        self.parentCommentId = nil
        self.parentAuthorName = nil
        self.parentAuthorUsername = nil
        self.parentPreviewText = nil
        self.originalPostAvailable = true
    }

    init(
        originalPost: Post?,
        userReply: Comment,
        contextType: ReplyContextType,
        visibilityState: ReplyVisibilityState,
        parentCommentId: String?,
        parentAuthorName: String?,
        parentAuthorUsername: String?,
        parentPreviewText: String?
    ) {
        self.id = userReply.id ?? UUID().uuidString
        self.originalPost = originalPost ?? ReplyThread.unavailablePost()
        self.userReply = userReply
        self.contextType = contextType
        self.visibilityState = visibilityState
        self.parentCommentId = parentCommentId
        self.parentAuthorName = parentAuthorName
        self.parentAuthorUsername = parentAuthorUsername
        self.parentPreviewText = parentPreviewText
        self.originalPostAvailable = originalPost != nil
    }

    var canOpenThread: Bool {
        originalPostAvailable
    }

    var replyTargetDisplay: String {
        if let parentAuthorUsername, !parentAuthorUsername.isEmpty {
            return "@\(parentAuthorUsername)"
        }
        if let parentAuthorName, !parentAuthorName.isEmpty {
            return parentAuthorName
        }
        if originalPostAvailable, let username = originalPost.authorUsername, !username.isEmpty {
            return "@\(username)"
        }
        return "this conversation"
    }

    var previewText: String? {
        if let parentPreviewText, !parentPreviewText.isEmpty {
            return parentPreviewText
        }
        return originalPostAvailable ? originalPost.content : nil
    }

    private static func unavailablePost() -> Post {
        Post(
            authorId: "",
            authorName: "",
            authorUsername: nil,
            authorInitials: "",
            content: "",
            category: .openTable,
            visibility: .everyone
        )
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
    private lazy var db = Firestore.firestore()
    
    /// Fetch replies for a specific user
    /// Since comments are in Realtime Database, we'll fetch posts the user has interacted with
    /// and then check RTDB for their comments on those posts
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
            // Fetch recent posts (we'll check each for user's comments)
            // In production, you'd want a separate Firestore collection tracking user comments
            // For now, we'll fetch posts and check Realtime DB for comments
            var query = db.collection("posts")
                .order(by: "createdAt", descending: true)
                .limit(to: 50)  // Check recent posts
            
            if let lastDoc = lastDocument {
                query = query.start(afterDocument: lastDoc)
            }
            
            let snapshot = try await query.getDocuments()
            
            // Update pagination state
            lastDocument = snapshot.documents.last
            
            var newThreads: [ReplyThread] = []
            
            // Import Firebase Database
            let database = Database.database()
            let ref = database.reference()
            
            // Check each post for user's comments
            for postDoc in snapshot.documents {
                guard let post = try? postDoc.data(as: Post.self) else { continue }
                
                let postId = postDoc.documentID
                
                // Check RTDB for this user's comments on this post
                let commentsRef = ref.child("postInteractions").child(postId).child("comments")
                
                do {
                    let commentsSnapshot = try await commentsRef.getData()
                    
                    guard commentsSnapshot.exists() else { continue }
                    
                    // Parse all comments and find ones by this user
                    for child in commentsSnapshot.children.allObjects as? [DataSnapshot] ?? [] {
                        guard let commentData = child.value as? [String: Any],
                              let commentAuthorId = commentData["authorId"] as? String,
                              commentAuthorId == userId else {
                            continue
                        }
                        
                        // Parse the comment
                        guard let authorName = commentData["authorName"] as? String,
                              let authorUsername = commentData["authorUsername"] as? String,
                              let authorInitials = commentData["authorInitials"] as? String,
                              let content = commentData["content"] as? String,
                              let timestamp = commentData["timestamp"] as? Int64 else {
                            continue
                        }
                        
                        let createdAt = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0)
                        let authorProfileImageURL = commentData["authorProfileImageURL"] as? String
                        let amenCount = commentData["amenCount"] as? Int ?? 0
                        let lightbulbCount = commentData["lightbulbCount"] as? Int ?? 0
                        let replyCount = commentData["replyCount"] as? Int ?? 0
                        let amenUserIds = (commentData["amenUserIds"] as? [String: Bool])?.keys.map { $0 } ?? []
                        
                        let comment = Comment(
                            id: child.key,
                            postId: postId,
                            authorId: commentAuthorId,
                            authorName: authorName,
                            authorUsername: authorUsername,
                            authorInitials: authorInitials,
                            authorProfileImageURL: authorProfileImageURL,
                            content: content,
                            createdAt: createdAt,
                            updatedAt: createdAt,
                            amenCount: amenCount,
                            lightbulbCount: lightbulbCount,
                            replyCount: replyCount,
                            amenUserIds: amenUserIds
                        )
                        
                        let thread = ReplyThread(originalPost: post, userReply: comment)
                        newThreads.append(thread)
                    }
                } catch {
                    print("⚠️ Failed to fetch comments from RTDB for post \(postId): \(error)")
                    continue
                }
            }
            
            // Sort by reply creation time (most recent first)
            newThreads.sort { $0.createdAt > $1.createdAt }
            
            // Take only the pageSize most recent
            let limitedThreads = Array(newThreads.prefix(pageSize))
            
            // Append new threads
            if isInitialLoad {
                replyThreads = limitedThreads
            } else {
                replyThreads.append(contentsOf: limitedThreads)
            }
            
            hasMoreData = snapshot.documents.count == 50
            
            print("✅ Loaded \(limitedThreads.count) reply threads for user \(userId)")
            
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
