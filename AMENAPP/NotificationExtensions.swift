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
    
    /// Posted when a group join link should be opened
    /// UserInfo should contain: ["token": String]
    static let openGroupJoinLink = Notification.Name("openGroupJoinLink")

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

    /// Posted by App Intents / Focus Filter to navigate to a specific tab.
    /// UserInfo: ["tab": Int]
    static let navigateToTab = Notification.Name("navigateToTab")

    /// Posted to open the create post sheet from anywhere in the app
    static let openCreatePost = Notification.Name("openCreatePost")

    /// Posted when the user taps the Home tab button while already on the Home tab.
    /// HomeView observes this to scroll to top and refresh the feed.
    static let homeTabTapped = Notification.Name("homeTabTapped")

    /// Posted when the user re-taps the Search tab while already on it.
    static let searchTabTapped = Notification.Name("searchTabTapped")

    /// Posted when the user re-taps the Messages tab while already on it.
    static let messagesTabTapped = Notification.Name("messagesTabTapped")

    /// Posted when the user re-taps the Library tab while already on it.
    static let libraryTabTapped = Notification.Name("libraryTabTapped")

    /// Posted when the user re-taps the Notifications tab while already on it.
    static let notificationsTabTapped = Notification.Name("notificationsTabTapped")

    /// Posted when the user re-taps the Profile tab while already on it.
    static let profileTabTapped = Notification.Name("profileTabTapped")

    /// Posted when the user re-taps the Gatherings tab while already on it.
    static let gatheringsTabTapped = Notification.Name("gatheringsTabTapped")

    /// Posted when the Share Extension hands off a draft to the main app.
    /// UserInfo: ["text": String, "linkURL": String, "destination": String]
    static let openCreatePostFromShare = Notification.Name("openCreatePostFromShare")

    /// Posted when a push notification tap requests opening a specific post.
    /// UserInfo: ["postId": String, "scrollToCommentId": String?]
    static let openPostFromNotification = Notification.Name("openPostFromNotification")

    /// Posted when a push notification tap requests opening a specific user profile.
    /// UserInfo: ["userId": String]
    static let openProfileFromNotification = Notification.Name("openProfileFromNotification")

    /// Posted when a deep link resolves to a user profile.
    /// UserInfo: ["userId": String]
    static let navigateToUser = Notification.Name("navigateToUser")

    /// Posted when a deep link resolves to a specific post.
    /// UserInfo: ["postId": String]
    static let navigateToPost = Notification.Name("navigateToPost")

    /// Posted when a push notification tap (or deep link) requests opening Walk With Christ.
    static let openWalkWithChristFromNotification = Notification.Name("amen.openWalkWithChrist")

    /// Posted when Firebase Remote Config activates a newly fetched config.
    /// Feature flag services observe this to re-apply remote values.
    static let remoteConfigActivated = Notification.Name("amen.remoteConfigActivated")

    // MARK: - Optimistic DM insert / rollback

    /// Posted by `sendMessageWithPermissions` immediately before any async work,
    /// so the chat view can display the message optimistically.
    ///
    /// UserInfo keys:
    ///   - "clientId"       : String  — UUID used as the temporary Firestore document ID
    ///   - "conversationId" : String
    ///   - "text"           : String
    ///   - "senderId"       : String  — current user UID
    ///   - "timestamp"      : Date
    static let dmOptimisticInsert = Notification.Name("amen.dmOptimisticInsert")

    /// Posted by `sendMessageWithPermissions` when `batch.commit()` fails, so the
    /// chat view can roll back the optimistic message and surface an error.
    ///
    /// UserInfo keys:
    ///   - "clientId"       : String  — matches the ID in the matching `dmOptimisticInsert`
    ///   - "conversationId" : String
    ///   - "error"          : Error
    static let dmOptimisticRollback = Notification.Name("amen.dmOptimisticRollback")
}
