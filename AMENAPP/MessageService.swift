//
//  MessageService.swift
//  AMENAPP
//
//  Created by Assistant on 1/26/26.
//
//  Complete messaging service with Firebase backend integration
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

@MainActor
class MessageService: ObservableObject {
    static let shared = MessageService()
    
    // Published properties
    @Published var conversations: [Conversation] = []
    @Published var archivedConversations: [Conversation] = []  // ✅ NEW: Separate list for archived
    @Published var messageRequests: [MessageRequest] = []  // ✅ NEW: Message requests
    @Published var currentMessages: [Message] = []
    @Published var unreadCount: Int = 0
    @Published var unreadRequestsCount: Int = 0  // ✅ NEW: Unread requests count
    @Published var isLoading = false
    @Published var error: String?
    
    private let db = Firestore.firestore()
    private let firebaseManager = FirebaseManager.shared
    private var conversationListeners: [ListenerRegistration] = []
    private var messageListener: ListenerRegistration?
    
    private init() {}
    
    deinit {
        // Clean up all conversation listeners
        conversationListeners.forEach { $0.remove() }
        conversationListeners.removeAll()
        
        // Clean up message listener
        messageListener?.remove()
        messageListener = nil
        
        print("✅ MessageService deinitialized - all listeners cleaned up")
    }
    
    // MARK: - Fetch Conversations
    
    /// Fetch all conversations for current user
    func fetchConversations() async throws {
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        print("📥 Fetching conversations for user: \(currentUserId)")
        isLoading = true
        
        do {
            let snapshot = try await db.collection("conversations")
                .whereField("participants", arrayContains: currentUserId)
                .order(by: "lastMessageTime", descending: true)
                .getDocuments()
            
            // Filter out archived conversations for current user
            conversations = try snapshot.documents.compactMap { doc in
                try doc.data(as: Conversation.self)
            }.filter { conversation in
                !conversation.isArchivedByUser(currentUserId)
            }
            
            // Calculate unread count
            calculateUnreadCount()
            
            print("✅ Fetched \(conversations.count) conversations")
            isLoading = false
            
        } catch {
            print("❌ Error fetching conversations: \(error)")
            self.error = error.localizedDescription
            isLoading = false
            throw error
        }
    }
    
    // MARK: - Start Real-time Listener
    
    /// Start listening to conversations in real-time
    func startListeningToConversations() {
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            print("⚠️ No user ID for conversations listener")
            return
        }
        
        print("🔊 Starting conversations listener...")
        
        let listener = db.collection("conversations")
            .whereField("participants", arrayContains: currentUserId)
            .order(by: "lastMessageTime", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Conversations listener error: \(error)")
                    return
                }
                
                guard let snapshot = snapshot else { return }
                
                Task { @MainActor in
                    do {
                        // ✅ Filter OUT:
                        // 1. Archived conversations
                        // 2. Pending message requests WHERE current user is NOT the requester
                        //    (if you sent the request, you should see it in main tab)
                        // 3. Blocked conversations
                        self.conversations = try snapshot.documents.compactMap { doc in
                            try doc.data(as: Conversation.self)
                        }.filter { conversation in
                            // Don't show archived
                            guard !conversation.isArchivedByUser(currentUserId) else { return false }
                            
                            // Don't show blocked
                            guard !conversation.isBlocked else { return false }
                            
                            // ✅ FIX: Show pending conversations ONLY if current user is the requester
                            // (i.e., they sent the first message)
                            if conversation.isPending {
                                return conversation.requesterId == currentUserId
                            }
                            
                            // Show all accepted conversations
                            return true
                        }
                        
                        // Update unread count
                        self.calculateUnreadCount()
                        
                        print("✅ Real-time update: \(self.conversations.count) conversations (archived & pending filtered)")
                    } catch {
                        print("❌ Error parsing conversations: \(error)")
                    }
                }
            }
        
        conversationListeners.append(listener)
    }
    
    /// Start listening to archived conversations in real-time
    /// Note: Uses client-side filtering because Firebase only allows one array-contains per query
    func startListeningToArchivedConversations() {
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            print("⚠️ No user ID for archived conversations listener")
            return
        }
        
        print("🔊 Starting archived conversations listener...")
        
        // ✅ FIX: Only use array-contains for participants, then filter client-side for archivedBy
        let listener = db.collection("conversations")
            .whereField("participants", arrayContains: currentUserId)
            .order(by: "lastMessageTime", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Archived conversations listener error: \(error)")
                    return
                }
                
                guard let snapshot = snapshot else { return }
                
                Task { @MainActor in
                    do {
                        // ✅ Client-side filter for archived conversations
                        self.archivedConversations = try snapshot.documents.compactMap { doc in
                            try doc.data(as: Conversation.self)
                        }.filter { conversation in
                            // Only include conversations archived by current user
                            conversation.isArchivedByUser(currentUserId)
                        }
                        
                        print("✅ Real-time update: \(self.archivedConversations.count) archived conversations")
                    } catch {
                        print("❌ Error parsing archived conversations: \(error)")
                    }
                }
            }
        
        conversationListeners.append(listener)
    }
    
    // MARK: - Send Message
    
    /// Send a message to a user
    func sendMessage(to recipientId: String, content: String, type: Message.MessageType = .text) async throws {
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("⚠️ Cannot send empty message")
            return
        }
        
        // ============================================================================
        // ✅ STEP 1: AI CONTENT MODERATION
        // ============================================================================
        print("🛡️ Running AI moderation check for message...")
        
        // Create authenticity signals (messages are typically typed, not pasted)
        let signals = AuthenticitySignals(
            typedCharacters: content.count,
            pastedCharacters: 0,
            typedVsPastedRatio: 1.0,
            largestPasteLength: 0,
            pasteEventCount: 0,
            typingDurationSeconds: 0,
            hasLargePaste: false
        )
        
        let moderationResult = try await ContentModerationService.moderateContent(
            text: content,
            category: .comment,  // Use comment strictness for messages
            signals: signals
        )
        
        // Block message if moderation fails
        if moderationResult.shouldBlock {
            let reasons = moderationResult.reasons.joined(separator: ", ")
            print("❌ Message blocked by moderation: \(reasons)")
            throw NSError(
                domain: "MessageService",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Your message was flagged for: \(reasons). Please review and edit your content."]
            )
        }
        
        // ============================================================================
        // ✅ STEP 2: CRISIS DETECTION (in private messages)
        // ============================================================================
        print("🚨 Running crisis detection for message...")
        let crisisResult = try await CrisisDetectionService.shared.detectCrisis(
            in: content,
            userId: currentUserId
        )
        
        if crisisResult.isCrisis {
            print("🚨 Crisis detected in message: \(crisisResult.crisisTypes.map { $0.displayName })")
            // Log crisis detection but don't block message (user can still communicate)
            // Crisis resources will be shown in UI by calling code if needed
        }
        
        print("✅ Message passed safety checks")
        print("📤 Sending message to: \(recipientId)")
        
        // Get sender info
        let currentUser = try await getUserInfo(userId: currentUserId)
        let recipientUser = try await getUserInfo(userId: recipientId)
        
        // Find or create conversation
        let conversation = try await findOrCreateConversation(with: recipientId)
        
        guard let conversationId = conversation.id else {
            throw NSError(domain: "MessageService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid conversation ID"])
        }
        
        // Create message
        let message = Message(
            conversationId: conversationId,
            senderId: currentUserId,
            senderName: currentUser.displayName,
            senderPhoto: currentUser.profileImageURL,
            content: content,
            type: type,
            timestamp: Date(),
            isRead: false,
            isDelivered: true,
            deliveredAt: Date()
        )
        
        // Save message to Firestore
        // ✅ FIXED: Save to nested path so Cloud Function onMessageSent can trigger properly
        // Path: conversations/{conversationId}/messages/{messageId}
        let messageRef = try db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .addDocument(from: message)
        
        // Update conversation
        var unreadCount = conversation.unreadCount
        unreadCount[recipientId] = (unreadCount[recipientId] ?? 0) + 1
        
        try await db.collection("conversations").document(conversationId).updateData([
            "lastMessage": content,
            "lastMessageSenderId": currentUserId,
            "lastMessageTime": Date(),
            "unreadCount": unreadCount,
            "updatedAt": Date()
        ])
        
        // ❌ REMOVED: Duplicate notification prevention
        // Cloud Function `onMessageSent` already handles notifications when message is created
        // Uncommenting this line will cause duplicate notifications
        // try? await sendPushNotification(to: recipientId, from: currentUser.displayName, message: content)
        
        print("✅ Message sent: \(messageRef.documentID)")
    }
    
    // MARK: - Fetch Messages
    
    /// Fetch messages for a conversation
    func fetchMessages(conversationId: String) async throws {
        print("📥 Fetching messages for conversation: \(conversationId)")
        isLoading = true
        
        do {
            // ✅ FIXED: Fetch from nested path to match where messages are saved
            let snapshot = try await db.collection("conversations")
                .document(conversationId)
                .collection("messages")
                .order(by: "timestamp", descending: false)
                .getDocuments()
            
            currentMessages = try snapshot.documents.compactMap { doc in
                try doc.data(as: Message.self)
            }
            
            print("✅ Fetched \(currentMessages.count) messages")
            isLoading = false
            
        } catch {
            print("❌ Error fetching messages: \(error)")
            self.error = error.localizedDescription
            isLoading = false
            throw error
        }
    }
    
    // MARK: - Start Message Listener
    
    /// Start listening to messages in real-time
    func startListeningToMessages(conversationId: String) {
        stopListeningToMessages() // Stop any existing listener
        
        print("🔊 Starting messages listener for: \(conversationId)")
        
        // ✅ FIXED: Listen to nested path to match where messages are saved
        messageListener = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Messages listener error: \(error)")
                    return
                }
                
                guard let snapshot = snapshot else { return }
                
                Task { @MainActor in
                    do {
                        self.currentMessages = try snapshot.documents.compactMap { doc in
                            try doc.data(as: Message.self)
                        }
                        
                        print("✅ Real-time update: \(self.currentMessages.count) messages")
                        
                        // Mark messages as read
                        await self.markMessagesAsRead(in: conversationId)
                        
                    } catch {
                        print("❌ Error parsing messages: \(error)")
                    }
                }
            }
    }
    
    func stopListeningToMessages() {
        messageListener?.remove()
        messageListener = nil
        currentMessages = []
    }
    
    // MARK: - Mark as Read
    
    /// Mark all messages in a conversation as read
    func markMessagesAsRead(in conversationId: String) async {
        guard let currentUserId = firebaseManager.currentUser?.uid else { return }
        
        do {
            // ✅ FIXED: Get unread messages from nested path
            let snapshot = try await db.collection("conversations")
                .document(conversationId)
                .collection("messages")
                .whereField("senderId", isNotEqualTo: currentUserId)
                .whereField("isRead", isEqualTo: false)
                .getDocuments()
            
            guard !snapshot.documents.isEmpty else { return }
            
            // Batch update
            let batch = db.batch()
            let readTime = Date()
            
            for doc in snapshot.documents {
                batch.updateData([
                    "isRead": true,
                    "readAt": readTime
                ], forDocument: doc.reference)
            }
            
            try await batch.commit()
            
            // Reset unread count for conversation
            try await db.collection("conversations").document(conversationId).updateData([
                "unreadCount.\(currentUserId)": 0
            ])
            
            // Update local unread count
            calculateUnreadCount()
            
            print("✅ Marked \(snapshot.documents.count) messages as read")
            
        } catch {
            print("❌ Error marking messages as read: \(error)")
        }
    }
    
    // MARK: - Helper Methods
    
    /// Find existing conversation or create new one
    private func findOrCreateConversation(with userId: String) async throws -> Conversation {
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        // Check if conversation already exists
        let snapshot = try await db.collection("conversations")
            .whereField("participants", arrayContains: currentUserId)
            .getDocuments()
        
        // Find conversation with both participants
        if let existingConv = try snapshot.documents.compactMap({ try? $0.data(as: Conversation.self) })
            .first(where: { $0.participants.contains(userId) && $0.participants.count == 2 }) {
            print("✅ Found existing conversation: \(existingConv.id ?? "unknown")")
            return existingConv
        }
        
        // ============================================================================
        // ✅ PRIVACY CHECK: Determine if sender can directly message recipient
        // ============================================================================
        print("🔒 Checking DM permissions for recipient: \(userId)")
        
        let canSendDirect = try await TrustByDesignService.shared.canSendDM(
            from: currentUserId,
            to: userId
        )
        
        // Create new conversation
        if canSendDirect {
            print("✅ DM permission granted - creating accepted conversation")
        } else {
            print("⚠️ DM permission denied - creating pending message request")
        }
        
        let currentUser = try await getUserInfo(userId: currentUserId)
        let otherUser = try await getUserInfo(userId: userId)
        
        // ✅ PRIVACY: Create conversation as accepted OR pending based on permissions
        var conversation = Conversation(
            participants: [currentUserId, userId].sorted(),
            participantNames: [
                currentUserId: currentUser.displayName,
                userId: otherUser.displayName
            ],
            participantPhotos: [
                currentUserId: currentUser.profileImageURL ?? "",
                userId: otherUser.profileImageURL ?? ""
            ],
            unreadCount: [
                currentUserId: 0,
                userId: 0
            ],
            conversationStatus: canSendDirect ? "accepted" : "pending",  // ✅ Based on permission
            requesterId: canSendDirect ? nil : currentUserId             // ✅ Only set if pending
        )
        
        let docRef = try db.collection("conversations").addDocument(from: conversation)
        conversation.id = docRef.documentID
        
        print("✅ Created conversation: \(docRef.documentID)")
        return conversation
    }
    
    /// Get user info from Firestore
    private func getUserInfo(userId: String) async throws -> (displayName: String, profileImageURL: String?) {
        let doc = try await db.collection("users").document(userId).getDocument()
        
        guard let data = doc.data() else {
            throw NSError(domain: "MessageService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not found"])
        }
        
        let displayName = data["displayName"] as? String ?? "Unknown"
        let profileImageURL = data["profileImageURL"] as? String
        
        return (displayName, profileImageURL)
    }
    
    /// Calculate total unread count
    private func calculateUnreadCount() {
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            unreadCount = 0
            return
        }
        
        unreadCount = conversations.reduce(0) { total, conversation in
            total + conversation.unreadCountForUser(currentUserId)
        }
        
        print("📊 Unread count: \(unreadCount)")
    }
    
    /// Send push notification
    private func sendPushNotification(to userId: String, from senderName: String, message: String) async throws {
        let notification: [String: Any] = [
            "userId": userId,
            "type": "message",
            "title": senderName,
            "body": message,
            "createdAt": Date(),
            "isRead": false
        ]
        
        try await db.collection("notifications").addDocument(data: notification)
    }
    
    // MARK: - Cleanup
    
    func stopAllListeners() {
        conversationListeners.forEach { $0.remove() }
        conversationListeners.removeAll()
        stopListeningToMessages()
        print("🔇 Stopped all message listeners")
    }
    
    // MARK: - Message Requests
    
    /// Start listening to message requests in real-time
    func startListeningToMessageRequests() {
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            print("⚠️ No user ID for message requests listener")
            return
        }
        
        print("🔊 Starting message requests listener...")
        
        // Query conversations with pending status where user is a participant
        let listener = db.collection("conversations")
            .whereField("participants", arrayContains: currentUserId)
            .order(by: "lastMessageTime", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Message requests listener error: \(error)")
                    self.error = error.localizedDescription
                    return
                }
                
                guard let snapshot = snapshot else { return }
                
                Task { @MainActor in
                    do {
                        // Filter for pending conversations where current user is NOT the requester
                        let pendingConversations = try snapshot.documents.compactMap { doc in
                            try doc.data(as: Conversation.self)
                        }.filter { conversation in
                            conversation.isPending &&
                            conversation.requesterId != currentUserId &&
                            conversation.participants.contains(currentUserId)
                        }
                        
                        // Convert to MessageRequest objects
                        self.messageRequests = pendingConversations.compactMap { conversation in
                            guard let conversationId = conversation.id,
                                  let requesterId = conversation.requesterId else {
                                return nil
                            }
                            
                            let requesterName = conversation.participantNames[requesterId] ?? "Unknown"
                            let requesterPhoto = conversation.participantPhotos[requesterId]
                            let isRead = conversation.requestReadBy?.contains(currentUserId) ?? false
                            
                            return MessageRequest(
                                id: conversationId,
                                conversationId: conversationId,
                                fromUserId: requesterId,
                                fromUserName: requesterName,
                                fromUserPhoto: requesterPhoto,
                                isRead: isRead,
                                createdAt: conversation.createdAt
                            )
                        }
                        
                        // Update unread requests count
                        self.unreadRequestsCount = self.messageRequests.filter { !$0.isRead }.count
                        
                        print("✅ Real-time update: \(self.messageRequests.count) message requests (\(self.unreadRequestsCount) unread)")
                    } catch {
                        print("❌ Error parsing message requests: \(error)")
                    }
                }
            }
        
        conversationListeners.append(listener)
    }
    
    /// Accept a message request
    func acceptMessageRequest(_ requestId: String) async throws {
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        print("✅ Accepting message request: \(requestId)")
        
        try await db.collection("conversations").document(requestId).updateData([
            "conversationStatus": "accepted",
            "updatedAt": Date()
        ])
        
        print("✅ Message request accepted")
    }
    
    /// Decline a message request (deletes the conversation)
    func declineMessageRequest(_ requestId: String) async throws {
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        print("❌ Declining message request: \(requestId)")
        
        try await deleteConversation(requestId)
        
        print("✅ Message request declined")
    }
    
    /// Mark message request as read
    func markMessageRequestAsRead(_ requestId: String) async throws {
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        try await db.collection("conversations").document(requestId).updateData([
            "requestReadBy": FieldValue.arrayUnion([currentUserId]),
            "updatedAt": Date()
        ])
        
        print("📖 Message request marked as read")
    }
    
    // MARK: - Delete Conversation
    
    func deleteConversation(_ conversationId: String) async throws {
        // ✅ FIXED: Delete all messages from nested path
        let messagesSnapshot = try await db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .getDocuments()
        
        let batch = db.batch()
        
        for doc in messagesSnapshot.documents {
            batch.deleteDocument(doc.reference)
        }
        
        // Delete conversation
        batch.deleteDocument(db.collection("conversations").document(conversationId))
        
        try await batch.commit()
        
        print("✅ Deleted conversation: \(conversationId)")
    }
    
    // MARK: - Archive Conversations
    
    /// Archive a conversation for current user
    func archiveConversation(_ conversationId: String) async throws {
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        print("📦 Archiving conversation: \(conversationId)")
        
        try await db.collection("conversations").document(conversationId).updateData([
            "archivedBy": FieldValue.arrayUnion([currentUserId]),
            "updatedAt": Date()
        ])
        
        print("✅ Conversation archived")
    }
    
    /// Unarchive a conversation for current user
    func unarchiveConversation(_ conversationId: String) async throws {
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        print("📬 Unarchiving conversation: \(conversationId)")
        
        try await db.collection("conversations").document(conversationId).updateData([
            "archivedBy": FieldValue.arrayRemove([currentUserId]),
            "updatedAt": Date()
        ])
        
        print("✅ Conversation unarchived")
    }
    
    /// Fetch archived conversations
    /// Note: Uses client-side filtering because Firebase only allows one array-contains per query
    func fetchArchivedConversations() async throws -> [Conversation] {
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        print("📥 Fetching archived conversations")
        
        do {
            // ✅ FIX: Query only by participants, then filter client-side
            let snapshot = try await db.collection("conversations")
                .whereField("participants", arrayContains: currentUserId)
                .order(by: "lastMessageTime", descending: true)
                .getDocuments()
            
            // ✅ Client-side filter for archived conversations
            let archived = try snapshot.documents.compactMap { doc in
                try doc.data(as: Conversation.self)
            }.filter { conversation in
                conversation.isArchivedByUser(currentUserId)
            }
            
            print("✅ Fetched \(archived.count) archived conversations")
            return archived
            
        } catch {
            print("❌ Error fetching archived conversations: \(error)")
            throw error
        }
    }
    
    // MARK: - Pin Messages
    
    /// Pin a message in a conversation
    func pinMessage(_ messageId: String, in conversationId: String) async throws {
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        print("📌 Pinning message: \(messageId)")
        
        // ✅ FIXED: Update message in nested path
        try await db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
            .updateData([
                "isPinned": true,
                "pinnedBy": currentUserId,
                "pinnedAt": Date()
            ])
        
        print("✅ Message pinned")
    }
    
    /// Unpin a message
    func unpinMessage(_ messageId: String, in conversationId: String) async throws {
        guard let currentUserId = firebaseManager.currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        print("📌 Unpinning message: \(messageId)")
        
        // ✅ FIXED: Update message in nested path
        try await db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
            .updateData([
                "isPinned": false,
                "pinnedBy": FieldValue.delete(),
                "pinnedAt": FieldValue.delete()
            ])
        
        print("✅ Message unpinned")
    }
    
    /// Fetch pinned messages in a conversation
    func fetchPinnedMessages(in conversationId: String) async throws -> [Message] {
        print("📥 Fetching pinned messages for: \(conversationId)")
        
        do {
            // ✅ FIXED: Fetch from nested path
            let snapshot = try await db.collection("conversations")
                .document(conversationId)
                .collection("messages")
                .whereField("isPinned", isEqualTo: true)
                .order(by: "pinnedAt", descending: true)
                .getDocuments()
            
            let pinned = try snapshot.documents.compactMap { doc in
                try doc.data(as: Message.self)
            }
            
            print("✅ Fetched \(pinned.count) pinned messages")
            return pinned
            
        } catch {
            print("❌ Error fetching pinned messages: \(error)")
            throw error
        }
    }
}
