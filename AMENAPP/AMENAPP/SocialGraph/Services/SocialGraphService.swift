// SocialGraphService.swift
// AMENAPP
//
// Primary data-fetching service for followers/following/mutuals lists.
// Reads from Firestore `follows` collection (same schema as FollowService),
// enriches with activity data, and exposes paginated async results.

import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class SocialGraphService {

    static let shared = SocialGraphService()

    private let db = Firestore.firestore()
    private let pageSize = 30

    private init() {}

    // MARK: - Fetch Followers

    func fetchFollowers(
        for userId: String,
        after cursor: DocumentSnapshot? = nil
    ) async throws -> SocialGraphPage {
        var query = db.collection("follows")
            .whereField("followingId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .limit(to: pageSize)

        if let cursor { query = query.start(afterDocument: cursor) }

        let snap = try await query.getDocuments()
        return try await buildPage(snap, roleField: "followerId", userId: userId)
    }

    // MARK: - Fetch Following

    func fetchFollowing(
        for userId: String,
        after cursor: DocumentSnapshot? = nil
    ) async throws -> SocialGraphPage {
        var query = db.collection("follows")
            .whereField("followerId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .limit(to: pageSize)

        if let cursor { query = query.start(afterDocument: cursor) }

        let snap = try await query.getDocuments()
        return try await buildPage(snap, roleField: "followingId", userId: userId)
    }

    // MARK: - Fetch Mutuals

    /// Returns users that both follow the given userId AND are followed by them.
    func fetchMutuals(for userId: String) async throws -> [SmartUserRowViewModel] {
        // Get following set
        let followingSnap = try await db.collection("follows")
            .whereField("followerId", isEqualTo: userId)
            .getDocuments()
        let followingIds = Set(followingSnap.documents.compactMap { $0["followingId"] as? String })

        // Get follower set
        let followerSnap = try await db.collection("follows")
            .whereField("followingId", isEqualTo: userId)
            .getDocuments()
        let followerIds = Set(followerSnap.documents.compactMap { $0["followerId"] as? String })

        let mutualIds = Array(followingIds.intersection(followerIds))
        guard !mutualIds.isEmpty else { return [] }

        return try await buildViewModels(for: mutualIds, viewingUserId: userId, isFollowing: true, isFollowedBack: true)
    }

    // MARK: - Build Page

    private func buildPage(
        _ snap: QuerySnapshot,
        roleField: String,
        userId: String
    ) async throws -> SocialGraphPage {
        let targetIds = snap.documents.compactMap { $0[roleField] as? String }
        guard !targetIds.isEmpty else {
            return SocialGraphPage(rows: [], cursor: nil, hasMore: false)
        }

        let viewerId = Auth.auth().currentUser?.uid ?? userId
        let isFollowingPage = roleField == "followingId"

        let rows = try await buildViewModels(
            for: targetIds,
            viewingUserId: viewerId,
            isFollowing: isFollowingPage,
            isFollowedBack: !isFollowingPage
        )

        return SocialGraphPage(
            rows: rows,
            cursor: snap.documents.last,
            hasMore: snap.documents.count == pageSize
        )
    }

    // MARK: - Build ViewModels

    private func buildViewModels(
        for userIds: [String],
        viewingUserId: String,
        isFollowing: Bool,
        isFollowedBack: Bool
    ) async throws -> [SmartUserRowViewModel] {
        // Fetch profiles
        let profiles = try await fetchProfiles(userIds: userIds)

        // Fetch activity summaries + relationship states in parallel
        async let summaries = ActivitySummaryService.shared.fetchSummaries(for: userIds)
        async let relationships = RelationshipActivityService.shared.fetchAll(targetIds: userIds)

        let (summaryMap, relationshipMap) = await (summaries, relationships)

        return userIds.compactMap { uid in
            guard let profile = profiles[uid] else { return nil }

            let summary = summaryMap[uid]
            let relationship = relationshipMap[uid]

            let activityState = buildActivityState(
                userId: uid,
                summary: summary,
                relationship: relationship
            )
            let copy = SmartActivityCopyGenerator.generate(
                summary: summary,
                relationship: relationship
            )

            return SmartUserRowViewModel(
                id: uid,
                displayName: profile.displayName,
                username: profile.username,
                profileImageURL: profile.profileImageURL,
                bio: profile.bio,
                isFollowing: isFollowing,
                isFollowedBack: isFollowedBack,
                activityState: activityState,
                copy: copy
            )
        }
    }

    // MARK: - Profile Fetch

    private func fetchProfiles(userIds: [String]) async throws -> [String: SocialProfile] {
        var result: [String: SocialProfile] = [:]
        let chunks = userIds.socialGraphChunked(into: 30)

        try await withThrowingTaskGroup(of: [String: SocialProfile].self) { group in
            for chunk in chunks {
                group.addTask {
                    let snap = try await self.db.collection("users")
                        .whereField(FieldPath.documentID(), in: chunk)
                        .getDocuments()
                    var partial: [String: SocialProfile] = [:]
                    for doc in snap.documents {
                        let data = doc.data()
                        let profile = SocialProfile(
                            id: doc.documentID,
                            displayName: data["displayName"] as? String ?? data["name"] as? String ?? "",
                            username: data["username"] as? String ?? "",
                            profileImageURL: data["profileImageURL"] as? String,
                            bio: data["bio"] as? String
                        )
                        partial[doc.documentID] = profile
                    }
                    return partial
                }
            }
            for try await partial in group {
                result.merge(partial) { $1 }
            }
        }

        return result
    }

    // MARK: - ActivityState Builder

    private func buildActivityState(
        userId: String,
        summary: UserActivitySummary?,
        relationship: RelationshipActivityState?
    ) -> SmartActivityState {
        SmartActivityState(
            userId: userId,
            activityType: summary?.primaryActivityType ?? .none,
            unseenCount: relationship?.totalUnseenCount ?? 0,
            lastActivityAt: summary?.lastActiveAt,
            hasUnseen: relationship?.hasUnseen ?? false,
            hasMutualInteraction: relationship?.hasMutualInteraction ?? false,
            activeStreak: summary?.activeStreak ?? 0,
            mutualTopics: relationship?.mutualTopics ?? [],
            snippet: summary?.latestPostSnippet
        )
    }
}

// MARK: - Supporting Types

struct SocialGraphPage {
    let rows: [SmartUserRowViewModel]
    let cursor: DocumentSnapshot?
    let hasMore: Bool
}

struct SocialProfile {
    let id: String
    let displayName: String
    let username: String
    let profileImageURL: String?
    let bio: String?
}
