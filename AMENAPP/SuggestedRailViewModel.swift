// SuggestedRailViewModel.swift
// AMENAPP
//
// ViewModel for the Suggested Accounts rail, parameterized by surface.
// Refactored from SuggestionsViewModel in SuggestedForYouModule.swift.
// Handles load, follow, dismiss, hide, pagination, and cross-surface state sync.

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class SuggestedRailViewModel: ObservableObject {
    @Published var items: [SuggestionItem] = []
    @Published var isLoading = true
    @Published var isModuleHidden = false
    @Published var followStates: [String: FollowStateManager.FollowState] = [:]
    @Published var loadingFollowIds: Set<String> = []
    @Published var hasError = false

    let surface: SuggestionSurface

    // Pagination buffer
    private var fullBuffer: [SuggestionItem] = []
    private var displayLimit = 12
    private var hasLoadedOnce = false
    private var lastLoadDate: Date?
    private let staleDuration: TimeInterval = 15 * 60 // 15 min

    // Track follows from suggestions to fire "feed personalised" toast at 3+.
    // Uses UserDefaults so the toast fires once per session across all surfaces.
    private static let suggestionFollowCountKey = "amen_suggestion_follow_session_count"
    private static let suggestionPersonalizedFiredKey = "amen_suggestion_personalized_fired"

    private static let dismissedKey = "amen_dismissed_suggestions"
    private static let impressionKey = "amen_suggestion_impressions"

    private var hiddenKey: String {
        "amen_suggestions_hidden_\(surface.rawValue)"
    }

    init(surface: SuggestionSurface) {
        self.surface = surface
        isModuleHidden = UserDefaults.standard.bool(forKey: hiddenKey)

        // Listen for follow state changes from other surfaces
        NotificationCenter.default.addObserver(
            forName: .followStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self,
                      let info = notification.userInfo,
                      let userId = info["userId"] as? String,
                      let state = info["state"] as? FollowStateManager.FollowState else { return }
                self.followStates[userId] = state

                // If followed from another surface, remove from rail after delay
                if state.isFollowing {
                    let config = self.railConfig
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    withAnimation(Motion.adaptive(.spring(response: config.animationResponse, dampingFraction: config.animationDamping))) {
                        self.items.removeAll { $0.id == userId }
                        self.replenishFromBuffer()
                    }
                }
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private var railConfig: SuggestionRailConfig {
        switch surface {
        case .openTable:    return .openTable
        case .prayer:       return .prayer
        case .testimonies:  return .testimonies
        }
    }

    // MARK: - Load

    func load() async {
        guard !isModuleHidden else { isLoading = false; return }

        // Skip if loaded recently
        if hasLoadedOnce, let last = lastLoadDate, Date().timeIntervalSince(last) < staleDuration {
            isLoading = false
            return
        }

        isLoading = true
        hasError = false

        let fetched = await SuggestedRailService.shared.fetchSuggestions(surface: surface, limit: 20)

        if fetched.isEmpty && !hasLoadedOnce {
            isLoading = false
            hasError = items.isEmpty
            return
        }

        fullBuffer = fetched
        items = Array(fetched.prefix(displayLimit))
        hasLoadedOnce = true
        lastLoadDate = Date()
        isLoading = false

        // Pre-fetch follow states for all visible items
        for item in items {
            let state = await FollowStateManager.shared.getState(for: item.id)
            followStates[item.id] = state
        }
    }

    func refreshIfStale() async {
        if let last = lastLoadDate, Date().timeIntervalSince(last) > staleDuration {
            hasLoadedOnce = false
            await load()
        }
    }

    // MARK: - Follow

    func follow(id: String) async {
        let item = items.first { $0.id == id }
        let isPrivate = item?.isPrivate ?? false

        // Optimistic state
        loadingFollowIds.insert(id)
        followStates[id] = isPrivate ? .requested : .following
        AMENAnalyticsService.shared.track(.suggestionFollowTap(suggestedUserId: id, position: items.firstIndex(where: { $0.id == id }) ?? -1))

        do {
            try await FollowService.shared.followUser(userId: id)

            let newState: FollowStateManager.FollowState = isPrivate ? .requested : .following
            FollowStateManager.shared.updateState(for: id, state: newState)
            followStates[id] = newState
            loadingFollowIds.remove(id)

            AMENAnalyticsService.shared.track(.suggestionFollowSuccess(suggestedUserId: id))

            // Track follows-from-suggestions. At the 3rd follow, fire the
            // "Your feed is being personalized" toast once per session.
            if !isPrivate {
                let defaults = UserDefaults.standard
                let alreadyFired = defaults.bool(forKey: Self.suggestionPersonalizedFiredKey)
                if !alreadyFired {
                    let newCount = defaults.integer(forKey: Self.suggestionFollowCountKey) + 1
                    defaults.set(newCount, forKey: Self.suggestionFollowCountKey)
                    if newCount >= 3 {
                        defaults.set(true, forKey: Self.suggestionPersonalizedFiredKey)
                        NotificationCenter.default.post(name: .feedSuggestionsPersonalized, object: nil)
                    }
                }
            }

            // Animate out after user sees the state change
            if !isPrivate {
                let config = railConfig
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                withAnimation(Motion.adaptive(.spring(response: config.animationResponse, dampingFraction: config.animationDamping))) {
                    items.removeAll { $0.id == id }
                    replenishFromBuffer()
                }
            }
        } catch {
            followStates[id] = .notFollowing
            loadingFollowIds.remove(id)
            AMENAnalyticsService.shared.track(.suggestionFollowFailure(suggestedUserId: id))
            dlog("❌ Suggestion follow failed: \(error.localizedDescription)")
        }
    }

    func cancelRequest(id: String) async {
        followStates[id] = .notFollowing
        guard let currentUID = Auth.auth().currentUser?.uid else { return }
        do {
            let snap = try await Firestore.firestore().collection("followRequests")
                .whereField("fromUserId", isEqualTo: currentUID)
                .whereField("toUserId", isEqualTo: id)
                .whereField("status", isEqualTo: "pending")
                .limit(to: 1)
                .getDocuments()
            for doc in snap.documents {
                try await doc.reference.delete()
            }
            FollowStateManager.shared.updateState(for: id, state: .notFollowing)
        } catch {
            followStates[id] = .requested
            dlog("❌ Cancel request failed: \(error.localizedDescription)")
        }
    }

    func unfollow(id: String) async {
        let previousState = followStates[id] ?? .following
        followStates[id] = .notFollowing
        do {
            try await FollowService.shared.unfollowUser(userId: id)
            FollowStateManager.shared.updateState(for: id, state: .notFollowing)
        } catch {
            followStates[id] = previousState
            dlog("❌ Unfollow failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Dismiss

    func dismiss(id: String) {
        AMENAnalyticsService.shared.track(.suggestionDismiss(suggestedUserId: id))
        let config = railConfig
        withAnimation(Motion.adaptive(.spring(response: config.animationResponse, dampingFraction: config.animationDamping))) {
            items.removeAll { $0.id == id }
            fullBuffer.removeAll { $0.id == id }
            replenishFromBuffer()
        }
        var set = Self.loadDismissed()
        set.insert(id)
        UserDefaults.standard.set(Array(set), forKey: Self.dismissedKey)

        persistDismiss(userId: id)
    }

    // MARK: - Hide / Restore Module

    func hideModule() {
        let config = railConfig
        withAnimation(Motion.adaptive(.spring(response: config.animationResponse, dampingFraction: config.animationDamping))) {
            isModuleHidden = true
        }
        UserDefaults.standard.set(true, forKey: hiddenKey)
        AMENAnalyticsService.shared.track(.suggestionsModuleHidden)
    }

    func restoreModule() {
        UserDefaults.standard.set(false, forKey: hiddenKey)
        let config = railConfig
        withAnimation(Motion.adaptive(.spring(response: config.animationResponse, dampingFraction: config.animationDamping))) {
            isModuleHidden = false
        }
        AMENAnalyticsService.shared.track(.suggestionsModuleRestored)
        Task { await load() }
    }

    // MARK: - Pagination / Replenishment

    func loadMoreIfNeeded(currentItem: SuggestionItem) {
        guard let index = items.firstIndex(where: { $0.id == currentItem.id }),
              index >= items.count - 3 else { return }

        let currentIds = Set(items.map(\.id))
        let additionalItems = fullBuffer.filter { !currentIds.contains($0.id) }.prefix(5)
        if !additionalItems.isEmpty {
            let config = railConfig
            withAnimation(Motion.adaptive(.spring(response: config.animationResponse, dampingFraction: config.animationDamping))) {
                items.append(contentsOf: additionalItems)
            }
        }
    }

    private func replenishFromBuffer() {
        let currentIds = Set(items.map(\.id))
        let nextItems = fullBuffer.filter { !currentIds.contains($0.id) }
        let needed = max(0, displayLimit - items.count)
        if needed > 0 {
            let toAdd = Array(nextItems.prefix(needed))
            items.append(contentsOf: toAdd)
        }
    }

    // MARK: - Dismiss Persistence

    static func loadDismissed() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: dismissedKey) ?? [])
    }

    private func persistDismiss(userId: String) {
        guard let currentUID = Auth.auth().currentUser?.uid else { return }
        Task {
            var retries = 0
            let maxRetries = 3
            while retries < maxRetries {
                do {
                    try await Firestore.firestore()
                        .collection("users").document(currentUID)
                        .collection("suggestionFeedback").document(userId)
                        .setData([
                            "action": "dismiss",
                            "timestamp": FieldValue.serverTimestamp(),
                            "surface": surface.rawValue,
                            "shownCount": SuggestedRailViewModel.impressionCount(for: userId),
                            "cardSuppressedUntil": Timestamp(date: Date().addingTimeInterval(7 * 86400))
                        ])
                    return // success
                } catch {
                    retries += 1
                    if retries < maxRetries {
                        try? await Task.sleep(nanoseconds: UInt64(retries) * 1_000_000_000)
                    } else {
                        dlog("⚠️ SuggestedRail: dismiss persist failed after \(maxRetries) retries for \(userId)")
                    }
                }
            }
        }
    }

    // MARK: - Impression Tracking

    /// Record an impression for a suggestion card. Called from onAppear.
    func recordImpression(for userId: String) {
        var data = Self.loadImpressionData()
        var entry = data[userId] ?? ImpressionEntry(count: 0, lastShown: Date())
        entry.count += 1
        entry.lastShown = Date()
        data[userId] = entry
        Self.saveImpressionData(data)
    }

    /// Returns the number of times a user has been shown as a suggestion.
    static func impressionCount(for userId: String) -> Int {
        loadImpressionData()[userId]?.count ?? 0
    }

    /// Returns true if the card should be suppressed due to fatigue.
    static func isFatigued(userId: String) -> Bool {
        guard let entry = loadImpressionData()[userId] else { return false }
        // Shown 10+ times without follow/peek → suppress for 24h
        if entry.count >= 10 {
            return entry.lastShown.timeIntervalSinceNow > -86400 // within last 24h
        }
        return false
    }

    /// Fatigue multiplier for scoring: reduces score for over-shown cards.
    static func fatigueMultiplier(for userId: String) -> Double {
        let count = impressionCount(for: userId)
        if count >= 10 { return 0.0 }   // suppress entirely
        if count >= 5  { return 0.5 }   // halve the score
        return 1.0
    }

    // Impression data persistence
    struct ImpressionEntry: Codable {
        var count: Int
        var lastShown: Date
    }

    private static func loadImpressionData() -> [String: ImpressionEntry] {
        guard let data = UserDefaults.standard.data(forKey: impressionKey),
              let decoded = try? JSONDecoder().decode([String: ImpressionEntry].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func saveImpressionData(_ data: [String: ImpressionEntry]) {
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(encoded, forKey: impressionKey)
        }
    }

    // MARK: - Follow State Helpers

    func effectiveFollowState(for id: String) -> FollowStateManager.FollowState {
        followStates[id] ?? .notFollowing
    }

    func isLoadingFollow(for id: String) -> Bool {
        loadingFollowIds.contains(id)
    }
}
