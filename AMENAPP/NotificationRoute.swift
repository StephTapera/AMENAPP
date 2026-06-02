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
    case churchPage(churchID: String)
    case walkWithChrist

    // Failure states
    case unavailable(reason: String)
    case fallback

    // MARK: - Fallback Route Chain

    /// Returns a less-specific route to try when the primary navigation target
    /// is unavailable (deleted post, blocked user, etc.).
    /// Chain: postReply → postComment → post → fallback
    var fallbackRoute: NotificationRoute {
        switch self {
        case .postReply(let postID, let parentCommentID, _):
            return .postComment(postID: postID, commentID: parentCommentID)
        case .postComment(let postID, _):
            return .post(postID: postID)
        case .mentionInComment(let postID, _):
            return .post(postID: postID)
        case .post:
            return .fallback
        case .profile:
            return .fallback
        case .conversation:
            return .fallback
        case .prayer:
            return .fallback
        case .churchNote:
            return .fallback
        case .churchPage:
            return .fallback
        case .walkWithChrist:
            return .fallback
        case .followRequests, .unavailable, .fallback:
            return .fallback
        }
    }
}

// MARK: - NotificationRouteResolver

/// Translates an AppNotification into a NotificationRoute.
/// Single source of truth — do NOT add routing logic elsewhere.
enum NotificationRouteResolver {
    static func resolve(_ notification: AppNotification) -> NotificationRoute {
        // V2: If server provided explicit routing, use it
        if let routeType = notification.targetRouteType,
           let payload = notification.routePayload {
            if let route = resolveFromServerRoute(type: routeType, payload: payload) {
                return route
            }
        }

        // V1 fallback: derive route from notification fields
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

        case .actionThreadInvite, .actionThreadUpdate, .actionThreadReminder:
            // Action thread notifications link to the parent post
            guard let postId = notification.postId, !postId.isEmpty else { return .fallback }
            return .post(postID: postId)

        case .unknown:
            return .fallback
        }
    }

    /// Resolves a NotificationRoute from server-provided route type and payload.
    /// Returns nil if the route type is unknown (client should fall back to v1 resolution).
    static func resolveFromServerRoute(type: String, payload: [String: String]) -> NotificationRoute? {
        switch type {
        case "post":
            guard let postId = payload["postId"], !postId.isEmpty else { return nil }
            return .post(postID: postId)
        case "post_comment":
            guard let postId = payload["postId"], !postId.isEmpty,
                  let commentId = payload["commentId"], !commentId.isEmpty else { return nil }
            return .postComment(postID: postId, commentID: commentId)
        case "post_reply":
            guard let postId = payload["postId"], !postId.isEmpty,
                  let commentId = payload["commentId"], !commentId.isEmpty else { return nil }
            let parentId = payload["parentCommentId"] ?? commentId
            return .postReply(postID: postId, parentCommentID: parentId, replyID: commentId)
        case "mention_in_comment":
            guard let postId = payload["postId"], !postId.isEmpty,
                  let commentId = payload["commentId"], !commentId.isEmpty else { return nil }
            return .mentionInComment(postID: postId, commentID: commentId)
        case "profile":
            guard let userId = payload["userId"], !userId.isEmpty else { return nil }
            return .profile(userID: userId)
        case "conversation":
            guard let convId = payload["conversationId"], !convId.isEmpty else { return nil }
            return .conversation(conversationID: convId)
        case "follow_requests":
            return .followRequests
        case "prayer":
            guard let prayerId = payload["prayerId"], !prayerId.isEmpty else { return nil }
            return .prayer(prayerID: prayerId)
        case "church_note":
            guard let noteId = payload["noteId"], !noteId.isEmpty else { return nil }
            return .churchNote(noteID: noteId)
        case "church_page":
            guard let churchId = payload["churchId"], !churchId.isEmpty else { return nil }
            return .churchPage(churchID: churchId)
        case "walk_with_christ":
            return .walkWithChrist
        case "notifications_inbox":
            return .fallback
        default:
            return nil
        }
    }

    /// Resolves fallback route from server-provided fallback fields on a notification.
    static func resolveFallbackRoute(_ notification: AppNotification) -> NotificationRoute {
        if let fallbackType = notification.fallbackRouteType,
           let fallbackPayload = notification.fallbackRoutePayload,
           let route = resolveFromServerRoute(type: fallbackType, payload: fallbackPayload) {
            return route
        }
        // If no server fallback, use the computed fallback chain
        let primaryRoute = resolve(notification)
        return primaryRoute.fallbackRoute
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

        case .churchPage:
            NotificationDeepLinkRouter.shared.navigate(to: .notifications)

        case .walkWithChrist:
            NotificationCenter.default.post(name: .openWalkWithChristFromNotification, object: nil)

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
