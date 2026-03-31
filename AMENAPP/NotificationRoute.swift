//
//  NotificationRoute.swift
//  AMENAPP
//
//  Unified notification routing layer.
//  ALL notification taps — in-app rows, push callbacks, grouped children — flow through here.
//  Nothing outside this file should contain routing switch statements for notifications.
//

import SwiftUI
import Combine

// MARK: - NotificationRoute

/// Strongly-typed route for every notification destination.
/// Covers the full taxonomy: post, comment, reply, mention, profile, conversation, etc.
enum NotificationRoute: Equatable {
    // Post-level destinations
    case post(postID: String)
    case postComment(postID: String, commentID: String)
    case postReply(postID: String, parentCommentID: String, replyID: String)
    case mentionInComment(postID: String, commentID: String)

    // Profile
    case profile(userID: String)

    // Messaging
    case conversation(conversationID: String)

    // Social
    case followRequests

    // AMEN-specific
    case prayer(prayerID: String)
    case churchNote(noteID: String)

    // Failure states
    case unavailable(reason: String)
    case fallback
}

// MARK: - NotificationRouteResolver

/// Translates an AppNotification into a NotificationRoute.
/// Single source of truth — do NOT add routing logic elsewhere.
enum NotificationRouteResolver {
    static func resolve(_ notification: AppNotification) -> NotificationRoute {
        switch notification.type {

        case .follow, .followRequestAccepted:
            guard let actorId = notification.actorId, !actorId.isEmpty else { return .fallback }
            return .profile(userID: actorId)

        case .amen, .repost:
            guard let postId = notification.postId, !postId.isEmpty else { return .fallback }
            return .post(postID: postId)

        case .comment:
            guard let postId = notification.postId, !postId.isEmpty else { return .fallback }
            if let commentId = notification.commentId, !commentId.isEmpty {
                return .postComment(postID: postId, commentID: commentId)
            }
            return .post(postID: postId)

        case .reply:
            guard let postId = notification.postId, !postId.isEmpty else { return .fallback }
            // Full reply route when we have both parent + reply IDs
            if let replyId = notification.commentId, !replyId.isEmpty {
                // parentCommentId property removed - simplified routing
                return .postComment(postID: postId, commentID: replyId)
            }
            // Fallback: have at least the target comment
            if let commentId = notification.commentId, !commentId.isEmpty {
                return .postComment(postID: postId, commentID: commentId)
            }
            return .post(postID: postId)

        case .mention:
            guard let postId = notification.postId, !postId.isEmpty else { return .fallback }
            if let commentId = notification.commentId, !commentId.isEmpty {
                return .mentionInComment(postID: postId, commentID: commentId)
            }
            return .post(postID: postId)

        case .message, .messageRequest, .messageRequestAccepted:
            guard let convId = notification.conversationId, !convId.isEmpty else { return .fallback }
            return .conversation(conversationID: convId)

        case .prayerReminder, .prayerAnswered, .prayerSupported:
            guard let prayerId = notification.prayerId, !prayerId.isEmpty else { return .fallback }
            return .prayer(prayerID: prayerId)

        case .churchNoteShared, .churchNoteReplied:
            guard let noteId = notification.noteId, !noteId.isEmpty else { return .fallback }
            return .churchNote(noteID: noteId)

        case .unknown:
            return .fallback
        }
    }
}

// MARK: - NotificationTapHandler

/// Central tap handler for ALL notification entry points.
/// In-app rows pass their `navigationPath` binding so the nav stack stays inside the Notifications tab.
/// Push notifications (and cross-tab destinations) pass nil — the DeepLinkRouter handles tab switching.
@MainActor
final class NotificationTapHandler {
    static let shared = NotificationTapHandler()
    private init() {}

    /// Primary entry point. Call from both in-app rows and push notification callbacks.
    func handle(
        _ notification: AppNotification,
        navigationPath: Binding<[NotificationNavigationDestinations.NotificationDestination]>? = nil
    ) {
        // 1. Optimistic read mark
        if !notification.read, let notifId = notification.id, !notifId.isEmpty {
            Task {
                try? await NotificationService.shared.markAsRead(notifId)
            }
        }

        // 2. Resolve
        let route = NotificationRouteResolver.resolve(notification)
        dlog("🔔 [ROUTE] \(notification.type.rawValue) → \(route)")

        // 3. Execute
        execute(route, navigationPath: navigationPath)
    }

    /// Execute a pre-resolved route. Can be called directly from push payload handlers.
    func execute(
        _ route: NotificationRoute,
        navigationPath: Binding<[NotificationNavigationDestinations.NotificationDestination]>? = nil
    ) {
        switch route {

        // ── Post (no comment target) ──────────────────────────────────────
        case .post(let postID):
            if let path = navigationPath {
                path.wrappedValue.append(.post(postId: postID))
            } else {
                NotificationDeepLinkRouter.shared.navigate(to: .post(postId: postID))
            }

        // ── Post + scroll to specific comment ────────────────────────────
        case .postComment(let postID, let commentID):
            if let path = navigationPath {
                CommentFocusCoordinator.shared.set(
                    scrollTarget: commentID,
                    highlight: commentID
                )
                path.wrappedValue.append(.post(postId: postID))
            } else {
                NotificationDeepLinkRouter.shared.navigate(
                    to: .post(postId: postID, scrollToCommentId: commentID)
                )
            }

        // ── Post + expand thread + scroll to reply ────────────────────────
        case .postReply(let postID, let parentCommentID, let replyID):
            if let path = navigationPath {
                // Use postWithComment and let the view handle the reply/expand logic via CommentFocusCoordinator
                CommentFocusCoordinator.shared.set(
                    scrollTarget: replyID,
                    highlight: replyID,
                    expandThread: parentCommentID
                )
                path.wrappedValue.append(.post(postId: postID))
            } else {
                NotificationDeepLinkRouter.shared.navigate(
                    to: .post(postId: postID, scrollToCommentId: replyID)
                )
            }

        // ── Mention inside a comment ──────────────────────────────────────
        case .mentionInComment(let postID, let commentID):
            if let path = navigationPath {
                CommentFocusCoordinator.shared.set(
                    scrollTarget: commentID,
                    highlight: commentID
                )
                path.wrappedValue.append(.post(postId: postID))
            } else {
                NotificationDeepLinkRouter.shared.navigate(
                    to: .post(postId: postID, scrollToCommentId: commentID)
                )
            }

        // ── Profile ───────────────────────────────────────────────────────
        case .profile(let userID):
            if let path = navigationPath {
                path.wrappedValue.append(.profile(userId: userID))
            } else {
                NotificationDeepLinkRouter.shared.navigate(to: .profile(userId: userID))
            }

        // ── Conversation (always cross-tab) ───────────────────────────────
        case .conversation(let convID):
            NotificationDeepLinkRouter.shared.navigate(to: .conversation(conversationId: convID))

        // ── Follow requests ────────────────────────────────────────────────
        case .followRequests:
            NotificationCenter.default.post(name: .amenShowFollowRequests, object: nil)

        // ── Prayer / Church Notes (cross-tab) ─────────────────────────────
        case .prayer(let prayerID):
            NotificationDeepLinkRouter.shared.navigate(to: .prayer(prayerId: prayerID))

        case .churchNote(let noteID):
            NotificationDeepLinkRouter.shared.navigate(to: .churchNote(noteId: noteID))

        // ── Unavailable content ────────────────────────────────────────────
        case .unavailable(let reason):
            dlog("⚠️ [ROUTE] Content unavailable: \(reason)")
            NotificationCenter.default.post(
                name: .amenNotificationRouteUnavailable,
                object: nil,
                userInfo: ["reason": reason]
            )

        // ── Fallback ───────────────────────────────────────────────────────
        case .fallback:
            NotificationDeepLinkRouter.shared.navigate(to: .notifications)
        }
    }
}

// MARK: - CommentFocusCoordinator

/// Carries pending comment scroll/highlight/expand state across the post navigation.
/// PostDetailView / CommentsView should observe this on appear and consume the pending state.
@MainActor
final class CommentFocusCoordinator: ObservableObject {
    static let shared = CommentFocusCoordinator()
    private init() {}

    @Published var pendingScrollTarget: String?    // commentID to scroll to
    @Published var pendingHighlightTarget: String? // commentID to briefly highlight
    @Published var pendingExpandCommentID: String? // parentCommentID whose replies should be expanded

    /// Set all pending targets atomically.
    func set(scrollTarget: String?, highlight: String?, expandThread: String? = nil) {
        pendingScrollTarget = scrollTarget
        pendingHighlightTarget = highlight
        pendingExpandCommentID = expandThread
    }

    /// Consume pending state (call once from the destination view's onAppear).
    /// Returns the values and clears them so they don't re-fire on re-appear.
    func consume() -> (scroll: String?, highlight: String?, expand: String?) {
        defer {
            pendingScrollTarget = nil
            pendingHighlightTarget = nil
            pendingExpandCommentID = nil
        }
        return (pendingScrollTarget, pendingHighlightTarget, pendingExpandCommentID)
    }
}

// MARK: - Notification.Name extensions

extension Notification.Name {
    static let amenShowFollowRequests         = Notification.Name("amen.showFollowRequests")
    static let amenNotificationRouteUnavailable = Notification.Name("amen.notificationRouteUnavailable")
}
