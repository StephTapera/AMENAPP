import Foundation
import Firebase
import FirebaseFirestore
import FirebaseAuth

// MARK: - Data Models

enum MessagePrivacy: String, Codable {
    case anyone = "anyone"
    case followers = "followers"
}

enum MessageStatus {
    case unlimited
    case messageRequest
    case blocked
}

// Note: If you have existing User, Follow, Conversation, or Message models,
// you can extend them instead of redefining them here.
// Just make sure they have the required fields listed below.

/*
// Required fields for User model:
struct User {
    let id: String
    let username: String
    let messagePrivacy: MessagePrivacy  // NEW
    let followersCount: Int
    let followingCount: Int
    // ... other fields
}

// Required fields for Follow model:
struct Follow {
    let followerId: String
    let followerUserId: String  // For backward compatibility
    let followingId: String
    let followingUserId: String  // For backward compatibility
    let createdAt: Date
}

// Required fields for Conversation model:
struct Conversation {
    let id: String
    let participantIds: [String]
    let messageCounts: [String: Int]  // NEW
    // ... other fields
}

// Required fields for Message model:
struct Message {
    let id: String
    let senderId: String
    let text: String
    let createdAt: Date
    // ... other fields
}
*/

// MARK: - Messaging Extensions Service
// These are extension methods that work with your existing services

// MARK: - User Service Extensions

class UserServiceExtensions {
    static let shared = UserServiceExtensions()
    private let db = Firestore.firestore()
    
    private init() {}
    
    /// Update user's message privacy setting
    func updateMessagePrivacy(to privacy: MessagePrivacy) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        try await db.collection("users").document(userId).updateData([
            "messagePrivacy": privacy.rawValue,
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }
    
    /// Get user's message privacy setting
    func getMessagePrivacy(for userId: String) async throws -> MessagePrivacy {
        let doc = try await db.collection("users").document(userId).getDocument()
        let privacy = doc.data()?["messagePrivacy"] as? String ?? "followers"
        return MessagePrivacy(rawValue: privacy) ?? .followers
    }
}

extension FollowService {
    
    /// Check if two users follow each other (mutual follow)
    func areFollowingEachOther(userId1: String, userId2: String) async throws -> Bool {
        let db = Firestore.firestore()
        
        let follow1 = try await db.collection("follows")
            .whereField("followerId", isEqualTo: userId1)
            .whereField("followingId", isEqualTo: userId2)
            .limit(to: 1)
            .getDocuments()
        
        let follow2 = try await db.collection("follows")
            .whereField("followerId", isEqualTo: userId2)
            .whereField("followingId", isEqualTo: userId1)
            .limit(to: 1)
            .getDocuments()
        
        return !follow1.documents.isEmpty && !follow2.documents.isEmpty
    }
    
    /// Check if another user follows current user
    func isFollowedBy(userId: String) async throws -> Bool {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return false }
        
        let snapshot = try await Firestore.firestore().collection("follows")
            .whereField("followerId", isEqualTo: userId)
            .whereField("followingId", isEqualTo: currentUserId)
            .limit(to: 1)
            .getDocuments()
        
        return !snapshot.documents.isEmpty
    }
}

// MARK: - New Messaging Service

class MessagingPermissionService {
    static let shared = MessagingPermissionService()
    private let db = Firestore.firestore()
    
    /// Check if current user can message another user and if it's limited
    func canMessageUser(_ targetUserId: String) async throws -> (canMessage: Bool, isLimited: Bool) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return (false, false)
        }
        
        // Check if blocked
        let blockedByThem = try await db.collection("users")
            .document(targetUserId)
            .collection("blockedUsers")
            .document(currentUserId)
            .getDocument()
        
        let blockedByMe = try await db.collection("users")
            .document(currentUserId)
            .collection("blockedUsers")
            .document(targetUserId)
            .getDocument()
        
        if blockedByThem.exists || blockedByMe.exists {
            return (false, false)
        }
        
        // Get target user's privacy settings
        let privacy = try await UserServiceExtensions.shared.getMessagePrivacy(for: targetUserId)
        
        // If they allow messages from anyone
        if privacy == .anyone {
            return (true, false)
        }
        
        // Check if mutual followers
        let areMutual = try await FollowService.shared.areFollowingEachOther(
            userId1: currentUserId,
            userId2: targetUserId
        )
        
        if areMutual {
            return (true, false)
        }
        
        // Otherwise, it's a message request (limited to 1 message)
        return (true, true)
    }
    
    /// Get message status for UI display
    func getMessageStatus(for userId: String) async -> MessageStatus {
        guard let (canMessage, isLimited) = try? await canMessageUser(userId) else {
            return .blocked
        }
        
        if !canMessage {
            return .blocked
        }
        
        if isLimited {
            return .messageRequest
        }
        
        return .unlimited
    }
    
    /// Get remaining message requests
    func getRemainingMessageRequests(for conversationId: String) async throws -> Int? {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return nil }
        
        let conversation = try await db.collection("conversations")
            .document(conversationId)
            .getDocument()
        
        guard let data = conversation.data() else { return nil }
        
        let participantIds = data["participantIds"] as? [String] ?? []
        let otherUserId = participantIds.first { $0 != currentUserId } ?? ""
        
        // Check if limited
        let (_, isLimited) = try await canMessageUser(otherUserId)
        
        if !isLimited {
            return nil  // Unlimited
        }
        
        let messageCounts = data["messageCounts"] as? [String: Int] ?? [:]
        let currentCount = messageCounts[currentUserId] ?? 0
        
        return max(0, 1 - currentCount)
    }
}

// MARK: - Messaging Extensions

extension FirebaseMessagingService {
    
    /// Create a new conversation with message permission checking
    func createConversationWithPermissions(with otherUserId: String) async throws -> String {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // Check permissions first
        let (canMessage, _) = try await MessagingPermissionService.shared.canMessageUser(otherUserId)
        guard canMessage else {
            throw NSError(domain: "Permission", code: -1, userInfo: [NSLocalizedDescriptionKey: "You cannot message this user"])
        }
        
        let conversationData: [String: Any] = [
            "participantIds": [currentUserId, otherUserId].sorted(),
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
            "messageCounts": [
                currentUserId: 0,
                otherUserId: 0
            ]
        ]
        
        let conversationRef = try await Firestore.firestore().collection("conversations").addDocument(data: conversationData)
        return conversationRef.documentID
    }
    
    /// Send a message with permission checking
    func sendMessageWithPermissions(to conversationId: String, text: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let db = Firestore.firestore()
        
        // Get conversation
        let conversation = try await db.collection("conversations")
            .document(conversationId)
            .getDocument()
        
        guard let conversationData = conversation.data() else {
            throw NSError(domain: "Firestore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Conversation not found"])
        }
        
        let participantIds = conversationData["participantIds"] as? [String] ?? []
        let otherUserId = participantIds.first { $0 != currentUserId } ?? ""
        
        // Check permissions
        let (canMessage, isLimited) = try await MessagingPermissionService.shared.canMessageUser(otherUserId)
        
        guard canMessage else {
            throw NSError(domain: "Permission", code: -1, userInfo: [NSLocalizedDescriptionKey: "You cannot message this user"])
        }
        
        // Check message count for message requests
        if isLimited {
            let messageCounts = conversationData["messageCounts"] as? [String: Int] ?? [:]
            let currentCount = messageCounts[currentUserId] ?? 0
            
            if currentCount >= 1 {
                throw NSError(domain: "Permission", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Message request already sent. Wait for them to follow you back."])
            }
        }
        
        // Create message and update conversation in a batch
        let batch = db.batch()
        
        // Add message
        let messageRef = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document()
        
        batch.setData([
            "senderId": currentUserId,
            "text": text,
            "createdAt": FieldValue.serverTimestamp(),
            "isRead": false
        ], forDocument: messageRef)
        
        // Update conversation metadata
        let conversationRef = db.collection("conversations").document(conversationId)
        batch.updateData([
            "lastMessage": text,
            "lastMessageAt": FieldValue.serverTimestamp(),
            "lastMessageSenderId": currentUserId,
            "updatedAt": FieldValue.serverTimestamp(),
            "messageCounts.\(currentUserId)": FieldValue.increment(Int64(1))
        ], forDocument: conversationRef)
        
        try await batch.commit()
    }
}

