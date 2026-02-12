//
//  FirebaseMessagingService.swift
//  AMENAPP
//
//  Firebase/Firestore Integration for Messaging
//

import Foundation
import SwiftUI
import FirebaseCore
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage
import Combine
import UIKit

// MARK: - Type Alias to avoid ambiguity

// Import local ChatConversation type to avoid ambiguity with Firebase types
// We'll reference it directly rather than through module qualification
// The ChatConversation struct is defined in Conversation.swift

// MARK: - Error Types

public enum FirebaseMessagingError: LocalizedError {
    case notAuthenticated
    case invalidUserId
    case conversationNotFound
    case messageNotFound
    case uploadFailed(String)
    case networkError(Error)
    case permissionDenied
    case selfConversation
    case invalidInput(String)
    case userBlocked
    case followRequired
    case messagesNotAllowed
    case customError(String)

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be logged in to send messages"
        case .invalidUserId:
            return "Invalid user ID"
        case .conversationNotFound:
            return "Conversation not found"
        case .messageNotFound:
            return "Message not found"
        case .uploadFailed(let reason):
            return "Upload failed: \(reason)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .permissionDenied:
            return "You don't have permission to perform this action"
        case .selfConversation:
            return "Cannot create conversation with yourself"
        case .invalidInput(let reason):
            return "Invalid input: \(reason)"
        case .userBlocked:
            return "This user is blocked"
        case .followRequired:
            return "You must follow this user to message them"
        case .messagesNotAllowed:
            return "This user doesn't accept messages"
        case .customError(let message):
            return message
        }
    }
}

// MARK: - Firebase Messaging Service

public class FirebaseMessagingService: ObservableObject {
    public static let shared = FirebaseMessagingService()
    
    internal let db = Firestore.firestore()
    internal let storage = Storage.storage()
    
    @Published var conversations: [ChatConversation] = []
    @Published var archivedConversations: [ChatConversation] = []
    @Published var isLoading = false
    @Published var lastError: FirebaseMessagingError?
    
    // Error tracking for failed messages
    @Published var failedMessages: [String: (text: String, error: FirebaseMessagingError)] = [:]
    @Published var isOffline = false
    
    private var conversationsListener: ListenerRegistration?
    private var archivedConversationsListener: ListenerRegistration?
    private var messagesListeners: [String: ListenerRegistration] = [:]
    
    // Message pagination state
    private var lastDocuments: [String: DocumentSnapshot] = [:] // conversationId: lastDoc
    private var hasMoreMessages: [String: Bool] = [:] // conversationId: hasMore
    
    private init() {
        // Note: Offline persistence is already configured in AppDelegate
        // Do NOT configure cache settings here - it must be done immediately after FirebaseApp.configure()
        print("✅ FirebaseMessagingService initialized (using global Firestore settings)")
    }
    
    // MARK: - Current User
    
    internal var currentUserId: String {
        return Auth.auth().currentUser?.uid ?? "anonymous"
    }
    
    public var isAuthenticated: Bool {
        return Auth.auth().currentUser != nil
    }
    
    // MARK: - Offline Support
    // Note: Offline persistence is configured globally in AppDelegate.swift
    // Firestore cache settings can only be set ONCE, immediately after FirebaseApp.configure()
    
    // MARK: - Current User Info
    
    var currentUserName: String {
        // Try to get from Auth first
        if let displayName = Auth.auth().currentUser?.displayName, !displayName.isEmpty {
            return displayName
        }
        
        // Fallback: Try to get from UserDefaults (cached during login/profile setup)
        if let cachedName = UserDefaults.standard.string(forKey: "currentUserDisplayName"), !cachedName.isEmpty {
            return cachedName
        }
        
        // Last resort: Fetch from Firestore synchronously from cache
        if let userId = Auth.auth().currentUser?.uid {
            let docRef = db.collection("users").document(userId)
            
            // Try to get from Firestore cache (won't block)
            docRef.getDocument(source: .cache) { snapshot, error in
                if let data = snapshot?.data(),
                   let displayName = data["displayName"] as? String, !displayName.isEmpty {
                    // Cache it for future use
                    UserDefaults.standard.set(displayName, forKey: "currentUserDisplayName")
                }
            }
            
            // Check if it was just cached
            if let cachedName = UserDefaults.standard.string(forKey: "currentUserDisplayName"), !cachedName.isEmpty {
                return cachedName
            }
        }
        
        // Last resort fallback
        return "User"
    }
    
    /// Call this method after user logs in or updates their profile to cache the name
    func updateCurrentUserName(_ name: String) {
        UserDefaults.standard.set(name, forKey: "currentUserDisplayName")
    }
    
    /// Fetch and cache the current user's display name from Firestore
    func fetchAndCacheCurrentUserName() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            let doc = try await db.collection("users").document(userId).getDocument()
            if let data = doc.data(),
               let displayName = data["displayName"] as? String, !displayName.isEmpty {
                // Update Auth profile if needed
                let changeRequest = Auth.auth().currentUser?.createProfileChangeRequest()
                changeRequest?.displayName = displayName
                try? await changeRequest?.commitChanges()
                
                // Cache in UserDefaults
                UserDefaults.standard.set(displayName, forKey: "currentUserDisplayName")
                
                print("✅ Current user name cached: \(displayName)")
            }
        } catch {
            print("❌ Error fetching current user name: \(error)")
        }
    }
    
    // MARK: - Conversations
    
    /// Start listening to conversations for the current user
    func startListeningToConversations() {
        guard isAuthenticated else {
            lastError = .notAuthenticated
            return
        }
        
        // Stop existing listener to prevent duplicates
        stopListeningToConversations()
        
        isLoading = true
        lastError = nil
        
        conversationsListener = db.collection("conversations")
            .whereField("participantIds", arrayContains: currentUserId)
            .order(by: "updatedAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Error fetching conversations: \(error)")
                    self.lastError = .networkError(error)
                    self.isLoading = false
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    self.isLoading = false
                    return
                }
                
                print("📥 Received \(documents.count) total conversation documents from Firestore")
                
                // Use a dictionary to deduplicate by ID
                var conversationsDict: [String: ChatConversation] = [:]
                
                // Filter out archived and deleted conversations
                for doc in documents {
                    // 🔍 DEBUG: Try to decode and log any errors
                    var firebaseConv: FirebaseConversation
                    do {
                        firebaseConv = try doc.data(as: FirebaseConversation.self)
                    } catch {
                        print("   ❌ DECODING ERROR for document \(doc.documentID):")
                        print("      Error: \(error)")
                        let data = doc.data()
                        print("      Data keys: \(data.keys.joined(separator: ", "))")
                        continue
                    }
                    
                    // ✅ FIX: Use document ID if @DocumentID didn't populate
                    let convId: String
                    if let id = firebaseConv.id {
                        convId = id
                    } else {
                        convId = doc.documentID
                        firebaseConv.id = doc.documentID  // Manually set the ID
                    }
                    
                    // Debug: Log each conversation
                    print("   📋 Conv ID: \(convId), isGroup: \(firebaseConv.isGroup), name: \(firebaseConv.groupName ?? "N/A")")
                    
                    // Check if conversation is archived for current user (array-based)
                    if let archivedBy = firebaseConv.archivedByArray,
                       archivedBy.contains(self.currentUserId) {
                        print("   ⏭️ Skipping archived conversation: \(convId)")
                        continue
                    }
                    
                    // Check if conversation is deleted for current user
                    if let deletedBy = firebaseConv.deletedBy,
                       deletedBy[self.currentUserId] == true {
                        print("   ⏭️ Skipping deleted conversation: \(convId)")
                        continue
                    }
                    
                    // ✅ FIX: Skip pending conversations where current user is NOT the requester
                    // (Those should appear in Message Requests, not main Messages tab)
                    
                    // 🔍 DEBUG: Log conversation status details
                    print("   📊 Conversation \(convId):")
                    print("      Status: \(firebaseConv.conversationStatus ?? "nil")")
                    print("      RequesterID: \(firebaseConv.requesterId ?? "nil")")
                    print("      CurrentUserID: \(self.currentUserId)")
                    
                    if let status = firebaseConv.conversationStatus,
                       status == "pending" {
                        if let requesterId = firebaseConv.requesterId {
                            if requesterId != self.currentUserId {
                                print("      ❌ FILTERING OUT: Pending request from someone else (should be in requests tab)")
                                continue
                            } else {
                                print("      ✅ KEEPING: Pending request sent by current user")
                            }
                        } else {
                            print("      ⚠️ WARNING: Pending conversation missing requesterId!")
                        }
                    } else {
                        print("      ✅ KEEPING: Accepted conversation or nil status")
                    }
                    
                    let conversation = firebaseConv.toConversation()
                    conversationsDict[convId] = conversation
                    print("      ➕ Added to conversations list")
                }
                
                // Convert back to array and sort by timestamp
                self.conversations = Array(conversationsDict.values)
                    .sorted { conv1, conv2 in
                        // Sort by timestamp (most recent first)
                        // Since timestamp is a string, this is a simple comparison
                        return conv1.timestamp > conv2.timestamp
                    }
                
                print("✅ Loaded \(self.conversations.count) unique conversations")
                
                // ✅ Log groups specifically
                let groupCount = self.conversations.filter { $0.isGroup }.count
                print("   🎨 Groups: \(groupCount)")
                
                // 🔍 DEBUG: Log breakdown of conversations
                print("   📊 Final conversations breakdown:")
                for conv in self.conversations {
                    print("      - \(conv.id ?? "no-id"): name=\(conv.name)")
                }
                
                self.isLoading = false
                
                // Log offline status
                if let metadata = snapshot?.metadata {
                    if metadata.isFromCache {
                        print("📦 Conversations loaded from cache (offline mode)")
                    } else {
                        print("🌐 Conversations loaded from server")
                    }
                }
            }
    }
    
    /// Stop listening to conversations
    func stopListeningToConversations() {
        conversationsListener?.remove()
        conversationsListener = nil
    }
    
    /// Start listening to archived conversations for the current user
    func startListeningToArchivedConversations() {
        guard isAuthenticated else {
            lastError = .notAuthenticated
            return
        }
        
        // Stop existing listener to prevent duplicates
        stopListeningToArchivedConversations()
        
        print("👂 Starting real-time listener for archived conversations")
        
        archivedConversationsListener = db.collection("conversations")
            .whereField("participantIds", arrayContains: currentUserId)
            .order(by: "updatedAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Error fetching archived conversations: \(error)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    return
                }
                
                print("📥 Received \(documents.count) total documents for archived check")
                
                // Use a dictionary to deduplicate by ID
                var archivedDict: [String: ChatConversation] = [:]
                
                // Filter archived conversations in memory
                for doc in documents {
                    guard let firebaseConv = try? doc.data(as: FirebaseConversation.self),
                          let convId = firebaseConv.id else {
                        continue
                    }
                    
                    // ✅ Only include if archived by current user
                    guard let archivedBy = firebaseConv.archivedByArray,
                          archivedBy.contains(self.currentUserId) else {
                        continue
                    }
                    
                    print("   📦 Found archived: \(convId), name: \(firebaseConv.groupName ?? firebaseConv.participantNames.values.first ?? "Unknown")")
                    
                    // Don't include deleted conversations in archived list
                    if let deletedBy = firebaseConv.deletedBy,
                       deletedBy[self.currentUserId] == true {
                        print("   ⏭️ Skipping deleted archived conversation: \(convId)")
                        continue
                    }
                    
                    let conversation = firebaseConv.toConversation()
                    archivedDict[convId] = conversation
                }
                
                // Convert back to array and sort
                self.archivedConversations = Array(archivedDict.values)
                    .sorted { conv1, conv2 in
                        return conv1.timestamp > conv2.timestamp
                    }
                
                print("✅ Loaded \(self.archivedConversations.count) unique archived conversations")
                
                // Log offline status
                if let metadata = snapshot?.metadata {
                    if metadata.isFromCache {
                        print("📦 Archived conversations loaded from cache (offline mode)")
                    } else {
                        print("🌐 Archived conversations loaded from server")
                    }
                }
            }
    }
    
    /// Stop listening to archived conversations
    func stopListeningToArchivedConversations() {
        archivedConversationsListener?.remove()
        archivedConversationsListener = nil
        print("🔇 Stopped listening to archived conversations")
    }
    
    /// Create a new conversation
    func createConversation(
        participantIds: [String],
        participantNames: [String: String],
        isGroup: Bool,
        groupName: String? = nil,
        conversationStatus: String? = nil  // ✅ Changed from "accepted" to nil - will be set based on context
    ) async throws -> String {
        guard isAuthenticated else {
            throw FirebaseMessagingError.notAuthenticated
        }

        if participantIds.isEmpty {
            throw FirebaseMessagingError.invalidInput("At least one participant is required")
        }

        let conversationRef = db.collection("conversations").document()

        var allParticipantIds = participantIds
        if !allParticipantIds.contains(currentUserId) {
            allParticipantIds.append(currentUserId)
        }

        // Fetch profile photos for all participants
        var participantPhotoURLs: [String: String] = [:]
        for userId in allParticipantIds {
            do {
                let userDoc = try await db.collection("users").document(userId).getDocument()
                // Check both possible field names for profile photo
                let photoURL = userDoc.data()?["profilePhotoURL"] as? String ?? userDoc.data()?["profileImageURL"] as? String
                if let photoURL = photoURL, !photoURL.isEmpty {
                    participantPhotoURLs[userId] = photoURL
                }
            } catch {
                print("⚠️ Failed to fetch profile photo for user \(userId): \(error)")
                // Continue - missing photo URLs are optional
            }
        }

        // ✅ NEW: For 1-on-1 conversations, default to "pending" (message request)
        // For group conversations, default to "accepted" (immediate access)
        let finalStatus: String
        if let providedStatus = conversationStatus {
            finalStatus = providedStatus
        } else {
            finalStatus = isGroup ? "accepted" : "pending"
        }

        let conversationData: [String: Any] = [
            "participantIds": allParticipantIds,
            "participantNames": participantNames,
            "participantPhotoURLs": participantPhotoURLs,
            "isGroup": isGroup,
            "groupName": groupName as Any,
            "groupAvatarUrl": NSNull(),
            "lastMessage": NSNull(),
            "lastMessageText": "",
            "lastMessageTimestamp": Timestamp(date: Date()),
            "unreadCounts": [:],
            "createdAt": Timestamp(date: Date()),
            "updatedAt": Timestamp(date: Date()),
            "conversationStatus": finalStatus,
            "requesterId": currentUserId,
            "requestReadBy": []
        ]
        
        // 🔍 DEBUG: Log conversation creation details
        print("📝 Creating conversation:")
        print("   ID: \(conversationRef.documentID)")
        print("   Participants: \(allParticipantIds)")
        print("   Status: \(finalStatus)")
        print("   RequesterID: \(currentUserId)")
        print("   IsGroup: \(isGroup)")
        print("   Profile Photos: \(participantPhotoURLs.count) fetched")

        do {
            try await conversationRef.setData(conversationData)
            print("✅ Conversation created successfully: \(conversationRef.documentID)")
            print("   Status saved: \(finalStatus)")
            print("   RequesterID saved: \(currentUserId)")
            return conversationRef.documentID
        } catch {
            print("❌ Error creating conversation: \(error)")
            throw FirebaseMessagingError.networkError(error)
        }
    }
    
    /// Get existing conversation or create new one (prevents duplicates)
    /// ✅ FIX: This ensures messages are always sent to the same conversation
    func getOrCreateConversation(
        with userId: String,
        participantName: String
    ) async throws -> String {
        guard isAuthenticated else {
            throw FirebaseMessagingError.notAuthenticated
        }
        
        print("🔍 Searching for existing conversation with user: \(userId)")
        
        // ✅ STEP 1: Check if conversation already exists
        let conversationsRef = db.collection("conversations")
        
        // Query for existing 1-on-1 conversation with this user
        let snapshot = try await conversationsRef
            .whereField("participantIds", arrayContains: currentUserId)
            .whereField("isGroup", isEqualTo: false)
            .getDocuments()
        
        // Find matching conversation (1-on-1 with both users)
        for doc in snapshot.documents {
            if let conversation = try? doc.data(as: FirebaseConversation.self),
               conversation.participantIds.contains(userId),
               conversation.participantIds.count == 2 {
                print("✅ Found existing conversation: \(doc.documentID)")
                return doc.documentID
            }
        }
        
        // ✅ STEP 2: No existing conversation - create new one
        print("📝 Creating new conversation with \(userId)")
        return try await createConversation(
            participantIds: [userId],
            participantNames: [
                currentUserId: currentUserName,
                userId: participantName
            ],
            isGroup: false,
            conversationStatus: nil  // Will auto-set to "pending" for 1-on-1
        )
    }

    /// Fetch a conversation by ID (cache-first for speed)
    func fetchConversation(conversationId: String) async -> ChatConversation? {
        guard isAuthenticated else { return nil }

        let conversationRef = db.collection("conversations").document(conversationId)

        if let cachedDoc = try? await conversationRef.getDocument(source: .cache),
           cachedDoc.exists,
           let cachedConversation = try? cachedDoc.data(as: FirebaseConversation.self) {
            return cachedConversation.toConversation()
        }

        do {
            let doc = try await conversationRef.getDocument()
            guard doc.exists,
                  let conversation = try? doc.data(as: FirebaseConversation.self) else {
                return nil
            }
            return conversation.toConversation()
        } catch {
            print("❌ Error fetching conversation: \(error)")
            return nil
        }
    }
    
    /// Get or create a direct conversation with a user
    public func getOrCreateDirectConversation(
        withUserId userId: String,
        userName: String
    ) async throws -> String {
        guard isAuthenticated else {
            throw FirebaseMessagingError.notAuthenticated
        }
        
        // Prevent creating conversation with yourself
        guard userId != currentUserId else {
            throw FirebaseMessagingError.selfConversation
        }
        
        do {
            // Check if user is blocked - using the extension's methods
            let isBlocked = try await checkIfBlocked(userId: userId)
            let isBlockedBy = try await checkIfBlockedByUser(userId: userId)
            
            if isBlocked || isBlockedBy {
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
                    print("✅ Found existing conversation: \(conversationId)")
                    return conversationId
                }
            }
            
            // Check follow status - using the extension's method with correct signature
            let followStatus = try await checkFollowStatus(userId1: currentUserId, userId2: userId)
            
            // Check recipient's privacy settings from Firestore
            let userDoc = try await db.collection("users").document(userId).getDocument()
            let allowMessages = userDoc.data()?["allowMessagesFromEveryone"] as? Bool ?? true
            let requireFollow = userDoc.data()?["requireFollowToMessage"] as? Bool ?? false
            
            // Determine conversation status based on mutual follow relationship
            let conversationStatus: String

            if !allowMessages {
                throw FirebaseMessagingError.messagesNotAllowed
            } else if requireFollow && !followStatus.user1FollowsUser2 {
                // Recipient requires follow, and sender doesn't follow them
                throw FirebaseMessagingError.followRequired
            } else if followStatus.user1FollowsUser2 && followStatus.user2FollowsUser1 {
                // ✅ MUTUAL FOLLOWS → Direct messaging (accepted)
                conversationStatus = "accepted"
            } else {
                // ✅ NOT MUTUAL → Message Request (pending)
                // This includes:
                // - A follows B, but B doesn't follow A → pending
                // - Neither follows → pending
                // - B follows A, but A doesn't follow B → pending
                conversationStatus = "pending"
            }
            
            // Create new conversation
            let participantNames = [
                currentUserId: currentUserName,
                userId: userName
            ]
            
            print("📝 Creating new conversation with \(userName) - Status: \(conversationStatus)")
            return try await createConversation(
                participantIds: [userId],
                participantNames: participantNames,
                isGroup: false,
                conversationStatus: conversationStatus
            )
        } catch let error as FirebaseMessagingError {
            throw error
        } catch {
            print("❌ Error in getOrCreateDirectConversation: \(error)")
            throw FirebaseMessagingError.networkError(error)
        }
    }
    
    // MARK: - Messages
    
    /// Start listening to messages in a conversation (with pagination)
    func startListeningToMessages(
        conversationId: String,
        onUpdate: @escaping ([AppMessage]) -> Void
    ) {
        startListeningToMessages(
            conversationId: conversationId,
            limit: 50,
            onUpdate: onUpdate
        )
    }
    
    /// Start listening to messages with custom limit
    func startListeningToMessages(
        conversationId: String,
        limit: Int,
        onUpdate: @escaping ([AppMessage]) -> Void
    ) {
        let listener = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Error fetching messages: \(error)")
                    self.lastError = .networkError(error)
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    return
                }
                
                // Store last document for pagination
                if let lastDoc = documents.last {
                    self.lastDocuments[conversationId] = lastDoc
                }
                
                // Check if there might be more messages
                self.hasMoreMessages[conversationId] = documents.count >= limit
                
                let messages: [AppMessage] = documents.compactMap { doc -> AppMessage? in
                    guard let firebaseMessage = try? doc.data(as: FirebaseMessage.self) else {
                        return nil
                    }
                    return firebaseMessage.toMessage(currentUserId: self.currentUserId)
                }.reversed() // Reverse to show oldest first
                
                onUpdate(Array(messages))
                
                // Log offline status
                if let metadata = snapshot?.metadata {
                    if metadata.isFromCache {
                        print("📦 Messages loaded from cache (offline mode)")
                    } else {
                        print("🌐 Messages loaded from server")
                    }
                }
            }
        
        messagesListeners[conversationId] = listener
    }
    
    /// Load more messages (pagination)
    func loadMoreMessages(
        conversationId: String,
        limit: Int = 50,
        onUpdate: @escaping ([AppMessage]) -> Void
    ) async throws {
        guard let lastDoc = lastDocuments[conversationId] else {
            print("⚠️ No last document found for pagination")
            return
        }
        
        guard hasMoreMessages[conversationId] == true else {
            print("📭 No more messages to load")
            return
        }
        
        do {
            let snapshot = try await db.collection("conversations")
                .document(conversationId)
                .collection("messages")
                .order(by: "timestamp", descending: true)
                .start(afterDocument: lastDoc)
                .limit(to: limit)
                .getDocuments()
            
            guard !snapshot.documents.isEmpty else {
                hasMoreMessages[conversationId] = false
                print("📭 Reached end of messages")
                return
            }
            
            // Update last document
            if let newLastDoc = snapshot.documents.last {
                lastDocuments[conversationId] = newLastDoc
            }
            
            // Check if there are more messages
            hasMoreMessages[conversationId] = snapshot.documents.count >= limit
            
            let messages: [AppMessage] = snapshot.documents.compactMap { doc -> AppMessage? in
                guard let firebaseMessage = try? doc.data(as: FirebaseMessage.self) else {
                    return nil
                }
                return firebaseMessage.toMessage(currentUserId: self.currentUserId)
            }.reversed()
            
            onUpdate(Array(messages))
            print("✅ Loaded \(messages.count) more messages")
            
        } catch {
            print("❌ Error loading more messages: \(error)")
            throw FirebaseMessagingError.networkError(error)
        }
    }
    
    /// Check if there are more messages to load
    func canLoadMoreMessages(conversationId: String) -> Bool {
        return hasMoreMessages[conversationId] ?? false
    }
    
    /// Stop listening to messages
    func stopListeningToMessages(conversationId: String) {
        messagesListeners[conversationId]?.remove()
        messagesListeners.removeValue(forKey: conversationId)
        
        // Clean up pagination state
        lastDocuments.removeValue(forKey: conversationId)
        hasMoreMessages.removeValue(forKey: conversationId)
    }
    
    /// Send a text message
    func sendMessage(
        conversationId: String,
        text: String,
        replyToMessageId: String? = nil,
        clientMessageId: String? = nil
    ) async throws {
        guard isAuthenticated else {
            throw FirebaseMessagingError.notAuthenticated
        }
        
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FirebaseMessagingError.invalidInput("Message cannot be empty")
        }
        
        // ✅ NEW: Check if user can send message (Instagram/Threads style limit)
        let (canSend, reason) = try await canSendMessage(conversationId: conversationId)
        guard canSend else {
            throw FirebaseMessagingError.invalidInput(reason ?? "Cannot send message")
        }
        
        do {
            let messageId = clientMessageId ?? db.collection("conversations")
                .document(conversationId)
                .collection("messages")
                .document()
                .documentID
            let messageRef = db.collection("conversations")
                .document(conversationId)
                .collection("messages")
                .document(messageId)
            
            var replyToMessage: FirebaseMessage.ReplyInfo? = nil
            
            // Fetch reply-to message if specified
            if let replyToId = replyToMessageId {
                let replyDoc = try await db.collection("conversations")
                    .document(conversationId)
                    .collection("messages")
                    .document(replyToId)
                    .getDocument()
                
                if let replyData = try? replyDoc.data(as: FirebaseMessage.self),
                   let replyMessageId = replyData.id {
                    replyToMessage = FirebaseMessage.ReplyInfo(
                        messageId: replyMessageId,
                        text: replyData.text,
                        senderId: replyData.senderId,
                        senderName: replyData.senderName
                    )
                }
            }
            
            // ✅ Get sender's profile image URL from UserDefaults cache
            let senderProfileImageURL = UserDefaults.standard.string(forKey: "currentUserProfileImageURL")
            
            let message = FirebaseMessage(
                id: messageId,
                conversationId: conversationId,
                senderId: currentUserId,
                senderName: currentUserName,
                senderProfileImageURL: senderProfileImageURL, // ✅ Include profile image
                text: text,
                attachments: [],
                reactions: [],
                replyTo: replyToMessage,
                timestamp: Timestamp(date: Date()),
                readBy: [currentUserId]
            )
            
            // Fetch conversation to get participants and status
            let conversationRef = db.collection("conversations").document(conversationId)
            let conversationDoc = try await conversationRef.getDocument()
            
            guard conversationDoc.exists else {
                throw FirebaseMessagingError.conversationNotFound
            }
            
            guard let conversation = try? conversationDoc.data(as: FirebaseConversation.self) else {
                throw FirebaseMessagingError.conversationNotFound
            }
            
            let participantIds = conversation.participantIds
            let status = conversation.conversationStatus ?? "accepted"
            let requesterId = conversation.requesterId
            
            // Use batch to update both message and conversation
            let batch = db.batch()
            
            try batch.setData(from: message, forDocument: messageRef)
            
            // Build conversation updates
            var updates: [String: Any] = [
                "lastMessageText": text,
                "lastMessageTimestamp": Timestamp(date: Date()),
                "updatedAt": Timestamp(date: Date())
            ]
            
            // ✅ NEW: Increment message count for sender (Instagram/Threads style tracking)
            updates["messageCount.\(currentUserId)"] = FieldValue.increment(Int64(1))
            
            // ✅ NEW: Auto-accept if recipient sends a message (Instagram/Threads style)
            if status == "pending" && requesterId != currentUserId {
                updates["conversationStatus"] = "accepted"
                print("✅ Conversation auto-accepted (recipient replied)")
            }
            
            // Increment unread count for all participants except sender
            for participantId in participantIds where participantId != currentUserId {
                updates["unreadCounts.\(participantId)"] = FieldValue.increment(Int64(1))
            }
            
            batch.updateData(updates, forDocument: conversationRef)
            
            try await batch.commit()
            
            print("✅ Message sent and unread counts updated for other participants")
        } catch let error as FirebaseMessagingError {
            print("❌ FirebaseMessagingError: \(error.localizedDescription)")
            throw error
        } catch {
            print("❌ Error sending message: \(error)")
            throw FirebaseMessagingError.networkError(error)
        }
    }
    
    /// Send a message with photo attachments
    func sendMessageWithPhotos(
        conversationId: String,
        text: String,
        images: [UIImage],
        clientMessageId: String? = nil
    ) async throws {
        guard isAuthenticated else {
            throw FirebaseMessagingError.notAuthenticated
        }
        
        guard !images.isEmpty else {
            throw FirebaseMessagingError.invalidInput("No images provided")
        }
        
        do {
            // Upload images first
            let attachments = try await uploadImages(images, conversationId: conversationId)
            
            let messageId = clientMessageId ?? db.collection("conversations")
                .document(conversationId)
                .collection("messages")
                .document()
                .documentID
            let messageRef = db.collection("conversations")
                .document(conversationId)
                .collection("messages")
                .document(messageId)
            
            // ✅ Get sender's profile image URL from UserDefaults cache
            let senderProfileImageURL = UserDefaults.standard.string(forKey: "currentUserProfileImageURL")
            
            let message = FirebaseMessage(
                id: messageId,
                conversationId: conversationId,
                senderId: currentUserId,
                senderName: currentUserName,
                senderProfileImageURL: senderProfileImageURL, // ✅ Include profile image
                text: text,
                attachments: attachments,
                reactions: [],
                replyTo: nil,
                timestamp: Timestamp(date: Date()),
                readBy: [currentUserId]
            )
            
            // Fetch conversation to get participants
            let conversationRef = db.collection("conversations").document(conversationId)
            let conversationDoc = try await conversationRef.getDocument()
            
            guard conversationDoc.exists else {
                throw FirebaseMessagingError.conversationNotFound
            }
            
            let participantIds = conversationDoc.data()?["participantIds"] as? [String] ?? []
            
            let batch = db.batch()
            
            try batch.setData(from: message, forDocument: messageRef)
            
            // Build unread count updates for other participants
            var updates: [String: Any] = [
                "lastMessageText": text.isEmpty ? "📷 Photo" : text,
                "lastMessageTimestamp": Timestamp(date: Date()),
                "updatedAt": Timestamp(date: Date())
            ]
            
            // Increment unread count for all participants except sender
            for participantId in participantIds where participantId != currentUserId {
                updates["unreadCounts.\(participantId)"] = FieldValue.increment(Int64(1))
            }
            
            batch.updateData(updates, forDocument: conversationRef)
            
            try await batch.commit()
            
            print("✅ Photo message sent and unread counts updated for other participants")
        } catch let error as FirebaseMessagingError {
            print("❌ FirebaseMessagingError: \(error.localizedDescription)")
            throw error
        } catch {
            print("❌ Error sending photo message: \(error)")
            throw FirebaseMessagingError.networkError(error)
        }
    }
    
    /// Upload images to Firebase Storage
    private func uploadImages(_ images: [UIImage], conversationId: String) async throws -> [FirebaseMessage.Attachment] {
        var attachments: [FirebaseMessage.Attachment] = []
        
        for (index, image) in images.enumerated() {
            guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                print("⚠️ Failed to convert image \(index) to JPEG data")
                continue
            }
            
            let filename = "\(UUID().uuidString).jpg"
            let path = "messages/\(conversationId)/\(filename)"
            let storageRef = storage.reference().child(path)
            
            do {
                // Upload
                let metadata = StorageMetadata()
                metadata.contentType = "image/jpeg"
                _ = try await storageRef.putData(imageData, metadata: metadata)
                
                // Get download URL
                let downloadURL = try await storageRef.downloadURL()
                
                // Create thumbnail
                let thumbnail = image.resized(to: CGSize(width: 200, height: 200))
                let thumbnailData = thumbnail?.jpegData(compressionQuality: 0.6)
                
                let attachment = FirebaseMessage.Attachment(
                    id: UUID().uuidString,
                    type: "photo",
                    url: downloadURL.absoluteString,
                    thumbnailUrl: nil, // Could upload thumbnail separately
                    metadata: [
                        "width": image.size.width,
                        "height": image.size.height
                    ]
                )
                
                attachments.append(attachment)
                print("✅ Uploaded image \(index + 1)/\(images.count)")
                
            } catch {
                print("❌ Failed to upload image \(index): \(error)")
                throw FirebaseMessagingError.uploadFailed("Image \(index + 1) failed: \(error.localizedDescription)")
            }
        }
        
        guard !attachments.isEmpty else {
            throw FirebaseMessagingError.uploadFailed("All image uploads failed")
        }
        
        return attachments
    }
    
    /// Add reaction to a message
    func addReaction(
        conversationId: String,
        messageId: String,
        emoji: String
    ) async throws {
        let messageRef = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)

        let reactionId = UUID().uuidString

        let reaction = FirebaseMessage.Reaction(
            id: reactionId,
            emoji: emoji,
            userId: currentUserId,
            userName: currentUserName,
            timestamp: Date()
        )

        // 1. Add to message's reactions array (for display in UI)
        try await messageRef.updateData([
            "reactions": FieldValue.arrayUnion([try Firestore.Encoder().encode(reaction)])
        ])

        // 2. Create reaction document in subcollection (triggers Cloud Function for notifications)
        let reactionRef = messageRef.collection("reactions").document(reactionId)
        try await reactionRef.setData([
            "emoji": emoji,
            "userId": currentUserId,
            "userName": currentUserName,
            "timestamp": Timestamp(date: Date())
        ])

        print("✅ Reaction added to message and notification triggered")
    }
    
    /// Remove reaction from a message
    func removeReaction(
        conversationId: String,
        messageId: String,
        reactionId: String
    ) async throws {
        let messageRef = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
        
        // Fetch the message to find and remove the specific reaction
        let document = try await messageRef.getDocument()
        guard var message = try? document.data(as: FirebaseMessage.self) else {
            return
        }
        
        message.reactions.removeAll { $0.id == reactionId }
        
        try messageRef.setData(from: message)
    }
    
    /// Mark messages as read
    func markMessagesAsRead(conversationId: String, messageIds: [String]) async throws {
        guard !messageIds.isEmpty else { return }
        
        let batch = db.batch()
        
        for messageId in messageIds {
            let messageRef = db.collection("conversations")
                .document(conversationId)
                .collection("messages")
                .document(messageId)
            
            batch.updateData([
                "readBy": FieldValue.arrayUnion([currentUserId])
            ], forDocument: messageRef)
        }
        
        // Reset unread count for current user in conversation
        let conversationRef = db.collection("conversations").document(conversationId)
        batch.updateData([
            "unreadCounts.\(currentUserId)": 0
        ], forDocument: conversationRef)
        
        try await batch.commit()
        
        print("✅ Marked \(messageIds.count) messages as read and cleared unread count")
    }
    
    // MARK: - Typing Indicators
    
    /// Update typing status
    func updateTypingStatus(conversationId: String, isTyping: Bool) async throws {
        let typingRef = db.collection("conversations")
            .document(conversationId)
            .collection("typing")
            .document(currentUserId)
        
        if isTyping {
            try await typingRef.setData([
                "userId": currentUserId,
                "userName": currentUserName,
                "timestamp": Timestamp(date: Date())
            ])
        } else {
            try await typingRef.delete()
        }
    }
    
    /// Listen to typing indicators
    func startListeningToTyping(
        conversationId: String,
        onUpdate: @escaping ([String]) -> Void
    ) {
        db.collection("conversations")
            .document(conversationId)
            .collection("typing")
            .addSnapshotListener { snapshot, error in
                guard let documents = snapshot?.documents else {
                    onUpdate([])
                    return
                }
                
                // Filter out current user and expired typing indicators
                let typingUsers = documents.compactMap { doc -> String? in
                    guard let userId = doc.data()["userId"] as? String,
                          userId != self.currentUserId,
                          let timestamp = doc.data()["timestamp"] as? Timestamp,
                          Date().timeIntervalSince(timestamp.dateValue()) < 5 else {
                        return nil
                    }
                    return doc.data()["userName"] as? String
                }
                
                onUpdate(typingUsers)
            }
    }
    
    // MARK: - Message Actions
    
    /// Delete a message (soft delete - marks as deleted)
    func deleteMessage(conversationId: String, messageId: String) async throws {
        let messageRef = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
        
        try await messageRef.updateData([
            "isDeleted": true,
            "deletedBy": currentUserId,
            "text": "This message was deleted"
        ])
        
        print("✅ Message deleted: \(messageId)")
    }
    
    /// Delete a message permanently (hard delete)
    func deleteMessagePermanently(conversationId: String, messageId: String) async throws {
        let messageRef = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
        
        try await messageRef.delete()
        
        print("✅ Message permanently deleted: \(messageId)")
    }
    
    /// Pin a message in a conversation
    func pinMessage(conversationId: String, messageId: String) async throws {
        let messageRef = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
        
        try await messageRef.updateData([
            "isPinned": true,
            "pinnedBy": currentUserId,
            "pinnedAt": Timestamp(date: Date())
        ])
        
        print("✅ Message pinned: \(messageId)")
    }
    
    /// Unpin a message
    func unpinMessage(conversationId: String, messageId: String) async throws {
        let messageRef = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
        
        try await messageRef.updateData([
            "isPinned": false,
            "pinnedBy": FieldValue.delete(),
            "pinnedAt": FieldValue.delete()
        ])
        
        print("✅ Message unpinned: \(messageId)")
    }
    
    /// Star a message for the current user
    func starMessage(conversationId: String, messageId: String) async throws {
        let messageRef = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
        
        try await messageRef.updateData([
            "isStarred": FieldValue.arrayUnion([currentUserId])
        ])
        
        print("✅ Message starred: \(messageId)")
    }
    
    /// Unstar a message
    func unstarMessage(conversationId: String, messageId: String) async throws {
        let messageRef = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
        
        try await messageRef.updateData([
            "isStarred": FieldValue.arrayRemove([currentUserId])
        ])
        
        print("✅ Message unstarred: \(messageId)")
    }
    
    /// Edit a message
    func editMessage(conversationId: String, messageId: String, newText: String) async throws {
        let messageRef = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
        
        try await messageRef.updateData([
            "text": newText,
            "editedAt": Timestamp(date: Date())
        ])
        
        // Update last message in conversation if this was the last message
        let conversationRef = db.collection("conversations").document(conversationId)
        let conversation = try await conversationRef.getDocument()
        
        if let lastMessageId = conversation.data()?["lastMessage"] as? String,
           lastMessageId == messageId {
            try await conversationRef.updateData([
                "lastMessageText": newText
            ])
        }
        
        print("✅ Message edited: \(messageId)")
    }
    
    /// Forward a message to another conversation
    func forwardMessage(messageId: String, fromConversation: String, toConversation: String) async throws {
        // Fetch the original message
        let originalMessageRef = db.collection("conversations")
            .document(fromConversation)
            .collection("messages")
            .document(messageId)
        
        let originalDoc = try await originalMessageRef.getDocument()
        guard let originalMessage = try? originalDoc.data(as: FirebaseMessage.self) else {
            throw NSError(domain: "MessagingService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Message not found"])
        }
        
        // Create new message in destination conversation
        let newMessageRef = db.collection("conversations")
            .document(toConversation)
            .collection("messages")
            .document()
        
        let forwardedMessage = FirebaseMessage(
            id: newMessageRef.documentID,
            conversationId: toConversation,
            senderId: currentUserId,
            senderName: currentUserName,
            text: originalMessage.text,
            attachments: originalMessage.attachments,
            reactions: [],
            replyTo: nil,
            timestamp: Timestamp(date: Date()),
            readBy: [currentUserId]
        )
        
        let batch = db.batch()
        try batch.setData(from: forwardedMessage, forDocument: newMessageRef)
        
        // Update destination conversation
        let destConversationRef = db.collection("conversations").document(toConversation)
        batch.updateData([
            "lastMessageText": originalMessage.text,
            "lastMessageTimestamp": Timestamp(date: Date()),
            "updatedAt": Timestamp(date: Date())
        ], forDocument: destConversationRef)
        
        try await batch.commit()
        
        print("✅ Message forwarded from \(fromConversation) to \(toConversation)")
    }
    
    /// Fetch pinned messages in a conversation
    func fetchPinnedMessages(conversationId: String) async throws -> [AppMessage] {
        let snapshot = try await db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .whereField("isPinned", isEqualTo: true)
            .order(by: "pinnedAt", descending: true)
            .getDocuments()
        
        let messages: [AppMessage] = snapshot.documents.compactMap { doc in
            guard let firebaseMessage = try? doc.data(as: FirebaseMessage.self) else {
                return nil
            }
            return firebaseMessage.toMessage(currentUserId: self.currentUserId)
        }
        
        return messages
    }
    
    /// Search messages within a specific conversation
    func searchMessagesInConversation(conversationId: String, query: String) async throws -> [AppMessage] {
        print("🔍 Searching messages in conversation: \(conversationId) for: '\(query)'")
        
        let snapshot = try await db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .order(by: "timestamp", descending: true)
            .limit(to: 100)  // Limit to recent 100 messages for performance
            .getDocuments()
        
        let allMessages: [AppMessage] = snapshot.documents.compactMap { doc in
            guard let firebaseMessage = try? doc.data(as: FirebaseMessage.self) else {
                return nil
            }
            return firebaseMessage.toMessage(currentUserId: self.currentUserId)
        }
        
        // Filter messages that contain the query (case-insensitive)
        let lowercaseQuery = query.lowercased()
        let matchingMessages = allMessages.filter { message in
            message.text.lowercased().contains(lowercaseQuery)
        }
        
        print("✅ Found \(matchingMessages.count) matching messages in conversation")
        return matchingMessages
    }
    
    /// Fetch starred messages for current user
    func fetchStarredMessages(conversationId: String) async throws -> [AppMessage] {
        let snapshot = try await db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .whereField("isStarred", arrayContains: currentUserId)
            .order(by: "timestamp", descending: true)
            .getDocuments()
        
        let messages: [AppMessage] = snapshot.documents.compactMap { doc in
            guard let firebaseMessage = try? doc.data(as: FirebaseMessage.self) else {
                return nil
            }
            return firebaseMessage.toMessage(currentUserId: self.currentUserId)
        }
        
        return messages
    }
    
    
    // MARK: - Group Chat Management
    
    /// Create a group conversation
    func createGroupConversation(
        participantIds: [String],
        participantNames: [String: String],
        groupName: String,
        groupAvatarUrl: String? = nil
    ) async throws -> String {
        guard isAuthenticated else {
            throw FirebaseMessagingError.notAuthenticated
        }
        
        guard !groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FirebaseMessagingError.invalidInput("Group name cannot be empty")
        }
        
        guard participantIds.count >= 1 else {
            throw FirebaseMessagingError.invalidInput("Group must have at least 2 members (including you)")
        }
        
        var allParticipantNames = participantNames
        allParticipantNames[currentUserId] = currentUserName
        
        return try await createConversation(
            participantIds: participantIds,
            participantNames: allParticipantNames,
            isGroup: true,
            groupName: groupName
        )
    }
    
    /// Add participants to a group conversation
    func addParticipantsToGroup(
        conversationId: String,
        participantIds: [String],
        participantNames: [String: String]
    ) async throws {
        guard isAuthenticated else {
            throw FirebaseMessagingError.notAuthenticated
        }
        
        guard !participantIds.isEmpty else {
            throw FirebaseMessagingError.invalidInput("No participants provided")
        }
        
        do {
            let conversationRef = db.collection("conversations").document(conversationId)
            let doc = try await conversationRef.getDocument()
            
            guard doc.exists else {
                throw FirebaseMessagingError.conversationNotFound
            }
            
            guard let conversation = try? doc.data(as: FirebaseConversation.self) else {
                throw FirebaseMessagingError.conversationNotFound
            }
            
            guard conversation.isGroup else {
                throw FirebaseMessagingError.invalidInput("Can only add participants to group conversations")
            }
            
            // Build updates
            var updates: [String: Any] = [
                "participantIds": FieldValue.arrayUnion(participantIds),
                "updatedAt": Timestamp(date: Date())
            ]
            
            // Add participant names
            for (id, name) in participantNames {
                updates["participantNames.\(id)"] = name
            }
            
            try await conversationRef.updateData(updates)
            
            // Send system message
            let participantList = participantNames.values.joined(separator: ", ")
            let systemMessage = "\(currentUserName) added \(participantList) to the group"
            
            try await sendSystemMessage(conversationId: conversationId, text: systemMessage)
            
            print("✅ Added \(participantIds.count) participants to group")
            
        } catch let error as FirebaseMessagingError {
            throw error
        } catch {
            throw FirebaseMessagingError.networkError(error)
        }
    }
    
    /// Remove participants from a group conversation
    func removeParticipantFromGroup(
        conversationId: String,
        participantId: String
    ) async throws {
        guard isAuthenticated else {
            throw FirebaseMessagingError.notAuthenticated
        }
        
        guard participantId != currentUserId else {
            throw FirebaseMessagingError.invalidInput("Use leaveGroup to remove yourself")
        }
        
        do {
            let conversationRef = db.collection("conversations").document(conversationId)
            let doc = try await conversationRef.getDocument()
            
            guard doc.exists else {
                throw FirebaseMessagingError.conversationNotFound
            }
            
            guard let conversation = try? doc.data(as: FirebaseConversation.self) else {
                throw FirebaseMessagingError.conversationNotFound
            }
            
            guard conversation.isGroup else {
                throw FirebaseMessagingError.invalidInput("Can only remove participants from group conversations")
            }
            
            // Get participant name before removing
            let participantName = conversation.participantNames[participantId] ?? "User"
            
            // Remove participant
            let updates: [String: Any] = [
                "participantIds": FieldValue.arrayRemove([participantId]),
                "participantNames.\(participantId)": FieldValue.delete(),
                "updatedAt": Timestamp(date: Date())
            ]
            
            try await conversationRef.updateData(updates)
            
            // Send system message
            let systemMessage = "\(currentUserName) removed \(participantName) from the group"
            try await sendSystemMessage(conversationId: conversationId, text: systemMessage)
            
            print("✅ Removed participant from group")
            
        } catch let error as FirebaseMessagingError {
            throw error
        } catch {
            throw FirebaseMessagingError.networkError(error)
        }
    }
    
    /// Leave a group conversation
    func leaveGroup(conversationId: String) async throws {
        guard isAuthenticated else {
            throw FirebaseMessagingError.notAuthenticated
        }
        
        do {
            let conversationRef = db.collection("conversations").document(conversationId)
            let doc = try await conversationRef.getDocument()
            
            guard doc.exists else {
                throw FirebaseMessagingError.conversationNotFound
            }
            
            guard let conversation = try? doc.data(as: FirebaseConversation.self) else {
                throw FirebaseMessagingError.conversationNotFound
            }
            
            guard conversation.isGroup else {
                throw FirebaseMessagingError.invalidInput("Can only leave group conversations")
            }
            
            // Remove current user
            let updates: [String: Any] = [
                "participantIds": FieldValue.arrayRemove([currentUserId]),
                "participantNames.\(currentUserId)": FieldValue.delete(),
                "updatedAt": Timestamp(date: Date())
            ]
            
            try await conversationRef.updateData(updates)
            
            // Send system message
            let systemMessage = "\(currentUserName) left the group"
            try await sendSystemMessage(conversationId: conversationId, text: systemMessage)
            
            print("✅ Left group conversation")
            
        } catch let error as FirebaseMessagingError {
            throw error
        } catch {
            throw FirebaseMessagingError.networkError(error)
        }
    }
    
    /// Update group name
    func updateGroupName(conversationId: String, newName: String) async throws {
        guard isAuthenticated else {
            throw FirebaseMessagingError.notAuthenticated
        }
        
        guard !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FirebaseMessagingError.invalidInput("Group name cannot be empty")
        }
        
        do {
            let conversationRef = db.collection("conversations").document(conversationId)
            let doc = try await conversationRef.getDocument()
            
            guard doc.exists else {
                throw FirebaseMessagingError.conversationNotFound
            }
            
            guard let conversation = try? doc.data(as: FirebaseConversation.self) else {
                throw FirebaseMessagingError.conversationNotFound
            }
            
            guard conversation.isGroup else {
                throw FirebaseMessagingError.invalidInput("Can only update name for group conversations")
            }
            
            let oldName = conversation.groupName ?? "Unnamed Group"
            
            try await conversationRef.updateData([
                "groupName": newName,
                "updatedAt": Timestamp(date: Date())
            ])
            
            // Send system message
            let systemMessage = "\(currentUserName) changed the group name from \"\(oldName)\" to \"\(newName)\""
            try await sendSystemMessage(conversationId: conversationId, text: systemMessage)
            
            print("✅ Updated group name to: \(newName)")
            
        } catch let error as FirebaseMessagingError {
            throw error
        } catch {
            throw FirebaseMessagingError.networkError(error)
        }
    }
    
    /// Update group avatar
    func updateGroupAvatar(conversationId: String, image: UIImage) async throws {
        guard isAuthenticated else {
            throw FirebaseMessagingError.notAuthenticated
        }
        
        do {
            // Upload avatar
            guard let imageData = image.jpegData(compressionQuality: 0.7) else {
                throw FirebaseMessagingError.uploadFailed("Failed to convert image to JPEG")
            }
            
            let filename = "\(conversationId)_avatar.jpg"
            let path = "group_avatars/\(filename)"
            let storageRef = storage.reference().child(path)
            
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            _ = try await storageRef.putData(imageData, metadata: metadata)
            let downloadURL = try await storageRef.downloadURL()
            
            // Update conversation
            let conversationRef = db.collection("conversations").document(conversationId)
            try await conversationRef.updateData([
                "groupAvatarUrl": downloadURL.absoluteString,
                "updatedAt": Timestamp(date: Date())
            ])
            
            // Send system message
            let systemMessage = "\(currentUserName) changed the group photo"
            try await sendSystemMessage(conversationId: conversationId, text: systemMessage)
            
            print("✅ Updated group avatar")
            
        } catch let error as FirebaseMessagingError {
            throw error
        } catch {
            throw FirebaseMessagingError.networkError(error)
        }
    }
    
    /// Send a system message (for group events)
    private func sendSystemMessage(conversationId: String, text: String) async throws {
        let messageRef = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document()
        
        let message = FirebaseMessage(
            id: messageRef.documentID,
            conversationId: conversationId,
            senderId: "system",
            senderName: "System",
            text: text,
            attachments: [],
            reactions: [],
            replyTo: nil,
            timestamp: Timestamp(date: Date()),
            readBy: []
        )
        
        try messageRef.setData(from: message)
    }
    
    /// Get group participants
    func getGroupParticipants(conversationId: String) async throws -> [String: String] {
        guard isAuthenticated else {
            throw FirebaseMessagingError.notAuthenticated
        }
        
        do {
            let doc = try await db.collection("conversations")
                .document(conversationId)
                .getDocument()
            
            guard doc.exists else {
                throw FirebaseMessagingError.conversationNotFound
            }
            
            guard let conversation = try? doc.data(as: FirebaseConversation.self) else {
                throw FirebaseMessagingError.conversationNotFound
            }
            
            return conversation.participantNames
            
        } catch let error as FirebaseMessagingError {
            throw error
        } catch {
            throw FirebaseMessagingError.networkError(error)
        }
    }
    
    // MARK: - Search
    
    /// Search users by display name or username
    public func searchUsers(query: String) async throws -> [ContactUser] {
        guard !query.isEmpty else { return [] }
        
        let lowercaseQuery = query.lowercased()
        print("🔍 Messaging: Searching users with query: '\(query)'")
        
        var users: [ContactUser] = []
        var seenUserIds = Set<String>()
        
        // STRATEGY 1: Try searching with lowercase fields (if they exist)
        do {
            // Search by displayNameLowercase
            let displayNameSnapshot = try await db.collection("users")
                .whereField("displayNameLowercase", isGreaterThanOrEqualTo: lowercaseQuery)
                .whereField("displayNameLowercase", isLessThanOrEqualTo: lowercaseQuery + "\u{f8ff}")
                .limit(to: 20)
                .getDocuments()
            
            print("✅ Found \(displayNameSnapshot.documents.count) users by displayNameLowercase")
            
            for doc in displayNameSnapshot.documents {
                if let user = try? doc.data(as: ContactUser.self), let userId = user.id {
                    if !seenUserIds.contains(userId) {
                        users.append(user)
                        seenUserIds.insert(userId)
                    }
                }
            }
            
            // Search by usernameLowercase
            let usernameSnapshot = try await db.collection("users")
                .whereField("usernameLowercase", isGreaterThanOrEqualTo: lowercaseQuery)
                .whereField("usernameLowercase", isLessThanOrEqualTo: lowercaseQuery + "\u{f8ff}")
                .limit(to: 20)
                .getDocuments()
            
            print("✅ Found \(usernameSnapshot.documents.count) users by usernameLowercase")
            
            for doc in usernameSnapshot.documents {
                if let user = try? doc.data(as: ContactUser.self), let userId = user.id {
                    if !seenUserIds.contains(userId) {
                        users.append(user)
                        seenUserIds.insert(userId)
                    }
                }
            }
            
        } catch {
            print("⚠️ Lowercase field search failed: \(error)")
            print("📝 Falling back to client-side filtering for messaging...")
            
            // STRATEGY 2: Fallback - Get users and filter client-side
            let allUsersSnapshot = try await db.collection("users")
                .limit(to: 100)
                .getDocuments()
            
            print("📥 Downloaded \(allUsersSnapshot.documents.count) users for messaging search")
            
            for doc in allUsersSnapshot.documents {
                let data = doc.data()
                
                // Check if displayName or username contains the query
                let displayName = (data["displayName"] as? String ?? "").lowercased()
                let username = (data["username"] as? String ?? "").lowercased()
                
                if displayName.contains(lowercaseQuery) || username.contains(lowercaseQuery) {
                    if let user = try? doc.data(as: ContactUser.self), let userId = user.id {
                        if !seenUserIds.contains(userId) {
                            users.append(user)
                            seenUserIds.insert(userId)
                        }
                    }
                }
            }
            
            print("✅ Client-side filter found \(users.count) matching users for messaging")
        }
        
        // Filter out current user
        if let currentUserId = Auth.auth().currentUser?.uid {
            users = users.filter { $0.id != currentUserId }
        }
        
        print("✅ Messaging search results for '\(query)': \(users.count) users found")
        
        return users
    }
    
    // MARK: - Conversation Management
    
    /// Pin a conversation (max 3 pins)
    public func pinConversation(_ conversationId: String) async throws {
        guard isAuthenticated else {
            throw FirebaseMessagingError.notAuthenticated
        }

        // Check current pin count
        let pinnedCount = await MainActor.run {
            conversations.filter { $0.isPinned }.count
        }

        guard pinnedCount < 3 else {
            throw FirebaseMessagingError.customError("You can only pin up to 3 conversations. Unpin one first.")
        }

        let convRef = db.collection("conversations").document(conversationId)

        try await convRef.updateData([
            "pinnedBy": FieldValue.arrayUnion([currentUserId]),
            "pinnedAt.\(currentUserId)": Timestamp(date: Date())
        ])

        // Update local state
        await MainActor.run {
            if let index = conversations.firstIndex(where: { $0.id == conversationId }) {
                var updated = conversations[index]
                updated = ChatConversation(
                    id: updated.id,
                    name: updated.name,
                    lastMessage: updated.lastMessage,
                    timestamp: updated.timestamp,
                    isGroup: updated.isGroup,
                    unreadCount: updated.unreadCount,
                    avatarColor: updated.avatarColor,
                    status: updated.status,
                    profilePhotoURL: updated.profilePhotoURL,
                    isPinned: true,
                    isMuted: updated.isMuted
                )
                conversations[index] = updated
            }
        }

        print("📌 Conversation \(conversationId) pinned")
    }

    /// Unpin a conversation
    public func unpinConversation(_ conversationId: String) async throws {
        guard isAuthenticated else {
            throw FirebaseMessagingError.notAuthenticated
        }

        let convRef = db.collection("conversations").document(conversationId)

        try await convRef.updateData([
            "pinnedBy": FieldValue.arrayRemove([currentUserId]),
            "pinnedAt.\(currentUserId)": FieldValue.delete()
        ])

        // Update local state
        await MainActor.run {
            if let index = conversations.firstIndex(where: { $0.id == conversationId }) {
                var updated = conversations[index]
                updated = ChatConversation(
                    id: updated.id,
                    name: updated.name,
                    lastMessage: updated.lastMessage,
                    timestamp: updated.timestamp,
                    isGroup: updated.isGroup,
                    unreadCount: updated.unreadCount,
                    avatarColor: updated.avatarColor,
                    status: updated.status,
                    profilePhotoURL: updated.profilePhotoURL,
                    isPinned: false,
                    isMuted: updated.isMuted
                )
                conversations[index] = updated
            }
        }

        print("📌 Conversation \(conversationId) unpinned")
    }

    /// Mute a conversation
    public func muteConversation(_ conversationId: String) async throws {
        guard isAuthenticated else {
            throw FirebaseMessagingError.notAuthenticated
        }

        let convRef = db.collection("conversations").document(conversationId)

        try await convRef.updateData([
            "mutedBy": FieldValue.arrayUnion([currentUserId])
        ])

        // Update local state
        await MainActor.run {
            if let index = conversations.firstIndex(where: { $0.id == conversationId }) {
                var updated = conversations[index]
                updated = ChatConversation(
                    id: updated.id,
                    name: updated.name,
                    lastMessage: updated.lastMessage,
                    timestamp: updated.timestamp,
                    isGroup: updated.isGroup,
                    unreadCount: updated.unreadCount,
                    avatarColor: updated.avatarColor,
                    status: updated.status,
                    profilePhotoURL: updated.profilePhotoURL,
                    isPinned: updated.isPinned,
                    isMuted: true
                )
                conversations[index] = updated
            }
        }

        print("🔕 Conversation \(conversationId) muted")
    }

    /// Unmute a conversation
    public func unmuteConversation(_ conversationId: String) async throws {
        guard isAuthenticated else {
            throw FirebaseMessagingError.notAuthenticated
        }

        let convRef = db.collection("conversations").document(conversationId)

        try await convRef.updateData([
            "mutedBy": FieldValue.arrayRemove([currentUserId])
        ])

        // Update local state
        await MainActor.run {
            if let index = conversations.firstIndex(where: { $0.id == conversationId }) {
                var updated = conversations[index]
                updated = ChatConversation(
                    id: updated.id,
                    name: updated.name,
                    lastMessage: updated.lastMessage,
                    timestamp: updated.timestamp,
                    isGroup: updated.isGroup,
                    unreadCount: updated.unreadCount,
                    avatarColor: updated.avatarColor,
                    status: updated.status,
                    profilePhotoURL: updated.profilePhotoURL,
                    isPinned: updated.isPinned,
                    isMuted: false
                )
                conversations[index] = updated
            }
        }

        print("🔕 Conversation \(conversationId) unmuted")
    }

    /// Report a conversation as spam
    public func reportSpam(_ conversationId: String, reason: String) async throws {
        guard isAuthenticated else {
            throw FirebaseMessagingError.notAuthenticated
        }

        // Create spam report document
        let reportData: [String: Any] = [
            "conversationId": conversationId,
            "reportedBy": currentUserId,
            "reason": reason,
            "timestamp": FieldValue.serverTimestamp(),
            "status": "pending"
        ]

        try await db.collection("spamReports").addDocument(data: reportData)

        // Automatically archive the conversation for the reporter
        try await archiveConversation(conversationId: conversationId)

        print("⚠️ Conversation \(conversationId) reported as spam")
    }
    
    /// Delete a conversation for current user (soft delete)
    public func deleteConversation(conversationId: String) async throws {
        guard isAuthenticated else {
            throw FirebaseMessagingError.notAuthenticated
        }
        
        try await db.collection("conversations")
            .document(conversationId)
            .updateData([
                "deletedBy.\(currentUserId)": true,
                "deletedAt.\(currentUserId)": Timestamp(date: Date())
            ])
        
        print("🗑️ Conversation \(conversationId) deleted for user \(currentUserId)")
    }
    
    /// Delete all conversations with a specific user
    public func deleteConversationsWithUser(userId: String) async throws {
        guard isAuthenticated else {
            throw FirebaseMessagingError.notAuthenticated
        }
        
        let snapshot = try await db.collection("conversations")
            .whereField("participantIds", arrayContains: currentUserId)
            .getDocuments()
        
        let batch = db.batch()
        var count = 0
        
        for doc in snapshot.documents {
            if let conversation = try? doc.data(as: FirebaseConversation.self),
               conversation.participantIds.contains(userId) {
                batch.deleteDocument(doc.reference)
                count += 1
            }
        }
        
        try await batch.commit()
        print("🗑️ Deleted \(count) conversations with user \(userId)")
    }
    
    /// Archive a conversation
    public func archiveConversation(conversationId: String) async throws {
        guard isAuthenticated else {
            throw FirebaseMessagingError.notAuthenticated
        }
        
        try await db.collection("conversations")
            .document(conversationId)
            .updateData([
                "archivedBy": FieldValue.arrayUnion([currentUserId]),
                "updatedAt": Timestamp(date: Date())
            ])
        
        await MainActor.run {
            if let index = conversations.firstIndex(where: { $0.id == conversationId }) {
                let conversation = conversations.remove(at: index)
                if !archivedConversations.contains(where: { $0.id == conversationId }) {
                    archivedConversations.insert(conversation, at: 0)
                }
            }
        }
        
        print("📦 Conversation \(conversationId) archived")
    }
    
    /// Unarchive a conversation
    public func unarchiveConversation(conversationId: String) async throws {
        guard isAuthenticated else {
            throw FirebaseMessagingError.notAuthenticated
        }
        
        try await db.collection("conversations")
            .document(conversationId)
            .updateData([
                "archivedBy": FieldValue.arrayRemove([currentUserId]),
                "updatedAt": Timestamp(date: Date())
            ])
        
        await MainActor.run {
            if let index = archivedConversations.firstIndex(where: { $0.id == conversationId }) {
                let conversation = archivedConversations.remove(at: index)
                if !conversations.contains(where: { $0.id == conversationId }) {
                    conversations.insert(conversation, at: 0)
                }
            }
        }
        
        print("📬 Conversation \(conversationId) unarchived")
    }
    
    /// Get archived conversations (internal use)
    internal func getArchivedConversations() async throws -> [ChatConversation] {
        let snapshot = try await db.collection("conversations")
            .whereField("participantIds", arrayContains: currentUserId)
            .order(by: "updatedAt", descending: true)
            .getDocuments()
        
        // Filter archived conversations in memory
        return snapshot.documents.compactMap { doc -> ChatConversation? in
            guard let firebaseConv = try? doc.data(as: FirebaseConversation.self) else {
                return nil
            }
            
            // Check if archived by current user
            guard let archivedBy = firebaseConv.archivedByArray,
                  archivedBy.contains(currentUserId) else {
                return nil
            }
            
            return firebaseConv.toConversation()
        }
        
        // Filter out deleted conversations from archived list
        let conversations = snapshot.documents.compactMap { doc -> ChatConversation? in
            guard let firebaseConv = try? doc.data(as: FirebaseConversation.self) else {
                return nil
            }
            
            // Don't include deleted conversations in archived list
            if let deletedBy = firebaseConv.deletedBy,
               deletedBy[self.currentUserId] == true {
                return nil
            }
            
            return firebaseConv.toConversation()
        }
        
        print("📦 Fetched \(conversations.count) archived conversations")
        return conversations
    }
    
    // MARK: - Message Requests
    // Note: fetchMessageRequests, acceptMessageRequest, declineMessageRequest, and 
    // markMessageRequestAsRead methods are defined in a separate extension file
    
    // MARK: - Instagram-Style Message Limits & Requests
    
    /// Check if user can send a message in this conversation (Instagram/Threads style)
    /// Returns: (canSend: Bool, reason: String?)
    public func canSendMessage(conversationId: String) async throws -> (canSend: Bool, reason: String?) {
        guard isAuthenticated else {
            return (false, "Not authenticated")
        }
        
        // Fetch conversation
        let conversationRef = db.collection("conversations").document(conversationId)
        let doc = try await conversationRef.getDocument()
        
        guard doc.exists,
              let conversation = try? doc.data(as: FirebaseConversation.self) else {
            return (false, "Conversation not found")
        }
        
        let status = conversation.conversationStatus ?? "accepted"
        
        // ✅ If conversation is accepted, can always send
        if status == "accepted" {
            return (true, nil)
        }
        
        // ✅ If conversation is declined or blocked, cannot send
        if status == "declined" || status == "blocked" {
            return (false, "This conversation is not available")
        }
        
        // ✅ If conversation is pending
        if status == "pending" {
            let messageCount = conversation.messageCount?[currentUserId] ?? 0
            
            // Check if sender is the requester
            let isRequester = conversation.requesterId == currentUserId
            
            if isRequester {
                // Requester can only send 1 message until accepted
                if messageCount >= 1 {
                    return (false, "Please wait for \(conversation.participantNames.values.first(where: { _ in true }) ?? "them") to accept your message request")
                } else {
                    return (true, nil)
                }
            } else {
                // Recipient can send unlimited messages (accepting by sending a message)
                return (true, nil)
            }
        }
        
        return (true, nil)
    }
    
    /// Get message count for current user in conversation
    public func getMessageCount(conversationId: String) async throws -> Int {
        let conversationRef = db.collection("conversations").document(conversationId)
        let doc = try await conversationRef.getDocument()
        
        guard let conversation = try? doc.data(as: FirebaseConversation.self) else {
            return 0
        }
        
        return conversation.messageCount?[currentUserId] ?? 0
    }
    
    /// Accept a message request (Instagram/Threads style)
    public func acceptMessageRequest(conversationId: String) async throws {
        guard isAuthenticated else {
            throw FirebaseMessagingError.notAuthenticated
        }
        
        let conversationRef = db.collection("conversations").document(conversationId)
        
        try await conversationRef.updateData([
            "conversationStatus": "accepted",
            "updatedAt": Timestamp(date: Date())
        ])
        
        print("✅ Message request accepted for conversation: \(conversationId)")
    }
    
    /// Decline a message request (Instagram/Threads style)
    public func declineMessageRequest(conversationId: String) async throws {
        guard isAuthenticated else {
            throw FirebaseMessagingError.notAuthenticated
        }
        
        let conversationRef = db.collection("conversations").document(conversationId)
        
        try await conversationRef.updateData([
            "conversationStatus": "declined",
            "updatedAt": Timestamp(date: Date())
        ])
        
        print("✅ Message request declined for conversation: \(conversationId)")
    }
    
    /// Delete a message request
    public func deleteMessageRequest(conversationId: String) async throws {
        guard isAuthenticated else {
            throw FirebaseMessagingError.notAuthenticated
        }
        
        // Just decline it (don't actually delete to preserve data)
        try await declineMessageRequest(conversationId: conversationId)
    }
    
    /// Get pending message requests (for current user as recipient)
    public func fetchPendingRequests() async throws -> [ChatConversation] {
        guard isAuthenticated else {
            throw FirebaseMessagingError.notAuthenticated
        }
        
        let snapshot = try await db.collection("conversations")
            .whereField("participantIds", arrayContains: currentUserId)
            .whereField("conversationStatus", isEqualTo: "pending")
            .order(by: "updatedAt", descending: true)
            .getDocuments()
        
        // Filter to only show requests where current user is NOT the requester
        let requests = snapshot.documents.compactMap { doc -> ChatConversation? in
            guard let firebaseConv = try? doc.data(as: FirebaseConversation.self) else {
                return nil
            }
            
            // Only show if current user is the recipient (not the requester)
            guard firebaseConv.requesterId != currentUserId else {
                return nil
            }
            
            return firebaseConv.toConversation()
        }
        
        print("📬 Fetched \(requests.count) pending message requests")
        return requests
    }
    
    // MARK: - Message Requests
    
    /// Update message delivery status
    func updateMessageDeliveryStatus(
        conversationId: String,
        messageId: String,
        isSent: Bool? = nil,
        isDelivered: Bool? = nil,
        isFailed: Bool? = nil
    ) async throws {
        let messageRef = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
        
        var updates: [String: Any] = [:]
        
        if let isSent = isSent {
            updates["isSent"] = isSent
        }
        if let isDelivered = isDelivered {
            updates["isDelivered"] = isDelivered
        }
        if let isFailed = isFailed {
            updates["isSendFailed"] = isFailed
        }
        
        if !updates.isEmpty {
            try await messageRef.updateData(updates)
            print("📊 Updated delivery status for message: \(messageId)")
        }
    }
    
    /// Set disappearing message timer for a conversation
    func setDisappearingMessageDuration(
        conversationId: String,
        duration: TimeInterval?
    ) async throws {
        let conversationRef = db.collection("conversations").document(conversationId)
        
        if let duration = duration, duration > 0 {
            try await conversationRef.updateData([
                "disappearingMessageDuration": duration,
                "updatedAt": Timestamp(date: Date())
            ])
            print("⏰ Set disappearing messages to \(duration) seconds")
        } else {
            try await conversationRef.updateData([
                "disappearingMessageDuration": FieldValue.delete(),
                "updatedAt": Timestamp(date: Date())
            ])
            print("⏰ Disabled disappearing messages")
        }
    }
    
    /// Schedule message to disappear
    func scheduleMessageDisappear(
        conversationId: String,
        messageId: String,
        after duration: TimeInterval
    ) async throws {
        let messageRef = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
        
        let disappearAt = Date().addingTimeInterval(duration)
        
        try await messageRef.updateData([
            "disappearAfter": duration,
            "disappearAt": Timestamp(date: disappearAt)
        ])
        
        print("⏰ Message scheduled to disappear at: \(disappearAt)")
    }
    
    /// Delete disappeared messages (call from background task)
    func deleteDisappearedMessages() async throws {
        let now = Timestamp(date: Date())
        
        // Query all conversations for messages that should disappear
        let conversationsSnapshot = try await db.collection("conversations")
            .whereField("participantIds", arrayContains: currentUserId)
            .getDocuments()
        
        for conversationDoc in conversationsSnapshot.documents {
            let conversationId = conversationDoc.documentID
            
            // Find messages that should have disappeared
            let messagesSnapshot = try await db.collection("conversations")
                .document(conversationId)
                .collection("messages")
                .whereField("disappearAt", isLessThanOrEqualTo: now)
                .getDocuments()
            
            // Delete expired messages
            let batch = db.batch()
            for messageDoc in messagesSnapshot.documents {
                batch.deleteDocument(messageDoc.reference)
            }
            
            if !messagesSnapshot.documents.isEmpty {
                try await batch.commit()
                print("🗑️ Deleted \(messagesSnapshot.documents.count) disappeared messages in conversation \(conversationId)")
            }
        }
    }
    
    /// Save link preview URLs to message
    func saveLinkPreviewURLs(
        conversationId: String,
        messageId: String,
        urls: [String]
    ) async throws {
        let messageRef = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
        
        try await messageRef.updateData([
            "linkPreviewURLs": urls
        ])
        
        print("🔗 Saved \(urls.count) link preview URLs")
    }
    
    /// Save mentioned user IDs to message
    func saveMentionedUsers(
        conversationId: String,
        messageId: String,
        userIds: [String]
    ) async throws {
        let messageRef = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
        
        try await messageRef.updateData([
            "mentionedUserIds": userIds
        ])
        
        print("@️ Saved \(userIds.count) mentions")
    }
    
    /// Send notification to mentioned users
    func notifyMentionedUsers(
        conversationId: String,
        messageId: String,
        mentionedUserIds: [String],
        messageText: String
    ) async throws {
        let senderName = Auth.auth().currentUser?.displayName ?? UserDefaults.standard.string(forKey: "currentUserDisplayName") ?? "User"
        
        // Get conversation details
        let conversationDoc = try await db.collection("conversations")
            .document(conversationId)
            .getDocument()
        
        guard let conversationData = conversationDoc.data() else {
            return
        }
        
        let conversationName = (conversationData["groupName"] as? String) ?? "Chat"
        
        // TODO: Send push notifications to mentioned users
        // This would typically use Firebase Cloud Messaging
        // For now, we'll just log it
        for userId in mentionedUserIds {
            print("📢 Would notify user \(userId): @\(senderName) mentioned you in \(conversationName)")
        }
    }
    
    /// Listen to message requests in real-time
    func listenToMessageRequests(
        userId: String,
        completion: @escaping ([MessagingRequest]) -> Void
    ) -> (() -> Void) {
        let listener = db.collection("conversations")
            .whereField("participantIds", arrayContains: userId)
            .whereField("conversationStatus", isEqualTo: "pending")
            .whereField("requesterId", isNotEqualTo: userId)
            .order(by: "requesterId")
            .order(by: "updatedAt", descending: true)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("❌ Error listening to message requests: \(error)")
                    completion([])
                    return
                }
                
                guard let snapshot = snapshot else {
                    completion([])
                    return
                }
                
                var requests: [MessagingRequest] = []
                
                for doc in snapshot.documents {
                    guard let conversation = try? doc.data(as: FirebaseConversation.self),
                          let conversationId = conversation.id,
                          let requesterId = conversation.requesterId else {
                        continue
                    }
                    
                    // Get requester's name from participant names
                    let requesterName = conversation.participantNames[requesterId] ?? "Unknown"
                    
                    // Check if request has been read
                    let requestReadBy = conversation.requestReadBy ?? []
                    let isRead = requestReadBy.contains(userId)
                    
                    let request = MessagingRequest(
                        id: conversationId,
                        conversationId: conversationId,
                        fromUserId: requesterId,
                        fromUserName: requesterName,
                        fromUserUsername: nil,
                        fromUserAvatarUrl: nil,
                        lastMessage: conversation.lastMessageText,
                        timestamp: conversation.updatedAt?.dateValue() ?? Date(),
                        isRead: isRead
                    )
                    
                    requests.append(request)
                }
                
                print("📬 Updated message requests: \(requests.count) pending")
                completion(requests)
            }
        
        // Return cleanup function
        return {
            listener.remove()
        }
    }
}

// MARK: - Firebase Models

struct FirebaseConversation: Codable {
    @DocumentID var id: String?
    let participantIds: [String]
    let participantNames: [String: String] // userId: userName
    let participantPhotoURLs: [String: String]? // userId: profilePhotoURL
    let isGroup: Bool
    let groupName: String?
    let groupAvatarUrl: String?
    let lastMessage: String?
    let lastMessageText: String
    let lastMessageTimestamp: Timestamp?
    let unreadCounts: [String: Int] // userId: count
    let conversationStatus: String? // "pending", "accepted", "declined"
    let requesterId: String? // User who initiated the conversation request
    let requestReadBy: [String]? // Users who have seen the request
    let messageCount: [String: Int]? // userId: message count (for Instagram/Threads style limits)
    let createdAt: Timestamp?
    let updatedAt: Timestamp?
    let archivedBy: [String: Bool]? // OLD: userId: archived status (deprecated)
    let archivedByArray: [String]? // NEW: array of user IDs who archived
    let archivedAt: Timestamp? // Shared archived timestamp
    let deletedBy: [String: Bool]? // userId: deleted status
    let pinnedBy: [String]? // Array of user IDs who pinned this conversation
    let pinnedAt: [String: Timestamp]? // userId: when they pinned it
    let mutedBy: [String]? // Array of user IDs who muted this conversation
    
    enum CodingKeys: String, CodingKey {
        case id
        case participantIds
        case participantNames
        case participantPhotoURLs
        case isGroup
        case groupName
        case groupAvatarUrl
        case lastMessage
        case lastMessageText
        case lastMessageTimestamp
        case unreadCounts
        case conversationStatus
        case requesterId
        case requestReadBy
        case messageCount
        case createdAt
        case updatedAt
        case archivedBy
        case archivedAt
        case deletedBy
        case pinnedBy
        case pinnedAt
        case mutedBy
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // @DocumentID needs special handling - decode without the wrapper
        _id = DocumentID(wrappedValue: try container.decodeIfPresent(String.self, forKey: .id))
        
        participantIds = try container.decode([String].self, forKey: .participantIds)
        participantNames = try container.decode([String: String].self, forKey: .participantNames)
        participantPhotoURLs = try container.decodeIfPresent([String: String].self, forKey: .participantPhotoURLs)
        isGroup = try container.decode(Bool.self, forKey: .isGroup)
        groupName = try container.decodeIfPresent(String.self, forKey: .groupName)
        groupAvatarUrl = try container.decodeIfPresent(String.self, forKey: .groupAvatarUrl)
        lastMessage = try container.decodeIfPresent(String.self, forKey: .lastMessage)
        lastMessageText = try container.decode(String.self, forKey: .lastMessageText)
        lastMessageTimestamp = try container.decodeIfPresent(Timestamp.self, forKey: .lastMessageTimestamp)
        unreadCounts = try container.decode([String: Int].self, forKey: .unreadCounts)
        conversationStatus = try container.decodeIfPresent(String.self, forKey: .conversationStatus)
        requesterId = try container.decodeIfPresent(String.self, forKey: .requesterId)
        requestReadBy = try container.decodeIfPresent([String].self, forKey: .requestReadBy)
        messageCount = try container.decodeIfPresent([String: Int].self, forKey: .messageCount)
        createdAt = try container.decodeIfPresent(Timestamp.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Timestamp.self, forKey: .updatedAt)
        
        // Handle archivedBy - try to decode as array first (new format), then as dictionary (old format)
        if let archivedByArrayValue = try? container.decode([String].self, forKey: .archivedBy) {
            // New format: array of user IDs
            archivedByArray = archivedByArrayValue
            archivedBy = nil
        } else if let archivedByDictValue = try? container.decode([String: Bool].self, forKey: .archivedBy) {
            // Old format: dictionary of userId: Bool
            archivedBy = archivedByDictValue
            // Convert to array for convenience
            archivedByArray = archivedByDictValue.filter { $0.value }.map { $0.key }
        } else {
            archivedBy = nil
            archivedByArray = nil
        }
        
        archivedAt = try container.decodeIfPresent(Timestamp.self, forKey: .archivedAt)
        deletedBy = try container.decodeIfPresent([String: Bool].self, forKey: .deletedBy)

        // Decode new pin/mute fields
        pinnedBy = try container.decodeIfPresent([String].self, forKey: .pinnedBy)
        pinnedAt = try container.decodeIfPresent([String: Timestamp].self, forKey: .pinnedAt)
        mutedBy = try container.decodeIfPresent([String].self, forKey: .mutedBy)
    }
    
    init(
        id: String? = nil,
        participantIds: [String],
        participantNames: [String: String],
        isGroup: Bool,
        groupName: String? = nil,
        groupAvatarUrl: String? = nil,
        lastMessage: String? = nil,
        lastMessageText: String,
        lastMessageTimestamp: Date,
        unreadCounts: [String: Int],
        createdAt: Date,
        updatedAt: Date,
        conversationStatus: String? = "accepted",
        requesterId: String? = nil,
        requestReadBy: [String]? = nil
    ) {
        self.id = id
        self.participantIds = participantIds
        self.participantNames = participantNames
        self.isGroup = isGroup
        self.groupName = groupName
        self.groupAvatarUrl = groupAvatarUrl
        self.lastMessage = lastMessage
        self.lastMessageText = lastMessageText
        self.lastMessageTimestamp = Timestamp(date: lastMessageTimestamp)
        self.unreadCounts = unreadCounts
        self.conversationStatus = conversationStatus
        self.requesterId = requesterId
        self.requestReadBy = requestReadBy
        self.messageCount = [:] // Initialize as empty
        self.createdAt = Timestamp(date: createdAt)
        self.updatedAt = Timestamp(date: updatedAt)
        self.archivedBy = nil
        self.archivedByArray = nil
        self.archivedAt = nil
        self.deletedBy = nil
        self.participantPhotoURLs = nil
        self.pinnedBy = nil
        self.pinnedAt = nil
        self.mutedBy = nil
    }
    
    func toConversation() -> ChatConversation {
        let currentUserId = Auth.auth().currentUser?.uid ?? ""
        let otherParticipants = participantIds.filter { $0 != currentUserId }

        let name: String
        if isGroup {
            name = groupName ?? "Group Chat"
        } else {
            name = otherParticipants.compactMap { participantNames[$0] }.first ?? "Unknown"
        }

        let unreadCount = unreadCounts[currentUserId] ?? 0

        let timestamp = lastMessageTimestamp?.dateValue() ?? Date()

        // Get profile photo URL for the other participant (for 1-on-1 chats)
        let profilePhotoURL: String?
        if !isGroup, let otherUserId = otherParticipants.first {
            profilePhotoURL = participantPhotoURLs?[otherUserId]
        } else {
            profilePhotoURL = groupAvatarUrl // For groups, use group avatar
        }

        // Check if current user pinned this conversation
        let isPinned = pinnedBy?.contains(currentUserId) ?? false

        // Check if current user muted this conversation
        let isMuted = mutedBy?.contains(currentUserId) ?? false

        let conversation = ChatConversation(
            id: id ?? UUID().uuidString,
            name: name,
            lastMessage: lastMessageText,
            timestamp: formatTimestamp(timestamp),
            isGroup: isGroup,
            unreadCount: unreadCount,
            avatarColor: colorForString(name),
            status: conversationStatus ?? "accepted",
            profilePhotoURL: profilePhotoURL,
            isPinned: isPinned,
            isMuted: isMuted,
            requesterId: requesterId
        )
        return conversation
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            let minutes = Int(now.timeIntervalSince(date) / 60)
            if minutes < 1 {
                return "Just now"
            } else if minutes < 60 {
                return "\(minutes)m ago"
            } else {
                let hours = minutes / 60
                return "\(hours)h ago"
            }
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            return formatter.string(from: date)
        }
    }
    
    private func colorForString(_ string: String) -> Color {
        let colors: [Color] = [.blue, .purple, .green, .orange, .pink, .cyan, .red, .indigo]
        let hash = abs(string.hashValue)
        return colors[hash % colors.count]
    }
}

struct FirebaseMessage: Codable {
    @DocumentID var id: String?
    let conversationId: String
    let senderId: String
    let senderName: String
    let senderProfileImageURL: String? // ✅ Sender's profile image URL
    let text: String
    let attachments: [Attachment]
    var reactions: [Reaction]
    let replyTo: ReplyInfo?
    let timestamp: Timestamp?
    let readBy: [String]
    var isPinned: Bool?
    var pinnedBy: String?
    var pinnedAt: Timestamp?
    var isStarred: [String]? // Array of user IDs who starred this message
    var isDeleted: Bool?
    var deletedBy: String?
    var editedAt: Timestamp?
    
    // New fields for enhanced features
    var isSent: Bool?
    var isDelivered: Bool?
    var isSendFailed: Bool?
    var disappearAfter: TimeInterval? // Disappearing message duration in seconds
    var disappearAt: Timestamp? // When the message should disappear
    var linkPreviewURLs: [String]? // URLs for link previews
    var mentionedUserIds: [String]? // User IDs mentioned with @
    
    init(
        id: String? = nil,
        conversationId: String,
        senderId: String,
        senderName: String,
        senderProfileImageURL: String? = nil,
        text: String,
        attachments: [Attachment],
        reactions: [Reaction],
        replyTo: ReplyInfo?,
        timestamp: Timestamp?,
        readBy: [String],
        isPinned: Bool? = false,
        pinnedBy: String? = nil,
        pinnedAt: Timestamp? = nil,
        isStarred: [String]? = [],
        isDeleted: Bool? = false,
        deletedBy: String? = nil,
        editedAt: Timestamp? = nil,
        isSent: Bool? = false,
        isDelivered: Bool? = false,
        isSendFailed: Bool? = false,
        disappearAfter: TimeInterval? = nil,
        disappearAt: Timestamp? = nil,
        linkPreviewURLs: [String]? = nil,
        mentionedUserIds: [String]? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.senderId = senderId
        self.senderName = senderName
        self.senderProfileImageURL = senderProfileImageURL
        self.text = text
        self.attachments = attachments
        self.reactions = reactions
        self.replyTo = replyTo
        self.timestamp = timestamp
        self.readBy = readBy
        self.isPinned = isPinned
        self.pinnedBy = pinnedBy
        self.pinnedAt = pinnedAt
        self.isStarred = isStarred
        self.isDeleted = isDeleted
        self.deletedBy = deletedBy
        self.editedAt = editedAt
        self.isSent = isSent
        self.isDelivered = isDelivered
        self.isSendFailed = isSendFailed
        self.disappearAfter = disappearAfter
        self.disappearAt = disappearAt
        self.linkPreviewURLs = linkPreviewURLs
        self.mentionedUserIds = mentionedUserIds
    }
    
    struct Attachment: Codable {
        let id: String
        let type: String // photo, video, audio, document
        let url: String
        let thumbnailUrl: String?
        let metadata: [String: Double]?
        
        enum CodingKeys: String, CodingKey {
            case id, type, url, thumbnailUrl, metadata
        }
        
        init(id: String, type: String, url: String, thumbnailUrl: String?, metadata: [String: Double]?) {
            self.id = id
            self.type = type
            self.url = url
            self.thumbnailUrl = thumbnailUrl
            self.metadata = metadata
        }
    }
    
    struct Reaction: Codable {
        let id: String
        let emoji: String
        let userId: String
        let userName: String
        let timestamp: Timestamp?
        
        init(id: String, emoji: String, userId: String, userName: String, timestamp: Date) {
            self.id = id
            self.emoji = emoji
            self.userId = userId
            self.userName = userName
            self.timestamp = Timestamp(date: timestamp)
        }
    }
    
    struct ReplyInfo: Codable {
        let messageId: String
        let text: String
        let senderId: String
        let senderName: String
    }
    
    func toMessage(currentUserId: String) -> AppMessage {
        // Convert Firebase attachments to MessageAttachment
        let messageAttachments = attachments.compactMap { attachment -> MessageAttachment? in
            guard let url = URL(string: attachment.url) else { return nil }
            
            let type: MessageAttachment.AttachmentType
            switch attachment.type {
            case "photo": type = .photo
            case "video": type = .video
            case "audio": type = .audio
            case "document": type = .document
            default: type = .document
            }
            
            return MessageAttachment(
                type: type,
                data: nil, // Will be loaded from URL
                thumbnail: nil,
                url: url
            )
        }
        
        // Convert reply-to message if present
        var replyToMessage: AppMessage? = nil
        if let reply = replyTo {
            replyToMessage = AppMessage(
                id: reply.messageId,
                text: reply.text,
                isFromCurrentUser: reply.senderId == currentUserId,
                timestamp: Date(), // Original timestamp not stored in ReplyInfo
                senderId: reply.senderId,
                senderName: reply.senderName,
                attachments: [],
                replyTo: nil,
                reactions: []
            )
        }
        
        return AppMessage(
            id: id ?? UUID().uuidString,
            text: text,
            isFromCurrentUser: senderId == currentUserId,
            timestamp: timestamp?.dateValue() ?? Date(),
            senderId: senderId,
            senderName: senderName,
            senderProfileImageURL: senderProfileImageURL, // ✅ Pass profile image URL
            attachments: messageAttachments,
            replyTo: replyToMessage,
            reactions: reactions.map { reaction in
                MessageReaction(
                    emoji: reaction.emoji,
                    userId: reaction.userId,
                    username: reaction.userName
                )
            },
            isRead: readBy.contains(currentUserId),
            isPinned: isPinned ?? false,
            pinnedBy: pinnedBy,
            pinnedAt: pinnedAt?.dateValue(),
            isStarred: isStarred?.contains(currentUserId) ?? false,
            isDeleted: isDeleted ?? false,
            deletedBy: deletedBy,
            editedAt: editedAt?.dateValue(),
            isSent: isSent ?? true,
            isDelivered: isDelivered ?? true,
            isSendFailed: isSendFailed ?? false,
            disappearAfter: disappearAfter,
            linkPreviews: [], // Will be loaded separately from URLs
            mentionedUserIds: mentionedUserIds ?? []
        )
    }
}

public struct ContactUser: Codable, Identifiable {
    @DocumentID public var id: String?
    public let displayName: String
    public let username: String
    public let email: String
    public let profileImageURL: String?
    public let showActivityStatus: Bool
    
    public var name: String { displayName }
    public var avatarUrl: String? { profileImageURL }
    // Note: isOnline property removed - we don't show activity status in UI
    
    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case username
        case email
        case profileImageURL
        case showActivityStatus
    }
}

// MARK: - Message Request Models

public struct MessagingRequest: Identifiable, Codable {
    public let id: String
    public let conversationId: String
    public let fromUserId: String
    public let fromUserName: String
    public let fromUserUsername: String?
    public let fromUserAvatarUrl: String?
    public let lastMessage: String
    public let timestamp: Date
    public let isRead: Bool
    
    public init(id: String, conversationId: String, fromUserId: String, fromUserName: String, fromUserUsername: String?, fromUserAvatarUrl: String?, lastMessage: String, timestamp: Date, isRead: Bool) {
        self.id = id
        self.conversationId = conversationId
        self.fromUserId = fromUserId
        self.fromUserName = fromUserName
        self.fromUserUsername = fromUserUsername
        self.fromUserAvatarUrl = fromUserAvatarUrl
        self.lastMessage = lastMessage
        self.timestamp = timestamp
        self.isRead = isRead
    }
}

public struct UserPrivacySettings: Codable {
    public let allowMessagesFromEveryone: Bool
    public let requireFollowToMessage: Bool
    public let autoDeclineSpam: Bool
    
    public init(allowMessagesFromEveryone: Bool, requireFollowToMessage: Bool, autoDeclineSpam: Bool) {
        self.allowMessagesFromEveryone = allowMessagesFromEveryone
        self.requireFollowToMessage = requireFollowToMessage
        self.autoDeclineSpam = autoDeclineSpam
    }
}

// MARK: - Helper Extensions

extension UIImage {
    func resized(to size: CGSize) -> UIImage? {
        // Use modern UIGraphicsImageRenderer (iOS 10+)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            self.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - Note: Additional extensions are in FirebaseMessagingService+RequestsAndBlocking.swift
// MARK: - Note: BlockService is defined in BlockService.swift (separate file)




