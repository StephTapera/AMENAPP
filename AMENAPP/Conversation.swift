//
//  Conversation.swift
//  AMENAPP
//
//  Model for conversations
//

import Foundation
import SwiftUI

// MARK: - Conversation Model

struct ChatConversation: Identifiable, Equatable {
    var id: String
    let name: String
    let lastMessage: String
    let timestamp: String
    let isGroup: Bool
    let unreadCount: Int
    let avatarColor: Color
    
    // Equatable conformance
    static func == (lhs: ChatConversation, rhs: ChatConversation) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.lastMessage == rhs.lastMessage &&
        lhs.timestamp == rhs.timestamp &&
        lhs.isGroup == rhs.isGroup &&
        lhs.unreadCount == rhs.unreadCount
        // Note: Excluding avatarColor from comparison as Color doesn't conform to Equatable
    }
    
    init(id: String = UUID().uuidString, name: String, lastMessage: String, timestamp: String, isGroup: Bool, unreadCount: Int, avatarColor: Color) {
        self.id = id
        self.name = name
        self.lastMessage = lastMessage
        self.timestamp = timestamp
        self.isGroup = isGroup
        self.unreadCount = unreadCount
        self.avatarColor = avatarColor
    }
    
    var initials: String {
        let words = name.split(separator: " ")
        if words.count > 1 {
            return String(words[0].prefix(1)) + String(words[1].prefix(1))
        } else if let first = words.first {
            return String(first.prefix(2))
        }
        return "?"
    }
}
