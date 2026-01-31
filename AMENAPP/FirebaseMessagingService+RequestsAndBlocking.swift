//
//  FirebaseMessagingService+RequestsAndBlocking.swift
//  AMENAPP
//
//  Message Requests, Blocking, and Follow Status Detection
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Message Requests Extension

extension FirebaseMessagingService {
    
    // MARK: - Follow Status Detection
    
    /// Check if two users follow each other
    /// UPDATED: Use /follows collection instead of subcollections
    func checkFollowStatus(userId1: String, userId2: String) async throws -> (user1FollowsUser2: Bool, user2FollowsUser1: Bool) {
        let db = Firestore.firestore()
        
        // Check if user1 follows user2
        async let user1FollowsQuery = db.collection("follows")
            .whereField("followerId", isEqualTo: userId1)
            .whereField("followingId", isEqualTo: userId2)
            .limit(to: 1)
            .getDocuments()
        
        // Check if user2 follows user1
        async let user2FollowsQuery = db.collection("follows")
            .whereField("followerId", isEqualTo: userId2)
            .whereField("followingId", isEqualTo: userId1)
            .limit(to: 1)
            .getDocuments()
        
        let (snapshot1, snapshot2) = try await (user1FollowsQuery, user2FollowsQuery)
        
        return (!snapshot1.documents.isEmpty, !snapshot2.documents.isEmpty)
    }
    
    /// Check if current user can message another user
    func canMessageUser(userId: String) async throws -> (canMessage: Bool, requiresRequest: Bool, reason: String?) {
        guard isAuthenticated else {
            return (false, false, "Not authenticated")
        }
        
        guard userId != currentUserId else {
            return (false, false, "Cannot message yourself")
        }
        
        // Check if user is blocked
        let isBlocked = try await checkIfBlocked(userId: userId)
        if isBlocked {
            return (false, false, "User is blocked")
        }
        
        // Check if blocked by user
        let blockedByUser = try await checkIfBlockedByUser(userId: userId)
        if blockedByUser {
            return (false, false, "You are blocked by this user")
        }
        
        // Get recipient's privacy settings
        let recipientSettings = try await getUserPrivacySettings(userId: userId)
        
        // If user doesn't allow message requests at all
        if !recipientSettings.allowMessagesFromEveryone {
            return (false, false, "User doesn't accept messages")
        }
        
        // Check follow status
        let followStatus = try await checkFollowStatus(userId1: currentUserId, userId2: userId)
        
        // If recipient requires follow and current user doesn't follow them
        if recipientSettings.requireFollowToMessage && !followStatus.user1FollowsUser2 {
            return (false, false, "You must follow this user to message them")
        }
        
        // If they follow each other, can message directly
        if followStatus.user1FollowsUser2 && followStatus.user2FollowsUser1 {
            return (true, false, nil) // Direct messaging allowed
        }
        
        // If current user follows them but not vice versa
        if followStatus.user1FollowsUser2 {
            return (true, false, nil) // Can message directly (one-way follow)
        }
        
        // Otherwise, requires message request
        return (true, true, nil)
    }
    
    /// Get user's privacy settings
    private func getUserPrivacySettings(userId: String) async throws -> (allowMessagesFromEveryone: Bool, requireFollowToMessage: Bool) {
        let doc = try await db.collection("users").document(userId).getDocument()
        
        let allowMessages = doc.data()?["allowMessagesFromEveryone"] as? Bool ?? true
        let requireFollow = doc.data()?["requireFollowToMessage"] as? Bool ?? false
        
        return (allowMessages, requireFollow)
    }
    
    // MARK: - Message Requests
    
    /// Load pending message requests for current user
    func loadMessageRequests() async throws -> [MessagingRequest] {
        guard isAuthenticated else {
            throw FirebaseMessagingError.notAuthenticated
        }
        
        let snapshot = try await db.collection("conversations")
            .whereField("participantIds", arrayContains: currentUserId)
            .whereField("conversationStatus", isEqualTo: "pending")
            .order(by: "updatedAt", descending: true)
            .getDocuments()
        
        var requests: [MessagingRequest] = []
        
        for doc in snapshot.documents {
            guard let conversation = try? doc.data(as: FirebaseConversation.self) else { continue }
            
            // Only show requests where current user is the recipient (not sender)
            guard let requesterId = conversation.requesterId,
                  requesterId != currentUserId else { continue }
            
            let isRead = conversation.requestReadBy?.contains(currentUserId) ?? false
            
            let request = MessagingRequest(
                id: doc.documentID,
                conversationId: doc.documentID,
                fromUserId: requesterId,
                fromUserName: conversation.participantNames[requesterId] ?? "Unknown",
                fromUserUsername: nil, // Could fetch from user document if needed
                fromUserAvatarUrl: nil,
                lastMessage: conversation.lastMessageText,
                timestamp: conversation.updatedAt?.dateValue() ?? Date(),
                isRead: isRead
            )
            
            requests.append(request)
        }
        
        return requests
    }
    
    /// Accept a message request
    func acceptMessageRequest(requestId: String) async throws {
        guard isAuthenticated else {
            throw FirebaseMessagingError.notAuthenticated
        }
        
        let conversationRef = db.collection("conversations").document(requestId)
        
        try await conversationRef.updateData([
            "conversationStatus": "accepted",
            "acceptedAt": Timestamp(date: Date()),
            "acceptedBy": currentUserId,
            "updatedAt": Timestamp(date: Date())
        ])
        
        print("✅ Message request accepted: \(requestId)")
    }
    
    /// Decline a message request
    func declineMessageRequest(requestId: String) async throws {
        guard isAuthenticated else {
            throw FirebaseMessagingError.notAuthenticated
        }
        
        let conversationRef = db.collection("conversations").document(requestId)
        
        // Option 1: Soft delete (mark as declined)
        try await conversationRef.updateData([
            "conversationStatus": "declined",
            "declinedAt": Timestamp(date: Date()),
            "declinedBy": currentUserId,
            "updatedAt": Timestamp(date: Date())
        ])
        
        // Option 2: Hard delete (uncomment if you prefer)
        // try await conversationRef.delete()
        
        print("✅ Message request declined: \(requestId)")
    }
    
    /// Mark message request as read
    func markMessageRequestAsRead(requestId: String) async throws {
        guard isAuthenticated else {
            throw FirebaseMessagingError.notAuthenticated
        }
        
        let conversationRef = db.collection("conversations").document(requestId)
        
        try await conversationRef.updateData([
            "requestReadBy": FieldValue.arrayUnion([currentUserId])
        ])
    }
    
    /// Start listening to message requests in real-time
    func startListeningToMessageRequests(
        userId: String,
        onChange: @escaping ([MessagingRequest]) -> Void
    ) -> (() -> Void) {
        let listener = db.collection("conversations")
            .whereField("participantIds", arrayContains: userId)
            .whereField("conversationStatus", isEqualTo: "pending")
            .order(by: "updatedAt", descending: true)
            .addSnapshotListener { snapshot, error in
                guard let snapshot = snapshot else {
                    print("❌ Error listening to message requests: \(error?.localizedDescription ?? "unknown")")
                    return
                }
                
                var requests: [MessagingRequest] = []
                
                for doc in snapshot.documents {
                    guard let conversation = try? doc.data(as: FirebaseConversation.self) else { continue }
                    
                    // Only show requests where current user is the recipient (not sender)
                    guard let requesterId = conversation.requesterId,
                          requesterId != userId else { continue }
                    
                    let isRead = conversation.requestReadBy?.contains(userId) ?? false
                    
                    let request = MessagingRequest(
                        id: doc.documentID,
                        conversationId: doc.documentID,
                        fromUserId: requesterId,
                        fromUserName: conversation.participantNames[requesterId] ?? "Unknown",
                        fromUserUsername: nil,
                        fromUserAvatarUrl: nil,
                        lastMessage: conversation.lastMessageText,
                        timestamp: conversation.updatedAt?.dateValue() ?? Date(),
                        isRead: isRead
                    )
                    
                    requests.append(request)
                }
                
                onChange(requests)
            }
        
        // Return a closure to stop listening
        return {
            listener.remove()
        }
    }
    
    // MARK: - Blocking System
    
    /// Block a user
    func blockUser(userId: String) async throws {
        guard isAuthenticated else {
            throw FirebaseMessagingError.notAuthenticated
        }
        
        guard userId != currentUserId else {
            throw FirebaseMessagingError.invalidInput("Cannot block yourself")
        }
        
        let batch = db.batch()
        
        // Add to blocked users collection
        let blockRef = db.collection("users")
            .document(currentUserId)
            .collection("blockedUsers")
            .document(userId)
        
        batch.setData([
            "userId": userId,
            "blockedAt": Timestamp(date: Date())
        ], forDocument: blockRef)
        
        // Delete any existing conversations (optional - or just hide them)
        let conversationsQuery = try await db.collection("conversations")
            .whereField("participantIds", arrayContains: currentUserId)
            .whereField("isGroup", isEqualTo: false)
            .getDocuments()
        
        for doc in conversationsQuery.documents {
            if let conversation = try? doc.data(as: FirebaseConversation.self),
               conversation.participantIds.contains(userId) {
                // Hide conversation by removing current user from participants
                batch.updateData([
                    "hiddenFor": FieldValue.arrayUnion([currentUserId])
                ], forDocument: doc.reference)
            }
        }
        
        try await batch.commit()
        
        print("✅ User blocked: \(userId)")
    }
    
    /// Unblock a user
    func unblockUser(userId: String) async throws {
        guard isAuthenticated else {
            throw FirebaseMessagingError.notAuthenticated
        }
        
        let blockRef = db.collection("users")
            .document(currentUserId)
            .collection("blockedUsers")
            .document(userId)
        
        try await blockRef.delete()
        
        print("✅ User unblocked: \(userId)")
    }
    
    /// Check if a user is blocked by current user
    func checkIfBlocked(userId: String) async throws -> Bool {
        guard isAuthenticated else {
            return false
        }
        
        let doc = try await db.collection("users")
            .document(currentUserId)
            .collection("blockedUsers")
            .document(userId)
            .getDocument()
        
        return doc.exists
    }
    
    /// Check if current user is blocked by another user
    func checkIfBlockedByUser(userId: String) async throws -> Bool {
        guard isAuthenticated else {
            return false
        }
        
        let doc = try await db.collection("users")
            .document(userId)
            .collection("blockedUsers")
            .document(currentUserId)
            .getDocument()
        
        return doc.exists
    }
    
    /// Get list of blocked users
    func getBlockedUsers() async throws -> [BlockedUserInfo] {
        guard isAuthenticated else {
            throw FirebaseMessagingError.notAuthenticated
        }
        
        let snapshot = try await db.collection("users")
            .document(currentUserId)
            .collection("blockedUsers")
            .order(by: "blockedAt", descending: true)
            .getDocuments()
        
        var blockedUsers: [BlockedUserInfo] = []
        
        for doc in snapshot.documents {
            guard let userId = doc.data()["userId"] as? String else { continue }
            
            // Fetch user details
            let userDoc = try? await db.collection("users").document(userId).getDocument()
            let displayName = userDoc?.data()?["displayName"] as? String ?? "Unknown User"
            let username = userDoc?.data()?["username"] as? String
            let avatarUrl = userDoc?.data()?["profileImageURL"] as? String
            
            let blockedUser = BlockedUserInfo(
                id: userId,
                displayName: displayName,
                username: username,
                avatarUrl: avatarUrl,
                blockedAt: (doc.data()["blockedAt"] as? Timestamp)?.dateValue() ?? Date()
            )
            
            blockedUsers.append(blockedUser)
        }
        
        return blockedUsers
    }
    
    // MARK: - Reporting System
    
    /// Report a user for spam or abuse
    func reportUser(userId: String, reason: String, conversationId: String? = nil) async throws {
        guard isAuthenticated else {
            throw FirebaseMessagingError.notAuthenticated
        }
        
        let reportRef = db.collection("reports").document()
        
        let report: [String: Any] = [
            "id": reportRef.documentID,
            "reporterId": currentUserId,
            "reportedUserId": userId,
            "reason": reason,
            "conversationId": conversationId as Any,
            "status": "pending",
            "createdAt": Timestamp(date: Date())
        ]
        
        try await reportRef.setData(report)
        
        // Auto-block if spam report (optional)
        if reason.lowercased().contains("spam") {
            print("📊 Spam detected - auto-blocking user")
            try? await blockUser(userId: userId)
        }
        
        print("✅ User reported: \(userId) for \(reason)")
    }
    
    // MARK: - Enhanced Conversation Creation
    
    /// Create or get conversation with follow status checking
    func getOrCreateDirectConversationWithChecks(
        withUserId userId: String,
        userName: String
    ) async throws -> String {
        guard isAuthenticated else {
            throw FirebaseMessagingError.notAuthenticated
        }
        
        guard userId != currentUserId else {
            throw FirebaseMessagingError.selfConversation
        }
        
        // Check if can message user
        let permissionCheck = try await canMessageUser(userId: userId)
        
        guard permissionCheck.canMessage else {
            // Throw appropriate error based on reason
            if let reason = permissionCheck.reason {
                if reason.contains("blocked") {
                    throw FirebaseMessagingError.userBlocked
                } else if reason.contains("follow") {
                    throw FirebaseMessagingError.followRequired
                } else {
                    throw FirebaseMessagingError.messagesNotAllowed
                }
            }
            throw FirebaseMessagingError.permissionDenied
        }
        
        // Check if conversation already exists
        let querySnapshot = try await db.collection("conversations")
            .whereField("participantIds", arrayContains: currentUserId)
            .whereField("isGroup", isEqualTo: false)
            .getDocuments()
        
        for document in querySnapshot.documents {
            if let conversation = try? document.data(as: FirebaseConversation.self),
               let conversationId = conversation.id,
               conversation.participantIds.contains(userId) {
                
                // If declined, reopen it
                if conversation.conversationStatus == "declined" {
                    try await document.reference.updateData([
                        "conversationStatus": permissionCheck.requiresRequest ? "pending" : "accepted",
                        "updatedAt": Timestamp(date: Date())
                    ])
                }
                
                print("✅ Found existing conversation: \(conversationId)")
                return conversationId
            }
        }
        
        // Create new conversation
        let conversationRef = db.collection("conversations").document()
        
        var allParticipantIds = [userId, currentUserId]
        let participantNames = [
            currentUserId: currentUserName,
            userId: userName
        ]
        
        // Determine status based on follow relationship
        let status = permissionCheck.requiresRequest ? "pending" : "accepted"
        
        let conversation = FirebaseConversation(
            id: conversationRef.documentID,
            participantIds: allParticipantIds,
            participantNames: participantNames,
            isGroup: false,
            groupName: nil,
            lastMessage: nil,
            lastMessageText: "",
            lastMessageTimestamp: Date(),
            unreadCounts: [:],
            createdAt: Date(),
            updatedAt: Date(),
            conversationStatus: status,
            requesterId: currentUserId,
            requestReadBy: []
        )
        
        try conversationRef.setData(from: conversation)
        
        print("✅ Conversation created with status: \(status)")
        return conversationRef.documentID
    }
}

// MARK: - Supporting Models

// Note: MessagingRequest is defined in FirebaseMessagingService.swift

struct BlockedUserInfo: Identifiable, Codable {
    let id: String
    let displayName: String
    let username: String?
    let avatarUrl: String?
    let blockedAt: Date
}

