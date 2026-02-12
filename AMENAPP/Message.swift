//
//  Message.swift
//  AMENAPP
//
//  Model for messages
//

import Foundation
import SwiftUI
import UIKit

// MARK: - Message Delivery Status

public enum MessageDeliveryStatus {
    case sending      // Gray clock icon
    case sent         // Single gray checkmark
    case delivered    // Double gray checkmarks
    case read         // Double blue checkmarks
    case failed       // Red exclamation
    
    public var icon: String {
        switch self {
        case .sending: return "clock"
        case .sent: return "checkmark"
        case .delivered: return "checkmark.circle"
        case .read: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        }
    }
    
    public var color: SwiftUI.Color {
        switch self {
        case .sending: return .secondary
        case .sent: return .secondary
        case .delivered: return .secondary
        case .read: return .blue
        case .failed: return .red
        }
    }
}

// MARK: - Message Model

public class AppMessage: Identifiable, Equatable, Hashable {
    public var id: String
    let text: String
    let isFromCurrentUser: Bool
    let timestamp: Date
    var senderId: String
    var senderName: String?
    var senderProfileImageURL: String? // ✅ Sender's profile image URL
    var attachments: [MessageAttachment] = []
    var replyTo: AppMessage?
    var reactions: [MessageReaction] = []
    var isRead: Bool = false
    var isPinned: Bool = false
    var pinnedBy: String?
    var pinnedAt: Date?
    var isStarred: Bool = false
    var isDeleted: Bool = false
    var deletedBy: String?
    var editedAt: Date?
    
    // New properties for delivery status and features
    var isSent: Bool = false
    var isDelivered: Bool = false
    var isSendFailed: Bool = false
    var disappearAfter: TimeInterval? = nil // Disappearing message duration
    var linkPreviews: [MessageLinkPreview] = []
    var mentionedUserIds: [String] = []
    
    init(
        id: String = UUID().uuidString,
        text: String,
        isFromCurrentUser: Bool,
        timestamp: Date,
        senderId: String = "",
        senderName: String? = nil,
        senderProfileImageURL: String? = nil,
        attachments: [MessageAttachment] = [],
        replyTo: AppMessage? = nil,
        reactions: [MessageReaction] = [],
        isRead: Bool = false,
        isPinned: Bool = false,
        pinnedBy: String? = nil,
        pinnedAt: Date? = nil,
        isStarred: Bool = false,
        isDeleted: Bool = false,
        deletedBy: String? = nil,
        editedAt: Date? = nil,
        isSent: Bool = false,
        isDelivered: Bool = false,
        isSendFailed: Bool = false,
        disappearAfter: TimeInterval? = nil,
        linkPreviews: [MessageLinkPreview] = [],
        mentionedUserIds: [String] = []
    ) {
        self.id = id
        self.text = text
        self.isFromCurrentUser = isFromCurrentUser
        self.timestamp = timestamp
        self.senderId = senderId
        self.senderName = senderName
        self.senderProfileImageURL = senderProfileImageURL
        self.attachments = attachments
        self.replyTo = replyTo
        self.reactions = reactions
        self.isRead = isRead
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
        self.linkPreviews = linkPreviews
        self.mentionedUserIds = mentionedUserIds
    }
    
    var senderInitials: String {
        let name = senderName ?? "U"
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        }
        return String(name.prefix(1)).uppercased()
    }
    
    var deliveryStatus: MessageDeliveryStatus {
        if isSendFailed {
            return .failed
        } else if !isFromCurrentUser {
            return .delivered // Received messages are always delivered
        } else if isRead {
            return .read
        } else if isDelivered {
            return .delivered
        } else if isSent {
            return .sent
        } else {
            return .sending
        }
    }
    
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
    
    public static func == (lhs: AppMessage, rhs: AppMessage) -> Bool {
        lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

public struct MessageAttachment: Identifiable, Equatable, Hashable {
    public let id: UUID
    public let type: AttachmentType
    public let data: Data?
    public let thumbnail: UIImage?
    public let url: URL?
    
    public enum AttachmentType: Hashable {
        case photo
        case video
        case audio
        case document
        case location
    }
    
    public init(
        id: UUID = UUID(),
        type: AttachmentType,
        data: Data? = nil,
        thumbnail: UIImage? = nil,
        url: URL? = nil
    ) {
        self.id = id
        self.type = type
        self.data = data
        self.thumbnail = thumbnail
        self.url = url
    }
    
    public static func == (lhs: MessageAttachment, rhs: MessageAttachment) -> Bool {
        lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

public struct MessageReaction: Identifiable, Equatable, Hashable {
    public let id: UUID
    public let emoji: String
    public let userId: String
    public let username: String
    
    public init(emoji: String, userId: String, username: String) {
        self.id = UUID()
        self.emoji = emoji
        self.userId = userId
        self.username = username
    }
    
    public static func == (lhs: MessageReaction, rhs: MessageReaction) -> Bool {
        lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Link Preview

public struct MessageLinkPreview: Identifiable, Equatable, Hashable {
    public let id: UUID
    public let url: URL
    public let title: String?
    public let description: String?
    public let imageUrl: String?
    public let favicon: String?
    
    public init(
        url: URL,
        title: String? = nil,
        description: String? = nil,
        imageUrl: String? = nil,
        favicon: String? = nil
    ) {
        self.id = UUID()
        self.url = url
        self.title = title
        self.description = description
        self.imageUrl = imageUrl
        self.favicon = favicon
    }
    
    public static func == (lhs: MessageLinkPreview, rhs: MessageLinkPreview) -> Bool {
        lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}


