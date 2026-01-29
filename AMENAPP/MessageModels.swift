//
//  MessageModels.swift
//  AMENAPP
//
//  Created by Assistant on 1/26/26.
//
//  Data models for messaging system
//

import Foundation
import FirebaseFirestore

// MARK: - Conversation Model

struct Conversation: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    var participants: [String]  // Array of user IDs
    var participantNames: [String: String]  // userId: displayName
    var participantPhotos: [String: String]  // userId: photoURL
    var lastMessage: String
    var lastMessageSenderId: String
    var lastMessageTime: Date
    var unreadCount: [String: Int]  // userId: unreadCount
    var archivedBy: [String]  // Array of userIds who archived this conversation
    var createdAt: Date
    var updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case participants
        case participantNames
        case participantPhotos
        case lastMessage
        case lastMessageSenderId
        case lastMessageTime
        case unreadCount
        case archivedBy
        case createdAt
        case updatedAt
    }
    
    init(
        id: String? = nil,
        participants: [String],
        participantNames: [String: String] = [:],
        participantPhotos: [String: String] = [:],
        lastMessage: String = "",
        lastMessageSenderId: String = "",
        lastMessageTime: Date = Date(),
        unreadCount: [String: Int] = [:],
        archivedBy: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.participants = participants
        self.participantNames = participantNames
        self.participantPhotos = participantPhotos
        self.lastMessage = lastMessage
        self.lastMessageSenderId = lastMessageSenderId
        self.lastMessageTime = lastMessageTime
        self.unreadCount = unreadCount
        self.archivedBy = archivedBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    /// Get the other participant's ID (for 1-on-1 conversations)
    func otherParticipant(currentUserId: String) -> String? {
        participants.first { $0 != currentUserId }
    }
    
    /// Get the other participant's name
    func otherParticipantName(currentUserId: String) -> String {
        guard let otherUserId = otherParticipant(currentUserId: currentUserId) else {
            return "Unknown"
        }
        return participantNames[otherUserId] ?? "Unknown User"
    }
    
    /// Get the other participant's photo URL
    func otherParticipantPhoto(currentUserId: String) -> String? {
        guard let otherUserId = otherParticipant(currentUserId: currentUserId) else {
            return nil
        }
        return participantPhotos[otherUserId]
    }
    
    /// Get unread count for current user
    func unreadCountForUser(_ userId: String) -> Int {
        unreadCount[userId] ?? 0
    }
    
    /// Check if conversation is archived by user
    func isArchivedByUser(_ userId: String) -> Bool {
        archivedBy.contains(userId)
    }
}

// MARK: - Message Model

struct Message: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    var conversationId: String
    var senderId: String
    var senderName: String
    var senderPhoto: String?
    var content: String
    var type: MessageType
    var timestamp: Date
    var isRead: Bool
    var readAt: Date?
    var isDelivered: Bool
    var deliveredAt: Date?
    var isPinned: Bool
    var pinnedBy: String?
    var pinnedAt: Date?
    
    enum MessageType: String, Codable {
        case text
        case image
        case video
        case audio
        case file
        case prayer  // Special type for prayer requests
        case verse   // Bible verse sharing
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case conversationId
        case senderId
        case senderName
        case senderPhoto
        case content
        case type
        case timestamp
        case isRead
        case readAt
        case isDelivered
        case deliveredAt
        case isPinned
        case pinnedBy
        case pinnedAt
    }
    
    init(
        id: String? = nil,
        conversationId: String,
        senderId: String,
        senderName: String,
        senderPhoto: String? = nil,
        content: String,
        type: MessageType = .text,
        timestamp: Date = Date(),
        isRead: Bool = false,
        readAt: Date? = nil,
        isDelivered: Bool = false,
        deliveredAt: Date? = nil,
        isPinned: Bool = false,
        pinnedBy: String? = nil,
        pinnedAt: Date? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.senderId = senderId
        self.senderName = senderName
        self.senderPhoto = senderPhoto
        self.content = content
        self.type = type
        self.timestamp = timestamp
        self.isRead = isRead
        self.readAt = readAt
        self.isDelivered = isDelivered
        self.deliveredAt = deliveredAt
        self.isPinned = isPinned
        self.pinnedBy = pinnedBy
        self.pinnedAt = pinnedAt
    }
}

// MARK: - Typing Indicator Model

struct TypingIndicator: Codable {
    var userId: String
    var conversationId: String
    var isTyping: Bool
    var timestamp: Date
}
