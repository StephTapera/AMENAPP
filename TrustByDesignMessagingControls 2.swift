//
//  TrustByDesignMessagingControls.swift
//  AMENAPP
//
//  Trust-by-Design Messaging & Contact Controls
//  Prevents abuse before it starts with granular privacy controls
//

import Foundation
import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Permission Levels

enum DMPermissionLevel: String, Codable, CaseIterable {
    case everyone = "everyone"
    case followersOnly = "followers_only"
    case mutualsOnly = "mutuals_only"
    case nobody = "nobody"
    
    var displayName: String {
        switch self {
        case .everyone: return "Everyone"
        case .followersOnly: return "Followers Only"
        case .mutualsOnly: return "Mutual Follows Only"
        case .nobody: return "Nobody"
        }
    }
    
    var description: String {
        switch self {
        case .everyone: return "Anyone can send you messages"
        case .followersOnly: return "Only people who follow you"
        case .mutualsOnly: return "Only people you both follow"
        case .nobody: return "No one can send you messages"
        }
    }
}

enum CommentPermissionLevel: String, Codable, CaseIterable {
    case everyone = "everyone"
    case followersOnly = "followers_only"
    case mutualsOnly = "mutuals_only"
    case nobody = "nobody"
    
    var displayName: String {
        switch self {
        case .everyone: return "Everyone"
        case .followersOnly: return "Followers Only"
        case .mutualsOnly: return "Mutual Follows Only"
        case .nobody: return "Turn Off Comments"
        }
    }
}

enum MentionPermissionLevel: String, Codable, CaseIterable {
    case everyone = "everyone"
    case followersOnly = "followers_only"
    case mutualsOnly = "mutuals_only"
    case nobody = "nobody"
    
    var displayName: String {
        switch self {
        case .everyone: return "Everyone"
        case .followersOnly: return "Followers Only"
        case .mutualsOnly: return "Mutual Follows Only"
        case .nobody: return "Nobody"
        }
    }
}

// MARK: - Quiet Block Action Types

enum QuietBlockAction: String, Codable {
    case block = "block"                    // Full block (can't see, DM, comment)
    case mute = "mute"                      // Hide their content
    case restrict = "restrict"              // Shadowban (they don't know)
    case hideReplies = "hide_replies"       // Hide their comment replies
    case limitMentions = "limit_mentions"   // Prevent @mentions
}

// MARK: - Trust Privacy Settings

struct TrustPrivacySettings: Codable {
    let userId: String
    
    // DM Controls
    var dmPermissionLevel: DMPermissionLevel
    var hideLinksInRequests: Bool
    var hideMediaInRequests: Bool
    
    // Comment Controls
    var defaultCommentPermission: CommentPermissionLevel
    
    // Mention Controls
    var mentionPermissionLevel: MentionPermissionLevel
    
    // Anti-Harassment
    var blockRepeatedMessageAttempts: Bool
    var autoRestrictAfterReports: Int  // Auto-restrict after N reports
    
    var createdAt: Date
    var updatedAt: Date
    
    // Conservative defaults for new users
    static func conservative(userId: String) -> TrustPrivacySettings {
        TrustPrivacySettings(
            userId: userId,
            dmPermissionLevel: .mutualsOnly,
            hideLinksInRequests: true,
            hideMediaInRequests: true,
            defaultCommentPermission: .everyone,
            mentionPermissionLevel: .followersOnly,
            blockRepeatedMessageAttempts: true,
            autoRestrictAfterReports: 3,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

// NOTE: MessageRequest already exists in MessageModels.swift
// We extend it with privacy-specific properties

// MARK: - Quiet Block Record

struct QuietBlockRecord: Codable {
    let id: String
    let userId: String              // Who is blocking
    let targetUserId: String        // Who is being blocked
    let action: QuietBlockAction
    let reason: String?
    let createdAt: Date
    
    // Restrict-specific (shadowban behavior)
    var isRestricted: Bool {
        return action == .restrict
    }
}

// MARK: - Repeated Contact Attempt

struct RepeatedContactAttempt: Codable {
    let targetUserId: String        // User being contacted
    let fromUserId: String          // User attempting contact
    var attemptCount: Int
    var lastAttemptAt: Date
    var isBlocked: Bool
    
    // Auto-block after 3 attempts in 24 hours
    func shouldAutoBlock() -> Bool {
        let dayAgo = Date().addingTimeInterval(-24 * 60 * 60)
        return attemptCount >= 3 && lastAttemptAt > dayAgo
    }
}

// MARK: - Trust By Design Service

@MainActor
class TrustByDesignService: ObservableObject {
    static let shared = TrustByDesignService()
    
    private let db = Firestore.firestore()
    
    @Published var userSettings: TrustPrivacySettings?
    @Published var messageRequests: [Conversation] = []  // Use existing Conversation model
    @Published var unreadRequestCount: Int = 0
    
    private init() {}
    
    // MARK: - Settings Management
    
    /// Load user privacy settings
    func loadPrivacySettings(userId: String) async throws {
        let doc = try await db.collection("user_privacy_settings").document(userId).getDocument()
        
        if doc.exists, let settings = try? doc.data(as: TrustPrivacySettings.self) {
            self.userSettings = settings
        } else {
            // Create conservative defaults for new users
            let newSettings = TrustPrivacySettings.conservative(userId: userId)
            try await savePrivacySettings(newSettings)
            self.userSettings = newSettings
        }
    }
    
    /// Save privacy settings
    func savePrivacySettings(_ settings: TrustPrivacySettings) async throws {
        var updatedSettings = settings
        updatedSettings.updatedAt = Date()
        
        try db.collection("user_privacy_settings")
            .document(settings.userId)
            .setData(from: updatedSettings)
        
        self.userSettings = updatedSettings
    }
    
    /// Update DM permission level
    func updateDMPermission(_ level: DMPermissionLevel, userId: String) async throws {
        guard var settings = userSettings else { return }
        settings.dmPermissionLevel = level
        try await savePrivacySettings(settings)
    }
    
    /// Update comment permission default
    func updateCommentPermission(_ level: CommentPermissionLevel, userId: String) async throws {
        guard var settings = userSettings else { return }
        settings.defaultCommentPermission = level
        try await savePrivacySettings(settings)
    }
    
    /// Update mention permission level
    func updateMentionPermission(_ level: MentionPermissionLevel, userId: String) async throws {
        guard var settings = userSettings else { return }
        settings.mentionPermissionLevel = level
        try await savePrivacySettings(settings)
    }
    
    // MARK: - DM Permission Checking
    
    /// Check if user can send DM to another user
    func canSendDM(from fromUserId: String, to toUserId: String) async throws -> Bool {
        // Load target user's settings
        let doc = try await db.collection("user_privacy_settings").document(toUserId).getDocument()
        
        guard let settings = try? doc.data(as: TrustPrivacySettings.self) else {
            // Default to conservative if no settings
            return try await areMutualFollows(fromUserId, toUserId)
        }
        
        switch settings.dmPermissionLevel {
        case .everyone:
            return true
            
        case .followersOnly:
            return try await isFollower(fromUserId, of: toUserId)
            
        case .mutualsOnly:
            return try await areMutualFollows(fromUserId, toUserId)
            
        case .nobody:
            return false
        }
    }
    
    /// Check if user can comment on a post
    func canComment(userId: String, on postId: String, authorId: String, postPermission: CommentPermissionLevel?) async throws -> Bool {
        // Use post-specific permission if set, otherwise user default
        let permission: CommentPermissionLevel
        if let postPerm = postPermission {
            permission = postPerm
        } else {
            // Load author's default settings
            let doc = try await db.collection("user_privacy_settings").document(authorId).getDocument()
            if let settings = try? doc.data(as: TrustPrivacySettings.self) {
                permission = settings.defaultCommentPermission
            } else {
                permission = .everyone  // Default if no settings
            }
        }
        
        switch permission {
        case .everyone:
            return true
            
        case .followersOnly:
            return try await isFollower(userId, of: authorId)
            
        case .mutualsOnly:
            return try await areMutualFollows(userId, authorId)
            
        case .nobody:
            return false
        }
    }
    
    /// Check if user can mention another user
    func canMention(from fromUserId: String, mention toUserId: String) async throws -> Bool {
        let doc = try await db.collection("user_privacy_settings").document(toUserId).getDocument()
        
        guard let settings = try? doc.data(as: TrustPrivacySettings.self) else {
            return try await isFollower(fromUserId, of: toUserId)
        }
        
        switch settings.mentionPermissionLevel {
        case .everyone:
            return true
            
        case .followersOnly:
            return try await isFollower(fromUserId, of: toUserId)
            
        case .mutualsOnly:
            return try await areMutualFollows(fromUserId, toUserId)
            
        case .nobody:
            return false
        }
    }
    
    // MARK: - Message Requests
    
    /// Create message request (conversation with pending status)
    func createMessageRequest(from fromUserId: String, to toUserId: String, initialMessage: String) async throws {
        guard Auth.auth().currentUser != nil else { return }
        
        // Get sender info
        let userDoc = try await db.collection("users").document(fromUserId).getDocument()
        let displayName = userDoc.data()?["displayName"] as? String ?? "User"
        let profileImageURL = userDoc.data()?["profileImageURL"] as? String
        
        // Create conversation with "pending" status
        let conversationId = UUID().uuidString
        let conversation = Conversation(
            id: conversationId,
            participants: [fromUserId, toUserId],
            participantNames: [fromUserId: displayName],
            participantPhotos: [fromUserId: profileImageURL ?? ""],
            lastMessage: initialMessage,
            lastMessageSenderId: fromUserId,
            lastMessageTime: Date(),
            unreadCount: [toUserId: 1],
            conversationStatus: "pending",
            requesterId: fromUserId,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        // Save to conversations collection with pending status
        let docRef = db.collection("conversations").document(conversationId)
        try docRef.setData(from: conversation)
    }
    
    /// Load message requests for user (pending conversations)
    func loadMessageRequests(userId: String) async throws {
        let snapshot = try await db.collection("conversations")
            .whereField("participants", arrayContains: userId)
            .whereField("conversationStatus", isEqualTo: "pending")
            .order(by: "createdAt", descending: true)
            .getDocuments()
        
        let requests = snapshot.documents.compactMap { try? $0.data(as: Conversation.self) }
            .filter { $0.requesterId != userId }  // Only show requests TO this user
        
        await MainActor.run {
            self.messageRequests = requests
            self.unreadRequestCount = requests.count
        }
    }
    
    /// Accept message request
    func acceptMessageRequest(_ conversationId: String) async throws {
        try await db.collection("conversations")
            .document(conversationId)
            .updateData([
                "conversationStatus": "accepted",
                "updatedAt": FieldValue.serverTimestamp()
            ])
        
        // Remove from local list
        messageRequests.removeAll { $0.id == conversationId }
        unreadRequestCount = messageRequests.count
    }
    
    /// Reject message request
    func rejectMessageRequest(_ conversationId: String) async throws {
        try await db.collection("conversations")
            .document(conversationId)
            .updateData([
                "conversationStatus": "rejected",
                "updatedAt": FieldValue.serverTimestamp()
            ])
        
        messageRequests.removeAll { $0.id == conversationId }
        unreadRequestCount = messageRequests.count
    }
    
    // MARK: - Quiet Block Actions
    
    /// Perform quiet block action
    func performQuietBlock(userId: String, targetUserId: String, action: QuietBlockAction, reason: String? = nil) async throws {
        let record = QuietBlockRecord(
            id: UUID().uuidString,
            userId: userId,
            targetUserId: targetUserId,
            action: action,
            reason: reason,
            createdAt: Date()
        )
        
        try db.collection("quiet_blocks")
            .document(record.id)
            .setData(from: record)
        
        print("🛡️ Quiet block applied: \(action.rawValue) on \(targetUserId)")
    }
    
    /// Check if user is blocked by quiet action
    func isQuietBlocked(userId: String, by targetUserId: String, action: QuietBlockAction) async throws -> Bool {
        let snapshot = try await db.collection("quiet_blocks")
            .whereField("userId", isEqualTo: targetUserId)
            .whereField("targetUserId", isEqualTo: userId)
            .whereField("action", isEqualTo: action.rawValue)
            .limit(to: 1)
            .getDocuments()
        
        return !snapshot.isEmpty
    }
    
    // MARK: - Anti-Harassment Repeat Detection
    
    /// Record contact attempt
    func recordContactAttempt(from fromUserId: String, to toUserId: String) async throws {
        let docId = "\(toUserId)_\(fromUserId)"
        let docRef = db.collection("repeated_contact_attempts").document(docId)
        
        let doc = try await docRef.getDocument()
        
        if var attempt = try? doc.data(as: RepeatedContactAttempt.self) {
            // Increment attempt
            attempt.attemptCount += 1
            attempt.lastAttemptAt = Date()
            
            // Auto-block if threshold exceeded
            if attempt.shouldAutoBlock() {
                attempt.isBlocked = true
                try await performQuietBlock(userId: toUserId, targetUserId: fromUserId, action: .block, reason: "Repeated unwanted contact")
            }
            
            try docRef.setData(from: attempt)
        } else {
            // First attempt
            let attempt = RepeatedContactAttempt(
                targetUserId: toUserId,
                fromUserId: fromUserId,
                attemptCount: 1,
                lastAttemptAt: Date(),
                isBlocked: false
            )
            try docRef.setData(from: attempt)
        }
    }
    
    /// Check if blocked due to repeated attempts
    func isBlockedByRepeatedAttempts(from fromUserId: String, to toUserId: String) async throws -> Bool {
        let docId = "\(toUserId)_\(fromUserId)"
        let doc = try await db.collection("repeated_contact_attempts").document(docId).getDocument()
        
        guard let attempt = try? doc.data(as: RepeatedContactAttempt.self) else {
            return false
        }
        
        return attempt.isBlocked
    }
    
    // MARK: - Helper Functions
    
    private func isFollower(_ userId: String, of targetUserId: String) async throws -> Bool {
        let snapshot = try await db.collection("follows")
            .whereField("followerId", isEqualTo: userId)
            .whereField("followingId", isEqualTo: targetUserId)
            .limit(to: 1)
            .getDocuments()
        
        return !snapshot.isEmpty
    }
    
    private func areMutualFollows(_ userId1: String, _ userId2: String) async throws -> Bool {
        let follows1 = try await isFollower(userId1, of: userId2)
        let follows2 = try await isFollower(userId2, of: userId1)
        return follows1 && follows2
    }
}
