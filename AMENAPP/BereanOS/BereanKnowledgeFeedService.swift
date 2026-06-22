// BereanKnowledgeFeedService.swift
// AMENAPP — Berean OS
//
// Social Knowledge Feed service with anti-doom-scroll architecture.
// Fetches from bereanSocialProjects ordered by lastActivityAt,
// ranked by usefulness + trust (no engagement-time amplification).
// Anti-doom-scroll: max 3 pages, explicit load-more only, never auto-refresh.

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Feed Item Type

enum BereanFeedItemType: String, CaseIterable, Identifiable {
    case research, projectUpdate, insight, learningThread, mentorGuidance

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .research:       return "Research"
        case .projectUpdate:  return "Project Update"
        case .insight:        return "Insight"
        case .learningThread: return "Learning Thread"
        case .mentorGuidance: return "Mentor Guidance"
        }
    }

    var systemIcon: String {
        switch self {
        case .research:       return "magnifyingglass.circle.fill"
        case .projectUpdate:  return "arrow.clockwise.circle.fill"
        case .insight:        return "lightbulb.fill"
        case .learningThread: return "book.fill"
        case .mentorGuidance: return "person.bust.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .research:       return .blue
        case .projectUpdate:  return .green
        case .insight:        return .orange
        case .learningThread: return .purple
        case .mentorGuidance: return Color(red: 0.55, green: 0.33, blue: 0.73)
        }
    }
}

// MARK: - Feed Item Model

struct BereanFeedItem: Identifiable {
    let id: String
    let itemType: BereanFeedItemType
    let title: String
    let summary: String
    let authorId: String
    let publishedAt: Date
    let projectId: String?
    let usefulnessScore: Double
    let communityTrustScore: Double

    /// Ranking score: usefulness * 0.6 + trust * 0.4 — no engagement time amplification.
    var rankedScore: Double {
        usefulnessScore * 0.6 + communityTrustScore * 0.4
    }
}

// MARK: - Errors

enum BereanKnowledgeFeedError: LocalizedError {
    case featureDisabled
    case notAuthenticated
    case reachedEnd

    var errorDescription: String? {
        switch self {
        case .featureDisabled:  return "Knowledge Feed is not available yet."
        case .notAuthenticated: return "You must be signed in to view the feed."
        case .reachedEnd:       return "You have reached the end of your feed."
        }
    }
}

// MARK: - Service

@MainActor
final class BereanKnowledgeFeedService: ObservableObject {

    static let shared = BereanKnowledgeFeedService()
    private init() {}

    // MARK: - Published State

    @Published private(set) var feedItems: [BereanFeedItem] = []
    @Published private(set) var hasReachedEnd = false
    @Published private(set) var isLoading = false

    // MARK: - Anti-Doom-Scroll Controls

    private(set) var loadCount = 0
    private let maxLoads = 3
    private let pageSize = 15

    // MARK: - Private

    private let db = Firestore.firestore()
    private var lastDocument: DocumentSnapshot?

    private var currentUID: String? {
        Auth.auth().currentUser?.uid
    }

    // MARK: - Public API

    /// Initial load of the knowledge feed. Resets all state before fetching.
    func loadFeed() async throws {
        guard AMENFeatureFlags.shared.bereanOSSocialKnowledgeFeedEnabled else {
            throw BereanKnowledgeFeedError.featureDisabled
        }
        guard currentUID != nil else {
            throw BereanKnowledgeFeedError.notAuthenticated
        }
        feedItems = []
        loadCount = 0
        hasReachedEnd = false
        lastDocument = nil
        try await fetchNextPage()
    }

    /// Loads the next page. Blocked after maxLoads — no infinite scroll.
    func loadMore() async throws {
        guard AMENFeatureFlags.shared.bereanOSSocialKnowledgeFeedEnabled else {
            throw BereanKnowledgeFeedError.featureDisabled
        }
        guard !hasReachedEnd else {
            throw BereanKnowledgeFeedError.reachedEnd
        }
        guard loadCount < maxLoads else {
            hasReachedEnd = true
            return
        }
        try await fetchNextPage()
    }

    // MARK: - Private Helpers

    private func fetchNextPage() async throws {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        var query: Query = db
            .collection(BereanOSFirestore.socialProjects)
            .order(by: "lastActivityAt", descending: true)
            .limit(to: pageSize)

        if let last = lastDocument {
            query = query.start(afterDocument: last)
        }

        let snapshot = try await query.getDocuments()
        let docs = snapshot.documents

        let newItems: [BereanFeedItem] = docs.compactMap { doc in
            let data = doc.data()
            let itemType = BereanFeedItemType(rawValue: data["feedItemType"] as? String ?? "") ?? .projectUpdate
            return BereanFeedItem(
                id: doc.documentID,
                itemType: itemType,
                title: data["title"] as? String ?? "Untitled",
                summary: data["description"] as? String ?? "",
                authorId: data["ownerUid"] as? String ?? "",
                publishedAt: (data["lastActivityAt"] as? Timestamp)?.dateValue() ?? Date(),
                projectId: data["projectId"] as? String,
                usefulnessScore: data["usefulnessScore"] as? Double ?? 0.5,
                communityTrustScore: data["communityTrustScore"] as? Double ?? 0.5
            )
        }

        // Rank by usefulness + trust — no time-based engagement amplification
        let ranked = newItems.sorted { $0.rankedScore > $1.rankedScore }
        feedItems.append(contentsOf: ranked)

        lastDocument = docs.last
        loadCount += 1

        if docs.count < pageSize || loadCount >= maxLoads {
            hasReachedEnd = true
        }
    }
}
