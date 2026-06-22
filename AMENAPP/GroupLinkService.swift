//
//  GroupLinkService.swift
//  AMENAPP
//
//  Service layer for group invite link operations.
//  All Firebase/backend interactions go through here — views never call Firebase directly.
//  Extends the existing FirebaseMessagingService rather than duplicating its responsibilities.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

@MainActor
final class GroupLinkService: ObservableObject {
    static let shared = GroupLinkService()

    private lazy var db = Firestore.firestore()
    private lazy var functions = Functions.functions()
    private let messagingService = FirebaseMessagingService.shared

    private var currentUserId: String {
        Auth.auth().currentUser?.uid ?? ""
    }

    private var currentUserName: String {
        Auth.auth().currentUser?.displayName ?? "Unknown"
    }

    private init() {}

    // MARK: - Create Group with Link

    /// Creates a new group conversation and generates an invite link in one operation.
    /// Returns the created GroupLink with the conversation ID.
    func createGroupWithLink(config: CreateGroupLinkConfig) async throws -> GroupLink {
        guard !currentUserId.isEmpty else {
            throw GroupLinkError.notAuthenticated
        }

        let trimmedName = config.groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw GroupLinkError.invalidInput("Group name cannot be empty")
        }

        // 1. Create the group conversation using existing service
        let participantNames: [String: String] = [currentUserId: currentUserName]
        let conversationId = try await messagingService.createGroupConversation(
            participantIds: [],
            participantNames: participantNames,
            groupName: trimmedName
        )

        // 2. Write group metadata (purpose, join mode, safety tier)
        let metadataUpdate: [String: Any] = [
            "groupPurpose": config.purpose.rawValue,
            "groupJoinMode": config.joinMode.rawValue,
            "groupSafetyTier": config.safetyTier.rawValue,
            "groupMemberLimit": config.memberLimit as Any
        ]
        try await db.collection("conversations").document(conversationId).updateData(metadataUpdate)

        // 3. Generate invite link
        let link = try await generateLink(
            conversationId: conversationId,
            joinMode: config.joinMode,
            safetyTier: config.safetyTier,
            memberLimit: config.memberLimit,
            expirationDays: config.expirationDays,
            expirationHours: config.expirationHours
        )

        return link
    }

    // MARK: - Generate Link

    /// Generates a new invite link for an existing group.
    func generateLink(
        conversationId: String,
        joinMode: GroupJoinMode = .open,
        safetyTier: GroupSafetyTier = .standard,
        memberLimit: Int? = nil,
        expirationDays: Int? = nil,
        expirationHours: Int? = nil
    ) async throws -> GroupLink {
        guard !currentUserId.isEmpty else {
            throw GroupLinkError.notAuthenticated
        }

        // Generate cryptographically secure token
        let token = generateSecureToken()

        var expiresAt: Date? = nil
        if let hours = expirationHours, hours > 0, hours < 24 {
            expiresAt = Calendar.current.date(byAdding: .hour, value: hours, to: Date())
        } else if let days = expirationDays, days > 0 {
            expiresAt = Calendar.current.date(byAdding: .day, value: days, to: Date())
        }

        let link = GroupLink(
            conversationId: conversationId,
            token: token,
            createdBy: currentUserId,
            createdAt: Date(),
            status: .active,
            expiresAt: expiresAt,
            memberLimit: memberLimit,
            joinCount: 0,
            joinMode: joinMode,
            safetyTier: safetyTier
        )

        // Write to Firestore subcollection
        let linkRef = db.collection("conversations").document(conversationId)
            .collection("groupLinks").document()
        try linkRef.setData(from: link)

        // Also write a top-level token lookup for fast resolution
        try await db.collection("groupLinkTokens").document(token).setData([
            "conversationId": conversationId,
            "linkId": linkRef.documentID,
            "createdAt": Timestamp(date: Date()),
            "status": GroupLinkStatus.active.rawValue
        ])

        // Return with the ID set
        var savedLink = link
        savedLink.id = linkRef.documentID
        return savedLink
    }

    // MARK: - Fetch Link Preview

    /// Resolves a token and returns safe preview data. No sensitive member data exposed.
    func fetchLinkPreview(token: String) async throws -> GroupLinkPreview {
        // 1. Look up token
        let tokenDoc = try await db.collection("groupLinkTokens").document(token).getDocument()
        guard tokenDoc.exists,
              let data = tokenDoc.data(),
              let conversationId = data["conversationId"] as? String,
              let statusRaw = data["status"] as? String else {
            throw GroupLinkError.linkNotFound
        }

        let tokenStatus = GroupLinkStatus(rawValue: statusRaw) ?? .disabled

        // 2. Fetch conversation metadata
        let convDoc = try await db.collection("conversations").document(conversationId).getDocument()
        guard convDoc.exists, let convData = convDoc.data() else {
            throw GroupLinkError.linkNotFound
        }

        let groupName = convData["groupName"] as? String ?? "Group Chat"
        let purposeRaw = convData["groupPurpose"] as? String ?? "general"
        let purpose = GroupPurpose(rawValue: purposeRaw) ?? .general
        let participantIds = convData["participantIds"] as? [String] ?? []
        let joinModeRaw = convData["groupJoinMode"] as? String ?? "open"
        let joinMode = GroupJoinMode(rawValue: joinModeRaw) ?? .open
        let groupAvatarURL = convData["groupAvatarUrl"] as? String
        let safetyTierRaw = convData["groupSafetyTier"] as? String ?? "standard"
        let safetyTier = GroupSafetyTier(rawValue: safetyTierRaw) ?? .standard
        let _ = convData["groupMemberLimit"] as? Int

        // 3. Fetch link document for expiry/status
        let linkId = data["linkId"] as? String ?? ""
        var isExpired = false
        var isPaused = false
        var isFull = false
        let isDisabled = tokenStatus == .disabled

        if !linkId.isEmpty {
            let linkDoc = try await db.collection("conversations").document(conversationId)
                .collection("groupLinks").document(linkId).getDocument()
            if let linkData = linkDoc.data() {
                if let expiresAtTS = linkData["expiresAt"] as? Timestamp {
                    isExpired = expiresAtTS.dateValue() < Date()
                }
                if let statusStr = linkData["status"] as? String {
                    isPaused = statusStr == GroupLinkStatus.paused.rawValue
                }
                if let limit = linkData["memberLimit"] as? Int,
                   let count = linkData["joinCount"] as? Int {
                    isFull = count >= limit
                }
            }
        }

        // Get creator name (safe to show)
        let creatorId = data["createdBy"] as? String
        var creatorName: String? = nil
        if let creatorId {
            let creatorDoc = try? await db.collection("users").document(creatorId).getDocument()
            creatorName = creatorDoc?.data()?["name"] as? String
        }

        // Compute mutual members: people the viewer follows who are in this group
        var mutualCount = 0
        var mutualNames: [String] = []
        if !participantIds.isEmpty {
            let viewerFollowing = await MainActor.run { FollowService.shared.following }
            let mutualIds = Array(viewerFollowing.intersection(Set(participantIds)))
                .filter { $0 != currentUserId }
                .prefix(3)

            mutualCount = mutualIds.count
            // Fetch display names for up to 2 mutual members
            for uid in mutualIds.prefix(2) {
                if let doc = try? await db.collection("users").document(uid).getDocument(),
                   let name = doc.data()?["username"] as? String ?? doc.data()?["name"] as? String {
                    mutualNames.append(name)
                }
            }
        }

        return GroupLinkPreview(
            groupName: groupName,
            purpose: purpose,
            memberCount: participantIds.count,
            joinMode: joinMode,
            safetyTier: safetyTier,
            isExpired: isExpired || (tokenStatus == .expired),
            isFull: isFull,
            isDisabled: isDisabled,
            isPaused: isPaused,
            groupAvatarURL: groupAvatarURL,
            creatorName: creatorName,
            mutualMemberCount: mutualCount,
            mutualMemberNames: mutualNames
        )
    }

    // MARK: - Evaluate Join

    /// Evaluates whether the current user can join a group via link.
    func evaluateJoin(token: String) async throws -> JoinEvaluationResult {
        guard !currentUserId.isEmpty else {
            throw GroupLinkError.notAuthenticated
        }

        // 1. Resolve token
        let tokenDoc = try await db.collection("groupLinkTokens").document(token).getDocument()
        guard tokenDoc.exists,
              let data = tokenDoc.data(),
              let conversationId = data["conversationId"] as? String,
              let linkId = data["linkId"] as? String else {
            return JoinEvaluationResult(outcome: .expired, reason: "This link is no longer valid.", conversationId: nil)
        }

        let tokenStatus = GroupLinkStatus(rawValue: data["status"] as? String ?? "") ?? .disabled

        // 2. Check link status
        if tokenStatus == .disabled {
            return JoinEvaluationResult(outcome: .disabled, reason: "This invite link has been disabled.", conversationId: conversationId)
        }

        // 3. Fetch conversation
        let convDoc = try await db.collection("conversations").document(conversationId).getDocument()
        guard convDoc.exists, let convData = convDoc.data() else {
            return JoinEvaluationResult(outcome: .expired, reason: "This group no longer exists.", conversationId: nil)
        }

        let participantIds = convData["participantIds"] as? [String] ?? []

        // 4. Already a member?
        if participantIds.contains(currentUserId) {
            return JoinEvaluationResult(outcome: .alreadyMember, reason: nil, conversationId: conversationId)
        }

        // 5. Fetch link details
        let linkDoc = try await db.collection("conversations").document(conversationId)
            .collection("groupLinks").document(linkId).getDocument()
        guard let linkData = linkDoc.data() else {
            return JoinEvaluationResult(outcome: .expired, reason: "This link is no longer valid.", conversationId: nil)
        }

        let linkStatus = GroupLinkStatus(rawValue: linkData["status"] as? String ?? "") ?? .disabled

        if linkStatus == .paused {
            return JoinEvaluationResult(outcome: .paused, reason: "This invite link is temporarily paused.", conversationId: nil)
        }
        if linkStatus == .disabled || linkStatus == .expired {
            return JoinEvaluationResult(outcome: .disabled, reason: "This invite link is no longer active.", conversationId: nil)
        }

        // Check expiry
        if let expiresAtTS = linkData["expiresAt"] as? Timestamp, expiresAtTS.dateValue() < Date() {
            return JoinEvaluationResult(outcome: .expired, reason: "This invite link has expired.", conversationId: nil)
        }

        // Check member limit
        let joinCount = linkData["joinCount"] as? Int ?? 0
        if let memberLimit = linkData["memberLimit"] as? Int, joinCount >= memberLimit {
            return JoinEvaluationResult(outcome: .full, reason: "This group has reached its member limit.", conversationId: nil)
        }

        // 6. Block check — is user blocked by any admin?
        let adminIds = convData["adminIds"] as? [String] ?? []
        let blockedByAdmin = await checkBlockRelationship(userId: currentUserId, againstUserIds: adminIds)
        if blockedByAdmin {
            return JoinEvaluationResult(outcome: .blocked, reason: "You cannot join this group.", conversationId: nil)
        }

        // 7. Check if previously removed from this group
        let removedMembers = convData["removedMembers"] as? [String] ?? []
        if removedMembers.contains(currentUserId) {
            return JoinEvaluationResult(outcome: .blocked, reason: "You were previously removed from this group.", conversationId: nil)
        }

        // 8. Check join mode
        let joinModeRaw = linkData["joinMode"] as? String ?? "open"
        let joinMode = GroupJoinMode(rawValue: joinModeRaw) ?? .open

        if joinMode == .restricted {
            return JoinEvaluationResult(outcome: .blocked, reason: "This group only accepts invited members.", conversationId: nil)
        }

        if joinMode == .approvalRequired {
            // Check if there's already a pending request
            let existingRequest = try await db.collection("conversations").document(conversationId)
                .collection("joinRequests")
                .whereField("userId", isEqualTo: currentUserId)
                .whereField("status", isEqualTo: JoinRequestStatus.pending.rawValue)
                .limit(to: 1)
                .getDocuments()

            if !existingRequest.documents.isEmpty {
                return JoinEvaluationResult(outcome: .requestRequired, reason: "Your request is already pending.", conversationId: nil)
            }

            return JoinEvaluationResult(outcome: .requestRequired, reason: "An admin must approve your request to join.", conversationId: nil)
        }

        // Open join
        return JoinEvaluationResult(outcome: .allowed, reason: nil, conversationId: conversationId)
    }

    // MARK: - Join Group

    /// Atomically adds the current user to a group. Must pass evaluation first.
    func joinGroup(token: String) async throws -> String {
        guard !currentUserId.isEmpty else {
            throw GroupLinkError.notAuthenticated
        }

        // Re-evaluate (defense in depth)
        let evaluation = try await evaluateJoin(token: token)
        guard evaluation.outcome == .allowed || evaluation.outcome == .alreadyMember else {
            throw GroupLinkError.joinDenied(evaluation.reason ?? "Cannot join this group.")
        }

        if evaluation.outcome == .alreadyMember, let convId = evaluation.conversationId {
            return convId
        }

        // Resolve token to get conversation + link IDs
        let tokenDoc = try await db.collection("groupLinkTokens").document(token).getDocument()
        guard let data = tokenDoc.data(),
              let conversationId = data["conversationId"] as? String,
              let linkId = data["linkId"] as? String else {
            throw GroupLinkError.linkNotFound
        }

        // Add user to conversation
        let participantNames = [currentUserId: currentUserName]
        try await messagingService.addParticipantsToGroup(
            conversationId: conversationId,
            participantIds: [currentUserId],
            participantNames: participantNames
        )

        // Increment join count on link
        try await db.collection("conversations").document(conversationId)
            .collection("groupLinks").document(linkId)
            .updateData(["joinCount": FieldValue.increment(Int64(1))])

        return conversationId
    }

    // MARK: - Request to Join

    /// Submits a join request for approval-required groups.
    func requestJoin(token: String) async throws {
        guard !currentUserId.isEmpty else {
            throw GroupLinkError.notAuthenticated
        }

        let tokenDoc = try await db.collection("groupLinkTokens").document(token).getDocument()
        guard let data = tokenDoc.data(),
              let conversationId = data["conversationId"] as? String,
              let linkId = data["linkId"] as? String else {
            throw GroupLinkError.linkNotFound
        }

        // Check for duplicate pending request
        let existing = try await db.collection("conversations").document(conversationId)
            .collection("joinRequests")
            .whereField("userId", isEqualTo: currentUserId)
            .whereField("status", isEqualTo: JoinRequestStatus.pending.rawValue)
            .limit(to: 1)
            .getDocuments()

        guard existing.documents.isEmpty else {
            throw GroupLinkError.duplicateRequest
        }

        // Get current user photo
        let userDoc = try? await db.collection("users").document(currentUserId).getDocument()
        let photoURL = userDoc?.data()?["profilePhotoURL"] as? String
            ?? userDoc?.data()?["profileImageURL"] as? String

        let request = GroupJoinRequest(
            conversationId: conversationId,
            linkId: linkId,
            userId: currentUserId,
            userName: currentUserName,
            userPhotoURL: photoURL,
            requestedAt: Date(),
            status: .pending
        )

        let requestRef = db.collection("conversations").document(conversationId)
            .collection("joinRequests").document()
        try requestRef.setData(from: request)

        // Notify admins
        await notifyAdminsOfJoinRequest(conversationId: conversationId, requesterName: currentUserName)
    }

    // MARK: - Admin: Respond to Join Request

    func respondToJoinRequest(
        conversationId: String,
        requestId: String,
        approve: Bool,
        reason: String? = nil
    ) async throws {
        guard !currentUserId.isEmpty else {
            throw GroupLinkError.notAuthenticated
        }

        // Verify caller is admin
        let convDoc = try await db.collection("conversations").document(conversationId).getDocument()
        let adminIds = convDoc.data()?["adminIds"] as? [String] ?? []
        guard adminIds.contains(currentUserId) else {
            throw GroupLinkError.notAdmin
        }

        let requestRef = db.collection("conversations").document(conversationId)
            .collection("joinRequests").document(requestId)
        let requestDoc = try await requestRef.getDocument()
        guard let requestData = requestDoc.data(),
              let userId = requestData["userId"] as? String,
              let userName = requestData["userName"] as? String else {
            throw GroupLinkError.requestNotFound
        }

        // Update request
        var updates: [String: Any] = [
            "status": approve ? JoinRequestStatus.approved.rawValue : JoinRequestStatus.denied.rawValue,
            "respondedBy": currentUserId,
            "respondedAt": Timestamp(date: Date())
        ]
        if let reason { updates["reason"] = reason }
        try await requestRef.updateData(updates)

        // If approved, add user to group
        if approve {
            let participantNames = [userId: userName]
            try await messagingService.addParticipantsToGroup(
                conversationId: conversationId,
                participantIds: [userId],
                participantNames: participantNames
            )
        }

        // Notify the requester
        await notifyUserOfRequestResponse(userId: userId, conversationId: conversationId, approved: approve)
    }

    // MARK: - Admin: Manage Link

    func pauseLink(conversationId: String, linkId: String) async throws {
        try await updateLinkStatus(conversationId: conversationId, linkId: linkId, status: .paused)
    }

    func resumeLink(conversationId: String, linkId: String) async throws {
        try await updateLinkStatus(conversationId: conversationId, linkId: linkId, status: .active)
    }

    func disableLink(conversationId: String, linkId: String) async throws {
        try await updateLinkStatus(conversationId: conversationId, linkId: linkId, status: .disabled)
        // Also update the token lookup
        if let link = try await fetchActiveLink(conversationId: conversationId) {
            try await db.collection("groupLinkTokens").document(link.token)
                .updateData(["status": GroupLinkStatus.disabled.rawValue])
        }
    }

    func regenerateLink(conversationId: String, oldLinkId: String) async throws -> GroupLink {
        // Disable old link
        try await disableLink(conversationId: conversationId, linkId: oldLinkId)

        // Fetch old link to preserve settings
        let oldDoc = try await db.collection("conversations").document(conversationId)
            .collection("groupLinks").document(oldLinkId).getDocument()
        let joinModeRaw = oldDoc.data()?["joinMode"] as? String ?? "open"
        let safetyTierRaw = oldDoc.data()?["safetyTier"] as? String ?? "standard"
        let memberLimit = oldDoc.data()?["memberLimit"] as? Int

        // Generate new link with same settings
        return try await generateLink(
            conversationId: conversationId,
            joinMode: GroupJoinMode(rawValue: joinModeRaw) ?? .open,
            safetyTier: GroupSafetyTier(rawValue: safetyTierRaw) ?? .standard,
            memberLimit: memberLimit
        )
    }

    // MARK: - Fetch Active Link

    func fetchActiveLink(conversationId: String) async throws -> GroupLink? {
        let snapshot = try await db.collection("conversations").document(conversationId)
            .collection("groupLinks")
            .whereField("status", isEqualTo: GroupLinkStatus.active.rawValue)
            .order(by: "createdAt", descending: true)
            .limit(to: 1)
            .getDocuments()

        return try snapshot.documents.first?.data(as: GroupLink.self)
    }

    // MARK: - Fetch Pending Requests

    func fetchPendingRequests(conversationId: String) async throws -> [GroupJoinRequest] {
        let snapshot = try await db.collection("conversations").document(conversationId)
            .collection("joinRequests")
            .whereField("status", isEqualTo: JoinRequestStatus.pending.rawValue)
            .order(by: "requestedAt", descending: false)
            .getDocuments()

        return try snapshot.documents.compactMap { try $0.data(as: GroupJoinRequest.self) }
    }

    // MARK: - Private Helpers

    private func updateLinkStatus(conversationId: String, linkId: String, status: GroupLinkStatus) async throws {
        guard !currentUserId.isEmpty else {
            throw GroupLinkError.notAuthenticated
        }

        // Verify caller is admin
        let convDoc = try await db.collection("conversations").document(conversationId).getDocument()
        let adminIds = convDoc.data()?["adminIds"] as? [String] ?? []
        guard adminIds.contains(currentUserId) else {
            throw GroupLinkError.notAdmin
        }

        try await db.collection("conversations").document(conversationId)
            .collection("groupLinks").document(linkId)
            .updateData(["status": status.rawValue])
    }

    /// Generate a cryptographically secure random token.
    private func generateSecureToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Check if user is blocked by any of the given user IDs.
    private func checkBlockRelationship(userId: String, againstUserIds: [String]) async -> Bool {
        for adminId in againstUserIds {
            if BlockService.shared.blockedUsers.contains(adminId) {
                return true
            }
            // Also check if the admin blocked the user (server-side would be better)
            let blockDoc = try? await db.collection("users").document(adminId)
                .collection("blockedUsers").document(userId).getDocument()
            if blockDoc?.exists == true {
                return true
            }
        }
        return false
    }

    /// Send notification to group admins about a join request.
    private func notifyAdminsOfJoinRequest(conversationId: String, requesterName: String) async {
        let convDoc = try? await db.collection("conversations").document(conversationId).getDocument()
        let adminIds = convDoc?.data()?["adminIds"] as? [String] ?? []
        let groupName = convDoc?.data()?["groupName"] as? String ?? "Group"

        for adminId in adminIds where adminId != currentUserId {
            let notification: [String: Any] = [
                "type": "groupJoinRequest",
                "userId": adminId,
                "recipientId": adminId,
                "actorId": currentUserId,
                "actorName": requesterName,
                "conversationId": conversationId,
                "body": "\(requesterName) wants to join \(groupName)",
                "timestamp": Timestamp(date: Date()),
                "isRead": false
            ]
            _ = try? await db
                .collection("users")
                .document(adminId)
                .collection("notifications")
                .addDocument(data: notification)
        }
    }

    /// Notify user about their join request response.
    private func notifyUserOfRequestResponse(userId: String, conversationId: String, approved: Bool) async {
        let convDoc = try? await db.collection("conversations").document(conversationId).getDocument()
        let groupName = convDoc?.data()?["groupName"] as? String ?? "Group"

        let body = approved
            ? "Your request to join \(groupName) was approved"
            : "Your request to join \(groupName) was not approved"

        let notification: [String: Any] = [
            "type": approved ? "groupJoinApproved" : "groupJoinDenied",
            "userId": userId,
            "recipientId": userId,
            "actorId": currentUserId,
            "conversationId": conversationId,
            "body": body,
            "timestamp": Timestamp(date: Date()),
            "isRead": false
        ]
        _ = try? await db
            .collection("users")
            .document(userId)
            .collection("notifications")
            .addDocument(data: notification)
    }
}

// MARK: - Error Types

enum GroupLinkError: LocalizedError {
    case notAuthenticated
    case invalidInput(String)
    case linkNotFound
    case joinDenied(String)
    case duplicateRequest
    case notAdmin
    case requestNotFound
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You must be logged in."
        case .invalidInput(let msg): return msg
        case .linkNotFound: return "This invite link is no longer valid."
        case .joinDenied(let msg): return msg
        case .duplicateRequest: return "You already have a pending request."
        case .notAdmin: return "Only group admins can perform this action."
        case .requestNotFound: return "Join request not found."
        case .networkError(let error): return error.localizedDescription
        }
    }
}
