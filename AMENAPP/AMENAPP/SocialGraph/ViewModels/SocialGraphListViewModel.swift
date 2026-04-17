// SocialGraphListViewModel.swift
// AMENAPP
//
// Shared base ViewModel for Followers, Following, and Mutuals list screens.
// Handles pagination, filtering, sorting, search, and live activity updates.

import Foundation
import FirebaseFirestore
import SwiftUI

@MainActor
final class SocialGraphListViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var rows: [SmartUserRowViewModel] = []
    @Published private(set) var filteredRows: [SmartUserRowViewModel] = []
    @Published private(set) var loadState: SocialGraphLoadState = .idle
    @Published var searchQuery: String = "" {
        didSet { applyFiltersAndSort() }
    }
    @Published var activeFilter: SocialGraphFilter = .all {
        didSet { applyFiltersAndSort() }
    }
    @Published var sortMode: SocialGraphSortMode = .smartDefault {
        didSet { applyFiltersAndSort() }
    }

    private(set) var hasMore = false
    private(set) var isLoadingMore = false

    // MARK: - Configuration

    let listType: SocialGraphListType

    // MARK: - Private

    private var cursor: DocumentSnapshot?
    private var activityUpdateTask: Task<Void, Never>?

    init(listType: SocialGraphListType) {
        self.listType = listType
    }

    deinit {
        activityUpdateTask?.cancel()
        Task { @MainActor in
            RelationshipActivityService.shared.stopAllListeners()
        }
    }

    // MARK: - Load

    func load() async {
        guard shouldStartLoad else { return }
        loadState = .loading
        cursor = nil
        rows = []

        do {
            let page = try await fetchPage()
            rows = page.rows
            cursor = page.cursor
            hasMore = page.hasMore
            loadState = rows.isEmpty ? .empty : .loaded
            applyFiltersAndSort()
            startActivityListener()
        } catch {
            dlog("[SocialGraph] load error: \(error)")
            loadState = .error(error.localizedDescription)
        }
    }

    func loadMore() async {
        guard hasMore, !isLoadingMore, cursor != nil else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page = try await fetchPage(after: cursor)
            rows.append(contentsOf: page.rows)
            cursor = page.cursor
            hasMore = page.hasMore
            applyFiltersAndSort()
        } catch {
            dlog("[SocialGraph] loadMore error: \(error)")
        }
    }

    func refresh() async {
        loadState = .idle
        await load()
    }

    private var shouldStartLoad: Bool {
        if loadState == .idle {
            return true
        }
        if case .error = loadState {
            return true
        }
        return false
    }

    // MARK: - Fetch

    private func fetchPage(after cursor: DocumentSnapshot? = nil) async throws -> SocialGraphPage {
        let userId = listType.userId
        switch listType {
        case .followers:
            return try await SocialGraphService.shared.fetchFollowers(for: userId, after: cursor)
        case .following:
            return try await SocialGraphService.shared.fetchFollowing(for: userId, after: cursor)
        case .mutuals:
            let mutuals = try await SocialGraphService.shared.fetchMutuals(for: userId)
            return SocialGraphPage(rows: mutuals, cursor: nil, hasMore: false)
        }
    }

    // MARK: - Live Activity Updates

    private func startActivityListener() {
        let targetIds = rows.map { $0.id }
        guard !targetIds.isEmpty else { return }

        RelationshipActivityService.shared.startListener(targetIds: targetIds) { [weak self] updates in
            guard let self else { return }
            self.applyActivityUpdates(updates)
        }
    }

    private func applyActivityUpdates(_ updates: [String: RelationshipActivityState]) {
        var changed = false
        for i in rows.indices {
            let uid = rows[i].id
            guard let rel = updates[uid] else { continue }

            let summary = ActivitySummaryService.shared
            Task {
                let sum = await summary.fetchSummary(for: uid)
                let newState = SmartActivityState(
                    userId: uid,
                    activityType: sum?.primaryActivityType ?? rows[i].activityState.activityType,
                    unseenCount: rel.totalUnseenCount,
                    lastActivityAt: rel.lastActivityAt ?? rows[i].activityState.lastActivityAt,
                    hasUnseen: rel.hasUnseen,
                    hasMutualInteraction: rel.hasMutualInteraction,
                    activeStreak: sum?.activeStreak ?? rows[i].activityState.activeStreak,
                    mutualTopics: rel.mutualTopics,
                    snippet: rows[i].activityState.snippet
                )
                let newCopy = SmartActivityCopyGenerator.generate(summary: sum, relationship: rel)

                if newState != self.rows[i].activityState {
                    self.rows[i].activityState = newState
                    self.rows[i].copy = newCopy
                    changed = true
                }
            }
        }
        if changed { applyFiltersAndSort() }
    }

    // MARK: - Filtering + Sorting

    func applyFiltersAndSort() {
        var result = rows

        // Search
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            result = result.filter {
                $0.displayName.lowercased().contains(q) ||
                $0.username.lowercased().contains(q) ||
                ($0.bio?.lowercased().contains(q) ?? false)
            }
        }

        // Filter
        switch activeFilter {
        case .all:
            break
        case .mutual:
            result = result.filter { $0.isMutual }
        case .recentlyActive:
            result = result.filter { $0.activityState.isActive }
        case .hasUnseen:
            result = result.filter { $0.activityState.hasUnseen }
        case .notFollowingBack:
            result = result.filter { !$0.isFollowedBack }
        }

        // Sort
        switch sortMode {
        case .smartDefault:
            result = smartSort(result)
        case .newest:
            result = result.sorted {
                ($0.activityState.lastActivityAt ?? .distantPast) >
                ($1.activityState.lastActivityAt ?? .distantPast)
            }
        case .oldest:
            result = result.sorted {
                ($0.activityState.lastActivityAt ?? .distantFuture) <
                ($1.activityState.lastActivityAt ?? .distantFuture)
            }
        case .mostActive:
            result = result.sorted { $0.activityState.unseenCount > $1.activityState.unseenCount }
        case .alphabetical:
            result = result.sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
        }

        filteredRows = result
    }

    private func smartSort(_ rows: [SmartUserRowViewModel]) -> [SmartUserRowViewModel] {
        rows.sorted { a, b in
            // 1. Unseen content first
            if a.activityState.hasUnseen != b.activityState.hasUnseen {
                return a.activityState.hasUnseen
            }
            // 2. Higher unseen count
            if a.activityState.unseenCount != b.activityState.unseenCount {
                return a.activityState.unseenCount > b.activityState.unseenCount
            }
            // 3. Mutual interaction
            if a.activityState.hasMutualInteraction != b.activityState.hasMutualInteraction {
                return a.activityState.hasMutualInteraction
            }
            // 4. More recent activity
            let aDate = a.activityState.lastActivityAt ?? .distantPast
            let bDate = b.activityState.lastActivityAt ?? .distantPast
            return aDate > bDate
        }
    }

    // MARK: - Mark Seen

    func markSeen(userId: String) {
        SeenStateService.shared.markSeen(targetId: userId)

        // Optimistic local update
        if let idx = rows.firstIndex(where: { $0.id == userId }) {
            rows[idx].activityState.unseenCount = 0
            rows[idx].activityState.hasUnseen = false
            rows[idx].copy = SmartActivityCopyModel(
                headline: rows[idx].copy.headline,
                subtext: rows[idx].copy.subtext,
                badgeCount: 0,
                badgeLabel: nil,
                accentColor: .moderate
            )
        }
        applyFiltersAndSort()
    }
}

// MARK: - Load State

enum SocialGraphLoadState: Equatable {
    case idle
    case loading
    case loaded
    case empty
    case error(String)

    static func == (lhs: SocialGraphLoadState, rhs: SocialGraphLoadState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.loaded, .loaded), (.empty, .empty): return true
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}
