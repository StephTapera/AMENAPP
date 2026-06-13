//
//  MessagingThreadFilter.swift
//  AMENAPP
//
//  Thread-level (inside a single conversation) filter model.
//  Strictly local — operates on the in-memory `[AppMessage]` array that
//  UnifiedChatView already holds. No backend signals, no fake counts.
//
//  Filters intentionally rely only on fields that exist on AppMessage today:
//    - .all       no-op
//    - .unread    !isRead && !isFromCurrentUser
//    - .media     messageType in {image, video} OR media attachment present
//    - .links     messageType == .link OR linkURL present OR linkPreviews non-empty
//    - .files     messageType == .file OR mediaFileName present
//    - .mentions  mentionedUserIds contains currentUserId
//    - .pinned    isPinned
//    - .starred   isStarred
//

import Foundation

@available(iOS 17.0, *)
public enum MessagingThreadFilter: String, CaseIterable, Identifiable, Equatable {
    case all
    case unread
    case media
    case links
    case files
    case mentions
    case pinned
    case starred

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all:      return "All"
        case .unread:   return "Unread"
        case .media:    return "Media"
        case .links:    return "Links"
        case .files:    return "Files"
        case .mentions: return "Mentions"
        case .pinned:   return "Pinned"
        case .starred:  return "Starred"
        }
    }

    public var symbol: String {
        switch self {
        case .all:      return "tray.full"
        case .unread:   return "circle.fill"
        case .media:    return "photo.on.rectangle"
        case .links:    return "link"
        case .files:    return "doc"
        case .mentions: return "at"
        case .pinned:   return "pin.fill"
        case .starred:  return "star.fill"
        }
    }

    /// Stable analytics key (never localized).
    public var analyticsKey: String { rawValue }
}

// MARK: - Availability

@available(iOS 17.0, *)
public struct MessagingThreadFilterCapabilities: Equatable {
    public var hasUnread: Bool
    public var hasMedia: Bool
    public var hasLinks: Bool
    public var hasFiles: Bool
    public var hasMentions: Bool
    public var hasPinned: Bool
    public var hasStarred: Bool

    public init(
        hasUnread: Bool = false,
        hasMedia: Bool = false,
        hasLinks: Bool = false,
        hasFiles: Bool = false,
        hasMentions: Bool = false,
        hasPinned: Bool = false,
        hasStarred: Bool = false
    ) {
        self.hasUnread = hasUnread
        self.hasMedia = hasMedia
        self.hasLinks = hasLinks
        self.hasFiles = hasFiles
        self.hasMentions = hasMentions
        self.hasPinned = hasPinned
        self.hasStarred = hasStarred
    }
}

@available(iOS 17.0, *)
public extension MessagingThreadFilter {

    func isAvailable(in caps: MessagingThreadFilterCapabilities) -> Bool {
        switch self {
        case .all:      return true
        case .unread:   return caps.hasUnread
        case .media:    return caps.hasMedia
        case .links:    return caps.hasLinks
        case .files:    return caps.hasFiles
        case .mentions: return caps.hasMentions
        case .pinned:   return caps.hasPinned
        case .starred:  return caps.hasStarred
        }
    }

    static func available(for caps: MessagingThreadFilterCapabilities) -> [MessagingThreadFilter] {
        Self.allCases.filter { $0.isAvailable(in: caps) }
    }
}

// MARK: - SystemCapability Derivation from AppMessage

@available(iOS 17.0, *)
public enum MessagingThreadFilterAvailability {

    public static func capabilities(
        messages: [AppMessage],
        currentUserId: String
    ) -> MessagingThreadFilterCapabilities {
        var caps = MessagingThreadFilterCapabilities()
        for m in messages {
            if !m.isRead && !m.isFromCurrentUser { caps.hasUnread = true }
            if isMediaMessage(m) { caps.hasMedia = true }
            if isLinkMessage(m) { caps.hasLinks = true }
            if isFileMessage(m) { caps.hasFiles = true }
            if !currentUserId.isEmpty, m.mentionedUserIds.contains(currentUserId) { caps.hasMentions = true }
            if m.isPinned { caps.hasPinned = true }
            if m.isStarred { caps.hasStarred = true }
        }
        return caps
    }

    static func isMediaMessage(_ m: AppMessage) -> Bool {
        if m.messageType == .image || m.messageType == .video { return true }
        if m.attachments.contains(where: { $0.type == .photo || $0.type == .video }) { return true }
        if m.mediaURL != nil { return true }
        return false
    }

    static func isLinkMessage(_ m: AppMessage) -> Bool {
        if m.messageType == .link { return true }
        if !m.linkPreviews.isEmpty { return true }
        if let url = m.linkURL, !url.isEmpty { return true }
        return false
    }

    static func isFileMessage(_ m: AppMessage) -> Bool {
        if m.messageType == .file { return true }
        if m.attachments.contains(where: { $0.type == .document }) { return true }
        if let name = m.mediaFileName, !name.isEmpty { return true }
        return false
    }
}

// MARK: - Apply

@available(iOS 17.0, *)
public extension MessagingThreadFilter {

    func apply(
        to messages: [AppMessage],
        currentUserId: String
    ) -> [AppMessage] {
        switch self {
        case .all:
            return messages
        case .unread:
            return messages.filter { !$0.isRead && !$0.isFromCurrentUser }
        case .media:
            return messages.filter(MessagingThreadFilterAvailability.isMediaMessage)
        case .links:
            return messages.filter(MessagingThreadFilterAvailability.isLinkMessage)
        case .files:
            return messages.filter(MessagingThreadFilterAvailability.isFileMessage)
        case .mentions:
            guard !currentUserId.isEmpty else { return [] }
            return messages.filter { $0.mentionedUserIds.contains(currentUserId) }
        case .pinned:
            return messages.filter { $0.isPinned }
        case .starred:
            return messages.filter { $0.isStarred }
        }
    }
}

// MARK: - Search (text + filter combined)

@available(iOS 17.0, *)
public enum MessagingThreadSearch {

    /// Applies the filter first (cheap predicate), then a case-insensitive
    /// text substring match across text + linkTitle + mediaFileName.
    /// Never reads message bodies for analytics — only for local display.
    public static func results(
        messages: [AppMessage],
        filter: MessagingThreadFilter,
        query: String,
        currentUserId: String
    ) -> [AppMessage] {
        let filtered = filter.apply(to: messages, currentUserId: currentUserId)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return filtered }
        let needle = trimmed.lowercased()
        return filtered.filter { m in
            if m.text.lowercased().contains(needle) { return true }
            if let t = m.linkTitle?.lowercased(), t.contains(needle) { return true }
            if let n = m.mediaFileName?.lowercased(), n.contains(needle) { return true }
            return false
        }
    }
}
