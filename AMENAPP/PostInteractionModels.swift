//
//  PostInteractionModels.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//
//  Models for post interactions: comments, replies, saved posts, reposts
//

import Foundation
import FirebaseFirestore

// MARK: - Comment Model

struct Comment: Identifiable, Codable, Equatable {
    var id: String?
    var postId: String
    var authorId: String
    var authorName: String
    var authorUsername: String
    var authorInitials: String
    var authorProfileImageURL: String?
    var content: String
    var createdAt: Date
    var updatedAt: Date
    var isEdited: Bool  // Track if comment has been edited
    
    // Interaction counts
    var amenCount: Int
    var lightbulbCount: Int  // For OpenTable posts (lightbulb = like)
    var replyCount: Int
    
    // Lists of users who interacted
    var amenUserIds: [String]
    
    // Parent comment ID (if this is a reply)
    var parentCommentId: String?
    
    // Mentions in comment
    var mentionedUserIds: [String]?
    
    enum CodingKeys: String, CodingKey {
        case id
        case postId
        case authorId
        case authorName
        case authorUsername
        case authorInitials
        case authorProfileImageURL
        case content
        case createdAt
        case updatedAt
        case isEdited
        case amenCount
        case lightbulbCount
        case replyCount
        case amenUserIds
        case parentCommentId
        case mentionedUserIds
    }
    
    init(
        id: String? = nil,
        postId: String,
        authorId: String,
        authorName: String,
        authorUsername: String,
        authorInitials: String,
        authorProfileImageURL: String? = nil,
        content: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isEdited: Bool = false,
        amenCount: Int = 0,
        lightbulbCount: Int = 0,
        replyCount: Int = 0,
        amenUserIds: [String] = [],
        parentCommentId: String? = nil,
        mentionedUserIds: [String]? = nil
    ) {
        self.id = id
        self.postId = postId
        self.authorId = authorId
        self.authorName = authorName
        self.authorUsername = authorUsername
        self.authorInitials = authorInitials
        self.authorProfileImageURL = authorProfileImageURL
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isEdited = isEdited
        self.amenCount = amenCount
        self.lightbulbCount = lightbulbCount
        self.replyCount = replyCount
        self.amenUserIds = amenUserIds
        self.parentCommentId = parentCommentId
        self.mentionedUserIds = mentionedUserIds
    }
    
    /// Display time ago
    var timeAgo: String {
        createdAt.timeAgoDisplay()
    }
    
    /// Check if this is a reply (has parent)
    var isReply: Bool {
        parentCommentId != nil
    }
}

// MARK: - Saved Post Model

struct SavedPost: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    var userId: String
    var postId: String
    var savedAt: Date
    
    // Optional: organize saved posts into collections
    var collectionName: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case postId
        case savedAt
        case collectionName
    }
    
    init(
        id: String? = nil,
        userId: String,
        postId: String,
        savedAt: Date = Date(),
        collectionName: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.postId = postId
        self.savedAt = savedAt
        self.collectionName = collectionName
    }
}

// MARK: - Repost Model

/// Model for tracking when a user reposts a post to their profile
/// This is the ONLY Repost model in the app - defined in PostInteractionModels.swift
public struct Repost: Identifiable, Codable, Equatable {
    @DocumentID public var id: String?
    public var userId: String
    public var originalPostId: String
    public var repostedAt: Date
    public var withComment: String?  // Optional comment when reposting
    
    public enum CodingKeys: String, CodingKey {
        case id
        case userId
        case originalPostId
        case repostedAt
        case withComment
    }
    
    public init(
        id: String? = nil,
        userId: String,
        originalPostId: String,
        repostedAt: Date = Date(),
        withComment: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.originalPostId = originalPostId
        self.repostedAt = repostedAt
        self.withComment = withComment
    }
}

// MARK: - Post Mention Model

struct PostMention: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    var postId: String
    var commentId: String?  // nil if mention is in post, not comment
    var mentionedUserId: String
    var mentionedByUserId: String
    var createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case postId
        case commentId
        case mentionedUserId
        case mentionedByUserId
        case createdAt
    }
}

// MARK: - Nested Comment with Replies

/// Wrapper for displaying comments with their nested replies
struct CommentWithReplies: Identifiable, Equatable {
    let id: String // ✅ FIXED: Store stable ID instead of computing it each time
    let comment: Comment
    var replies: [Comment]
    
    init(comment: Comment, replies: [Comment] = []) {
        // ✅ Create ID once and store it (prevents duplicate IDs in ForEach)
        self.id = comment.id ?? UUID().uuidString
        self.comment = comment
        self.replies = replies
    }
}
