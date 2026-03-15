//
//  Conversation.swift
//  AMENAPP
//
//  Model for conversations
//

import Foundation
import SwiftUI

// MARK: - Conversation Source Context

/// Where/how a conversation was initiated — shown as a subtle banner.
public enum ConversationSource: String, Codable, Equatable {
    case direct          = "direct"
    case fromPost        = "from_post"
    case fromTestimony   = "from_testimony"
    case fromPrayer      = "from_prayer"
    case fromChurch      = "from_church"
    case fromChurchNotes = "from_church_notes"
    case fromProfile     = "from_profile"
    case fromOpportunity = "from_opportunity"
    case fromComment     = "from_comment"

    var label: String {
        switch self {
        case .direct:          return ""
        case .fromPost:        return "Messaged you from your post"
        case .fromTestimony:   return "Responded to your testimony"
        case .fromPrayer:      return "Reached out about a prayer request"
        case .fromChurch:      return "Connected through a church page"
        case .fromChurchNotes: return "Reached out through Church Notes"
        case .fromProfile:     return "Started from your profile"
        case .fromOpportunity: return "Contacted you through Opportunities"
        case .fromComment:     return "Replied to your comment"
        }
    }

    var icon: String {
        switch self {
        case .direct:          return "bubble.left.and.bubble.right"
        case .fromPost:        return "doc.text"
        case .fromTestimony:   return "star"
        case .fromPrayer:      return "hands.sparkles"
        case .fromChurch:      return "building.columns"
        case .fromChurchNotes: return "note.text"
        case .fromProfile:     return "person.circle"
        case .fromOpportunity: return "briefcase"
        case .fromComment:     return "text.bubble"
        }
    }
}

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
    public let otherParticipantId: String? // Non-current user's ID for 1:1 conversations
    public let source: ConversationSource // How/where this conversation was initiated
    public let otherUserBio: String? // Short bio preview for identity card
    public let otherUserUsername: String? // @username for identity card

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
        lhs.requesterId == rhs.requesterId &&
        lhs.otherParticipantId == rhs.otherParticipantId &&
        lhs.source == rhs.source &&
        lhs.otherUserBio == rhs.otherUserBio &&
        lhs.otherUserUsername == rhs.otherUserUsername
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
        requesterId: String? = nil,
        otherParticipantId: String? = nil,
        source: ConversationSource = .direct,
        otherUserBio: String? = nil,
        otherUserUsername: String? = nil
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
        self.otherParticipantId = otherParticipantId
        self.source = source
        self.otherUserBio = otherUserBio
        self.otherUserUsername = otherUserUsername
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
