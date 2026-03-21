//
//  MockServices.swift
//  AMENAPPTests
//
//  Lightweight in-memory mock implementations of service protocols.
//  Inject these in unit tests instead of the real Firebase-backed singletons.
//
//  Example:
//    func testCommentCount() async throws {
//        let mock = MockCommentService()
//        mock.stubbedComments["post1"] = [makeComment(id: "c1"), makeComment(id: "c2")]
//        XCTAssertEqual(mock.comments["post1"]?.count, 2)
//    }
//

import Foundation
import Combine
@testable import AMENAPP

// MARK: - MockCommentService

@MainActor
final class MockCommentService: ObservableObject, CommentServiceProtocol {
    @Published var comments: [String: [Comment]] = [:]
    @Published var commentReplies: [String: [Comment]] = [:]
    @Published var isLoading: Bool = false
    @Published var error: String? = nil

    // Configurable stubs
    var stubbedComments: [String: [Comment]] = [:]
    var canCommentResult = true
    var addCommentResult: Comment?
    var shouldThrowOnAdd = false
    var shouldThrowOnDelete = false
    var amenedComments: Set<String> = []

    func canComment(postId: String, post: Post) async -> Bool {
        canCommentResult
    }

    func addComment(postId: String, content: String, mentionedUserIds: [String]?, post: Post?) async throws -> Comment {
        if shouldThrowOnAdd { throw MockError.stubbed }
        let comment = addCommentResult ?? Comment(
            id: UUID().uuidString,
            authorId: "testUser",
            authorName: "Test User",
            text: content,
            createdAt: Date(),
            postId: postId,
            amenCount: 0,
            isOptimistic: false
        )
        comments[postId, default: []].append(comment)
        return comment
    }

    func addReply(postId: String, commentId: String, content: String, mentionedUserIds: [String]?) async throws -> Comment {
        if shouldThrowOnAdd { throw MockError.stubbed }
        let reply = Comment(
            id: UUID().uuidString,
            authorId: "testUser",
            authorName: "Test User",
            text: content,
            createdAt: Date(),
            postId: postId,
            parentCommentId: commentId,
            amenCount: 0,
            isOptimistic: false
        )
        commentReplies[commentId, default: []].append(reply)
        return reply
    }

    func fetchComments(for postId: String) async throws -> [Comment] {
        stubbedComments[postId] ?? []
    }

    func fetchReplies(for commentId: String) async throws -> [Comment] {
        commentReplies[commentId] ?? []
    }

    func fetchUserComments(userId: String, limit: Int) async throws -> [Comment] {
        stubbedComments.values.flatMap { $0 }.filter { $0.authorId == userId }
    }

    func editComment(commentId: String, postId: String, newContent: String) async throws {
        // no-op in mock
    }

    func deleteComment(commentId: String, postId: String) async throws {
        if shouldThrowOnDelete { throw MockError.stubbed }
        comments[postId]?.removeAll { $0.id == commentId }
    }

    func toggleAmen(commentId: String, postId: String, currentlyAmened: Bool) async throws {
        if currentlyAmened {
            amenedComments.remove(commentId)
        } else {
            amenedComments.insert(commentId)
        }
    }

    func startListening(to postId: String) {}
    func stopListening(to postId: String, clearCache: Bool) {}
    func hasUserAmened(commentId: String, postId: String) async -> Bool {
        amenedComments.contains(commentId)
    }
}

// MARK: - MockPostInteractionsService

@MainActor
final class MockPostInteractionsService: ObservableObject, PostInteractionsServiceProtocol {
    @Published var userAmenedPosts: Set<String> = []
    @Published var userLightbulbedPosts: Set<String> = []
    @Published var userRepostedPosts: Set<String> = []
    @Published var postAmens: [String: Int] = [:]
    @Published var postLightbulbs: [String: Int] = [:]
    @Published var postComments: [String: Int] = [:]
    @Published var postReposts: [String: Int] = [:]
    @Published var hasLoadedInitialCache: Bool = true

    var shouldThrow = false

    func toggleAmen(postId: String) async throws {
        if shouldThrow { throw MockError.stubbed }
        if userAmenedPosts.contains(postId) {
            userAmenedPosts.remove(postId)
            postAmens[postId] = max(0, (postAmens[postId] ?? 1) - 1)
        } else {
            userAmenedPosts.insert(postId)
            postAmens[postId] = (postAmens[postId] ?? 0) + 1
        }
    }

    func toggleLightbulb(postId: String) async throws {
        if shouldThrow { throw MockError.stubbed }
        if userLightbulbedPosts.contains(postId) {
            userLightbulbedPosts.remove(postId)
            postLightbulbs[postId] = max(0, (postLightbulbs[postId] ?? 1) - 1)
        } else {
            userLightbulbedPosts.insert(postId)
            postLightbulbs[postId] = (postLightbulbs[postId] ?? 0) + 1
        }
    }

    func toggleRepost(postId: String) async throws -> Bool {
        if shouldThrow { throw MockError.stubbed }
        let added = !userRepostedPosts.contains(postId)
        if added { userRepostedPosts.insert(postId) } else { userRepostedPosts.remove(postId) }
        postReposts[postId] = (postReposts[postId] ?? 0) + (added ? 1 : -1)
        return added
    }

    func hasAmened(postId: String) async -> Bool { userAmenedPosts.contains(postId) }
    func hasLitLightbulb(postId: String) async -> Bool { userLightbulbedPosts.contains(postId) }
    func hasReposted(postId: String) async -> Bool { userRepostedPosts.contains(postId) }
    func getAmenCount(postId: String) async -> Int { postAmens[postId] ?? 0 }
    func getLightbulbCount(postId: String) async -> Int { postLightbulbs[postId] ?? 0 }
    func getCommentCount(postId: String) async -> Int { postComments[postId] ?? 0 }
    func getRepostCount(postId: String) async -> Int { postReposts[postId] ?? 0 }
    func observePostInteractions(postId: String) {}
    func stopObservingPost(postId: String) {}
    func loadInteractionsForPosts(_ postIds: [String]) async {}
    func getInteractionCounts(postId: String) async -> (amenCount: Int, commentCount: Int, repostCount: Int, lightbulbCount: Int) {
        (postAmens[postId] ?? 0, postComments[postId] ?? 0, postReposts[postId] ?? 0, postLightbulbs[postId] ?? 0)
    }
}

// MARK: - MockFollowService

@MainActor
final class MockFollowService: ObservableObject, FollowServiceProtocol {
    @Published var following: Set<String> = []
    @Published var followers: Set<String> = []
    @Published var followingList: [FollowUserProfile] = []
    @Published var followersList: [FollowUserProfile] = []
    @Published var isLoading: Bool = false
    @Published var error: String? = nil
    @Published var currentUserFollowersCount: Int = 0
    @Published var currentUserFollowingCount: Int = 0

    var shouldThrow = false

    func followUser(userId: String) async throws {
        if shouldThrow { throw MockError.stubbed }
        following.insert(userId)
        currentUserFollowingCount += 1
    }

    func unfollowUser(userId: String) async throws {
        if shouldThrow { throw MockError.stubbed }
        following.remove(userId)
        currentUserFollowingCount = max(0, currentUserFollowingCount - 1)
    }

    func toggleFollow(userId: String) async throws {
        if following.contains(userId) {
            try await unfollowUser(userId: userId)
        } else {
            try await followUser(userId: userId)
        }
    }

    func isFollowing(userId: String) async -> Bool { following.contains(userId) }
    func fetchFollowerIds(userId: String) async throws -> [String] { Array(followers) }
    func fetchFollowingIds(userId: String) async throws -> [String] { Array(following) }
    func fetchFollowers(userId: String) async throws -> [FollowUserProfile] { followersList }
    func fetchFollowing(userId: String) async throws -> [FollowUserProfile] { followingList }
    func removeFollower(followerId: String) async throws { followers.remove(followerId) }
    func loadCurrentUserFollowing() async {}
    func loadCurrentUserFollowers() async {}
    func areMutualFollowers(userId: String) async -> Bool {
        following.contains(userId) && followers.contains(userId)
    }
    func startListening() {}
    func stopListening() {}
    func getFollowCounts(userId: String) async throws -> (followers: Int, following: Int) {
        (currentUserFollowersCount, currentUserFollowingCount)
    }
}

// MARK: - MockNotificationService

@MainActor
final class MockNotificationService: ObservableObject, NotificationServiceProtocol {
    @Published var notifications: [AppNotification] = []
    @Published var unreadCount: Int = 0
    @Published var isLoading: Bool = false

    var shouldThrow = false
    private(set) var markedReadIds: [String] = []
    private(set) var deletedIds: [String] = []

    func startListening() {}
    func stopListening() {}

    func markAsRead(_ notificationId: String) async throws {
        if shouldThrow { throw MockError.stubbed }
        markedReadIds.append(notificationId)
        if let idx = notifications.firstIndex(where: { $0.id == notificationId }) {
            notifications[idx].isRead = true
        }
        unreadCount = notifications.filter { !$0.isRead }.count
    }

    func markAllAsRead() async throws {
        if shouldThrow { throw MockError.stubbed }
        notifications = notifications.map { n in
            var copy = n; copy.isRead = true; return copy
        }
        unreadCount = 0
    }

    func deleteNotification(_ notificationId: String) async throws {
        if shouldThrow { throw MockError.stubbed }
        deletedIds.append(notificationId)
        notifications.removeAll { $0.id == notificationId }
    }

    func deleteAllRead() async throws {
        if shouldThrow { throw MockError.stubbed }
        notifications.removeAll { $0.isRead }
    }

    func refresh() async {
        // no-op in mock
    }

    func removeNotifications(where predicate: (AppNotification) -> Bool) {
        notifications.removeAll(where: predicate)
    }
}

// MARK: - MockError

enum MockError: Error, LocalizedError {
    case stubbed
    var errorDescription: String? { "MockError: stubbed failure" }
}
