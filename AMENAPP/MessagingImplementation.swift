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
    private lazy var db = Firestore.firestore()
    
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
        lazy var db = Firestore.firestore()
        
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
    private lazy var db = Firestore.firestore()
    
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

        // New-account DM rate-limit check
        let (canDM, dmReason) = await NewAccountRestrictionService.shared.canDMStrangers(userId: currentUserId)
        guard canDM else {
            throw NSError(
                domain: "RateLimit",
                code: 429,
                userInfo: [NSLocalizedDescriptionKey: dmReason ?? "Daily message limit reached. Try again tomorrow."]
            )
        }
        
        lazy var db = Firestore.firestore()

        // Check for existing 1-on-1 conversation before creating a new one
        let existing = try await db.collection("conversations")
            .whereField("participantIds", arrayContains: currentUserId)
            .whereField("isGroup", isEqualTo: false)
            .limit(to: 200)
            .getDocuments()

        for doc in existing.documents {
            let ids = doc.data()["participantIds"] as? [String] ?? []
            if ids.count == 2 && ids.contains(otherUserId) {
                // Return existing conversation instead of creating a duplicate
                return doc.documentID
            }
        }

        let conversationData: [String: Any] = [
            "participantIds": [currentUserId, otherUserId].sorted(),
            "isGroup": false,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
            "messageCounts": [
                currentUserId: 0,
                otherUserId: 0
            ]
        ]

        let conversationRef = try await db.collection("conversations").addDocument(data: conversationData)
        return conversationRef.documentID
    }
    
    /// Send a message with permission checking.
    ///
    /// Optimistic-insert flow:
    ///   1. A temporary `clientId` (UUID) is generated immediately.
    ///   2. `.dmOptimisticInsert` is posted on `NotificationCenter.default` so any
    ///      observing chat view can show the message *before* any network round-trip.
    ///   3. Permission checks + batch write happen in the background.
    ///   4. On `batch.commit()` failure, `.dmOptimisticRollback` is posted so the
    ///      observer can remove the optimistic row and surface the error.
    ///   5. On success, the real-time Firestore listener fires and the confirmed
    ///      document (keyed by the same `clientId`) replaces the optimistic row.
    func sendMessageWithPermissions(to conversationId: String, text: String) async throws {
        let _dmToken = PerfBegin("dm_send")
        defer { PerfEnd(_dmToken, threshold: 300) }
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }

        // ── STEP 1: Optimistic insert ─────────────────────────────────────────
        // Generate the client-side document ID before any async work so the chat
        // view can display the message immediately. Using this UUID as the Firestore
        // document ID makes the write idempotent on retry.
        let clientId = UUID().uuidString
        let optimisticTimestamp = Date()

        NotificationCenter.default.post(
            name: .dmOptimisticInsert,
            object: nil,
            userInfo: [
                "clientId"       : clientId,
                "conversationId" : conversationId,
                "text"           : text,
                "senderId"       : currentUserId,
                "timestamp"      : optimisticTimestamp
            ]
        )
        // ── END optimistic insert ─────────────────────────────────────────────

        lazy var db = Firestore.firestore()

        // Get conversation
        let conversation = try await db.collection("conversations")
            .document(conversationId)
            .getDocument()

        guard let conversationData = conversation.data() else {
            let err = NSError(domain: "Firestore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Conversation not found"])
            NotificationCenter.default.post(
                name: .dmOptimisticRollback,
                object: nil,
                userInfo: ["clientId": clientId, "conversationId": conversationId, "error": err]
            )
            throw err
        }

        let participantIds = conversationData["participantIds"] as? [String] ?? []
        let otherUserId = participantIds.first { $0 != currentUserId } ?? ""

        // Check permissions
        let (canMessage, isLimited) = try await MessagingPermissionService.shared.canMessageUser(otherUserId)

        guard canMessage else {
            let err = NSError(domain: "Permission", code: -1, userInfo: [NSLocalizedDescriptionKey: "You cannot message this user"])
            NotificationCenter.default.post(
                name: .dmOptimisticRollback,
                object: nil,
                userInfo: ["clientId": clientId, "conversationId": conversationId, "error": err]
            )
            throw err
        }

        // Check message count for message requests
        if isLimited {
            let messageCounts = conversationData["messageCounts"] as? [String: Int] ?? [:]
            let currentCount = messageCounts[currentUserId] ?? 0

            if currentCount >= 1 {
                let err = NSError(domain: "Permission", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Message request already sent. Wait for them to follow you back."])
                NotificationCenter.default.post(
                    name: .dmOptimisticRollback,
                    object: nil,
                    userInfo: ["clientId": clientId, "conversationId": conversationId, "error": err]
                )
                throw err
            }
        }

        // Create message and update conversation in a batch.
        // Use `clientId` as the Firestore document ID so:
        //   a) the chat view can de-duplicate the server snapshot against pendingMessages, and
        //   b) retries with the same clientId are idempotent (setData is an upsert).
        let batch = db.batch()

        // Add message — use clientId as document ID for idempotency + de-dup
        let messageRef = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(clientId)

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

        do {
            try await batch.commit()
        } catch {
            // ── STEP 4: Rollback on commit failure ────────────────────────────
            NotificationCenter.default.post(
                name: .dmOptimisticRollback,
                object: nil,
                userInfo: ["clientId": clientId, "conversationId": conversationId, "error": error]
            )
            throw error
        }
    }
}

