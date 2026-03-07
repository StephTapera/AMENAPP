//
//  FirebasePostServiceEnhancements.swift
//  AMENAPP
//
//  Additional features and enhancements for FirebasePostService
//

import Foundation
import FirebaseFirestore
import FirebaseStorage
import FirebaseAuth
import SwiftUI
import UIKit

// MARK: - Post Service Enhancements

extension FirebasePostService {
    
    // MARK: - Image Upload Support
    
    /// Upload images to Firebase Storage and return download URLs
    func uploadPostImages(_ images: [UIImage], postId: String? = nil) async throws -> [String] {
        guard !images.isEmpty else { return [] }
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "FirebasePostServiceEnhancements", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }

        let storage = Storage.storage()
        var downloadURLs: [String] = []

        // Use the supplied postId or generate a stable group folder for this batch
        let postIdentifier = postId ?? UUID().uuidString

        for (index, image) in images.enumerated() {
            // Compress image
            guard let imageData = image.jpegData(compressionQuality: 0.7) else {
                continue
            }

            // Canonical path: post_media/{userId}/{postId}/{filename} — matches Storage rules
            let filename = "\(postIdentifier)_\(index)_\(Date().timeIntervalSince1970).jpg"
            let storageRef = storage.reference()
                .child("post_media")
                .child(userId)
                .child(postIdentifier)
                .child(filename)

            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"

            // Upload image
            _ = try await storageRef.putDataAsync(imageData, metadata: metadata)

            // Get download URL
            let downloadURL = try await storageRef.downloadURL()
            downloadURLs.append(downloadURL.absoluteString)
        }

        return downloadURLs
    }

    /// Create post with image upload
    func createPostWithImages(
        content: String,
        category: Post.PostCategory,
        images: [UIImage],
        topicTag: String? = nil,
        visibility: Post.PostVisibility = .everyone,
        allowComments: Bool = true,
        linkURL: String? = nil
    ) async throws {
        // Upload images first
        let imageURLs = try await uploadPostImages(images)

        // Create post with image URLs
        try await createPost(
            content: content,
            category: category,
            topicTag: topicTag,
            visibility: visibility,
            allowComments: allowComments,
            imageURLs: imageURLs,
            linkURL: linkURL
        )
    }
    
    // MARK: - Post Analytics
    
    /// Track post view/impression
    func trackPostView(postId: String) async throws {
        guard let userId = firebaseManager.currentUser?.uid else { return }
        
        let viewData: [String: Any] = [
            "userId": userId,
            "timestamp": Date(),
            "postId": postId
        ]
        
        try await db.collection("postViews")
            .document("\(postId)_\(userId)")
            .setData(viewData, merge: true)
        
        // Update view count on post
        try await db.collection(FirebaseManager.CollectionPath.posts)
            .document(postId)
            .updateData([
                "viewCount": FieldValue.increment(Int64(1))
            ])
    }
    
    /// Get post analytics
    func getPostAnalytics(postId: String) async throws -> PostAnalytics {
        let postDoc = try await db.collection(FirebaseManager.CollectionPath.posts)
            .document(postId)
            .getDocument()
        
        guard let data = postDoc.data() else {
            throw FirebaseError.documentNotFound
        }
        
        let viewCount = data["viewCount"] as? Int ?? 0
        let amenCount = data["amenCount"] as? Int ?? 0
        let lightbulbCount = data["lightbulbCount"] as? Int ?? 0
        let commentCount = data["commentCount"] as? Int ?? 0
        let repostCount = data["repostCount"] as? Int ?? 0
        
        // Calculate engagement rate
        let totalEngagements = amenCount + lightbulbCount + commentCount + repostCount
        let engagementRate = viewCount > 0 ? Double(totalEngagements) / Double(viewCount) : 0.0
        
        return PostAnalytics(
            postId: postId,
            viewCount: viewCount,
            amenCount: amenCount,
            lightbulbCount: lightbulbCount,
            commentCount: commentCount,
            repostCount: repostCount,
            totalEngagements: totalEngagements,
            engagementRate: engagementRate
        )
    }
    
    // MARK: - Post Saving (Bookmarking)
    
    /// Save/bookmark a post
    func savePost(postId: String) async throws {
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        print("💾 Saving post: \(postId)")
        
        let savedPostData: [String: Any] = [
            "userId": userId,
            "postId": postId,
            "savedAt": Date()
        ]
        
        try await db.collection(FirebaseManager.CollectionPath.savedPosts)
            .document("\(userId)_\(postId)")
            .setData(savedPostData)
        
        print("✅ Post saved successfully")
        
        // Haptic feedback
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
    }
    
    /// Unsave/unbookmark a post
    func unsavePost(postId: String) async throws {
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        print("🗑️ Unsaving post: \(postId)")
        
        try await db.collection(FirebaseManager.CollectionPath.savedPosts)
            .document("\(userId)_\(postId)")
            .delete()
        
        print("✅ Post unsaved successfully")
        
        // Haptic feedback
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
    }
    
    /// Check if post is saved by current user
    func isPostSaved(postId: String) async throws -> Bool {
        guard let userId = firebaseManager.currentUser?.uid else {
            return false
        }
        
        let doc = try await db.collection(FirebaseManager.CollectionPath.savedPosts)
            .document("\(userId)_\(postId)")
            .getDocument()
        
        return doc.exists
    }
    
    // MARK: - Post Reporting
    
    /// Report a post for inappropriate content
    func reportPost(
        postId: String,
        reason: PostReportReason,
        additionalDetails: String? = nil
    ) async throws {
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        print("🚨 Reporting post: \(postId)")
        
        let reportData: [String: Any] = [
            "postId": postId,
            "reportedBy": userId,
            "reason": reason.rawValue,
            "additionalDetails": additionalDetails ?? "",
            "reportedAt": Date(),
            "status": "pending" // pending, reviewed, resolved
        ]
        
        try await db.collection("postReports")
            .addDocument(data: reportData)
        
        print("✅ Post reported successfully")
        
        // Haptic feedback
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.warning)
    }
    
    // MARK: - Post Pinning
    
    /// Pin a post to the top of user's profile
    func pinPost(postId: String) async throws {
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        // Verify user owns the post
        let postDoc = try await db.collection(FirebaseManager.CollectionPath.posts)
            .document(postId)
            .getDocument()
        
        guard let authorId = postDoc.data()?["authorId"] as? String,
              authorId == userId else {
            throw FirebaseError.unauthorized
        }
        
        print("📌 Pinning post: \(postId)")
        
        // Mark post as pinned
        try await db.collection(FirebaseManager.CollectionPath.posts)
            .document(postId)
            .updateData([
                "isPinned": true,
                "pinnedAt": Date()
            ])
        
        // Unpin other posts (only one pinned post at a time)
        let pinnedPosts = try await db.collection(FirebaseManager.CollectionPath.posts)
            .whereField("authorId", isEqualTo: userId)
            .whereField("isPinned", isEqualTo: true)
            .getDocuments()
        
        for doc in pinnedPosts.documents where doc.documentID != postId {
            try await doc.reference.updateData(["isPinned": false])
        }
        
        print("✅ Post pinned successfully")
    }
    
    /// Unpin a post
    func unpinPost(postId: String) async throws {
        guard firebaseManager.currentUser?.uid != nil else {
            throw FirebaseError.unauthorized
        }
        
        print("📌 Unpinning post: \(postId)")
        
        try await db.collection(FirebaseManager.CollectionPath.posts)
            .document(postId)
            .updateData([
                "isPinned": false,
                "pinnedAt": FieldValue.delete()
            ])
        
        print("✅ Post unpinned successfully")
    }
    
    // MARK: - Post Drafts
    
    /// Save post as draft
    func saveDraft(
        content: String,
        category: Post.PostCategory,
        images: [UIImage]? = nil,
        topicTag: String? = nil
    ) async throws -> String {
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        print("💾 Saving post draft...")
        
        // Upload images if any (as drafts)
        var imageURLs: [String]? = nil
        if let images = images, !images.isEmpty {
            imageURLs = try await uploadPostImages(images, postId: "draft_\(UUID().uuidString)")
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
        
        let draftData: [String: Any] = [
            "userId": userId,
            "content": content,
            "category": categoryString,
            "topicTag": topicTag as Any,
            "imageURLs": imageURLs as Any,
            "createdAt": Date(),
            "updatedAt": Date()
        ]
        
        let draftRef = try await db.collection("postDrafts")
            .addDocument(data: draftData)
        
        print("✅ Draft saved with ID: \(draftRef.documentID)")
        return draftRef.documentID
    }
    
    /// Load all drafts for current user
    func loadDrafts() async throws -> [FirebasePostDraft] {
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        print("📥 Loading drafts...")
        
        let snapshot = try await db.collection("postDrafts")
            .whereField("userId", isEqualTo: userId)
            .order(by: "updatedAt", descending: true)
            .getDocuments()
        
        let drafts = try snapshot.documents.compactMap { doc -> FirebasePostDraft? in
            try doc.data(as: FirebasePostDraft.self)
        }
        
        print("✅ Loaded \(drafts.count) drafts")
        return drafts
    }
    
    /// Delete draft
    func deleteDraft(draftId: String) async throws {
        print("🗑️ Deleting draft: \(draftId)")
        
        try await db.collection("postDrafts")
            .document(draftId)
            .delete()
        
        print("✅ Draft deleted successfully")
    }
    
    /// Publish draft as post
    func publishDraft(draftId: String) async throws {
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        print("📤 Publishing draft: \(draftId)")
        
        // Get draft
        let draftDoc = try await db.collection("postDrafts")
            .document(draftId)
            .getDocument()
        
        guard let draft = try? draftDoc.data(as: FirebasePostDraft.self) else {
            throw FirebaseError.documentNotFound
        }
        
        // Verify ownership
        guard draft.userId == userId else {
            throw FirebaseError.unauthorized
        }
        
        // Create post from draft
        try await createPost(
            content: draft.content,
            category: draft.category,
            topicTag: draft.topicTag,
            visibility: .everyone,
            allowComments: true,
            imageURLs: draft.imageURLs,
            linkURL: nil
        )
        
        // Delete draft
        try await deleteDraft(draftId: draftId)
        
        print("✅ Draft published successfully")
    }
    
    // MARK: - Scheduled Posts
    
    /// Schedule a post for future publishing
    func schedulePost(
        content: String,
        category: Post.PostCategory,
        scheduledFor: Date,
        images: [UIImage]? = nil,
        topicTag: String? = nil
    ) async throws -> String {
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        guard scheduledFor > Date() else {
            throw NSError(domain: "PostService", code: -1, 
                         userInfo: [NSLocalizedDescriptionKey: "Scheduled time must be in the future"])
        }
        
        print("📅 Scheduling post for: \(scheduledFor)")
        
        // Upload images if any
        var imageURLs: [String]? = nil
        if let images = images, !images.isEmpty {
            imageURLs = try await uploadPostImages(images, postId: "scheduled_\(UUID().uuidString)")
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
        
        let scheduledPostData: [String: Any] = [
            "userId": userId,
            "content": content,
            "category": categoryString,
            "topicTag": topicTag as Any,
            "imageURLs": imageURLs as Any,
            "scheduledFor": scheduledFor,
            "status": "scheduled", // scheduled, published, cancelled
            "createdAt": Date()
        ]
        
        let scheduledRef = try await db.collection("scheduledPosts")
            .addDocument(data: scheduledPostData)
        
        print("✅ Post scheduled with ID: \(scheduledRef.documentID)")
        
        // Note: You'll need a Cloud Function to publish scheduled posts
        // Or a background task that checks for scheduled posts to publish
        
        return scheduledRef.documentID
    }
    
    /// Cancel scheduled post
    func cancelScheduledPost(scheduledPostId: String) async throws {
        print("🚫 Cancelling scheduled post: \(scheduledPostId)")
        
        try await db.collection("scheduledPosts")
            .document(scheduledPostId)
            .updateData([
                "status": "cancelled",
                "cancelledAt": Date()
            ])
        
        print("✅ Scheduled post cancelled")
    }
    
    // MARK: - Block and Hide
    
    /// Hide post from feed (user-specific)
    func hidePost(postId: String) async throws {
        guard let userId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        print("🙈 Hiding post: \(postId)")
        
        let hiddenPostData: [String: Any] = [
            "userId": userId,
            "postId": postId,
            "hiddenAt": Date()
        ]
        
        try await db.collection("hiddenPosts")
            .document("\(userId)_\(postId)")
            .setData(hiddenPostData)
        
        print("✅ Post hidden successfully")
    }
    
    /// Check if post is hidden by current user
    func isPostHidden(postId: String) async throws -> Bool {
        guard let userId = firebaseManager.currentUser?.uid else {
            return false
        }
        
        let doc = try await db.collection("hiddenPosts")
            .document("\(userId)_\(postId)")
            .getDocument()
        
        return doc.exists
    }
}

// MARK: - Supporting Models

struct PostAnalytics {
    let postId: String
    let viewCount: Int
    let amenCount: Int
    let lightbulbCount: Int
    let commentCount: Int
    let repostCount: Int
    let totalEngagements: Int
    let engagementRate: Double
    
    var formattedEngagementRate: String {
        String(format: "%.1f%%", engagementRate * 100)
    }
}

struct FirebasePostDraft: Codable, Identifiable {
    @DocumentID var id: String?
    var userId: String
    var content: String
    var category: Post.PostCategory
    var topicTag: String?
    var imageURLs: [String]?
    var createdAt: Date
    var updatedAt: Date
}

enum PostReportReason: String, CaseIterable {
    case spam = "Spam"
    case harassment = "Harassment"
    case hateSpeech = "Hate Speech"
    case violence = "Violence"
    case sexualContent = "Sexual Content"
    case misinformation = "Misinformation"
    case other = "Other"
}

// MARK: - Firebase Storage Extension

extension StorageReference {
    func putDataAsync(_ data: Data, metadata: StorageMetadata?) async throws -> StorageMetadata {
        return try await withCheckedThrowingContinuation { continuation in
            self.putData(data, metadata: metadata) { metadata, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let metadata = metadata {
                    continuation.resume(returning: metadata)
                } else {
                    continuation.resume(throwing: NSError(domain: "StorageError", code: -1))
                }
            }
        }
    }
}
