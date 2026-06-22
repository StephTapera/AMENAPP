//
//  SuggestedFollowsViewModel.swift
//  AMENAPP
//
//  System 13: Suggested Follows
//  Manages the suggestion list for the SuggestedFollowsSheet.
//  Responsibilities:
//    - Fetch recommendations from RecommendedUsersAIService
//    - Apply FollowSafetyFilter exclusions
//    - Track dismissed user IDs so they don't re-appear within the session
//    - Support "load more" to surface additional candidates
//

import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class SuggestedFollowsViewModel: ObservableObject {

    @Published var suggestions: [RecommendedUsersAIService.UserRecommendation] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var hasLoaded = false

    /// The profile being viewed — used as a seeding hint for recommendations.
    let profileUserId: String

    /// Set of user IDs the current user dismissed this session.
    /// Persisted for the session; not written to Firestore (low-stakes dismissal).
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

        // Trigger fetch (internally cached for 6 hours)
        await RecommendedUsersAIService.shared.fetchRecommendations()

        let raw = RecommendedUsersAIService.shared.recommendations
        suggestions = applyFilters(raw, limit: pageSize)
        hasLoaded = true
    }

    // MARK: - Load More

    func loadMoreSuggestions() async {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        // Force a fresh fetch to get extended candidates
        await RecommendedUsersAIService.shared.fetchRecommendations()

        let raw = RecommendedUsersAIService.shared.recommendations
        let currentIds = Set(suggestions.map { $0.id })

        // Filter the full set, remove already-shown, apply safety rules, append
        let newCandidates = applyFilters(raw, limit: pageSize + 8)
            .filter { !currentIds.contains($0.id) }
            .prefix(pageSize)

        suggestions.append(contentsOf: newCandidates)
    }

    // MARK: - Remove Followed

    /// Call when a user taps Follow — removes them from the visible list.
    func removeFollowed(userId: String) {
        withAnimation(.easeOut(duration: 0.25)) {
            suggestions.removeAll { $0.id == userId }
        }
    }

    // MARK: - Dismiss (Not relevant)

    /// Call when a user taps "Not now" on a row.
    /// Records dismissal in session memory and removes the row.
    func dismiss(userId: String) {
        dismissedUserIds.insert(userId)
        withAnimation(.easeOut(duration: 0.25)) {
            suggestions.removeAll { $0.id == userId }
        }
        // Optionally persist dismiss to Firestore so it survives app restarts
        Task.detached {
            await self.writeDismissal(userId: userId)
        }
    }

    // MARK: - Private Helpers

    private func applyFilters(
        _ raw: [RecommendedUsersAIService.UserRecommendation],
        limit: Int
    ) -> [RecommendedUsersAIService.UserRecommendation] {
        // First apply the safety filter (blocked, following, restricted, trust score)
        let safetyFiltered = FollowSafetyFilter.shared.filter(raw, limit: limit + 20)

        // Then remove session-dismissed users
        return safetyFiltered
            .filter { !dismissedUserIds.contains($0.id) }
            .prefix(limit)
            .map { $0 }
    }

    /// Write a lightweight dismissal record so future recommendation batches
    /// can exclude recently dismissed users on the backend.
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
