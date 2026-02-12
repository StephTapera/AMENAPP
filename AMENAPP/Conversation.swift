//
//  Conversation.swift
//  AMENAPP
//
//  Model for conversations
//

import Foundation
import SwiftUI

// MARK: - Conversation Model

public struct ChatConversation: Identifiable, Equatable {
    public var id: String
    public let name: String
    public let lastMessage: String
    public let timestamp: String
    public let isGroup: Bool
    public let unreadCount: Int
    public let avatarColor: Color
    public let status: String // "accepted", "pending", "declined"
    public let profilePhotoURL: String? // Profile photo URL
    public let isPinned: Bool // Whether conversation is pinned
    public let isMuted: Bool // Whether notifications are muted
    public let requesterId: String? // User who initiated the conversation (for message requests)
    
    // Equatable conformance
    public static func == (lhs: ChatConversation, rhs: ChatConversation) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.lastMessage == rhs.lastMessage &&
        lhs.timestamp == rhs.timestamp &&
        lhs.isGroup == rhs.isGroup &&
        lhs.unreadCount == rhs.unreadCount &&
        lhs.status == rhs.status &&
        lhs.profilePhotoURL == rhs.profilePhotoURL &&
        lhs.isPinned == rhs.isPinned &&
        lhs.isMuted == rhs.isMuted &&
        lhs.requesterId == rhs.requesterId
        // Note: Excluding avatarColor from comparison as Color doesn't conform to Equatable
    }
    
    public init(
        id: String = UUID().uuidString,
        name: String,
        lastMessage: String,
        timestamp: String,
        isGroup: Bool,
        unreadCount: Int,
        avatarColor: Color,
        status: String = "accepted",
        profilePhotoURL: String? = nil,
        isPinned: Bool = false,
        isMuted: Bool = false,
        requesterId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.lastMessage = lastMessage
        self.timestamp = timestamp
        self.isGroup = isGroup
        self.unreadCount = unreadCount
        self.avatarColor = avatarColor
        self.status = status
        self.profilePhotoURL = profilePhotoURL
        self.isPinned = isPinned
        self.isMuted = isMuted
        self.requesterId = requesterId
    }
    
    public var initials: String {
        let words = name.split(separator: " ")
        if words.count > 1 {
            return String(words[0].prefix(1)) + String(words[1].prefix(1))
        } else if let first = words.first {
            return String(first.prefix(2))
        }
        return "?"
    }
}
