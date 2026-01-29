//
//  ModerationService.swift
//  AMENAPP
//
//  Created by Steph on 1/21/26.
//
//  Service for content moderation, reporting, blocking, and muting users
//

import Foundation
import FirebaseFirestore
import Combine
import FirebaseAuth

// MARK: - Report Models

struct ContentReport: Identifiable, Codable {
    @DocumentID var id: String?
    var reporterId: String
    var reporterName: String
    var reportedUserId: String?
    var reportedPostId: String?
    var reportedCommentId: String?
    var reason: String
    var reasonCategory: String
    var additionalDetails: String?
    var status: String  // "pending", "reviewed", "action_taken", "dismissed"
    var createdAt: Date
    var reviewedAt: Date?
    var reviewedBy: String?
    var actionTaken: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case reporterId
        case reporterName
        case reportedUserId
        case reportedPostId
        case reportedCommentId
        case reason
        case reasonCategory
        case additionalDetails
        case status
        case createdAt
        case reviewedAt
        case reviewedBy
        case actionTaken
    }
}

enum ModerationReportReason: String, CaseIterable {
    case spam = "Spam or misleading"
    case harassment = "Harassment or bullying"
    case hateSpeech = "Hate speech or violence"
    case inappropriateContent = "Inappropriate content"
    case falseInformation = "False information"
    case offTopic = "Off-topic or irrelevant"
    case copyright = "Copyright violation"
    case other = "Other"
    
    var icon: String {
        switch self {
        case .spam: return "envelope.badge.fill"
        case .harassment: return "exclamationmark.bubble.fill"
        case .hateSpeech: return "hand.raised.fill"
        case .inappropriateContent: return "eye.slash.fill"
        case .falseInformation: return "checkmark.seal.fill"
        case .offTopic: return "arrow.triangle.branch"
        case .copyright: return "c.circle.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }
    
    var description: String {
        switch self {
        case .spam:
            return "Unwanted commercial content or repetitive posts"
        case .harassment:
            return "Targeted harassment, threats, or bullying"
        case .hateSpeech:
            return "Content promoting violence or hatred"
        case .inappropriateContent:
            return "Sexually explicit or disturbing content"
        case .falseInformation:
            return "Deliberately misleading or false claims"
        case .offTopic:
            return "Content that doesn't fit this category"
        case .copyright:
            return "Unauthorized use of copyrighted material"
        case .other:
            return "Something else that violates community guidelines"
        }
    }
}

struct BlockedUserRelationship: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String           // User who blocked
    var blockedUserId: String    // User who is blocked
    var blockedAt: Date
    var reason: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case blockedUserId
        case blockedAt
        case reason
    }
}

struct MutedUser: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String          // User who muted
    var mutedUserId: String     // User who is muted
    var mutedAt: Date
    var mutedUntil: Date?       // Optional expiration
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case mutedUserId
        case mutedAt
        case mutedUntil
    }
}

// MARK: - Moderation Service

@MainActor
class ModerationService: ObservableObject {
    static let shared = ModerationService()
    
    @Published var blockedUsers: Set<String> = []
    @Published var mutedUsers: Set<String> = []
    @Published var reportedContent: [ContentReport] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let db = Firestore.firestore()
    private let firebaseManager = FirebaseManager.shared
    private var listeners: [ListenerRegistration] = []
    
    private init() {}
    
    // MARK: - Report Content
    
    /// Report a post
    func reportPost(
        postId: String,
        postAuthorId: String,
        reason: ModerationReportReason,
        additionalDetails: String?
    ) async throws {
        print("🚨 Reporting post: \(postId)")
        
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        // Fetch reporter's name
        let userDoc = try await db.collection(FirebaseManager.CollectionPath.users)
            .document(currentUserId)
            .getDocument()
        
        let reporterName = userDoc.data()?["displayName"] as? String ?? "Anonymous"
        
        let report = ContentReport(
            reporterId: currentUserId,
            reporterName: reporterName,
            reportedUserId: postAuthorId,
            reportedPostId: postId,
            reportedCommentId: nil,
            reason: reason.rawValue,
            reasonCategory: reason.rawValue,
            additionalDetails: additionalDetails,
            status: "pending",
            createdAt: Date()
        )
        
        try await db.collection(FirebaseManager.CollectionPath.reports)
            .addDocument(from: report)
        
        print("✅ Report submitted successfully")
        
        // Haptic feedback
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
    }
    
    /// Report a comment
    func reportComment(
        commentId: String,
        commentAuthorId: String,
        postId: String,
        reason: ModerationReportReason,
        additionalDetails: String?
    ) async throws {
        print("🚨 Reporting comment: \(commentId)")
        
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        let userDoc = try await db.collection(FirebaseManager.CollectionPath.users)
            .document(currentUserId)
            .getDocument()
        
        let reporterName = userDoc.data()?["displayName"] as? String ?? "Anonymous"
        
        let report = ContentReport(
            reporterId: currentUserId,
            reporterName: reporterName,
            reportedUserId: commentAuthorId,
            reportedPostId: postId,
            reportedCommentId: commentId,
            reason: reason.rawValue,
            reasonCategory: reason.rawValue,
            additionalDetails: additionalDetails,
            status: "pending",
            createdAt: Date()
        )
        
        try await db.collection(FirebaseManager.CollectionPath.reports)
            .addDocument(from: report)
        
        print("✅ Comment report submitted successfully")
        
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
    }
    
    /// Report a user
    func reportUser(
        userId: String,
        reason: ModerationReportReason,
        additionalDetails: String?
    ) async throws {
        print("🚨 Reporting user: \(userId)")
        
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        let userDoc = try await db.collection(FirebaseManager.CollectionPath.users)
            .document(currentUserId)
            .getDocument()
        
        let reporterName = userDoc.data()?["displayName"] as? String ?? "Anonymous"
        
        let report = ContentReport(
            reporterId: currentUserId,
            reporterName: reporterName,
            reportedUserId: userId,
            reportedPostId: nil,
            reportedCommentId: nil,
            reason: reason.rawValue,
            reasonCategory: reason.rawValue,
            additionalDetails: additionalDetails,
            status: "pending",
            createdAt: Date()
        )
        
        try await db.collection(FirebaseManager.CollectionPath.reports)
            .addDocument(from: report)
        
        print("✅ User report submitted successfully")
        
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
    }
    
    // MARK: - Block User
    
    /// Block a user
    func blockUser(userId: String, reason: String? = nil) async throws {
        print("🚫 Blocking user: \(userId)")
        
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        // Don't block yourself
        guard userId != currentUserId else {
            print("⚠️ Cannot block yourself")
            return
        }
        
        // Check if already blocked
        if blockedUsers.contains(userId) {
            print("⚠️ User already blocked")
            return
        }
        
        let block = BlockedUserRelationship(
            userId: currentUserId,
            blockedUserId: userId,
            blockedAt: Date(),
            reason: reason
        )
        
        try await db.collection(FirebaseManager.CollectionPath.blockedUsers)
            .addDocument(from: block)
        
        print("✅ User blocked successfully")
        
        // Update local cache
        blockedUsers.insert(userId)
        
        // Also unfollow if following
        if await FollowService.shared.isFollowing(userId: userId) {
            try? await FollowService.shared.unfollowUser(userId: userId)
        }
        
        // Haptic feedback
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.warning)
    }
    
    /// Unblock a user
    func unblockUser(userId: String) async throws {
        print("🔓 Unblocking user: \(userId)")
        
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        // Find the block document
        let query = db.collection(FirebaseManager.CollectionPath.blockedUsers)
            .whereField("userId", isEqualTo: currentUserId)
            .whereField("blockedUserId", isEqualTo: userId)
            .limit(to: 1)
        
        let snapshot = try await query.getDocuments()
        
        guard let blockDoc = snapshot.documents.first else {
            print("⚠️ User not blocked")
            return
        }
        
        try await blockDoc.reference.delete()
        
        print("✅ User unblocked successfully")
        
        // Update local cache
        blockedUsers.remove(userId)
        
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
    }
    
    /// Check if user is blocked
    func isBlocked(userId: String) async -> Bool {
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            return false
        }
        
        // Check local cache
        if blockedUsers.contains(userId) {
            return true
        }
        
        // Check Firestore
        do {
            let query = db.collection(FirebaseManager.CollectionPath.blockedUsers)
                .whereField("userId", isEqualTo: currentUserId)
                .whereField("blockedUserId", isEqualTo: userId)
                .limit(to: 1)
            
            let snapshot = try await query.getDocuments()
            let isBlocked = !snapshot.documents.isEmpty
            
            if isBlocked {
                blockedUsers.insert(userId)
            }
            
            return isBlocked
        } catch {
            return false
        }
    }
    
    // MARK: - Mute User
    
    /// Mute a user (hide their posts from feed)
    func muteUser(userId: String, duration: TimeInterval? = nil) async throws {
        print("🔇 Muting user: \(userId)")
        
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        // Don't mute yourself
        guard userId != currentUserId else {
            print("⚠️ Cannot mute yourself")
            return
        }
        
        // Check if already muted
        if mutedUsers.contains(userId) {
            print("⚠️ User already muted")
            return
        }
        
        let mutedUntil = duration != nil ? Date().addingTimeInterval(duration!) : nil
        
        let mute = MutedUser(
            userId: currentUserId,
            mutedUserId: userId,
            mutedAt: Date(),
            mutedUntil: mutedUntil
        )
        
        try await db.collection(FirebaseManager.CollectionPath.mutedUsers)
            .addDocument(from: mute)
        
        print("✅ User muted successfully")
        
        // Update local cache
        mutedUsers.insert(userId)
        
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
    }
    
    /// Unmute a user
    func unmuteUser(userId: String) async throws {
        print("🔊 Unmuting user: \(userId)")
        
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        // Find the mute document
        let query = db.collection(FirebaseManager.CollectionPath.mutedUsers)
            .whereField("userId", isEqualTo: currentUserId)
            .whereField("mutedUserId", isEqualTo: userId)
            .limit(to: 1)
        
        let snapshot = try await query.getDocuments()
        
        guard let muteDoc = snapshot.documents.first else {
            print("⚠️ User not muted")
            return
        }
        
        try await muteDoc.reference.delete()
        
        print("✅ User unmuted successfully")
        
        // Update local cache
        mutedUsers.remove(userId)
        
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
    }
    
    /// Check if user is muted
    func isMuted(userId: String) async -> Bool {
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            return false
        }
        
        // Check local cache
        if mutedUsers.contains(userId) {
            return true
        }
        
        // Check Firestore
        do {
            let query = db.collection(FirebaseManager.CollectionPath.mutedUsers)
                .whereField("userId", isEqualTo: currentUserId)
                .whereField("mutedUserId", isEqualTo: userId)
                .limit(to: 1)
            
            let snapshot = try await query.getDocuments()
            
            guard let muteDoc = snapshot.documents.first else {
                return false
            }
            
            // Check if mute has expired
            if let mutedUntilTimestamp = muteDoc.data()["mutedUntil"] as? Timestamp {
                let mutedUntil = mutedUntilTimestamp.dateValue()
                if mutedUntil < Date() {
                    // Mute expired, remove it
                    try? await muteDoc.reference.delete()
                    return false
                }
            }
            
            mutedUsers.insert(userId)
            return true
            
        } catch {
            return false
        }
    }
    
    // MARK: - Fetch Lists
    
    /// Fetch all blocked users
    func fetchBlockedUsers() async throws -> [String] {
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        let snapshot = try await db.collection(FirebaseManager.CollectionPath.blockedUsers)
            .whereField("userId", isEqualTo: currentUserId)
            .order(by: "blockedAt", descending: true)
            .getDocuments()
        
        let blocked = snapshot.documents.compactMap { $0.data()["blockedUserId"] as? String }
        blockedUsers = Set(blocked)
        
        print("✅ Fetched \(blocked.count) blocked users")
        
        return blocked
    }
    
    /// Fetch all muted users
    func fetchMutedUsers() async throws -> [String] {
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        let snapshot = try await db.collection(FirebaseManager.CollectionPath.mutedUsers)
            .whereField("userId", isEqualTo: currentUserId)
            .order(by: "mutedAt", descending: true)
            .getDocuments()
        
        var muted: [String] = []
        
        for doc in snapshot.documents {
            // Check if mute is still active
            if let mutedUntilTimestamp = doc.data()["mutedUntil"] as? Timestamp {
                let mutedUntil = mutedUntilTimestamp.dateValue()
                if mutedUntil < Date() {
                    // Mute expired, remove it
                    try? await doc.reference.delete()
                    continue
                }
            }
            
            if let mutedUserId = doc.data()["mutedUserId"] as? String {
                muted.append(mutedUserId)
            }
        }
        
        mutedUsers = Set(muted)
        
        print("✅ Fetched \(muted.count) muted users")
        
        return muted
    }
    
    // MARK: - Load Current User's Data
    
    func loadCurrentUserModeration() async {
        do {
            _ = try await fetchBlockedUsers()
            _ = try await fetchMutedUsers()
            print("✅ Loaded moderation data")
        } catch {
            print("❌ Failed to load moderation data: \(error)")
        }
    }
    
    // MARK: - Content Filtering
    
    /// Filter out posts from blocked/muted users
    func filterPosts(_ posts: [Post]) -> [Post] {
        return posts.filter { post in
            let authorId = post.id.uuidString // Assuming authorId can be derived
            return !blockedUsers.contains(authorId) && !mutedUsers.contains(authorId)
        }
    }
}

// MARK: - Firestore Collection Paths

extension FirebaseManager.CollectionPath {
    static let reports = "reports"
    static let blockedUsers = "blockedUsers"
    static let mutedUsers = "mutedUsers"
}
