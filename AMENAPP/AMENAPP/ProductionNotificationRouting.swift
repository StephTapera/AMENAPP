//
//  ProductionNotificationRouting.swift
//  AMENAPP
//
//  Production-grade notification routing foundation for push taps,
//  in-app notification opens, and compatible deep-link entry.
//

import Foundation
import Combine
import UserNotifications
import FirebaseAuth
import FirebaseFirestore

enum NotificationPayloadVersion: String, Codable {
    case legacy = "1"
    case v2 = "2"
    case v3 = "3"
}

enum NotificationOpenSource: String, Codable {
    case pushTap
    case foregroundPush
    case inAppNotificationCenter
    case universalLink
    case internalAction
}

enum NotificationOpenBehavior: String, Codable {
    case directOpen
    case guardedOpen
    case inboxOpen
    case softPrompt
}

enum ContentVisibilityState: String, Codable {
    case visible
    case deleted
    case privateNow
    case blocked
    case restricted
    case unknown
}

enum SafetyRoutingState: String, Codable {
    case clear
    case guarded
    case restricted
    case moderated
}

enum FallbackRoute: Equatable {
    case notificationsInbox
    case unavailable(reason: String)
    case restrictedShell(reason: String)

    var notificationRoute: NotificationRoute {
        switch self {
        case .notificationsInbox:
            return .fallback
        case .unavailable(let reason):
            return .unavailable(reason: reason)
        case .restrictedShell(let reason):
            return .unavailable(reason: reason)
        }
    }
}

enum RouteGuardOutcome: Equatable {
    case allow
    case guarded(SafetyRoutingState, NotificationRoute)
    case deny(reason: String, fallback: FallbackRoute)
}

struct RouteIntent: Codable, Equatable, Identifiable {
    let id: String
    let source: NotificationOpenSource
    let payloadVersion: NotificationPayloadVersion
    let notificationId: String?
    let type: String?
    let targetRouteType: String?
    let routePayload: [String: String]
    let fallbackRouteType: String?
    let fallbackRoutePayload: [String: String]
    let behavior: NotificationOpenBehavior
    let safetyState: SafetyRoutingState
    let receivedAt: Date

    init(
        id: String = UUID().uuidString,
        source: NotificationOpenSource,
        payloadVersion: NotificationPayloadVersion,
        notificationId: String?,
        type: String?,
        targetRouteType: String?,
        routePayload: [String: String],
        fallbackRouteType: String?,
        fallbackRoutePayload: [String: String],
        behavior: NotificationOpenBehavior,
        safetyState: SafetyRoutingState,
        receivedAt: Date = .now
    ) {
        self.id = id
        self.source = source
        self.payloadVersion = payloadVersion
        self.notificationId = notificationId
        self.type = type
        self.targetRouteType = targetRouteType
        self.routePayload = routePayload
        self.fallbackRouteType = fallbackRouteType
        self.fallbackRoutePayload = fallbackRoutePayload
        self.behavior = behavior
        self.safetyState = safetyState
        self.receivedAt = receivedAt
    }
}

struct ResolvedRoute: Equatable {
    let route: NotificationRoute
    let source: NotificationOpenSource
    let notificationId: String?
    let behavior: NotificationOpenBehavior
    let visibilityState: ContentVisibilityState
}

enum RouteResolutionResult: Equatable {
    case resolved(ResolvedRoute)
    case fallback(ResolvedRoute, reason: String)
    case blocked(FallbackRoute, reason: String)
}

@MainActor
final class PendingRouteStore: ObservableObject {
    static let shared = PendingRouteStore()

    @Published private(set) var pendingIntent: RouteIntent?

    private let defaultsKey = "amen.pending.notification.route.intent.v1"

    private init() {
        restore()
    }

    func set(_ intent: RouteIntent) {
        pendingIntent = intent
        persist(intent)
    }

    func clear() {
        pendingIntent = nil
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    private func restore() {
        guard
            let data = UserDefaults.standard.data(forKey: defaultsKey),
            let intent = try? JSONDecoder().decode(RouteIntent.self, from: data)
        else {
            return
        }
        pendingIntent = intent
    }

    private func persist(_ intent: RouteIntent) {
        guard let data = try? JSONEncoder().encode(intent) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}

enum NotificationIntentDecoder {
    static func decode(
        userInfo: [AnyHashable: Any],
        source: NotificationOpenSource
    ) -> RouteIntent? {
        let version = NotificationPayloadVersion(rawValue: stringValue(userInfo["schemaVersion"]) ?? "1") ?? .legacy
        let notificationId = stringValue(userInfo["notificationId"])
        let type = stringValue(userInfo["type"])
        let targetRouteType = stringValue(userInfo["targetRouteType"])
        let fallbackRouteType = stringValue(userInfo["fallbackRouteType"])

        let routePayload = decodePayloadDictionary(userInfo["routePayload"]) ?? extractLegacyPayload(userInfo)
        let fallbackPayload = decodePayloadDictionary(userInfo["fallbackRoutePayload"]) ?? [:]

        let behavior = NotificationOpenBehavior(rawValue: stringValue(userInfo["openBehavior"]) ?? "") ?? defaultBehavior(for: type)
        let safetyState = SafetyRoutingState(rawValue: stringValue(userInfo["safetyState"]) ?? "") ?? .clear

        guard notificationId != nil || type != nil || targetRouteType != nil else {
            return nil
        }

        return RouteIntent(
            source: source,
            payloadVersion: version,
            notificationId: notificationId,
            type: type,
            targetRouteType: targetRouteType,
            routePayload: routePayload,
            fallbackRouteType: fallbackRouteType,
            fallbackRoutePayload: fallbackPayload,
            behavior: behavior,
            safetyState: safetyState
        )
    }

    private static func extractLegacyPayload(_ userInfo: [AnyHashable: Any]) -> [String: String] {
        var payload: [String: String] = [:]
        [
            "postId",
            "commentId",
            "parentCommentId",
            "conversationId",
            "messageId",
            "actorId",
            "userId",
            "prayerId",
            "noteId"
        ].forEach { key in
            if let value = stringValue(userInfo[key]) {
                payload[key] = value
            }
        }
        return payload
    }

    private static func decodePayloadDictionary(_ value: Any?) -> [String: String]? {
        if let dictionary = value as? [String: String] {
            return dictionary
        }

        if let jsonString = value as? String,
           let data = jsonString.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var result: [String: String] = [:]
            object.forEach { key, value in
                result[key] = String(describing: value)
            }
            return result
        }

        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String, !string.isEmpty {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private static func defaultBehavior(for type: String?) -> NotificationOpenBehavior {
        switch type {
        case "message_request", "safety_guarded_message_event", "restricted_interaction_notice":
            return .guardedOpen
        case "moderation_update", "account_warning", "appeal_update":
            return .inboxOpen
        default:
            return .directOpen
        }
    }
}

@MainActor
final class NotificationAnalyticsTracker {
    static let shared = NotificationAnalyticsTracker()

    private init() {}

    func track(_ event: String, notificationId: String?, metadata: [String: String] = [:]) {
        dlog("📊 NotificationAnalytics: \(event) notificationId=\(notificationId ?? "nil") metadata=\(metadata)")

        guard let userId = Auth.auth().currentUser?.uid else { return }

        Task {
            let data: [String: Any] = [
                "event": event,
                "notificationId": notificationId as Any,
                "metadata": metadata,
                "userId": userId,
                "createdAt": FieldValue.serverTimestamp()
            ]

            try? await Firestore.firestore()
                .collection("users")
                .document(userId)
                .collection("notification_open_events")
                .document()
                .setData(data)
        }
    }
}

@MainActor
struct NotificationRouteGuard {
    func evaluate(intent: RouteIntent, notification: AppNotification?, route: NotificationRoute) -> RouteGuardOutcome {
        guard Auth.auth().currentUser != nil else {
            return .deny(reason: "not_authenticated", fallback: .notificationsInbox)
        }

        if notification?.invalidTarget == true {
            return .deny(reason: "invalid_target", fallback: .unavailable(reason: "Content is no longer available."))
        }

        if intent.behavior == .inboxOpen {
            return .deny(reason: "inbox_only", fallback: .notificationsInbox)
        }

        if intent.behavior == .guardedOpen || intent.safetyState == .guarded || intent.safetyState == .moderated {
            return .guarded(.guarded, route)
        }

        return .allow
    }
}

@MainActor
final class NotificationResolver {
    static let shared = NotificationResolver()

    private let db = Firestore.firestore()
    private let routeGuard = NotificationRouteGuard()

    private init() {}

    func resolve(intent: RouteIntent) async -> RouteResolutionResult {
        let canonicalNotification = await fetchCanonicalNotification(notificationId: intent.notificationId)

        let primaryRoute = primaryRoute(for: intent, notification: canonicalNotification) ?? .fallback
        let guardOutcome = routeGuard.evaluate(intent: intent, notification: canonicalNotification, route: primaryRoute)

        switch guardOutcome {
        case .allow:
            return .resolved(
                ResolvedRoute(
                    route: primaryRoute,
                    source: intent.source,
                    notificationId: intent.notificationId,
                    behavior: intent.behavior,
                    visibilityState: canonicalNotification?.invalidTarget == true ? .deleted : .visible
                )
            )

        case .guarded:
            return .resolved(
                ResolvedRoute(
                    route: primaryRoute,
                    source: intent.source,
                    notificationId: intent.notificationId,
                    behavior: .guardedOpen,
                    visibilityState: .restricted
                )
            )

        case .deny(let reason, let fallback):
            let route = fallback.notificationRoute
            return .fallback(
                ResolvedRoute(
                    route: route,
                    source: intent.source,
                    notificationId: intent.notificationId,
                    behavior: .inboxOpen,
                    visibilityState: .restricted
                ),
                reason: reason
            )
        }
    }

    private func primaryRoute(for intent: RouteIntent, notification: AppNotification?) -> NotificationRoute? {
        if let routeType = intent.targetRouteType,
           let route = NotificationRouteResolver.resolveFromServerRoute(type: routeType, payload: intent.routePayload) {
            return route
        }

        if let notification {
            return NotificationRouteResolver.resolve(notification)
        }

        guard let type = intent.type else { return nil }
        return legacyRoute(type: type, payload: intent.routePayload)
    }

    private func legacyRoute(type: String, payload: [String: String]) -> NotificationRoute? {
        switch type {
        case "follow", "follow_request_accepted":
            guard let actorId = payload["actorId"] ?? payload["userId"] else { return .fallback }
            return .profile(userID: actorId)
        case "comment":
            guard let postId = payload["postId"] else { return .fallback }
            if let commentId = payload["commentId"] {
                return .postComment(postID: postId, commentID: commentId)
            }
            return .post(postID: postId)
        case "reply":
            guard let postId = payload["postId"] else { return .fallback }
            if let commentId = payload["commentId"] {
                return .postReply(
                    postID: postId,
                    parentCommentID: payload["parentCommentId"] ?? commentId,
                    replyID: commentId
                )
            }
            return .post(postID: postId)
        case "mention":
            guard let postId = payload["postId"] else { return .fallback }
            if let commentId = payload["commentId"] {
                return .mentionInComment(postID: postId, commentID: commentId)
            }
            return .post(postID: postId)
        case "message", "message_request", "message_request_accepted":
            guard let conversationId = payload["conversationId"] else { return .fallback }
            return .conversation(conversationID: conversationId)
        case "prayer_reminder", "prayer_answered":
            guard let prayerId = payload["prayerId"] else { return .fallback }
            return .prayer(prayerID: prayerId)
        case "church_note_shared", "church_note_replied":
            guard let noteId = payload["noteId"] else { return .fallback }
            return .churchNote(noteID: noteId)
        default:
            if let postId = payload["postId"] {
                return .post(postID: postId)
            }
            return .fallback
        }
    }

    private func fetchCanonicalNotification(notificationId: String?) async -> AppNotification? {
        guard
            let notificationId,
            let userId = Auth.auth().currentUser?.uid
        else {
            return nil
        }

        do {
            let snapshot = try await db
                .collection("users")
                .document(userId)
                .collection("notifications")
                .document(notificationId)
                .getDocument()

            guard let data = snapshot.data() else { return nil }
            return AppNotification(documentID: snapshot.documentID, data: data)
        } catch {
            dlog("⚠️ NotificationResolver fetch failed: \(error)")
            return nil
        }
    }
}

@MainActor
final class NotificationOpenCoordinator: ObservableObject {
    static let shared = NotificationOpenCoordinator()

    @Published private(set) var lastResolvedRoute: ResolvedRoute?

    private let pendingStore = PendingRouteStore.shared
    private let resolver = NotificationResolver.shared
    private let analytics = NotificationAnalyticsTracker.shared

    private var appReady = false
    private var activeIntentID: String?

    private init() {}

    func markAppReady() {
        appReady = true
        Task {
            await processPendingIntentIfPossible()
        }
    }

    func handleNotificationResponse(_ response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        guard let intent = NotificationIntentDecoder.decode(userInfo: userInfo, source: .pushTap) else {
            analytics.track("notification_tap_decode_failed", notificationId: nil)
            NotificationTapHandler.shared.execute(.fallback)
            return
        }

        pendingStore.set(intent)
        analytics.track("notification_tapped", notificationId: intent.notificationId, metadata: [
            "source": intent.source.rawValue,
            "version": intent.payloadVersion.rawValue
        ])

        await processPendingIntentIfPossible()
    }

    func handleUserInfo(_ userInfo: [AnyHashable: Any], source: NotificationOpenSource) async {
        guard let intent = NotificationIntentDecoder.decode(userInfo: userInfo, source: source) else { return }
        pendingStore.set(intent)
        await processPendingIntentIfPossible()
    }

    func handleURL(_ url: URL) async -> Bool {
        guard let intent = RouteIntent(url: url) else { return false }
        pendingStore.set(intent)
        await processPendingIntentIfPossible()
        return true
    }

    func processPendingIntentIfPossible() async {
        guard appReady, let intent = pendingStore.pendingIntent else { return }
        guard activeIntentID != intent.id else { return }

        if Auth.auth().currentUser == nil {
            analytics.track("notification_waiting_for_auth", notificationId: intent.notificationId)
            return
        }

        activeIntentID = intent.id
        analytics.track("route_resolution_started", notificationId: intent.notificationId)

        let result = await resolver.resolve(intent: intent)

        switch result {
        case .resolved(let resolvedRoute):
            execute(resolvedRoute, analyticsEvent: "route_resolution_succeeded")

        case .fallback(let resolvedRoute, let reason):
            execute(resolvedRoute, analyticsEvent: "route_resolution_fallback", extra: ["reason": reason])

        case .blocked(let fallback, let reason):
            analytics.track("route_resolution_blocked", notificationId: intent.notificationId, metadata: ["reason": reason])
            let route = fallback.notificationRoute
            NotificationTapHandler.shared.execute(route)
        }

        if let notificationId = intent.notificationId {
            Task {
                try? await NotificationService.shared.markAsRead(notificationId)
            }
        }

        pendingStore.clear()
        activeIntentID = nil
    }

    private func execute(
        _ resolvedRoute: ResolvedRoute,
        analyticsEvent: String,
        extra: [String: String] = [:]
    ) {
        lastResolvedRoute = resolvedRoute
        NotificationTapHandler.shared.execute(resolvedRoute.route)

        var metadata = extra
        metadata["behavior"] = resolvedRoute.behavior.rawValue
        metadata["visibilityState"] = resolvedRoute.visibilityState.rawValue
        analytics.track(analyticsEvent, notificationId: resolvedRoute.notificationId, metadata: metadata)
    }
}

@MainActor
final class NotificationTapBootstrapper {
    static let shared = NotificationTapBootstrapper()

    private init() {}

    func appDidBecomeReady() {
        NotificationOpenCoordinator.shared.markAppReady()
    }

    func resumePendingRoute() async {
        await NotificationOpenCoordinator.shared.processPendingIntentIfPossible()
    }
}

extension RouteIntent {
    init?(url: URL) {
        let host = url.host ?? ""
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        let isAmenScheme = url.scheme == "amenapp" || url.scheme == "com.amenapp"
        let isAmenUniversalLink = (url.scheme == "https" || url.scheme == "http") && (url.host?.hasSuffix("amenapp.com") ?? false)

        guard isAmenScheme || isAmenUniversalLink else { return nil }

        var targetRouteType: String?
        var payload: [String: String] = [:]
        var type: String?

        if isAmenUniversalLink {
            switch pathComponents.first {
            case "post":
                guard pathComponents.count >= 2 else { return nil }
                payload["postId"] = pathComponents[1]
                if let commentId = url.queryParameters["commentId"] {
                    payload["commentId"] = commentId
                    targetRouteType = "post_comment"
                    type = "comment"
                } else {
                    targetRouteType = "post"
                    type = "amen"
                }
            case "profile":
                guard pathComponents.count >= 2 else { return nil }
                payload["userId"] = pathComponents[1]
                targetRouteType = "profile"
                type = "follow"
            case "conversation":
                guard pathComponents.count >= 2 else { return nil }
                payload["conversationId"] = pathComponents[1]
                targetRouteType = "conversation"
                type = "message"
            case "prayer":
                guard pathComponents.count >= 2 else { return nil }
                payload["prayerId"] = pathComponents[1]
                targetRouteType = "prayer"
                type = "prayer_answered"
            case "church-note":
                guard pathComponents.count >= 2 else { return nil }
                payload["noteId"] = pathComponents[1]
                targetRouteType = "church_note"
                type = "church_note_shared"
            default:
                return nil
            }
        } else {
            switch host {
            case "post":
                guard let postId = pathComponents.first else { return nil }
                payload["postId"] = postId
                if let commentId = url.queryParameters["commentId"] {
                    payload["commentId"] = commentId
                    targetRouteType = "post_comment"
                    type = "comment"
                } else {
                    targetRouteType = "post"
                    type = "amen"
                }
            case "profile":
                guard let userId = pathComponents.first else { return nil }
                payload["userId"] = userId
                targetRouteType = "profile"
                type = "follow"
            case "conversation":
                guard let conversationId = pathComponents.first else { return nil }
                payload["conversationId"] = conversationId
                targetRouteType = "conversation"
                type = "message"
            case "prayer":
                guard let prayerId = pathComponents.first else { return nil }
                payload["prayerId"] = prayerId
                targetRouteType = "prayer"
                type = "prayer_answered"
            case "church-note":
                guard let noteId = pathComponents.first else { return nil }
                payload["noteId"] = noteId
                targetRouteType = "church_note"
                type = "church_note_shared"
            default:
                return nil
            }
        }

        guard let targetRouteType, let type else { return nil }

        self.init(
            source: .universalLink,
            payloadVersion: .v3,
            notificationId: nil,
            type: type,
            targetRouteType: targetRouteType,
            routePayload: payload,
            fallbackRouteType: "notifications_inbox",
            fallbackRoutePayload: [:],
            behavior: .directOpen,
            safetyState: .clear
        )
    }
}

extension AppNotification {
    init?(documentID: String, data: [String: Any]) {
        guard
            let userId = data["userId"] as? String,
            let typeRaw = data["type"] as? String,
            let createdAt = data["createdAt"] as? Timestamp
        else {
            return nil
        }

        self.id = documentID
        self.userId = userId
        self.type = NotificationType(rawValue: typeRaw) ?? .unknown
        self.actorId = data["actorId"] as? String
        self.actorName = data["actorName"] as? String
        self.actorUsername = data["actorUsername"] as? String
        self.actorProfileImageURL = data["actorProfileImageURL"] as? String
        self.postId = data["postId"] as? String
        self.commentId = data["commentId"] as? String
        self.parentCommentId = data["parentCommentId"] as? String
        self.conversationId = data["conversationId"] as? String
        self.prayerId = data["prayerId"] as? String
        self.noteId = data["noteId"] as? String
        self.commentText = data["commentText"] as? String
        self.read = data["read"] as? Bool ?? false
        self.createdAt = createdAt
        self.priority = data["priority"] as? Int
        self.groupId = data["groupId"] as? String
        self.idempotencyKey = data["idempotencyKey"] as? String
        self.actors = (data["actors"] as? [[String: Any]])?.compactMap { actorData in
            guard
                let id = actorData["id"] as? String,
                let name = actorData["name"] as? String,
                let username = actorData["username"] as? String
            else {
                return nil
            }
            return NotificationActor(
                id: id,
                name: name,
                username: username,
                profileImageURL: actorData["profileImageURL"] as? String
            )
        }
        self.actorCount = data["actorCount"] as? Int
        self.updatedAt = data["updatedAt"] as? Timestamp
        self.seenAt = data["seenAt"] as? Timestamp
        self.openedAt = data["openedAt"] as? Timestamp
        self.dismissedAt = data["dismissedAt"] as? Timestamp
        self.targetRouteType = data["targetRouteType"] as? String
        self.routePayload = data["routePayload"] as? [String: String]
        self.fallbackRouteType = data["fallbackRouteType"] as? String
        self.fallbackRoutePayload = data["fallbackRoutePayload"] as? [String: String]
        self.schemaVersion = data["schemaVersion"] as? String
        self.deepLinkVersion = data["deepLinkVersion"] as? String
        self.invalidTarget = data["invalidTarget"] as? Bool
        self.pushDelivered = data["pushDelivered"] as? Bool
        self.pushDeliveredAt = data["pushDeliveredAt"] as? Timestamp
    }
}
