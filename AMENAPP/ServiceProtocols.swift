//
//  ServiceProtocols.swift
//  AMENAPP
//
//  Protocol abstractions for the core service layer.
//  Concrete services (CommentService, FollowService, etc.) conform to these protocols,
//  allowing unit tests to inject lightweight mock implementations without hitting Firebase.
//
//  Usage in tests:
//    let sut = CommentsView(commentService: MockCommentService())
//
//  Usage in production (unchanged):
//    @ObservedObject private var commentService = CommentService.shared
//

import Foundation
import Combine

// MARK: - CommentServiceProtocol

protocol CommentServiceProtocol: AnyObject, ObservableObject {
    var comments: [String: [Comment]] { get }
    var commentReplies: [String: [Comment]] { get }
    var isLoading: Bool { get }
    var error: String? { get }

    func canComment(postId: String, post: Post) async -> Bool
    func addComment(postId: String, content: String, mentionedUserIds: [String]?, post: Post?) async throws -> Comment
    func addReply(postId: String, parentCommentId: String, content: String, mentionedUserIds: [String]?, post: Post?) async throws -> Comment
    func fetchComments(for postId: String) async throws -> [Comment]
    func fetchReplies(for commentId: String) async throws -> [Comment]
    func fetchUserComments(userId: String, limit: Int) async throws -> [Comment]
    func editComment(commentId: String, postId: String, newContent: String) async throws
    func deleteComment(commentId: String, postId: String) async throws
    func toggleAmen(commentId: String, postId: String, currentlyAmened: Bool) async throws
    func startListening(to postId: String)
    func stopListening(to postId: String, clearCache: Bool)
    func hasUserAmened(commentId: String, postId: String) async -> Bool
}

// MARK: - PostInteractionsServiceProtocol

protocol PostInteractionsServiceProtocol: AnyObject, ObservableObject {
    var userAmenedPosts: Set<String> { get }
    var userLightbulbedPosts: Set<String> { get }
    var userRepostedPosts: Set<String> { get }
    var postAmens: [String: Int] { get }
    var postLightbulbs: [String: Int] { get }
    var postComments: [String: Int] { get }
    var postReposts: [String: Int] { get }
    var hasLoadedInitialCache: Bool { get }

    func toggleAmen(postId: String) async throws
    func toggleLightbulb(postId: String) async throws
    func toggleRepost(postId: String) async throws -> Bool
    func hasAmened(postId: String) async -> Bool
    func hasLitLightbulb(postId: String) async -> Bool
    func hasReposted(postId: String) async -> Bool
    func getAmenCount(postId: String) async -> Int
    func getLightbulbCount(postId: String) async -> Int
    func getCommentCount(postId: String) async -> Int
    func getRepostCount(postId: String) async -> Int
    func observePostInteractions(postId: String)
    func stopObservingPost(postId: String)
    func loadInteractionsForPosts(_ postIds: [String]) async
    func getInteractionCounts(postId: String) async -> (amenCount: Int, commentCount: Int, repostCount: Int, lightbulbCount: Int)
}

// MARK: - FollowServiceProtocol

protocol FollowServiceProtocol: AnyObject, ObservableObject {
    var following: Set<String> { get }
    var followers: Set<String> { get }
    var followingList: [FollowUserProfile] { get }
    var followersList: [FollowUserProfile] { get }
    var isLoading: Bool { get }
    var error: String? { get }
    var currentUserFollowersCount: Int { get }
    var currentUserFollowingCount: Int { get }

    func followUser(userId: String) async throws
    func unfollowUser(userId: String) async throws
    func toggleFollow(userId: String) async throws
    func isFollowing(userId: String) async -> Bool
    func fetchFollowerIds(userId: String) async throws -> [String]
    func fetchFollowingIds(userId: String) async throws -> [String]
    func fetchFollowers(userId: String) async throws -> [FollowUserProfile]
    func fetchFollowing(userId: String) async throws -> [FollowUserProfile]
    func removeFollower(followerId: String) async throws
    func loadCurrentUserFollowing() async
    func loadCurrentUserFollowers() async
    func areMutualFollowers(userId: String) async -> Bool
    func startListening()
    func stopListening()
    func getFollowCounts(userId: String) async throws -> (followers: Int, following: Int)
}

// MARK: - NotificationServiceProtocol

protocol NotificationServiceProtocol: AnyObject, ObservableObject {
    var notifications: [AppNotification] { get }
    var unreadCount: Int { get }
    var isLoading: Bool { get }

    func startListening()
    func stopListening()
    func markAsRead(_ notificationId: String) async throws
    func markAllAsRead() async throws
    func deleteNotification(_ notificationId: String) async throws
    func deleteAllRead() async throws
    func refresh() async
    func removeNotifications(where predicate: (AppNotification) -> Bool)
}

// MARK: - Protocol conformances (real services)
// These extensions declare that the concrete services satisfy the protocols.
// No implementation needed — the services already implement all methods.

extension CommentService: CommentServiceProtocol {}
extension PostInteractionsService: PostInteractionsServiceProtocol {}
extension FollowService: FollowServiceProtocol {}
extension NotificationService: NotificationServiceProtocol {}
