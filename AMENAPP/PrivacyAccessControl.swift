// PrivacyAccessControl.swift
// AMENAPP
//
// Central enforcement layer for private-account access control.
// ALL privacy decisions MUST go through this service.
// Never trust client state alone — this service re-validates against Firestore.
//
// Architecture:
//   PrivacyAccessControl.shared.canView(content:by:)  → Bool
//   PrivacyAccessControl.shared.canComment(on:by:)    → Bool
//   PrivacyAccessControl.shared.canMessage(user:by:)  → Bool
//   PrivacyAccessControl.shared.relationship(to:)     → ViewerRelationship
//
// All results are cached for 60 s with immediate invalidation on follow/block events.

import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth

// MARK: - Viewer Relationship

/// The full access relationship between the current viewer and a target user.
/// This is the single source of truth used by every privacy check in the app.
enum ViewerRelationship: Equatable {
    case ownProfile                // Viewer IS the target user
    case approvedFollower          // Viewer follows target AND target accepted
    case pendingRequest            // Viewer sent a request, not yet accepted
    case notFollowing              // No relationship at all
    case blocked                   // Viewer has blocked target
    case blockedBy                 // Target has blocked viewer
    case mutualFollowers           // Both follow each other

    var canViewPrivateContent: Bool {
        switch self {
        case .ownProfile, .approvedFollower, .mutualFollowers: return true
        default: return false
        }
    }

    var canComment: Bool {
        switch self {
        case .ownProfile, .approvedFollower, .mutualFollowers: return true
        default: return false
        }
    }

    var canSendMessage: Bool {
        switch self {
        case .ownProfile: return false // Can't DM yourself
        case .approvedFollower, .mutualFollowers: return true
        case .notFollowing, .pendingRequest: return false
        case .blocked, .blockedBy: return false
        }
    }

    var canSeeFollowerLists: Bool {
        switch self {
        case .ownProfile, .approvedFollower, .mutualFollowers: return true
        default: return false
        }
    }

    var isBlocking: Bool {
        self == .blocked || self == .blockedBy
    }
}

// MARK: - Privacy Access Control

@MainActor
final class PrivacyAccessControl: ObservableObject {
    static let shared = PrivacyAccessControl()

    private let db = Firestore.firestore()
    private var cache: [String: CachedRelationship] = [:]
    private let cacheExpirySeconds: TimeInterval = 60

    // Expose current user convenience
    var currentUserId: String? { Auth.auth().currentUser?.uid }

    private init() {
        // Invalidate cache when auth changes
        NotificationCenter.default.addObserver(
            forName: .followRelationshipChanged,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let userId = notification.userInfo?["userId"] as? String
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let userId {
                    self.cache.removeValue(forKey: userId)
                } else {
                    self.cache.removeAll()
                }
            }
        }
    }

    // MARK: - Main API

    /// Compute and cache the full access relationship between the current viewer and `targetUserId`.
    func relationship(to targetUserId: String) async -> ViewerRelationship {
        guard let viewerId = currentUserId else { return .notFollowing }

        // Own profile
        if viewerId == targetUserId { return .ownProfile }

        // Return cached result if still fresh
        if let cached = cache[targetUserId], !cached.isExpired {
            return cached.relationship
        }

        // Compute fresh
        let rel = await computeRelationship(viewerId: viewerId, targetUserId: targetUserId)
        cache[targetUserId] = CachedRelationship(relationship: rel)
        return rel
    }

    /// True if the current viewer can see a private user's protected content.
    func canViewPrivateContent(of targetUserId: String) async -> Bool {
        let rel = await relationship(to: targetUserId)
        return rel.canViewPrivateContent
    }

    /// True if the current viewer may comment on a post authored by `authorId`.
    func canComment(onPostBy authorId: String, postVisibility: String, isAuthorPrivate: Bool) async -> Bool {
        guard let viewerId = currentUserId else { return false }
        if viewerId == authorId { return true }

        let rel = await relationship(to: authorId)

        // Blocked relationships never get to comment
        if rel.isBlocking { return false }

        // If the author's account is private, only approved followers can comment
        if isAuthorPrivate && !rel.canViewPrivateContent { return false }

        // Respect the post-level visibility setting
        switch postVisibility {
        case "followers":
            return rel.canViewPrivateContent
        case "nobody":
            return viewerId == authorId
        default: // "everyone"
            return !rel.isBlocking
        }
    }

    /// True if the current viewer may initiate a DM with `targetUserId`.
    func canMessage(userId targetUserId: String, targetPrivacySettings: PrivacyUserSettings?) async -> Bool {
        guard let viewerId = currentUserId else { return false }
        if viewerId == targetUserId { return false }

        let rel = await relationship(to: targetUserId)

        // Blocked users can never message
        if rel.isBlocking { return false }

        // Apply whoCanDM setting
        let whoCanDM = targetPrivacySettings?.whoCanDM ?? .everyone
        switch whoCanDM {
        case .nobody:
            return false
        case .followers:
            return rel.canViewPrivateContent
        case .everyone:
            // Even with "everyone" setting, if target has a private account,
            // non-followers cannot initiate (they must request to follow first)
            // Private-account DM policy: mutual or approved followers only
            if targetPrivacySettings?.isPrivate == true {
                return rel.canViewPrivateContent
            }
            return true
        }
    }

    /// Invalidate a specific user's cached relationship (call on follow/unfollow/block/unblock).
    func invalidate(userId: String) {
        cache.removeValue(forKey: userId)
    }

    /// Invalidate all cached relationships.
    func invalidateAll() {
        cache.removeAll()
    }

    // MARK: - Profile Visibility

    /// Returns a `ProfileVisibility` describing exactly what a non-follower can see on a private profile.
    func profileVisibility(for targetUserId: String) async -> ProfileVisibility {
        let rel = await relationship(to: targetUserId)

        // Load the target user's privacy prefs
        let prefs = await fetchPrivacySettings(userId: targetUserId)
        let isPrivate = prefs?.isPrivate ?? false

        if rel.canViewPrivateContent || !isPrivate {
            return ProfileVisibility(
                canSeePostCount: true,
                canSeePosts: true,
                canSeeFollowerCount: prefs?.showFollowerCount ?? true,
                canSeeFollowingCount: prefs?.showFollowingCount ?? true,
                canSeeFollowerList: prefs?.showFollowersList ?? true,
                canSeeFollowingList: prefs?.showFollowingList ?? true,
                canSeeBio: true,
                canSeeProfilePhoto: true,
                showLockedState: false
            )
        }

        // Non-follower view of a private account: show minimal info only
        return ProfileVisibility(
            canSeePostCount: true,   // Show count but not content
            canSeePosts: false,
            canSeeFollowerCount: prefs?.showFollowerCount ?? true,
            canSeeFollowingCount: prefs?.showFollowingCount ?? true,
            canSeeFollowerList: false,  // Cannot browse follower list
            canSeeFollowingList: false,
            canSeeBio: true,         // Bio and photo are always visible
            canSeeProfilePhoto: true,
            showLockedState: true
        )
    }

    // MARK: - Private Computation

    private func computeRelationship(viewerId: String, targetUserId: String) async -> ViewerRelationship {
        // Run block and follow checks concurrently
        async let blockedTask = checkBlocked(viewerId: viewerId, targetUserId: targetUserId)
        async let youFollowTask = checkFollows(followerId: viewerId, followingId: targetUserId)
        async let theyFollowTask = checkFollows(followerId: targetUserId, followingId: viewerId)
        async let pendingTask = checkPendingRequest(fromUserId: viewerId, toUserId: targetUserId)

        let (blockState, youFollow, theyFollow, pending) = await (
            blockedTask, youFollowTask, theyFollowTask, pendingTask
        )

        if blockState == .blocked { return .blocked }
        if blockState == .blockedBy { return .blockedBy }

        if youFollow && theyFollow { return .mutualFollowers }
        if youFollow { return .approvedFollower }
        if pending { return .pendingRequest }
        return .notFollowing
    }

    private enum BlockState { case none, blocked, blockedBy }

    private func checkBlocked(viewerId: String, targetUserId: String) async -> BlockState {
        do {
            async let viewerBlockedTargetTask = db.collection("blocks")
                .whereField("blockerId", isEqualTo: viewerId)
                .whereField("blockedId", isEqualTo: targetUserId)
                .limit(to: 1)
                .getDocuments()

            async let targetBlockedViewerTask = db.collection("blocks")
                .whereField("blockerId", isEqualTo: targetUserId)
                .whereField("blockedId", isEqualTo: viewerId)
                .limit(to: 1)
                .getDocuments()

            let (viewerBlockedTarget, targetBlockedViewer) = try await (
                viewerBlockedTargetTask,
                targetBlockedViewerTask
            )

            if !viewerBlockedTarget.documents.isEmpty { return .blocked }
            if !targetBlockedViewer.documents.isEmpty { return .blockedBy }
        } catch {
            dlog("⚠️ PrivacyAccessControl: block check failed: \(error)")
        }
        return .none
    }

    private func checkFollows(followerId: String, followingId: String) async -> Bool {
        do {
            let snap = try await db.collection("follows")
                .whereField("followerId", isEqualTo: followerId)
                .whereField("followingId", isEqualTo: followingId)
                .limit(to: 1)
                .getDocuments()
            return !snap.documents.isEmpty
        } catch {
            return false
        }
    }

    private func checkPendingRequest(fromUserId: String, toUserId: String) async -> Bool {
        do {
            let snap = try await db.collection("followRequests")
                .whereField("fromUserId", isEqualTo: fromUserId)
                .whereField("toUserId", isEqualTo: toUserId)
                .whereField("status", isEqualTo: "pending")
                .limit(to: 1)
                .getDocuments()
            return !snap.documents.isEmpty
        } catch {
            return false
        }
    }

    func fetchPrivacySettings(userId: String) async -> PrivacyUserSettings? {
        do {
            let doc = try await db.collection("users").document(userId).getDocument()
            guard let data = doc.data() else { return nil }
            return PrivacyUserSettings(from: data)
        } catch {
            return nil
        }
    }
}

// MARK: - Supporting Models

struct PrivacyUserSettings {
    var isPrivate: Bool
    var whoCanComment: AudienceOption
    var whoCanDM: AudienceOption
    var whoCanMention: AudienceOption
    var showFollowerCount: Bool
    var showFollowingCount: Bool
    var showFollowersList: Bool
    var showFollowingList: Bool

    init(from data: [String: Any]) {
        isPrivate = data["isPrivate"] as? Bool ?? data["isPrivateAccount"] as? Bool ?? false
        let commentRaw = data["whoCanComment"] as? String ?? "everyone"
        let dmRaw = data["whoCanDM"] as? String ?? "everyone"
        let mentionRaw = data["whoCanMention"] as? String ?? "everyone"
        whoCanComment = AudienceOption(rawValue: commentRaw) ?? .everyone
        whoCanDM = AudienceOption(rawValue: dmRaw) ?? .everyone
        whoCanMention = AudienceOption(rawValue: mentionRaw) ?? .everyone
        showFollowerCount = data["showFollowerCount"] as? Bool ?? true
        showFollowingCount = data["showFollowingCount"] as? Bool ?? true
        showFollowersList = data["showFollowersList"] as? Bool ?? true
        showFollowingList = data["showFollowingList"] as? Bool ?? true
    }

    enum AudienceOption: String, CaseIterable {
        case everyone
        case followers
        case nobody
    }
}

struct ProfileVisibility {
    var canSeePostCount: Bool
    var canSeePosts: Bool
    var canSeeFollowerCount: Bool
    var canSeeFollowingCount: Bool
    var canSeeFollowerList: Bool
    var canSeeFollowingList: Bool
    var canSeeBio: Bool
    var canSeeProfilePhoto: Bool
    var showLockedState: Bool
}

// MARK: - Cache

private struct CachedRelationship {
    let relationship: ViewerRelationship
    let timestamp: Date = Date()

    var isExpired: Bool {
        Date().timeIntervalSince(timestamp) > 60
    }
}

// MARK: - Notification

extension Notification.Name {
    static let followRelationshipChanged = Notification.Name("followRelationshipChanged")
    static let privacySettingsChanged = Notification.Name("privacySettingsChanged")
}
