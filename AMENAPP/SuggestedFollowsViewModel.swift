//
//  SuggestedFollowsViewModel.swift
//  AMENAPP
//
//  System 13: Suggested Follows
//  Manages the suggestion list for the SuggestedFollowsSheet.
//  Responsibilities:
//    - When `suggestedFollowsSmartRankingEnabled` is ON, fetch from
//      SuggestedFollowsService (church/mutual/city/translation/recency signals).
//    - Fall back to RecommendedUsersAIService when flag is OFF.
//    - Unify both paths into [DisplaySuggestion] so the sheet renders identically.
//    - Apply FollowSafetyFilter exclusions on the fallback path.
//    - Track dismissed user IDs so they don't re-appear within the session.
//    - Support "load more" to surface additional candidates.
//

import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Unified display model

/// Single display type consumed by SuggestedFollowsSheet / SuggestedUserRow,
/// regardless of which backend pipeline produced the result.
struct DisplaySuggestion: Identifiable {
    let id: String              // userId
    let name: String
    let username: String
    let profileImageURL: String?
    let matchScore: Int         // 0-100 normalised
    let primaryReason: String   // "Goes to your church"
    let secondaryReasons: [String] // Up to 2 extra pills
    let mutualFriendCount: Int
    /// true when the target account requires a follow request (isPrivate = true)
    var isPrivate: Bool = false

    // Convenience bridge from RecommendedUsersAIService.UserRecommendation
    init(from rec: RecommendedUsersAIService.UserRecommendation) {
        self.id = rec.id
        self.name = rec.name
        self.username = rec.username
        self.profileImageURL = rec.profileImageURL
        self.matchScore = rec.matchScore
        self.primaryReason = rec.sharedInterests.first ?? rec.matchReason
        self.secondaryReasons = Array(rec.sharedInterests.dropFirst().prefix(2))
        self.mutualFriendCount = rec.mutualFriendCount
        self.isPrivate = rec.isPrivate ?? false
    }

    // Convenience bridge from SuggestedFollowsService.SuggestedUser
    init(from smart: SuggestedUser) {
        self.id = smart.id
        self.name = smart.displayName
        self.username = smart.username
        self.profileImageURL = smart.profileImageURL
        self.matchScore = smart.score
        self.primaryReason = smart.reason
        self.secondaryReasons = smart.secondaryReasons
        self.mutualFriendCount = smart.mutualCount
        self.isPrivate = smart.isPrivate
    }
}

// MARK: - ViewModel

@MainActor
final class SuggestedFollowsViewModel: ObservableObject {

    @Published var suggestions: [DisplaySuggestion] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var hasLoaded = false

    /// The profile being viewed — used as a seeding hint for recommendations.
    let profileUserId: String

    /// Set of user IDs the current user dismissed this session.
    private var dismissedUserIds: Set<String> = []

    /// Page size for each load batch
    private let pageSize = 8

    init(profileUserId: String) {
        self.profileUserId = profileUserId
    }

    // MARK: - Load Initial Suggestions

    func loadSuggestions() async {
        guard !hasLoaded else { return }
        isLoading = true
        defer { isLoading = false }

        if AMENFeatureFlags.shared.suggestedFollowsSmartRankingEnabled {
            let smartResults = await SuggestedFollowsService.shared.fetchSuggestions()
            suggestions = smartResults
                .filter { !dismissedUserIds.contains($0.id) }
                .prefix(pageSize)
                .map { DisplaySuggestion(from: $0) }
        } else {
            await RecommendedUsersAIService.shared.fetchRecommendations()
            let raw = RecommendedUsersAIService.shared.recommendations
            suggestions = applyLegacyFilters(raw, limit: pageSize)
                .map { DisplaySuggestion(from: $0) }
        }

        hasLoaded = true
    }

    // MARK: - Load More

    func loadMoreSuggestions() async {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        if AMENFeatureFlags.shared.suggestedFollowsSmartRankingEnabled {
            // Force-refresh to get fresh candidates
            let smartResults = await SuggestedFollowsService.shared.fetchSuggestions(forceRefresh: true)
            let currentIds = Set(suggestions.map { $0.id })
            let newCandidates = smartResults
                .filter { !currentIds.contains($0.id) && !dismissedUserIds.contains($0.id) }
                .prefix(pageSize)
                .map { DisplaySuggestion(from: $0) }
            suggestions.append(contentsOf: newCandidates)
        } else {
            await RecommendedUsersAIService.shared.fetchRecommendations()
            let raw = RecommendedUsersAIService.shared.recommendations
            let currentIds = Set(suggestions.map { $0.id })
            let newCandidates = applyLegacyFilters(raw, limit: pageSize + 8)
                .filter { !currentIds.contains($0.id) }
                .prefix(pageSize)
                .map { DisplaySuggestion(from: $0) }
            suggestions.append(contentsOf: newCandidates)
        }
    }

    // MARK: - Remove Followed

    func removeFollowed(userId: String) {
        withAnimation(.easeOut(duration: 0.25)) {
            suggestions.removeAll { $0.id == userId }
        }
        SuggestedFollowsService.shared.invalidateCache()
    }

    // MARK: - Dismiss (Not relevant)

    func dismiss(userId: String) {
        dismissedUserIds.insert(userId)
        withAnimation(.easeOut(duration: 0.25)) {
            suggestions.removeAll { $0.id == userId }
        }
        Task.detached {
            await self.writeDismissal(userId: userId)
        }
    }

    // MARK: - Private Helpers

    private func applyLegacyFilters(
        _ raw: [RecommendedUsersAIService.UserRecommendation],
        limit: Int
    ) -> [RecommendedUsersAIService.UserRecommendation] {
        let safetyFiltered = FollowSafetyFilter.shared.filter(raw, limit: limit + 20)
        return safetyFiltered
            .filter { !dismissedUserIds.contains($0.id) }
            .prefix(limit)
            .map { $0 }
    }

    private func writeDismissal(userId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        lazy var db = Firestore.firestore()
        let doc: [String: Any] = [
            "dismissedUserId": userId,
            "dismissedAt": Timestamp(date: Date()),
            "source": "suggested_follows_sheet"
        ]
        do {
            try await db.collection("users").document(uid)
                .collection("dismissedSuggestions")
                .document(userId)
                .setData(doc, merge: true)
        } catch {
            dlog("SuggestedFollowsViewModel: dismissal write failed: \(error.localizedDescription)")
        }
    }
}
