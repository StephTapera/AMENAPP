//
//  ServiceProtocolTests.swift
//  AMENAPPTests
//
//  Unit tests for core service logic using mock implementations.
//  These run entirely in-memory — no Firebase, no network required.
//

import XCTest
@testable import AMENAPP

@MainActor
final class MockCommentServiceTests: XCTestCase {

    func testAddCommentAppendsToList() async throws {
        let sut = MockCommentService()
        let post = Post.makeTest(id: "p1")

        let comment = try await sut.addComment(postId: "p1", content: "Hello", mentionedUserIds: nil, post: post)

        XCTAssertEqual(sut.comments["p1"]?.count, 1)
        XCTAssertEqual(comment.text, "Hello")
    }

    func testAddCommentThrowsWhenStubbedToFail() async {
        let sut = MockCommentService()
        sut.shouldThrowOnAdd = true
        let post = Post.makeTest(id: "p1")

        do {
            _ = try await sut.addComment(postId: "p1", content: "Hello", mentionedUserIds: nil, post: post)
            XCTFail("Expected throw")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    func testDeleteCommentRemovesFromList() async throws {
        let sut = MockCommentService()
        let post = Post.makeTest(id: "p1")
        let comment = try await sut.addComment(postId: "p1", content: "To delete", mentionedUserIds: nil, post: post)

        try await sut.deleteComment(commentId: comment.id ?? "", postId: "p1")

        XCTAssertEqual(sut.comments["p1"]?.count, 0)
    }

    func testToggleAmenAddsAndRemoves() async throws {
        let sut = MockCommentService()
        let commentId = "c1"

        try await sut.toggleAmen(commentId: commentId, postId: "p1", currentlyAmened: false)
        let afterAdd = await sut.hasUserAmened(commentId: commentId, postId: "p1")
        XCTAssertTrue(afterAdd)

        try await sut.toggleAmen(commentId: commentId, postId: "p1", currentlyAmened: true)
        let afterRemove = await sut.hasUserAmened(commentId: commentId, postId: "p1")
        XCTAssertFalse(afterRemove)
    }

    func testCanCommentRespectsStub() async {
        let sut = MockCommentService()
        sut.canCommentResult = false
        let result = await sut.canComment(postId: "p1", post: Post.makeTest(id: "p1"))
        XCTAssertFalse(result)
    }
}

// MARK: -

@MainActor
final class MockPostInteractionsServiceTests: XCTestCase {

    func testToggleAmenIncrementsAndDecrements() async throws {
        let sut = MockPostInteractionsService()
        sut.postAmens["p1"] = 5

        try await sut.toggleAmen(postId: "p1")
        XCTAssertEqual(sut.postAmens["p1"], 6)
        XCTAssertTrue(sut.userAmenedPosts.contains("p1"))

        try await sut.toggleAmen(postId: "p1")
        XCTAssertEqual(sut.postAmens["p1"], 5)
        XCTAssertFalse(sut.userAmenedPosts.contains("p1"))
    }

    func testToggleAmenDoesNotGoNegative() async throws {
        let sut = MockPostInteractionsService()
        sut.postAmens["p1"] = 0
        sut.userAmenedPosts.insert("p1")  // pretend already amened

        try await sut.toggleAmen(postId: "p1")
        XCTAssertEqual(sut.postAmens["p1"], 0, "Count should not go below 0")
    }

    func testToggleLightbulbRoundTrip() async throws {
        let sut = MockPostInteractionsService()

        try await sut.toggleLightbulb(postId: "p2")
        XCTAssertTrue(await sut.hasLitLightbulb(postId: "p2"))

        try await sut.toggleLightbulb(postId: "p2")
        XCTAssertFalse(await sut.hasLitLightbulb(postId: "p2"))
    }

    func testToggleRepostReturnsAddedState() async throws {
        let sut = MockPostInteractionsService()

        let added = try await sut.toggleRepost(postId: "p3")
        XCTAssertTrue(added)
        XCTAssertTrue(sut.userRepostedPosts.contains("p3"))

        let removed = try await sut.toggleRepost(postId: "p3")
        XCTAssertFalse(removed)
        XCTAssertFalse(sut.userRepostedPosts.contains("p3"))
    }

    func testGetInteractionCountsReflectsState() async {
        let sut = MockPostInteractionsService()
        sut.postAmens["p1"] = 3
        sut.postComments["p1"] = 7
        sut.postReposts["p1"] = 1
        sut.postLightbulbs["p1"] = 2

        let counts = await sut.getInteractionCounts(postId: "p1")
        XCTAssertEqual(counts.amenCount, 3)
        XCTAssertEqual(counts.commentCount, 7)
        XCTAssertEqual(counts.repostCount, 1)
        XCTAssertEqual(counts.lightbulbCount, 2)
    }

    func testShouldThrowPropagates() async {
        let sut = MockPostInteractionsService()
        sut.shouldThrow = true

        do {
            try await sut.toggleAmen(postId: "p1")
            XCTFail("Expected throw")
        } catch {
            XCTAssertNotNil(error)
        }
    }
}

// MARK: -

@MainActor
final class MockFollowServiceTests: XCTestCase {

    func testFollowUserAddsToSet() async throws {
        let sut = MockFollowService()
        try await sut.followUser(userId: "user2")
        XCTAssertTrue(sut.following.contains("user2"))
        XCTAssertEqual(sut.currentUserFollowingCount, 1)
    }

    func testUnfollowUserRemovesFromSet() async throws {
        let sut = MockFollowService()
        try await sut.followUser(userId: "user2")
        try await sut.unfollowUser(userId: "user2")
        XCTAssertFalse(sut.following.contains("user2"))
        XCTAssertEqual(sut.currentUserFollowingCount, 0)
    }

    func testFollowingCountDoesNotGoBelowZero() async throws {
        let sut = MockFollowService()
        sut.currentUserFollowingCount = 0
        try await sut.unfollowUser(userId: "nonexistent")
        XCTAssertEqual(sut.currentUserFollowingCount, 0)
    }

    func testToggleFollowRoundTrip() async throws {
        let sut = MockFollowService()
        try await sut.toggleFollow(userId: "user3")
        let following = await sut.isFollowing(userId: "user3")
        XCTAssertTrue(following)

        try await sut.toggleFollow(userId: "user3")
        let notFollowing = await sut.isFollowing(userId: "user3")
        XCTAssertFalse(notFollowing)
    }

    func testAreMutualFollowersRequiresBothDirections() async {
        let sut = MockFollowService()
        sut.following = ["user4"]
        // Not mutual — user4 doesn't follow back
        let mutual1 = await sut.areMutualFollowers(userId: "user4")
        XCTAssertFalse(mutual1)

        sut.followers = ["user4"]
        let mutual2 = await sut.areMutualFollowers(userId: "user4")
        XCTAssertTrue(mutual2)
    }
}

// MARK: -

@MainActor
final class MockNotificationServiceTests: XCTestCase {

    private func makeNotification(id: String, isRead: Bool = false) -> AppNotification {
        AppNotification(
            id: id,
            type: .newFollower,
            actorId: "actor",
            actorName: "Actor",
            actorProfileImageURL: nil,
            postId: nil,
            message: "test",
            isRead: isRead,
            timestamp: Date()
        )
    }

    func testMarkAsReadSetsFlag() async throws {
        let sut = MockNotificationService()
        sut.notifications = [makeNotification(id: "n1"), makeNotification(id: "n2")]
        sut.unreadCount = 2

        try await sut.markAsRead("n1")

        XCTAssertTrue(sut.notifications.first(where: { $0.id == "n1" })?.isRead == true)
        XCTAssertEqual(sut.unreadCount, 1)
    }

    func testMarkAllAsReadClearsCount() async throws {
        let sut = MockNotificationService()
        sut.notifications = [makeNotification(id: "n1"), makeNotification(id: "n2")]
        sut.unreadCount = 2

        try await sut.markAllAsRead()

        XCTAssertEqual(sut.unreadCount, 0)
        XCTAssertTrue(sut.notifications.allSatisfy { $0.isRead })
    }

    func testDeleteNotificationRemovesIt() async throws {
        let sut = MockNotificationService()
        sut.notifications = [makeNotification(id: "n1"), makeNotification(id: "n2")]

        try await sut.deleteNotification("n1")

        XCTAssertNil(sut.notifications.first(where: { $0.id == "n1" }))
        XCTAssertEqual(sut.notifications.count, 1)
    }

    func testDeleteAllReadKeepsUnread() async throws {
        let sut = MockNotificationService()
        sut.notifications = [
            makeNotification(id: "n1", isRead: true),
            makeNotification(id: "n2", isRead: false),
        ]

        try await sut.deleteAllRead()

        XCTAssertEqual(sut.notifications.count, 1)
        XCTAssertEqual(sut.notifications.first?.id, "n2")
    }

    func testRemoveNotificationsWherePredicateWorks() {
        let sut = MockNotificationService()
        sut.notifications = [makeNotification(id: "n1"), makeNotification(id: "n2")]
        sut.removeNotifications(where: { $0.id == "n1" })
        XCTAssertEqual(sut.notifications.count, 1)
    }
}

// MARK: - Test Helpers

private extension Post {
    static func makeTest(id: String) -> Post {
        Post(
            id: UUID(uuidString: id) ?? UUID(),
            authorId: "testAuthor",
            authorName: "Test Author",
            content: "Test content",
            category: .openTable,
            timestamp: Date(),
            isPrivate: false
        )
    }
}
