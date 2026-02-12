//
//  RealtimeDatabaseService.swift
//  AMENAPP
//
//  Firebase Realtime Database implementation for real-time messaging and posts
//

import Foundation
import FirebaseDatabase
import FirebaseAuth
import Combine
import SwiftUI

// MARK: - Realtime Database Service

@MainActor
class RealtimeDatabaseService: ObservableObject {
    static let shared = RealtimeDatabaseService()
    
    private static var _configuredDatabase: Database?
    private static let databaseURL = "https://amen-5e359-default-rtdb.firebaseio.com"
    
    // Get or create the database instance with persistence enabled
    private var database: Database {
        if let db = Self._configuredDatabase {
            return db
        }
        
        // First access - configure persistence BEFORE getting the database
        print("🔥 Configuring Realtime Database persistence...")
        
        // Get the database instance
        let db = Database.database(url: Self.databaseURL)
        
        // Enable persistence on FIRST access only
        db.isPersistenceEnabled = true
        
        // Cache it so we don't try to set persistence again
        Self._configuredDatabase = db
        
        print("✅ Realtime Database configured with persistence enabled")
        return db
    }
    
    private var ref: DatabaseReference {
        database.reference()
    }
    
    private init() {
        // Database is configured lazily on first access to ensure
        // persistence is enabled before any database operations
    }
    
    private func ensureDatabaseInitialized() {
        _ = database // Force lazy initialization
        if !hasSetupPresence {
            setupPresenceMonitoring()
            hasSetupPresence = true
        }
    }
    
    private var hasSetupPresence = false
    
    // Published properties for real-time updates
    @Published var realtimeMessages: [String: [RealtimeMessage]] = [:] // conversationId: [messages]
    @Published var realtimeConversations: [RealtimeConversation] = []
    @Published var typingUsers: [String: Set<String>] = [:] // conversationId: Set of user IDs typing
    @Published var onlineUsers: Set<String> = []
    
    private var messageObservers: [String: DatabaseHandle] = [:]
    private var conversationObservers: [DatabaseHandle] = []
    private var typingObservers: [String: DatabaseHandle] = [:]
    private var onlineStatusHandle: DatabaseHandle?
    
    var currentUserId: String {
        Auth.auth().currentUser?.uid ?? "anonymous"
    }
    
    var currentUserName: String {
        // Try Firebase Auth displayName
        if let displayName = Auth.auth().currentUser?.displayName, !displayName.isEmpty {
            return displayName
        }
        
        // Fallback to email username if displayName not set
        if let email = Auth.auth().currentUser?.email {
            let emailUsername = email.components(separatedBy: "@").first ?? "User"
            return emailUsername.capitalized
        }
        
        return "Anonymous"
    }
    
    // MARK: - Presence & Online Status
    
    private func setupPresenceMonitoring() {
        guard !currentUserId.isEmpty, currentUserId != "anonymous" else { return }
        
        let presenceRef = ref.child("presence").child(currentUserId)
        let connectedRef = database.reference(withPath: ".info/connected")
        
        connectedRef.observe(.value) { [weak self] snapshot in
            guard let self = self,
                  let connected = snapshot.value as? Bool,
                  connected else { return }
            
            // When connected, set online status
            presenceRef.setValue([
                "online": true,
                "lastSeen": ServerValue.timestamp()
            ])
            
            // When disconnected, update to offline
            presenceRef.onDisconnectUpdateChildValues([
                "online": false,
                "lastSeen": ServerValue.timestamp()
            ])
        }
        
        // Listen to all online users
        ref.child("presence").observe(.value) { [weak self] snapshot in
            guard let self = self,
                  let presenceData = snapshot.value as? [String: [String: Any]] else { return }
            
            let onlineUserIds = presenceData.compactMap { (userId, data) -> String? in
                guard let isOnline = data["online"] as? Bool, isOnline else { return nil }
                return userId
            }
            
            self.onlineUsers = Set(onlineUserIds)
        }
    }
    
    // MARK: - Messages
    
    /// Send a message using Realtime Database for instant delivery
    func sendRealtimeMessage(
        conversationId: String,
        text: String,
        replyToMessageId: String? = nil
    ) async throws {
        ensureDatabaseInitialized()
        let messageRef = ref.child("conversations").child(conversationId).child("messages").childByAutoId()
        
        guard let messageId = messageRef.key else {
            throw NSError(domain: "RealtimeDB", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to generate message ID"])
        }
        
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000) // milliseconds
        
        let messageData: [String: Any] = [
            "id": messageId,
            "conversationId": conversationId,
            "senderId": currentUserId,
            "senderName": currentUserName,
            "text": text,
            "timestamp": timestamp,
            "readBy": [currentUserId: true],
            "replyToMessageId": replyToMessageId as Any
        ]
        
        try await messageRef.setValue(messageData)
        
        // Update conversation last message
        let conversationRef = ref.child("conversations").child(conversationId).child("metadata")
        try await conversationRef.updateChildValues([
            "lastMessageText": text,
            "lastMessageTimestamp": timestamp,
            "lastMessageSenderId": currentUserId,
            "updatedAt": timestamp
        ])
        
        // Clear typing indicator
        try await clearTypingIndicator(conversationId: conversationId)
        
        print("✅ Realtime message sent: \(messageId)")
    }
    
    /// Observe messages in a conversation in real-time
    func observeMessages(conversationId: String) {
        ensureDatabaseInitialized()
        // Remove existing observer if any
        if let existingHandle = messageObservers[conversationId] {
            ref.child("conversations").child(conversationId).child("messages").removeObserver(withHandle: existingHandle)
        }
        
        let messagesRef = ref.child("conversations").child(conversationId).child("messages")
        
        let handle = messagesRef.observe(.value) { [weak self] snapshot in
            guard let self = self else { return }
            
            var messages: [RealtimeMessage] = []
            
            for child in snapshot.children {
                guard let childSnapshot = child as? DataSnapshot,
                      let messageData = childSnapshot.value as? [String: Any],
                      let id = messageData["id"] as? String,
                      let senderId = messageData["senderId"] as? String,
                      let senderName = messageData["senderName"] as? String,
                      let text = messageData["text"] as? String,
                      let timestamp = messageData["timestamp"] as? Int64 else {
                    continue
                }
                
                let readBy = messageData["readBy"] as? [String: Bool] ?? [:]
                let replyToMessageId = messageData["replyToMessageId"] as? String
                
                let message = RealtimeMessage(
                    id: id,
                    conversationId: conversationId,
                    senderId: senderId,
                    senderName: senderName,
                    text: text,
                    timestamp: Date(timeIntervalSince1970: Double(timestamp) / 1000.0),
                    readBy: Set(readBy.keys),
                    replyToMessageId: replyToMessageId
                )
                
                messages.append(message)
            }
            
            // Sort by timestamp
            messages.sort { $0.timestamp < $1.timestamp }
            
            self.realtimeMessages[conversationId] = messages
        }
        
        messageObservers[conversationId] = handle
    }
    
    /// Stop observing messages
    func stopObservingMessages(conversationId: String) {
        if let handle = messageObservers[conversationId] {
            ref.child("conversations").child(conversationId).child("messages").removeObserver(withHandle: handle)
            messageObservers.removeValue(forKey: conversationId)
        }
    }
    
    /// Mark messages as read
    func markMessagesAsRead(conversationId: String, messageIds: [String]) async throws {
        let messagesRef = ref.child("conversations").child(conversationId).child("messages")
        
        for messageId in messageIds {
            try await messagesRef.child(messageId).child("readBy").updateChildValues([
                currentUserId: true
            ])
        }
    }
    
    // MARK: - Typing Indicators
    
    /// Set typing indicator
    func setTypingIndicator(conversationId: String, isTyping: Bool) async throws {
        let typingRef = ref.child("conversations").child(conversationId).child("typing").child(currentUserId)
        
        if isTyping {
            try await typingRef.setValue([
                "userId": currentUserId,
                "userName": currentUserName,
                "timestamp": ServerValue.timestamp()
            ])
            
            // Auto-remove after 5 seconds
            try await typingRef.onDisconnectRemoveValue()
        } else {
            try await typingRef.removeValue()
        }
    }
    
    /// Clear typing indicator
    func clearTypingIndicator(conversationId: String) async throws {
        let typingRef = ref.child("conversations").child(conversationId).child("typing").child(currentUserId)
        try await typingRef.removeValue()
    }
    
    /// Observe typing indicators
    func observeTypingIndicators(conversationId: String) {
        // Remove existing observer
        if let existingHandle = typingObservers[conversationId] {
            ref.child("conversations").child(conversationId).child("typing").removeObserver(withHandle: existingHandle)
        }
        
        let typingRef = ref.child("conversations").child(conversationId).child("typing")
        
        let handle = typingRef.observe(.value) { [weak self] snapshot in
            guard let self = self else { return }
            
            var typingUserIds = Set<String>()
            
            for child in snapshot.children {
                guard let childSnapshot = child as? DataSnapshot,
                      let typingData = childSnapshot.value as? [String: Any],
                      let userId = typingData["userId"] as? String,
                      userId != self.currentUserId,
                      let timestamp = typingData["timestamp"] as? Double else {
                    continue
                }
                
                // Only count as typing if within last 5 seconds
                let typingTime = Date(timeIntervalSince1970: timestamp / 1000.0)
                if Date().timeIntervalSince(typingTime) < 5 {
                    typingUserIds.insert(userId)
                }
            }
            
            self.typingUsers[conversationId] = typingUserIds
        }
        
        typingObservers[conversationId] = handle
    }
    
    /// Stop observing typing indicators
    func stopObservingTypingIndicators(conversationId: String) {
        if let handle = typingObservers[conversationId] {
            ref.child("conversations").child(conversationId).child("typing").removeObserver(withHandle: handle)
            typingObservers.removeValue(forKey: conversationId)
        }
    }
    
    // MARK: - Conversations
    
    /// Observe all conversations for current user
    func observeConversations() {
        let conversationsRef = ref.child("userConversations").child(currentUserId)
        
        let handle = conversationsRef.observe(.value) { [weak self] snapshot in
            guard let self = self else { return }
            
            var conversations: [RealtimeConversation] = []
            
            for child in snapshot.children {
                guard let childSnapshot = child as? DataSnapshot,
                      let conversationId = childSnapshot.key as? String else {
                    continue
                }
                
                // Fetch conversation metadata
                self.ref.child("conversations").child(conversationId).child("metadata").getData { error, dataSnapshot in
                    guard error == nil,
                          let metadataData = dataSnapshot?.value as? [String: Any],
                          let participantIds = metadataData["participantIds"] as? [String],
                          let participantNames = metadataData["participantNames"] as? [String: String] else {
                        return
                    }
                    
                    let isGroup = metadataData["isGroup"] as? Bool ?? false
                    let groupName = metadataData["groupName"] as? String
                    let lastMessageText = metadataData["lastMessageText"] as? String ?? ""
                    let lastMessageTimestamp = metadataData["lastMessageTimestamp"] as? Int64 ?? 0
                    let unreadCount = metadataData["unreadCount_\(self.currentUserId)"] as? Int ?? 0
                    
                    let conversation = RealtimeConversation(
                        id: conversationId,
                        participantIds: participantIds,
                        participantNames: participantNames,
                        isGroup: isGroup,
                        groupName: groupName,
                        lastMessageText: lastMessageText,
                        lastMessageTimestamp: Date(timeIntervalSince1970: Double(lastMessageTimestamp) / 1000.0),
                        unreadCount: unreadCount
                    )
                    
                    conversations.append(conversation)
                    self.realtimeConversations = conversations.sorted { $0.lastMessageTimestamp > $1.lastMessageTimestamp }
                }
            }
        }
        
        conversationObservers.append(handle)
    }
    
    /// Create or get a conversation
    func createOrGetConversation(
        participantIds: [String],
        participantNames: [String: String],
        isGroup: Bool = false,
        groupName: String? = nil
    ) async throws -> String {
        // For direct messages, check if conversation already exists
        if !isGroup, participantIds.count == 1 {
            // Check if direct conversation exists
            let snapshot = try await ref.child("userConversations").child(currentUserId).getData()
            
            if let conversationIds = snapshot.value as? [String: Any] {
                for (conversationId, _) in conversationIds {
                    let metadataSnapshot = try await ref.child("conversations").child(conversationId).child("metadata").getData()
                    
                    if let metadata = metadataSnapshot.value as? [String: Any],
                       let existingParticipants = metadata["participantIds"] as? [String],
                       let existingIsGroup = metadata["isGroup"] as? Bool,
                       !existingIsGroup,
                       Set(existingParticipants) == Set([currentUserId] + participantIds) {
                        return conversationId
                    }
                }
            }
        }
        
        // Create new conversation
        let conversationRef = ref.child("conversations").childByAutoId()
        guard let conversationId = conversationRef.key else {
            throw NSError(domain: "RealtimeDB", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to generate conversation ID"])
        }
        
        var allParticipantIds = participantIds
        if !allParticipantIds.contains(currentUserId) {
            allParticipantIds.append(currentUserId)
        }
        
        var allParticipantNames = participantNames
        if allParticipantNames[currentUserId] == nil {
            allParticipantNames[currentUserId] = currentUserName
        }
        
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        
        let conversationData: [String: Any] = [
            "participantIds": allParticipantIds,
            "participantNames": allParticipantNames,
            "isGroup": isGroup,
            "groupName": groupName as Any,
            "lastMessageText": "",
            "lastMessageTimestamp": timestamp,
            "createdAt": timestamp,
            "updatedAt": timestamp
        ]
        
        try await conversationRef.child("metadata").setValue(conversationData)
        
        // Add to each participant's conversation list
        for participantId in allParticipantIds {
            try await ref.child("userConversations").child(participantId).child(conversationId).setValue(true)
        }
        
        print("✅ Realtime conversation created: \(conversationId)")
        return conversationId
    }
    
    // MARK: - Posts (Real-time feed updates)
    
    /// Publish a post to the realtime feed
    func publishRealtimePost(postId: String, authorId: String, category: String, timestamp: Date) async throws {
        let postRef = ref.child("posts").child("recent").child(postId)
        
        let postData: [String: Any] = [
            "postId": postId,
            "authorId": authorId,
            "category": category,
            "timestamp": Int64(timestamp.timeIntervalSince1970 * 1000),
            "likes": 0,
            "comments": 0
        ]
        
        try await postRef.setValue(postData)
        
        // Also add to category-specific feed
        let categoryRef = ref.child("posts").child("byCategory").child(category).child(postId)
        try await categoryRef.setValue(postData)
        
        // Initialize postInteractions node for real-time counts
        let interactionsRef = ref.child("postInteractions").child(postId)
        let interactionsData: [String: Any] = [
            "lightbulbCount": 0,
            "amenCount": 0,
            "commentCount": 0,
            "repostCount": 0
        ]
        try await interactionsRef.setValue(interactionsData)
        
        print("✅ Realtime post published: \(postId)")
        print("✅ Post interactions initialized: \(postId)")
    }
    
    /// Observe recent posts in real-time
    func observeRecentPosts(limit: Int = 50, onUpdate: @escaping ([String]) -> Void) {
        // Skip observing if user is not authenticated
        guard Auth.auth().currentUser != nil else {
            print("⏭️ Skipping observeRecentPosts - user not authenticated")
            return
        }
        
        let postsRef = ref.child("posts").child("recent").queryLimited(toLast: UInt(limit))
        
        postsRef.observe(.value) { snapshot in
            var postIds: [String] = []
            
            for child in snapshot.children {
                guard let childSnapshot = child as? DataSnapshot else { continue }
                postIds.append(childSnapshot.key)
            }
            
            onUpdate(postIds.reversed()) // Most recent first
        }
    }
    
    /// Update post engagement (likes, comments) in real-time
    func updatePostEngagement(postId: String, likes: Int? = nil, comments: Int? = nil) async throws {
        var updates: [String: Any] = [:]
        
        if let likes = likes {
            updates["likes"] = likes
        }
        if let comments = comments {
            updates["comments"] = comments
        }
        
        guard !updates.isEmpty else { return }
        
        try await ref.child("posts").child("recent").child(postId).updateChildValues(updates)
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        // Remove all observers
        for (conversationId, handle) in messageObservers {
            ref.child("conversations").child(conversationId).child("messages").removeObserver(withHandle: handle)
        }
        messageObservers.removeAll()
        
        for (conversationId, handle) in typingObservers {
            ref.child("conversations").child(conversationId).child("typing").removeObserver(withHandle: handle)
        }
        typingObservers.removeAll()
        
        for handle in conversationObservers {
            ref.child("userConversations").child(currentUserId).removeObserver(withHandle: handle)
        }
        conversationObservers.removeAll()
        
        if let handle = onlineStatusHandle {
            ref.child("presence").removeObserver(withHandle: handle)
        }
        
        // Set offline status
        ref.child("presence").child(currentUserId).updateChildValues([
            "online": false,
            "lastSeen": ServerValue.timestamp()
        ])
    }
    
    deinit {
        Task { @MainActor in
            cleanup()
        }
    }
}

// MARK: - Realtime Models

struct RealtimeMessage: Identifiable, Codable {
    let id: String
    let conversationId: String
    let senderId: String
    let senderName: String
    let text: String
    let timestamp: Date
    let readBy: Set<String>
    let replyToMessageId: String?
    
    var isFromCurrentUser: Bool {
        senderId == (Auth.auth().currentUser?.uid ?? "")
    }
    
    var isRead: Bool {
        readBy.contains(Auth.auth().currentUser?.uid ?? "")
    }
}

struct RealtimeConversation: Identifiable, Codable {
    let id: String
    let participantIds: [String]
    let participantNames: [String: String]
    let isGroup: Bool
    let groupName: String?
    let lastMessageText: String
    let lastMessageTimestamp: Date
    let unreadCount: Int
    
    var displayName: String {
        if isGroup {
            return groupName ?? "Group Chat"
        } else {
            let currentUserId = Auth.auth().currentUser?.uid ?? ""
            let otherParticipants = participantIds.filter { $0 != currentUserId }
            return otherParticipants.compactMap { participantNames[$0] }.first ?? "Unknown"
        }
    }
}
