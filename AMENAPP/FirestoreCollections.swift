// FirestoreCollections.swift
// AMENAPP
//
// Canonical Firestore collection name constants.
// Use these instead of raw strings to prevent typos and enable compile-time refactoring.
//
// Migration status: incremental — prayers + prayerWall + posts migrated first.
// For legacy code still using FirebaseManager.CollectionPath, both resolve to the
// same underlying string so they are interchangeable at runtime.

import Foundation

enum FirestoreCollections {
    static let users = "users"
    static let posts = "posts"
    static let prayers = "prayers"
    static let prayerRequests = "prayerRequests"
    static let prayerWall = "prayerWall"
    static let conversations = "conversations"
    static let messages = "messages"
    static let bereanConversations = "bereanConversations"
    static let selahEntries = "selahEntries"
    static let churches = "churches"
    static let media = "media"
    static let follows = "follows"
    static let savedPosts = "savedPosts"
    static let notifications = "notifications"
    static let covenants = "covenants"
    static let comments = "comments"
    static let spaces = "spaces"
    static let blocks = "blocks"
    static let followRequests = "followRequests"
    static let churchNotes = "churchNotes"

    // MARK: - Calm Control OS Paths
    // Subcollections under users/{uid}/
    static let privacySettings = "privacySettings"
    static let feedControls = "feedControls"
    static let notificationSettings = "notificationSettings"
    static let spiritualRhythm = "spiritualRhythm"
    static let streaks = "streaks"
    static let presence = "presence"
    static let audienceLayers = "audienceLayers"
    static let activity = "activity"
    static let rateLimits = "rateLimits"
    // Document IDs
    static let mainDocument = "main"
    // Streak types
    static let streakScripture = "scripture"
    static let streakPrayer = "prayer"
    static let streakCommunity = "community"
    static let streakReading = "reading"

    enum UserSubcollections {
        static let usage = "usage"
        static let safety = "safety"
        static let customTopicTags = "customTopicTags"
        static let actionThreadMemberships = "actionThreadMemberships"
    }

    enum PostSubcollections {
        static let media = "media"
        static let safety = "safety"
        static let actionThreads = "actionThreads"
        static let comments = "comments"
    }
}
