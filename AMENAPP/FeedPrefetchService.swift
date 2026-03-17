//
//  FeedPrefetchService.swift
//  AMENAPP
//
//  Feature 12: Feed Prefetching — loads the next 10 posts before user
//  scrolls to them, like Instagram. Also handles delta sync (Feature 15).
//

import Foundation
import Combine
import FirebaseFirestore

@MainActor
class FeedPrefetchService: ObservableObject {
    static let shared = FeedPrefetchService()

    @Published var prefetchedPosts: [Post] = []
    private var lastSyncTimestamp: Date?
    private var isPrefetching = false
    private let db = Firestore.firestore()

    private init() {}

    // MARK: - Prefetch Next Page

    /// When user reaches post N, prefetch posts N+1 to N+10.
    func prefetchIfNeeded(currentIndex: Int, totalPosts: Int) {
        // Trigger prefetch when user is within 5 posts of the end
        guard currentIndex >= totalPosts - 5, !isPrefetching else { return }

        isPrefetching = true
        Task {
            defer { isPrefetching = false }

            let lastTimestamp = PostsManager.shared.allPosts.last?.createdAt ?? Date()

            guard let snapshot = try? await db.collection("posts")
                .whereField("createdAt", isLessThan: Timestamp(date: lastTimestamp))
                .order(by: "createdAt", descending: true)
                .limit(to: 10)
                .getDocuments() else { return }

            let newPosts = snapshot.documents.compactMap { doc -> Post? in
                let data = doc.data()
                guard let content = data["content"] as? String,
                      let authorId = data["authorId"] as? String,
                      let timestamp = data["createdAt"] as? Timestamp else { return nil }

                return Post(
                    id: UUID(),
                    firebaseId: doc.documentID,
                    authorId: authorId,
                    authorName: data["authorName"] as? String ?? "Unknown",
                    authorUsername: data["authorUsername"] as? String,
                    authorInitials: String((data["authorName"] as? String ?? "U").prefix(1)),
                    authorProfileImageURL: data["authorProfileImageURL"] as? String,
                    timeAgo: "",
                    content: content,
                    category: Post.PostCategory(rawValue: data["category"] as? String ?? "openTable") ?? .openTable,
                    topicTag: data["topicTag"] as? String,
                    visibility: .everyone,
                    allowComments: true,
                    imageURLs: data["imageURLs"] as? [String],
                    linkURL: nil, linkPreviewTitle: nil, linkPreviewDescription: nil,
                    linkPreviewImageURL: nil, linkPreviewSiteName: nil, linkPreviewType: nil,
                    verseReference: data["verseReference"] as? String,
                    verseText: data["verseText"] as? String,
                    createdAt: timestamp.dateValue(),
                    amenCount: data["amenCount"] as? Int ?? 0,
                    lightbulbCount: data["lightbulbCount"] as? Int ?? 0,
                    commentCount: data["commentCount"] as? Int ?? 0,
                    repostCount: data["repostCount"] as? Int ?? 0
                )
            }

            prefetchedPosts = newPosts
        }
    }

    // MARK: - Delta Sync (Feature 15)

    /// Only fetch posts that changed since last sync, not the entire list.
    func deltaSync() async -> [Post] {
        let since = lastSyncTimestamp ?? Calendar.current.date(byAdding: .hour, value: -1, to: Date()) ?? Date()

        guard let snapshot = try? await db.collection("posts")
            .whereField("updatedAt", isGreaterThan: Timestamp(date: since))
            .order(by: "updatedAt", descending: true)
            .limit(to: 50)
            .getDocuments() else { return [] }

        lastSyncTimestamp = Date()

        return snapshot.documents.compactMap { doc -> Post? in
            let data = doc.data()
            guard let content = data["content"] as? String,
                  let authorId = data["authorId"] as? String else { return nil }

            let ts = data["createdAt"] as? Timestamp

            return Post(
                id: UUID(),
                firebaseId: doc.documentID,
                authorId: authorId,
                authorName: data["authorName"] as? String ?? "Unknown",
                authorUsername: data["authorUsername"] as? String,
                authorInitials: String((data["authorName"] as? String ?? "U").prefix(1)),
                authorProfileImageURL: data["authorProfileImageURL"] as? String,
                timeAgo: "",
                content: content,
                category: Post.PostCategory(rawValue: data["category"] as? String ?? "openTable") ?? .openTable,
                topicTag: data["topicTag"] as? String,
                visibility: .everyone,
                allowComments: true,
                imageURLs: data["imageURLs"] as? [String],
                linkURL: nil, linkPreviewTitle: nil, linkPreviewDescription: nil,
                linkPreviewImageURL: nil, linkPreviewSiteName: nil, linkPreviewType: nil,
                verseReference: data["verseReference"] as? String,
                verseText: data["verseText"] as? String,
                createdAt: ts?.dateValue() ?? Date(),
                amenCount: data["amenCount"] as? Int ?? 0,
                lightbulbCount: data["lightbulbCount"] as? Int ?? 0,
                commentCount: data["commentCount"] as? Int ?? 0,
                repostCount: data["repostCount"] as? Int ?? 0
            )
        }
    }
}
