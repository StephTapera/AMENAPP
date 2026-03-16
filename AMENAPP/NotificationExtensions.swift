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

    /// Posted when the Berean Live Activity "Go Deeper" button is tapped
    /// UserInfo: ["postID": String]
    static let openBereanFromLiveActivity = Notification.Name("openBereanFromLiveActivity")
    
    /// Posted when a new message request is received
    static let messageRequestReceived = Notification.Name("messageRequestReceived")
    
    /// Posted when a conversation is updated
    static let conversationUpdated = Notification.Name("conversationUpdated")
    
    /// Posted when the user taps "Publish" — before Firestore confirms.
    /// UserInfo: ["category": String]
    static let postingStarted = Notification.Name("postingStarted")

    /// Posted when a new post is created
    /// UserInfo should contain: ["category": String]
    static let newPostCreated = Notification.Name("newPostCreated")

    /// Posted when post creation fails (upload error, moderation block, etc.)
    /// Signals the posting bar to hide immediately.
    static let postingFailed = Notification.Name("postingFailed")
    
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

    /// Posted when the user taps the Home tab button while already on the Home tab.
    /// HomeView observes this to scroll to top and refresh the feed.
    static let homeTabTapped = Notification.Name("homeTabTapped")

    /// Posted when the Share Extension hands off a draft to the main app.
    /// UserInfo: ["text": String, "linkURL": String, "destination": String]
    static let openCreatePostFromShare = Notification.Name("openCreatePostFromShare")

    /// Posted when a push notification tap requests opening a specific post.
    /// UserInfo: ["postId": String, "scrollToCommentId": String?]
    static let openPostFromNotification = Notification.Name("openPostFromNotification")

    /// Posted when a push notification tap requests opening a specific user profile.
    /// UserInfo: ["userId": String]
    static let openProfileFromNotification = Notification.Name("openProfileFromNotification")
}
