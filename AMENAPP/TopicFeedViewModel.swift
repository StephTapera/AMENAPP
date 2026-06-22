// TopicFeedViewModel.swift
// AMENAPP
//
// Fetches and paginates posts for a specific topic using
// Firestore `normalizedTopicKeys` array-contains queries.

import SwiftUI
import FirebaseFirestore

@MainActor
final class TopicFeedViewModel: ObservableObject {

    // MARK: - Published State

    @Published var posts: [Post] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var hasMore = true
    @Published var error: String?

    @Published var activeFilter: TopicFeedFilter = .all
    @Published var activeSort: TopicFeedSort = .recent

    // MARK: - Configuration

    let topicKey: String
    let displayName: String

    private let pageSize = 20
    private lazy var db = Firestore.firestore()
    private var lastDocument: DocumentSnapshot?

    // MARK: - Init

    init(topicKey: String, displayName: String? = nil) {
        self.topicKey = topicKey
        self.displayName = displayName ?? TopicNormalizationService.shared.displayName(for: topicKey)
    }

    // MARK: - Load

    func loadInitial() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        lastDocument = nil
        hasMore = true

        do {
            let query = buildQuery()
                .limit(to: pageSize)

            let snapshot = try await query.getDocuments()
            let fetched = try parsePosts(from: snapshot)

            posts = TopicModerationFilter.shared.filter(posts: fetched)
            lastDocument = snapshot.documents.last
            hasMore = snapshot.documents.count >= pageSize

            if activeSort == .popular {
                posts.sort { ($0.amenCount + $0.commentCount) > ($1.amenCount + $1.commentCount) }
            }
        } catch {
            self.error = error.localizedDescription
            dlog("[TopicFeed] Error loading topic '\(topicKey)': \(error)")
        }

        isLoading = false
    }

    func loadMore() async {
        guard !isLoadingMore, hasMore, let lastDoc = lastDocument else { return }
        isLoadingMore = true

        do {
            let query = buildQuery()
                .start(afterDocument: lastDoc)
                .limit(to: pageSize)

            let snapshot = try await query.getDocuments()
            let fetched = try parsePosts(from: snapshot)
            let filtered = TopicModerationFilter.shared.filter(posts: fetched)

            posts.append(contentsOf: filtered)
            lastDocument = snapshot.documents.last
            hasMore = snapshot.documents.count >= pageSize

            if activeSort == .popular {
                posts.sort { ($0.amenCount + $0.commentCount) > ($1.amenCount + $1.commentCount) }
            }
        } catch {
            dlog("[TopicFeed] Error loading more for '\(topicKey)': \(error)")
        }

        isLoadingMore = false
    }

    // MARK: - Filter / Sort Changes

    func applyFilter(_ filter: TopicFeedFilter) async {
        activeFilter = filter
        await loadInitial()
    }

    func applySort(_ sort: TopicFeedSort) async {
        activeSort = sort
        await loadInitial()
    }

    // MARK: - Query Builder

    private func buildQuery() -> Query {
        var query: Query = db.collection(FirebaseManager.CollectionPath.posts)
            .whereField("normalizedTopicKeys", arrayContains: topicKey)

        // Category filter
        if let category = activeFilter.postCategory {
            query = query.whereField("category", isEqualTo: category.rawValue)
        }

        // Sort order
        switch activeSort {
        case .recent, .relevant:
            query = query.order(by: "createdAt", descending: true)
        case .popular:
            // Fetch by recency, sort client-side by engagement
            query = query.order(by: "createdAt", descending: true)
        }

        return query
    }

    // MARK: - Parse

    private func parsePosts(from snapshot: QuerySnapshot) throws -> [Post] {
        try snapshot.documents.compactMap { doc in
            var firestorePost = try doc.data(as: FirestorePost.self)
            firestorePost.id = doc.documentID
            return firestorePost.toPost()
        }
    }
}
