//
//  InteractionPolicyEngine.swift
//  AMENAPP
//
//  Unified interaction gate — one source of truth for:
//  canFollow, canDM, canTag, canMention, canReply, canInviteToGroup, canCall, canShareSensitiveMedia
//
//  Decision order:
//    1. Block / legal / trust-safety hard deny
//    2. Teen protection deny
//    3. Recipient setting deny
//    4. Existing accepted thread allow
//    5. Mutual follow / connected allow
//    6. Non-connected but allowed → Requests
//    7. High-risk first contact → Hidden Requests or deny
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

// MARK: - Relationship Edge (directional)

struct RelationshipEdge: Codable, Identifiable, Equatable {
    @DocumentID var id: String?
    var sourceUserID: String
    var targetUserID: String

    var followState: FollowEdgeState
    var isCloseFriend: Bool
    var isMutedPosts: Bool
    var isMutedStories: Bool
    var isDMAllowedOverride: Bool?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, sourceUserID, targetUserID, followState,
             isCloseFriend, isMutedPosts, isMutedStories,
             isDMAllowedOverride, createdAt, updatedAt
    }

    init(
        sourceUserID: String,
        targetUserID: String,
        followState: FollowEdgeState = .none,
        isCloseFriend: Bool = false,
        isMutedPosts: Bool = false,
        isMutedStories: Bool = false,
        isDMAllowedOverride: Bool? = nil
    ) {
        self.sourceUserID = sourceUserID
        self.targetUserID = targetUserID
        self.followState = followState
        self.isCloseFriend = isCloseFriend
        self.isMutedPosts = isMutedPosts
        self.isMutedStories = isMutedStories
        self.isDMAllowedOverride = isDMAllowedOverride
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Follow Edge State

enum FollowEdgeState: String, Codable, Equatable {
    case none = "NONE"
    case requestedOutgoing = "REQUESTED_OUTGOING"
    case requestedIncoming = "REQUESTED_INCOMING"
    case following = "FOLLOWING"
    case blocked = "BLOCKED"
    case restricted = "RESTRICTED"
}

// MARK: - DM Eligibility

struct DMEligibilityResult {
    let canOpenFullThread: Bool
    let canSendRequest: Bool
    let route: DMRoute
    let reasonCode: DMReasonCode
    let userFacingMessage: String
}

enum DMRoute: String {
    case direct = "DIRECT"
    case requests = "REQUESTS"
    case hiddenRequests = "HIDDEN_REQUESTS"
    case deny = "DENY"
}

enum DMReasonCode: String {
    case mutualOrAllowed = "MUTUAL_OR_ALLOWED"
    case targetPrivateNotConnected = "TARGET_PRIVATE_NOT_CONNECTED"
    case targetMessagesFollowersOnly = "TARGET_MESSAGES_FOLLOWERS_ONLY"
    case targetMessagesNoOne = "TARGET_MESSAGES_NO_ONE"
    case targetIsTeenRestricted = "TARGET_IS_TEEN_RESTRICTED"
    case senderFlaggedRisky = "SENDER_FLAGGED_RISKY"
    case blocked = "BLOCKED"
    case restricted = "RESTRICTED"
    case rateLimited = "RATE_LIMITED"
    case existingThread = "EXISTING_THREAD"
}

// MARK: - Interaction Permission Result

struct InteractionPermission {
    let allowed: Bool
    let reason: String?
    let route: DMRoute?
}

// MARK: - Follow Request (Enhanced)

struct FollowRequestEnhanced: Codable, Identifiable, Equatable {
    @DocumentID var id: String?
    var requesterId: String
    var recipientId: String
    var status: FollowRequestStatus
    var source: FollowRequestSource
    var requestedAt: Date
    var decidedAt: Date?
    var decisionBy: String?
    var note: String?
    var expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, requesterId, recipientId, status, source,
             requestedAt, decidedAt, decisionBy, note, expiresAt
    }

    init(requesterId: String, recipientId: String, source: FollowRequestSource = .profile) {
        self.requesterId = requesterId
        self.recipientId = recipientId
        self.status = .pending
        self.source = source
        self.requestedAt = Date()
        // Auto-expire after 90 days
        self.expiresAt = Calendar.current.date(byAdding: .day, value: 90, to: Date())
    }
}

enum FollowRequestStatus: String, Codable, Equatable {
    case pending, approved, denied, cancelled, expired
}

enum FollowRequestSource: String, Codable, Equatable {
    case profile, suggested, postHeader, messageGate, search
}

// MARK: - Thread Member

struct ThreadMember: Codable, Identifiable, Equatable {
    @DocumentID var id: String?
    var threadId: String
    var userId: String
    var role: ThreadRole
    var inboxFolder: InboxFolder
    var visibilityState: ThreadVisibility
    var canReply: Bool
    var canReact: Bool
    var canCall: Bool
    var isMuted: Bool
    var isPinned: Bool
    var unreadCount: Int
    var lastReadMessageId: String?
    var acceptedRequestAt: Date?
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, threadId, userId, role, inboxFolder, visibilityState,
             canReply, canReact, canCall, isMuted, isPinned,
             unreadCount, lastReadMessageId, acceptedRequestAt, deletedAt
    }
}

enum ThreadRole: String, Codable, Equatable {
    case owner, member
}

enum InboxFolder: String, Codable, Equatable, CaseIterable {
    case primary = "PRIMARY"
    case general = "GENERAL"
    case requests = "REQUESTS"
    case hiddenRequests = "HIDDEN_REQUESTS"
    case restricted = "RESTRICTED"

    var displayName: String {
        switch self {
        case .primary: return "Primary"
        case .general: return "General"
        case .requests: return "Requests"
        case .hiddenRequests: return "Hidden"
        case .restricted: return "Restricted"
        }
    }

    var icon: String {
        switch self {
        case .primary: return "tray.full"
        case .general: return "tray"
        case .requests: return "person.crop.circle.badge.questionmark"
        case .hiddenRequests: return "eye.slash"
        case .restricted: return "exclamationmark.shield"
        }
    }
}

enum ThreadVisibility: String, Codable, Equatable {
    case visible, deletedView, archivedLocal
}

// MARK: - Recipient Message Policy

enum RecipientMessagePolicy: String, Codable, Equatable {
    case everyone = "everyone"
    case peopleIFollow = "people_i_follow"
    case mutualFollowsOnly = "mutual_follows_only"
    case noOne = "no_one"

    func allowsDirect(isMutual: Bool, recipientFollowsSender: Bool) -> Bool {
        switch self {
        case .everyone: return true
        case .peopleIFollow: return recipientFollowsSender
        case .mutualFollowsOnly: return isMutual
        case .noOne: return false
        }
    }

    func allowsRequests() -> Bool {
        switch self {
        case .everyone, .peopleIFollow, .mutualFollowsOnly: return true
        case .noOne: return false
        }
    }
}

// MARK: - Interaction Policy Engine

@MainActor
final class InteractionPolicyEngine {
    static let shared = InteractionPolicyEngine()
    private lazy var db = Firestore.firestore()
    private init() {}

    // MARK: - Core Gate: Can the sender DM the recipient?

    func evaluateDMEligibility(
        senderID: String,
        recipientID: String
    ) async -> DMEligibilityResult {
        // 1. Block check (bidirectional)
        if await isBlockedEitherWay(senderID, recipientID) {
            return DMEligibilityResult(
                canOpenFullThread: false,
                canSendRequest: false,
                route: .deny,
                reasonCode: .blocked,
                userFacingMessage: "You can't message this account."
            )
        }

        // 2. Teen protection
        if await isTeenRestrictedRoute(senderID, recipientID) {
            return DMEligibilityResult(
                canOpenFullThread: false,
                canSendRequest: false,
                route: .deny,
                reasonCode: .targetIsTeenRestricted,
                userFacingMessage: "To protect younger users, messaging is limited for this conversation."
            )
        }

        // 3. Get connection state and policies
        let connection = await getConnectionState(senderID, recipientID)
        let policy = await getRecipientMessagePolicy(recipientID)

        // 4. Existing accepted thread → allow
        if connection.hasAcceptedThread {
            return DMEligibilityResult(
                canOpenFullThread: true,
                canSendRequest: false,
                route: .direct,
                reasonCode: .existingThread,
                userFacingMessage: ""
            )
        }

        // 5. Mutual follow or direct policy allows
        if connection.isMutual || policy.allowsDirect(
            isMutual: connection.isMutual,
            recipientFollowsSender: connection.recipientFollowsSender
        ) {
            return DMEligibilityResult(
                canOpenFullThread: true,
                canSendRequest: false,
                route: .direct,
                reasonCode: .mutualOrAllowed,
                userFacingMessage: ""
            )
        }

        // 6. Check if requests are allowed
        if !policy.allowsRequests() {
            let msg: String
            switch policy {
            case .noOne:
                msg = "This person only receives messages from people they follow."
            default:
                msg = "You can't message this account right now."
            }
            return DMEligibilityResult(
                canOpenFullThread: false,
                canSendRequest: false,
                route: .deny,
                reasonCode: .targetMessagesNoOne,
                userFacingMessage: msg
            )
        }

        // 7. Risk assessment for sender
        let riskTier = await assessSenderRisk(senderID, recipientID)
        if riskTier == .high {
            return DMEligibilityResult(
                canOpenFullThread: false,
                canSendRequest: true,
                route: .hiddenRequests,
                reasonCode: .senderFlaggedRisky,
                userFacingMessage: "Your message was sent as a request."
            )
        }

        // 8. Standard non-connected → Requests
        return DMEligibilityResult(
            canOpenFullThread: false,
            canSendRequest: true,
            route: .requests,
            reasonCode: .targetPrivateNotConnected,
            userFacingMessage: "Your message was sent as a request."
        )
    }

    // MARK: - Follow Request

    func requestFollow(requesterID: String, recipientID: String, source: FollowRequestSource = .profile) async throws -> FollowEdgeState {
        guard !(await isBlockedEitherWay(requesterID, recipientID)) else {
            throw InteractionError.blocked
        }
        // createFollow callable handles public/private routing, idempotency, GUARDIAN flag,
        // rate limiting, atomic writes, and server-side notification in one call.
        let callable = Functions.functions(region: "us-central1").httpsCallable("createFollow")
        let result = try await callable.call(["followingId": recipientID])
        let data = result.data as? [String: Any]
        if data?["requestSent"] as? Bool == true || data?["requestAlreadySent"] as? Bool == true {
            return .requestedOutgoing
        }
        return .following
    }

    // MARK: - Accept Follow Request

    func approveFollowRequest(requestID: String, recipientID: String) async throws {
        let ref = db.collection("followRequests").document(requestID)
        let doc = try await ref.getDocument()
        guard let data = doc.data(),
              data["recipientId"] as? String == recipientID,
              data["status"] as? String == FollowRequestStatus.pending.rawValue else {
            throw InteractionError.invalidRequest
        }
        let requesterID = data["requesterId"] as? String ?? ""
        // Route through callable — atomically deletes request, creates follow edges, updates counters.
        let callable = Functions.functions(region: "us-central1").httpsCallable("acceptFollowRequest")
        _ = try await callable.call(["requesterId": requesterID])
    }

    // MARK: - Deny Follow Request

    func denyFollowRequest(requestID: String, recipientID: String) async throws {
        let ref = db.collection("followRequests").document(requestID)
        let doc = try await ref.getDocument()
        guard let requesterID = doc.data()?["requesterId"] as? String else { return }
        let callable = Functions.functions(region: "us-central1").httpsCallable("rejectFollowRequest")
        _ = try await callable.call(["requesterId": requesterID])
    }

    // MARK: - Cancel Follow Request

    func cancelFollowRequest(requesterID: String, recipientID: String) async throws {
        // cancelFollowRequest callable deletes the request from users/{targetId}/followRequests/{requesterId}
        let callable = Functions.functions(region: "us-central1").httpsCallable("cancelFollowRequest")
        _ = try await callable.call(["targetId": recipientID])
    }

    // MARK: - Accept Message Request

    func acceptMessageRequest(threadID: String, recipientID: String) async throws {
        let memberRef = db.collection("conversations").document(threadID)

        try await memberRef.updateData([
            "status": "accepted",
            "inboxFolder": InboxFolder.primary.rawValue
        ])
    }

    // MARK: - Unified Permission Check

    func canPerformAction(_ action: InteractionAction, from senderID: String, to targetID: String) async -> InteractionPermission {
        // Block beats everything
        if await isBlockedEitherWay(senderID, targetID) {
            return InteractionPermission(allowed: false, reason: "This action is not available.", route: nil)
        }

        let connection = await getConnectionState(senderID, targetID)

        switch action {
        case .follow:
            return InteractionPermission(allowed: true, reason: nil, route: nil)
        case .dm:
            let result = await evaluateDMEligibility(senderID: senderID, recipientID: targetID)
            return InteractionPermission(
                allowed: result.canOpenFullThread || result.canSendRequest,
                reason: result.canOpenFullThread ? nil : result.userFacingMessage,
                route: result.route
            )
        case .tag, .mention:
            let targetDoc = try? await db.collection("users").document(targetID).getDocument()
            let allowTagging = targetDoc?.data()?["allowTagging"] as? Bool ?? true
            return InteractionPermission(
                allowed: allowTagging && connection.senderFollowsRecipient,
                reason: allowTagging ? nil : "This person doesn't allow tagging.",
                route: nil
            )
        case .reply:
            return InteractionPermission(allowed: connection.senderFollowsRecipient || !connection.recipientIsPrivate, reason: nil, route: nil)
        case .inviteToGroup:
            return InteractionPermission(
                allowed: connection.isMutual,
                reason: connection.isMutual ? nil : "You can only invite mutual followers to groups.",
                route: nil
            )
        case .call:
            return InteractionPermission(
                allowed: connection.isMutual,
                reason: connection.isMutual ? nil : "Calls are available with mutual followers only.",
                route: nil
            )
        case .shareSensitiveMedia:
            return InteractionPermission(
                allowed: connection.isMutual && connection.hasAcceptedThread,
                reason: "Media sharing requires an active conversation with a mutual follower.",
                route: nil
            )
        }
    }

    // MARK: - Connection State Helper

    private struct ConnectionState {
        var senderFollowsRecipient: Bool
        var recipientFollowsSender: Bool
        var isMutual: Bool
        var hasAcceptedThread: Bool
        var recipientIsPrivate: Bool
    }

    private func getConnectionState(_ senderID: String, _ recipientID: String) async -> ConnectionState {
        async let senderFollows = checkFollowing(from: senderID, to: recipientID)
        async let recipientFollows = checkFollowing(from: recipientID, to: senderID)
        async let thread = checkAcceptedThread(senderID, recipientID)
        async let isPrivate = checkIsPrivate(recipientID)

        let sf = await senderFollows
        let rf = await recipientFollows
        return ConnectionState(
            senderFollowsRecipient: sf,
            recipientFollowsSender: rf,
            isMutual: sf && rf,
            hasAcceptedThread: await thread,
            recipientIsPrivate: await isPrivate
        )
    }

    private func getRecipientMessagePolicy(_ recipientID: String) async -> RecipientMessagePolicy {
        do {
            let settingsDoc = try await db.collection("users").document(recipientID)
                .collection("settings").document("messaging").getDocument()

            if let raw = settingsDoc.data()?["whoCanSendMessageRequests"] as? String,
               let policy = MessageRequestPermission(rawValue: raw) {
                switch policy {
                case .everyone: return .everyone
                case .peopleIFollow: return .peopleIFollow
                case .mutualFollowsOnly: return .mutualFollowsOnly
                case .noOne: return .noOne
                case .trustedConnectionsOnly: return .mutualFollowsOnly
                }
            }

            // Fallback to user-level setting
            let userDoc = try await db.collection("users").document(recipientID).getDocument()
            let allowAll = userDoc.data()?["allowMessagesFromEveryone"] as? Bool ?? true
            return allowAll ? .everyone : .peopleIFollow
        } catch {
            return .everyone
        }
    }

    // MARK: - Private Helpers

    private func isBlockedEitherWay(_ a: String, _ b: String) async -> Bool {
        do {
            let snap1 = try await db.collection("blocks")
                .whereField("blockerId", isEqualTo: a)
                .whereField("blockedId", isEqualTo: b)
                .limit(to: 1)
                .getDocuments()
            if !snap1.documents.isEmpty { return true }

            let snap2 = try await db.collection("blocks")
                .whereField("blockerId", isEqualTo: b)
                .whereField("blockedId", isEqualTo: a)
                .limit(to: 1)
                .getDocuments()
            return !snap2.documents.isEmpty
        } catch {
            return false
        }
    }

    private func isTeenRestrictedRoute(_ senderID: String, _ recipientID: String) async -> Bool {
        do {
            let recipientDoc = try await db.collection("users").document(recipientID).getDocument()
            let ageBand = recipientDoc.data()?["ageBand"] as? String
            if ageBand == "teen" {
                let connection = await getConnectionState(senderID, recipientID)
                // Teens: only connected users can DM
                return !connection.isMutual
            }
            return false
        } catch {
            return false
        }
    }

    private func checkFollowing(from: String, to: String) async -> Bool {
        do {
            let snap = try await db.collection("follows")
                .whereField("followerId", isEqualTo: from)
                .whereField("followingId", isEqualTo: to)
                .limit(to: 1)
                .getDocuments()
            return !snap.documents.isEmpty
        } catch {
            return false
        }
    }

    private func checkAcceptedThread(_ a: String, _ b: String) async -> Bool {
        do {
            let snap = try await db.collection("conversations")
                .whereField("participantIds", arrayContains: a)
                .whereField("status", isEqualTo: "accepted")
                .limit(to: 20)
                .getDocuments()

            return snap.documents.contains { doc in
                let participants = doc.data()["participantIds"] as? [String] ?? []
                return participants.contains(b)
            }
        } catch {
            return false
        }
    }

    private func checkIsPrivate(_ userID: String) async -> Bool {
        do {
            let doc = try await db.collection("users").document(userID).getDocument()
            return doc.data()?["isPrivate"] as? Bool ?? false
        } catch {
            return false
        }
    }

    private enum RiskTier {
        case low, medium, high
    }

    private func assessSenderRisk(_ senderID: String, _ recipientID: String) async -> RiskTier {
        do {
            let senderDoc = try await db.collection("users").document(senderID).getDocument()
            let data = senderDoc.data() ?? [:]

            // New account with no followers → medium risk
            let followersCount = data["followersCount"] as? Int ?? 0
            let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
            let accountAge = Date().timeIntervalSince(createdAt)
            let threeDays: TimeInterval = 3 * 24 * 60 * 60

            if accountAge < threeDays && followersCount < 3 {
                return .medium
            }

            // Check recent DM request volume (rate limit)
            let recentRequests = try await db.collection("conversations")
                .whereField("requesterId", isEqualTo: senderID)
                .whereField("status", isEqualTo: "pending")
                .getDocuments()

            if recentRequests.documents.count > 10 {
                return .high
            }

            return .low
        } catch {
            return .low
        }
    }
}

// MARK: - Interaction Actions

enum InteractionAction {
    case follow
    case dm
    case tag
    case mention
    case reply
    case inviteToGroup
    case call
    case shareSensitiveMedia
}

// MARK: - Errors

enum InteractionError: LocalizedError {
    case blocked
    case invalidRequest
    case rateLimited
    case teenRestricted
    case policyDenied(String)

    var errorDescription: String? {
        switch self {
        case .blocked: return "This action is not available."
        case .invalidRequest: return "Invalid request."
        case .rateLimited: return "You've been rate limited. Please try again later."
        case .teenRestricted: return "To protect younger users, this action is limited."
        case .policyDenied(let msg): return msg
        }
    }
}
