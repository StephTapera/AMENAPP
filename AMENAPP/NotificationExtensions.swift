//
//  NotificationExtensions.swift
//  AMENAPP
//
//  Notification names for app-wide communication
//

import Foundation

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when a conversation should be opened
    /// UserInfo should contain: ["conversationId": String]
    static let openConversation = Notification.Name("openConversation")
    
    /// Posted when a new message request is received
    static let messageRequestReceived = Notification.Name("messageRequestReceived")
    
    /// Posted when a conversation is updated
    static let conversationUpdated = Notification.Name("conversationUpdated")
    
    /// Posted when a new post is created
    /// UserInfo should contain: ["category": String]
    static let newPostCreated = Notification.Name("newPostCreated")
    
    /// Posted when a post is edited
    static let postEdited = Notification.Name("postEdited")
    
    /// Posted when a post is deleted
    static let postDeleted = Notification.Name("postDeleted")
    
    /// Posted when a post is reposted
    static let postReposted = Notification.Name("postReposted")
    
    /// Posted when a follow state changes
    /// UserInfo should contain: ["userId": String, "isFollowing": Bool]
    static let followStateChanged = Notification.Name("followStateChanged")

    /// Posted to open the create post sheet from anywhere in the app
    static let openCreatePost = Notification.Name("openCreatePost")
}
