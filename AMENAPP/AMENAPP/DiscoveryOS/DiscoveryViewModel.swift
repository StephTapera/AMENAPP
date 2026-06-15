// ConnectDiscoveryViewModel.swift
// AMEN Connect Discovery Engine — Wave 2
// Observable view model for the Connect discovery surface.

import SwiftUI
import Observation

@Observable
@MainActor
final class ConnectDiscoveryViewModel {

    // MARK: - Feed state

    enum FeedState {
        case idle
        case loading
        case loaded(DiscoveryFeed)
        case empty
        case error(String)
    }

    enum SearchState {
        case idle
        case loading
        case loaded(ConnectDiscoverySearchResult)
        case error(String)
    }

    private(set) var feedState: FeedState = .idle
    private(set) var searchState: SearchState = .idle
    private(set) var selectedCategory: String = "all"
    private(set) var sessionStartTime: Date?
    private(set) var calmCapReached = false

    private let service = ConnectDiscoveryFeedService.shared
    private var geohash: String?
    private var interests: [String] = []
    private var currentFeedToken: String?

    // MARK: - Load feed

    func loadFeed(geohash: String? = nil, interests: [String] = []) async {
        self.geohash = geohash
        self.interests = interests
        feedState = .loading
        sessionStartTime = Date()
        calmCapReached = false

        do {
            let feed = try await service.fetchFeed(
                geohash: geohash,
                interests: interests,
                categoryFilter: selectedCategory == "all" ? nil : selectedCategory
            )
            currentFeedToken = feed.feedToken
            feedState = feed.shelves.isEmpty && feed.hero.isEmpty ? .empty : .loaded(feed)
        } catch {
            feedState = .error(error.localizedDescription)
        }
    }

    // MARK: - Category pill selection (re-queries server)

    func selectCategory(_ categoryId: String) {
        guard categoryId != selectedCategory else { return }
        selectedCategory = categoryId
        Task { await loadFeed(geohash: geohash, interests: interests) }
    }

    // MARK: - CalmCap soft limit

    func checkSessionLimit() {
        guard case .loaded(let feed) = feedState else { return }
        let elapsed = Date().timeIntervalSince(sessionStartTime ?? Date())
        if elapsed > Double(feed.calmCap.sessionSoftLimitSeconds) {
            calmCapReached = true
        }
    }

    // MARK: - Search

    func search(query: String) async {
        searchState = .loading
        do {
            let result = try await service.search(
                query: query,
                geohash: geohash,
                interests: interests
            )
            searchState = .loaded(result)
        } catch {
            searchState = .error(error.localizedDescription)
        }
    }

    func clearSearch() {
        searchState = .idle
    }

    // MARK: - Computed helpers

    var currentFeed: DiscoveryFeed? {
        if case .loaded(let feed) = feedState { return feed }
        return nil
    }

    var currentSearchResult: ConnectDiscoverySearchResult? {
        if case .loaded(let result) = searchState { return result }
        return nil
    }

    var isSearching: Bool {
        if case .loading = searchState { return true }
        return false
    }

    var isLoadingFeed: Bool {
        if case .loading = feedState { return true }
        return false
    }
}

// MARK: - Category pills model

struct DiscoveryCategoryPill: Identifiable, Hashable {
    let id: String
    let label: String
    let icon: String

    static let allPills: [DiscoveryCategoryPill] = [
        .init(id: "all",          label: "All",           icon: "square.grid.2x2"),
        .init(id: "liveNow",      label: "Live Now",      icon: "dot.radiowaves.left.and.right"),
        .init(id: "prayer",       label: "Prayer",        icon: "hands.sparkles"),
        .init(id: "bibleStudy",   label: "Bible Study",   icon: "book.closed"),
        .init(id: "theology",     label: "Theology",      icon: "cross"),
        .init(id: "youngAdults",  label: "Young Adults",  icon: "person.2"),
        .init(id: "men",          label: "Men",           icon: "person"),
        .init(id: "women",        label: "Women",         icon: "person"),
        .init(id: "marriage",     label: "Marriage",      icon: "heart"),
        .init(id: "missions",     label: "Missions",      icon: "globe.americas"),
        .init(id: "churches",     label: "Churches",      icon: "building.columns"),
        .init(id: "events",       label: "Events",        icon: "calendar"),
        .init(id: "leadership",   label: "Leadership",    icon: "star"),
        .init(id: "worship",      label: "Worship",       icon: "music.note"),
        .init(id: "local",        label: "Local",         icon: "location"),
    ]
}
