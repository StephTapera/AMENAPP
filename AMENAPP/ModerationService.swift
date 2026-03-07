//
//  ModerationService.swift
//  AMENAPP
//
//  Created by Steph on 1/21/26.
//
//  Service for content moderation, reporting, blocking, and muting users
//

import Foundation
import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

// MARK: - Typed Status / Action Enums

enum ContentReportStatus: String, Codable {
    case pending
    case queuedForUrgentReview
    case reviewed
    case actionTaken
    case dismissed
}

enum ModerationActionTaken: String, Codable {
    case none
    case warning
    case contentRemoved
    case temporaryRestriction
    case permanentBan
    case escalatedToLegal
}

// MARK: - Report Reason

enum ModerationReportReason: String, CaseIterable, Codable {
    case spam
    case harassment
    case hateSpeech
    case sexualContent
    case sexualSolicitation
    case minorSafety
    case inappropriateContent
    case falseInformation
    case offTopic
    case copyright
    case other

    /// Stable machine-readable key stored as `reasonCategory` in Firestore.
    /// The `rawValue` itself is already a stable snake-case identifier.
    var categoryKey: String { rawValue }

    /// Human-readable label stored as `reason` in Firestore and shown in UI.
    var displayName: String {
        switch self {
        case .spam:                 return "Spam or misleading"
        case .harassment:           return "Harassment or bullying"
        case .hateSpeech:           return "Hate speech or violence"
        case .sexualContent:        return "Sexual or explicit content"
        case .sexualSolicitation:   return "Sexual solicitation"
        case .minorSafety:          return "Child safety concern"
        case .inappropriateContent: return "Inappropriate content"
        case .falseInformation:     return "False information"
        case .offTopic:             return "Off-topic or irrelevant"
        case .copyright:            return "Copyright violation"
        case .other:                return "Other"
        }
    }

    /// Whether this report type requires immediate escalation (not standard 24h queue).
    var requiresImmediateEscalation: Bool { self == .minorSafety }

    /// Whether this report should trigger NCMEC CyberTipline consideration.
    var mayRequireMandatoryReport: Bool { self == .minorSafety }

    /// Triage priority fed into the moderation queue metadata.
    var priority: String {
        switch self {
        case .minorSafety:                          return "critical"
        case .sexualContent, .sexualSolicitation,
             .hateSpeech, .harassment:              return "high"
        default:                                    return "normal"
        }
    }

    /// Moderation queue routing key.
    var queue: String {
        switch self {
        case .minorSafety:          return "trust_safety_urgent"
        case .sexualContent,
             .sexualSolicitation:   return "trust_safety"
        case .hateSpeech,
             .harassment:           return "policy"
        default:                    return "standard"
        }
    }

    /// Initial report status based on severity.
    var initialStatus: ContentReportStatus {
        self == .minorSafety ? .queuedForUrgentReview : .pending
    }

    var icon: String {
        switch self {
        case .spam:                 return "envelope.badge.fill"
        case .harassment:           return "exclamationmark.bubble.fill"
        case .hateSpeech:           return "hand.raised.fill"
        case .sexualContent:        return "eye.slash.fill"
        case .sexualSolicitation:   return "dollarsign.circle.fill"
        case .minorSafety:          return "shield.fill"
        case .inappropriateContent: return "eye.slash.fill"
        case .falseInformation:     return "checkmark.seal.fill"
        case .offTopic:             return "arrow.triangle.branch"
        case .copyright:            return "c.circle.fill"
        case .other:                return "ellipsis.circle.fill"
        }
    }

    var description: String {
        switch self {
        case .spam:                 return "Unwanted commercial content or repetitive posts"
        case .harassment:           return "Targeted harassment, threats, or bullying"
        case .hateSpeech:           return "Content promoting violence or hatred"
        case .sexualContent:        return "Pornographic, explicit, or sexually graphic content"
        case .sexualSolicitation:   return "Advertising or requesting sexual services"
        case .minorSafety:          return "Content that sexualises or targets a minor — reviewed immediately"
        case .inappropriateContent: return "Other content that doesn't belong in a faith community"
        case .falseInformation:     return "Deliberately misleading or false claims"
        case .offTopic:             return "Content that doesn't fit this category"
        case .copyright:            return "Unauthorized use of copyrighted material"
        case .other:                return "Something else that violates community guidelines"
        }
    }
}

// MARK: - Report Model

struct ContentReport: Identifiable, Codable {
    @DocumentID var id: String?
    var reporterId: String
    var reporterName: String
    var reportedUserId: String?
    var reportedPostId: String?
    var reportedCommentId: String?
    /// Human-readable label (e.g. "Child safety concern")
    var reason: String
    /// Stable machine key (e.g. "minorSafety") — safe for backend pipelines and analytics
    var reasonCategory: String
    var additionalDetails: String?
    var status: ContentReportStatus
    var priority: String
    var queue: String
    var requiresImmediateEscalation: Bool
    var requiresLegalReview: Bool
    var createdAt: Date
    var reviewedAt: Date?
    var reviewedBy: String?
    var actionTaken: ModerationActionTaken?

    enum CodingKeys: String, CodingKey {
        case id
        case reporterId
        case reporterName
        case reportedUserId
        case reportedPostId
        case reportedCommentId
        case reason
        case reasonCategory
        case additionalDetails
        case status
        case priority
        case queue
        case requiresImmediateEscalation
        case requiresLegalReview
        case createdAt
        case reviewedAt
        case reviewedBy
        case actionTaken
    }
}

// MARK: - Block / Mute Models

struct BlockedUserRelationship: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String           // User who blocked
    var blockedUserId: String    // User who is blocked
    var blockedAt: Date
    var reason: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case blockedUserId
        case blockedAt
        case reason
    }
}

struct MutedUser: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String          // User who muted
    var mutedUserId: String     // User who is muted
    var mutedAt: Date
    var mutedUntil: Date?       // Optional expiration

    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case mutedUserId
        case mutedAt
        case mutedUntil
    }
}

// MARK: - Moderation Service Errors

enum ModerationServiceError: LocalizedError {
    case invalidOperation(String)
    case duplicateReport

    var errorDescription: String? {
        switch self {
        case .invalidOperation(let msg): return msg
        case .duplicateReport:           return "You have already submitted this report recently."
        }
    }
}

// MARK: - Moderation Service

@MainActor
class ModerationService: ObservableObject {
    static let shared = ModerationService()

    @Published var blockedUsers: Set<String> = []
    @Published var mutedUsers: Set<String> = []

    private let db = Firestore.firestore()
    private let firebaseManager = FirebaseManager.shared

    private init() {}

    // MARK: - Current User

    private var currentUserId: String? { firebaseManager.currentUser?.uid }

    private func requireCurrentUser() throws -> String {
        guard let uid = currentUserId else { throw FirebaseError.unauthorized }
        return uid
    }

    // MARK: - Report Content (public surface)

    /// Report a post. Calls the shared internal writer.
    func reportPost(
        postId: String,
        postAuthorId: String,
        reason: ModerationReportReason,
        additionalDetails: String?
    ) async throws {
        dlog("🚨 Reporting post: \(postId)")
        try await submitReport(
            reportedUserId: postAuthorId,
            reportedPostId: postId,
            reportedCommentId: nil,
            reason: reason,
            additionalDetails: additionalDetails
        )
    }

    /// Report a comment. Calls the shared internal writer.
    func reportComment(
        commentId: String,
        commentAuthorId: String,
        postId: String,
        reason: ModerationReportReason,
        additionalDetails: String?
    ) async throws {
        dlog("🚨 Reporting comment: \(commentId)")
        try await submitReport(
            reportedUserId: commentAuthorId,
            reportedPostId: postId,
            reportedCommentId: commentId,
            reason: reason,
            additionalDetails: additionalDetails
        )
    }

    /// Report a user. Calls the shared internal writer.
    func reportUser(
        userId: String,
        reason: ModerationReportReason,
        additionalDetails: String?
    ) async throws {
        dlog("🚨 Reporting user: \(userId)")
        try await submitReport(
            reportedUserId: userId,
            reportedPostId: nil,
            reportedCommentId: nil,
            reason: reason,
            additionalDetails: additionalDetails
        )
    }

    // MARK: - Internal Report Writer

    private func submitReport(
        reportedUserId: String?,
        reportedPostId: String?,
        reportedCommentId: String?,
        reason: ModerationReportReason,
        additionalDetails: String?
    ) async throws {
        let reporterId = try requireCurrentUser()

        // Self-report guard
        if let reportedUserId, reportedUserId == reporterId {
            throw ModerationServiceError.invalidOperation("You cannot report yourself.")
        }

        // Sanitize free-text input
        let safeDetails: String? = {
            guard let raw = additionalDetails else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : String(trimmed.prefix(1000))
        }()

        // Fetch reporter name (cache-friendly: call once)
        let userDoc = try await db.collection(FirebaseManager.CollectionPath.users)
            .document(reporterId)
            .getDocument()
        let reporterName = userDoc.data()?["displayName"] as? String ?? "Anonymous"

        // Duplicate-report check: same reporter + same target + same reasonCategory within 24h
        let isDuplicate = try await hasRecentDuplicateReport(
            reporterId: reporterId,
            reportedUserId: reportedUserId,
            reportedPostId: reportedPostId,
            reportedCommentId: reportedCommentId,
            reasonCategory: reason.categoryKey
        )
        if isDuplicate {
            dlog("⏭️ Duplicate report suppressed")
            throw ModerationServiceError.duplicateReport
        }

        let report = ContentReport(
            reporterId: reporterId,
            reporterName: reporterName,
            reportedUserId: reportedUserId,
            reportedPostId: reportedPostId,
            reportedCommentId: reportedCommentId,
            reason: reason.displayName,
            reasonCategory: reason.categoryKey,
            additionalDetails: safeDetails,
            status: reason.initialStatus,
            priority: reason.priority,
            queue: reason.queue,
            requiresImmediateEscalation: reason.requiresImmediateEscalation,
            requiresLegalReview: reason.mayRequireMandatoryReport,
            createdAt: Date(),
            actionTaken: ModerationActionTaken.none
        )

        let reportData = try Firestore.Encoder().encode(report)
        try await db.collection(FirebaseManager.CollectionPath.reports)
            .addDocument(data: reportData)

        dlog("✅ Report submitted — priority: \(reason.priority), queue: \(reason.queue)")
    }

    /// Returns true if an identical report was already submitted within the last 24 hours.
    private func hasRecentDuplicateReport(
        reporterId: String,
        reportedUserId: String?,
        reportedPostId: String?,
        reportedCommentId: String?,
        reasonCategory: String
    ) async throws -> Bool {
        let cutoff = Date().addingTimeInterval(-86_400)  // 24 hours ago
        var query: Query = db.collection(FirebaseManager.CollectionPath.reports)
            .whereField("reporterId", isEqualTo: reporterId)
            .whereField("reasonCategory", isEqualTo: reasonCategory)
            .whereField("createdAt", isGreaterThan: Timestamp(date: cutoff))
            .limit(to: 1)

        // Narrow by the most specific target available
        if let commentId = reportedCommentId {
            query = query.whereField("reportedCommentId", isEqualTo: commentId)
        } else if let postId = reportedPostId {
            query = query.whereField("reportedPostId", isEqualTo: postId)
        } else if let userId = reportedUserId {
            query = query.whereField("reportedUserId", isEqualTo: userId)
        }

        let snapshot = try await query.getDocuments()
        return !snapshot.documents.isEmpty
    }

    // MARK: - Block User

    /// Block a user. Uses a deterministic doc ID to prevent duplicate block records.
    func blockUser(userId: String, reason: String? = nil) async throws {
        dlog("🚫 Blocking user: \(userId)")

        let currentUserId = try requireCurrentUser()

        guard userId != currentUserId else {
            dlog("⚠️ Cannot block yourself")
            return
        }

        // Optimistic guard from local cache
        guard !blockedUsers.contains(userId) else {
            dlog("⚠️ User already blocked")
            return
        }

        let docId = "\(currentUserId)_\(userId)"
        let block = BlockedUserRelationship(
            userId: currentUserId,
            blockedUserId: userId,
            blockedAt: Date(),
            reason: reason
        )

        // setData(merge: true) is idempotent — safe to call even if the doc exists
        let blockData = try Firestore.Encoder().encode(block)
        try await db.collection(FirebaseManager.CollectionPath.blockedUsers)
            .document(docId)
            .setData(blockData, merge: true)

        dlog("✅ User blocked successfully")

        // Update local cache first so UI reflects state immediately
        blockedUsers.insert(userId)

        // Tear down follow relationship in both directions.
        // Errors here are logged but do not roll back the block.
        do {
            // Unfollow the blocked user (A → B)
            try await FollowService.shared.unfollowUser(userId: userId)
        } catch {
            dlog("⚠️ Unfollow after block failed (A→B): \(error) — block record is still valid")
        }
        do {
            // Remove the blocked user as a follower of us (B → A)
            try await FollowService.shared.removeFollower(followerId: userId)
        } catch {
            dlog("⚠️ Follower removal after block failed (B→A): \(error) — block record is still valid")
        }
    }

    /// Unblock a user.
    func unblockUser(userId: String) async throws {
        dlog("🔓 Unblocking user: \(userId)")

        let currentUserId = try requireCurrentUser()
        let docId = "\(currentUserId)_\(userId)"

        try await db.collection(FirebaseManager.CollectionPath.blockedUsers)
            .document(docId)
            .delete()

        dlog("✅ User unblocked successfully")
        blockedUsers.remove(userId)
    }

    /// Check if a user is blocked.
    /// Fail-closed: returns cached state on network failure so a known block is never silently dropped.
    func isBlocked(userId: String) async -> Bool {
        // Cache is authoritative for already-known blocks
        if blockedUsers.contains(userId) { return true }

        guard let currentUserId = currentUserId else { return false }

        do {
            let docId = "\(currentUserId)_\(userId)"
            let doc = try await db.collection(FirebaseManager.CollectionPath.blockedUsers)
                .document(docId)
                .getDocument()
            let blocked = doc.exists
            if blocked { blockedUsers.insert(userId) }
            return blocked
        } catch {
            dlog("⚠️ isBlocked lookup failed: \(error) — returning cached state")
            return blockedUsers.contains(userId)
        }
    }

    // MARK: - Mute User

    /// Mute a user. Uses a deterministic doc ID to prevent duplicate mute records.
    func muteUser(userId: String, duration: TimeInterval? = nil) async throws {
        dlog("🔇 Muting user: \(userId)")

        let currentUserId = try requireCurrentUser()

        guard userId != currentUserId else {
            dlog("⚠️ Cannot mute yourself")
            return
        }

        guard !mutedUsers.contains(userId) else {
            dlog("⚠️ User already muted")
            return
        }

        let mutedUntil = duration.map { Date().addingTimeInterval($0) }

        let mute = MutedUser(
            userId: currentUserId,
            mutedUserId: userId,
            mutedAt: Date(),
            mutedUntil: mutedUntil
        )

        let docId = "\(currentUserId)_\(userId)"
        let muteData = try Firestore.Encoder().encode(mute)
        try await db.collection(FirebaseManager.CollectionPath.mutedUsers)
            .document(docId)
            .setData(muteData, merge: true)

        dlog("✅ User muted successfully")
        mutedUsers.insert(userId)
    }

    /// Unmute a user.
    func unmuteUser(userId: String) async throws {
        dlog("🔊 Unmuting user: \(userId)")

        let currentUserId = try requireCurrentUser()
        let docId = "\(currentUserId)_\(userId)"

        try await db.collection(FirebaseManager.CollectionPath.mutedUsers)
            .document(docId)
            .delete()

        dlog("✅ User unmuted successfully")
        mutedUsers.remove(userId)
    }

    /// Check if a user is muted.
    /// Fail-closed: returns cached state on network failure.
    func isMuted(userId: String) async -> Bool {
        if mutedUsers.contains(userId) { return true }

        guard let currentUserId = currentUserId else { return false }

        do {
            let docId = "\(currentUserId)_\(userId)"
            let doc = try await db.collection(FirebaseManager.CollectionPath.mutedUsers)
                .document(docId)
                .getDocument()

            guard doc.exists else { return false }

            // Check expiry
            if let mutedUntilTimestamp = doc.data()?["mutedUntil"] as? Timestamp {
                let mutedUntil = mutedUntilTimestamp.dateValue()
                if mutedUntil < Date() {
                    // Expired — clean up asynchronously and return false
                    Task.detached { [weak self] in
                        try? await self?.unmuteUser(userId: userId)
                    }
                    return false
                }
            }

            mutedUsers.insert(userId)
            return true
        } catch {
            dlog("⚠️ isMuted lookup failed: \(error) — returning cached state")
            return mutedUsers.contains(userId)
        }
    }

    // MARK: - Hide Profile From User

    /// Hide your profile from a specific user.
    /// NOTE: The current implementation uses arrayUnion on the user document.
    /// For production at scale, migrate to a dedicated `hiddenProfileRelationships` collection
    /// with documents keyed by "\(ownerUserId)_\(hiddenFromUserId)" to avoid document-size limits.
    func hideProfileFromUser(userId: String) async throws {
        dlog("👁️‍🗨️ Hiding profile from user: \(userId)")

        let currentUserId = try requireCurrentUser()

        guard userId != currentUserId else {
            dlog("⚠️ Cannot hide from yourself")
            return
        }

        try await db.collection(FirebaseManager.CollectionPath.users)
            .document(currentUserId)
            .updateData(["hiddenFromUsers": FieldValue.arrayUnion([userId])])

        dlog("✅ Profile hidden from user successfully")
    }

    /// Unhide your profile from a specific user.
    func unhideProfileFromUser(userId: String) async throws {
        dlog("👁️ Unhiding profile from user: \(userId)")

        let currentUserId = try requireCurrentUser()

        try await db.collection(FirebaseManager.CollectionPath.users)
            .document(currentUserId)
            .updateData(["hiddenFromUsers": FieldValue.arrayRemove([userId])])

        dlog("✅ Profile unhidden from user successfully")
    }

    /// Check if your profile is hidden from a specific user.
    func isHiddenFrom(userId: String) async -> Bool {
        guard let currentUserId = currentUserId else { return false }

        do {
            let userDoc = try await db.collection(FirebaseManager.CollectionPath.users)
                .document(currentUserId)
                .getDocument()
            let hiddenFromUsers = userDoc.data()?["hiddenFromUsers"] as? [String] ?? []
            return hiddenFromUsers.contains(userId)
        } catch {
            dlog("⚠️ Failed to check hide status: \(error)")
            return false
        }
    }

    // MARK: - Fetch Lists

    /// Fetch and cache all blocked users for the current session.
    func fetchBlockedUsers() async throws -> [String] {
        let currentUserId = try requireCurrentUser()

        let snapshot = try await db.collection(FirebaseManager.CollectionPath.blockedUsers)
            .whereField("userId", isEqualTo: currentUserId)
            .order(by: "blockedAt", descending: true)
            .getDocuments()

        let blocked = snapshot.documents.compactMap { $0.data()["blockedUserId"] as? String }
        blockedUsers = Set(blocked)

        dlog("✅ Fetched \(blocked.count) blocked users")
        return blocked
    }

    /// Fetch and cache all muted users for the current session, pruning expired entries.
    func fetchMutedUsers() async throws -> [String] {
        let currentUserId = try requireCurrentUser()

        let snapshot = try await db.collection(FirebaseManager.CollectionPath.mutedUsers)
            .whereField("userId", isEqualTo: currentUserId)
            .order(by: "mutedAt", descending: true)
            .getDocuments()

        var muted: [String] = []

        for doc in snapshot.documents {
            if let mutedUntilTimestamp = doc.data()["mutedUntil"] as? Timestamp {
                let mutedUntil = mutedUntilTimestamp.dateValue()
                if mutedUntil < Date() {
                    try? await doc.reference.delete()
                    continue
                }
            }
            if let mutedUserId = doc.data()["mutedUserId"] as? String {
                muted.append(mutedUserId)
            }
        }

        mutedUsers = Set(muted)

        dlog("✅ Fetched \(muted.count) muted users")
        return muted
    }

    // MARK: - Load Current User's Moderation Data

    func loadCurrentUserModeration() async {
        do {
            _ = try await fetchBlockedUsers()
            _ = try await fetchMutedUsers()
            dlog("✅ Loaded moderation data")
        } catch {
            dlog("❌ Failed to load moderation data: \(error)")
        }
    }

    // MARK: - Visibility Policy Helpers

    /// Whether a user's content should be hidden from the current user's feed.
    func shouldHideUser(_ authorId: String) -> Bool {
        blockedUsers.contains(authorId) || mutedUsers.contains(authorId)
    }

    /// Whether a post from `authorId` should be shown to the current user.
    func shouldShowPost(authorId: String) -> Bool {
        !shouldHideUser(authorId)
    }

    /// Whether a comment from `authorId` should be shown to the current user.
    func shouldShowComment(authorId: String) -> Bool {
        !blockedUsers.contains(authorId)    // Muted users' comments are still visible
    }

    /// Whether the current user can interact with (reply to, mention, DM) another user.
    func canInteract(with userId: String) -> Bool {
        !blockedUsers.contains(userId)
    }

    /// Filter posts, removing those from blocked or muted users.
    func filterPosts(_ posts: [Post]) -> [Post] {
        posts.filter { shouldShowPost(authorId: $0.authorId) }
    }
}

// MARK: - Firestore Collection Paths

extension FirebaseManager.CollectionPath {
    static let reports = "reports"
    static let blockedUsers = "blockedUsers"
    static let mutedUsers = "mutedUsers"
}
