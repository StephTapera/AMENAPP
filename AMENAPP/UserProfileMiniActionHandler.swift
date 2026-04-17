//
//  UserProfileMiniActionHandler.swift
//  AMENAPP
//
//  Protocol-based service interfaces for UserProfileViewMini,
//  with lightweight live implementations that delegate to existing
//  AMEN services, and mock implementations for previews.
//

import Foundation
import FirebaseAuth

// MARK: - Follow Service Protocol

protocol UserProfileMiniFollowServicing {
    /// Follow the user. Throws on failure.
    func follow(userId: String) async throws
    /// Unfollow the user. Throws on failure.
    func unfollow(userId: String) async throws
    /// Whether the current user already follows this userId.
    func isFollowing(userId: String) -> Bool
}

// MARK: - Messaging Service Protocol

protocol UserProfileMiniMessagingServicing {
    /// Whether the current user can open a DM with this userId.
    func canMessage(userId: String) -> Bool
    /// Open a conversation with this userId. Throws on routing failure.
    func openConversation(userId: String, displayName: String) async throws
}

// MARK: - Analytics Protocol

protocol UserProfileMiniAnalyticsServicing {
    func track(_ event: UserMiniAnalyticsEvent)
}

// MARK: - Routing Protocol

protocol UserProfileMiniRouting {
    /// Navigate to the full profile for this userId.
    func openProfile(userId: String)
    /// Navigate to a post (e.g. testimony).
    func openPost(postId: String)
    /// Navigate to an existing or newly created DM conversation.
    func openConversation(conversationId: String)
    /// Present a lightweight feedback surface when messaging is unavailable.
    func showMessagingUnavailable(reason: String)
}

// MARK: - Live Implementations

/// Thin wrapper over the existing FollowService singleton.
struct LiveUserProfileMiniFollowService: UserProfileMiniFollowServicing {
    func follow(userId: String) async throws {
        try await FollowService.shared.followUser(userId: userId)
    }

    func unfollow(userId: String) async throws {
        try await FollowService.shared.unfollowUser(userId: userId)
    }

    func isFollowing(userId: String) -> Bool {
        FollowService.shared.following.contains(userId)
    }
}

struct LiveUserProfileMiniRouting: UserProfileMiniRouting {
    let onOpenProfile: (String) -> Void
    let onOpenPost: ((String) -> Void)?
    let onMessagingUnavailable: ((String) -> Void)?

    func openProfile(userId: String) {
        onOpenProfile(userId)
    }

    func openPost(postId: String) {
        onOpenPost?(postId)
    }

    func openConversation(conversationId: String) {
        MessagingCoordinator.shared.openConversation(conversationId)
    }

    func showMessagingUnavailable(reason: String) {
        onMessagingUnavailable?(reason)
    }
}

struct LiveUserProfileMiniMessagingService: UserProfileMiniMessagingServicing {
    let router: any UserProfileMiniRouting

    func canMessage(userId: String) -> Bool {
        guard let currentUserId = Auth.auth().currentUser?.uid, currentUserId != userId else {
            return false
        }
        return true
    }

    func openConversation(userId: String, displayName: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid, currentUserId != userId else {
            router.showMessagingUnavailable(reason: "You can’t start a conversation with this profile right now.")
            throw URLError(.userAuthenticationRequired)
        }

        let rateLimit = await AMENTrustScoreService.shared.checkRateLimit(for: currentUserId, isNewConversation: true)
        switch rateLimit {
        case .allowed:
            break
        case .exceeded(let message), .replyOnly(let message):
            await MainActor.run {
                router.showMessagingUnavailable(reason: message)
            }
            throw URLError(.cannotConnectToHost)
        }

        let conversationId = try await FirebaseMessagingService.shared.getOrCreateDirectConversation(
            withUserId: userId,
            userName: displayName
        )
        await AMENTrustScoreService.shared.recordNewConversationInitiated(by: currentUserId)
        await MainActor.run {
            router.openConversation(conversationId: conversationId)
        }
    }
}

/// No-op analytics for now; replace with AMENAnalyticsService call when ready.
struct LiveUserProfileMiniAnalytics: UserProfileMiniAnalyticsServicing {
    func track(_ event: UserMiniAnalyticsEvent) {
        dlog("UserProfileMini[\(event.source.rawValue)] \(event.kind.rawValue) userId=\(event.userId)")
    }
}

// MARK: - Mock Implementations (for previews)

struct MockUserProfileMiniFollowService: UserProfileMiniFollowServicing {
    var followDelay: Duration = .milliseconds(600)
    var shouldFail: Bool = false

    func follow(userId: String) async throws {
        try await Task.sleep(for: followDelay)
        if shouldFail { throw URLError(.networkConnectionLost) }
    }

    func unfollow(userId: String) async throws {
        try await Task.sleep(for: followDelay)
    }

    func isFollowing(userId: String) -> Bool { false }
}

struct MockUserProfileMiniMessagingService: UserProfileMiniMessagingServicing {
    var messagingAllowed: Bool = true
    func canMessage(userId: String) -> Bool { messagingAllowed }
    func openConversation(userId: String, displayName: String) async throws {}
}

struct MockUserProfileMiniAnalytics: UserProfileMiniAnalyticsServicing {
    func track(_ event: UserMiniAnalyticsEvent) {}
}

struct MockUserProfileMiniRouting: UserProfileMiniRouting {
    var onOpenProfile: (String) -> Void = { _ in }
    var onOpenPost: (String) -> Void = { _ in }
    var onOpenConversation: (String) -> Void = { _ in }
    var onMessagingUnavailable: (String) -> Void = { _ in }

    func openProfile(userId: String) { onOpenProfile(userId) }
    func openPost(postId: String) { onOpenPost(postId) }
    func openConversation(conversationId: String) { onOpenConversation(conversationId) }
    func showMessagingUnavailable(reason: String) { onMessagingUnavailable(reason) }
}

// MARK: - Action Handler Aggregate

/// Bundles all service dependencies for injection into the view model.
struct UserProfileMiniActionHandler {
    let followService: any UserProfileMiniFollowServicing
    let messagingService: any UserProfileMiniMessagingServicing
    let analytics: any UserProfileMiniAnalyticsServicing
    let routing: any UserProfileMiniRouting
    let onHide: ((String) -> Void)?

    static func live(
        onOpenProfile: @escaping (String) -> Void,
        onOpenPost: ((String) -> Void)? = nil,
        onMessagingUnavailable: ((String) -> Void)? = nil,
        onHide: ((String) -> Void)? = nil
    ) -> UserProfileMiniActionHandler {
        let routing = LiveUserProfileMiniRouting(
            onOpenProfile: onOpenProfile,
            onOpenPost: onOpenPost,
            onMessagingUnavailable: onMessagingUnavailable
        )
        return UserProfileMiniActionHandler(
            followService: LiveUserProfileMiniFollowService(),
            messagingService: LiveUserProfileMiniMessagingService(router: routing),
            analytics: LiveUserProfileMiniAnalytics(),
            routing: routing,
            onHide: onHide
        )
    }

    static func mock(
        messagingAllowed: Bool = true,
        followShouldFail: Bool = false,
        onOpenProfile: @escaping (String) -> Void = { _ in },
        onOpenPost: @escaping (String) -> Void = { _ in },
        onOpenConversation: @escaping (String) -> Void = { _ in },
        onMessagingUnavailable: @escaping (String) -> Void = { _ in },
        onHide: ((String) -> Void)? = nil
    ) -> UserProfileMiniActionHandler {
        let routing = MockUserProfileMiniRouting(
            onOpenProfile: onOpenProfile,
            onOpenPost: onOpenPost,
            onOpenConversation: onOpenConversation,
            onMessagingUnavailable: onMessagingUnavailable
        )
        return UserProfileMiniActionHandler(
            followService: MockUserProfileMiniFollowService(shouldFail: followShouldFail),
            messagingService: MockUserProfileMiniMessagingService(messagingAllowed: messagingAllowed),
            analytics: MockUserProfileMiniAnalytics(),
            routing: routing,
            onHide: onHide
        )
    }
}
