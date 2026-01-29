//
//  Message.swift
//  AMENAPP
//
//  Model for messages
//

import Foundation
import SwiftUI
import UIKit

// MARK: - Message Model

class AppMessage: Identifiable, Equatable, Hashable {
    var id: String
    let text: String
    let isFromCurrentUser: Bool
    let timestamp: Date
    var senderId: String
    var senderName: String?
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
    var linkPreviews: [LinkPreview] = []
    var mentionedUserIds: [String] = []
    
    init(
        id: String = UUID().uuidString,
        text: String,
        isFromCurrentUser: Bool,
        timestamp: Date,
        senderId: String = "",
        senderName: String? = nil,
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
        linkPreviews: [LinkPreview] = [],
        mentionedUserIds: [String] = []
    ) {
        self.id = id
        self.text = text
        self.isFromCurrentUser = isFromCurrentUser
        self.timestamp = timestamp
        self.senderId = senderId
        self.senderName = senderName
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
    
    static func == (lhs: AppMessage, rhs: AppMessage) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct MessageAttachment: Identifiable, Equatable, Hashable {
    let id: UUID
    let type: AttachmentType
    let data: Data?
    let thumbnail: UIImage?
    let url: URL?
    
    enum AttachmentType: Hashable {
        case photo
        case video
        case audio
        case document
        case location
    }
    
    init(
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
    
    static func == (lhs: MessageAttachment, rhs: MessageAttachment) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct MessageReaction: Identifiable, Equatable, Hashable {
    let id: UUID
    let emoji: String
    let userId: String
    let username: String
    
    init(emoji: String, userId: String, username: String) {
        self.id = UUID()
        self.emoji = emoji
        self.userId = userId
        self.username = username
    }
    
    static func == (lhs: MessageReaction, rhs: MessageReaction) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
