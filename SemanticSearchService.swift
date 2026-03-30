//
//  SemanticSearchService.swift
//  AMENAPP
//
//  Feature 7: Semantic Search — "forgiveness testimony" matches posts
//  that discuss forgiveness even without those exact words.
//  Uses keyword embedding vectors (same tech as PrayerMatchingService).
//

import Foundation
import Combine
import FirebaseFirestore

@MainActor
class SemanticSearchService: ObservableObject {
    static let shared = SemanticSearchService()

    @Published var searchResults: [SemanticSearchResult] = []
    @Published var isSearching = false

    private let db = Firestore.firestore()

    private init() {}

    struct SemanticSearchResult: Identifiable {
        let id: String
        let postID: String
        let content: String
        let authorName: String
        let category: String
        let relevanceScore: Float
        let matchReason: String // "Similar theme: forgiveness"
    }

    /// Search across all content using semantic similarity.
    func search(query: String) async {
        guard query.count >= 3 else {
            searchResults = []
            return
        }

        isSearching = true
        defer { isSearching = false }

        let queryEmbedding = generateKeywordVector(for: query)

        // Fetch recent posts (last 90 days)
        let ninetyDaysAgo = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        guard let snapshot = try? await db.collection("posts")
            .whereField("createdAt", isGreaterThan: Timestamp(date: ninetyDaysAgo))
            .order(by: "createdAt", descending: true)
            .limit(to: 500)
            .getDocuments() else {
            searchResults = []
            return
        }

        var matches: [SemanticSearchResult] = []
        let queryLower = query.lowercased()

        for doc in snapshot.documents {
            let data = doc.data()
            let content = data["content"] as? String ?? ""
            let contentLower = content.lowercased()

            // Exact text match (highest priority)
            var score: Float = 0
            if contentLower.contains(queryLower) {
                score = 1.0
            } else {
                // Semantic similarity via keyword vectors
                let contentVector = generateKeywordVector(for: content)
                score = PrayerMatchingService.shared.cosineSimilarity(queryEmbedding, contentVector)
            }

            if score > 0.3 {
                matches.append(SemanticSearchResult(
                    id: doc.documentID,
                    postID: doc.documentID,
                    content: String(content.prefix(120)),
                    authorName: data["authorName"] as? String ?? "Unknown",
                    category: data["category"] as? String ?? "openTable",
                    relevanceScore: score,
                    matchReason: score >= 0.8 ? "Exact match" : "Similar theme"
                ))
            }
        }

        matches.sort { $0.relevanceScore > $1.relevanceScore }
        searchResults = Array(matches.prefix(20))
    }

    // MARK: - Keyword Vector

    private let searchKeywords = [
        "prayer", "healing", "faith", "forgiveness", "testimony", "grace",
        "love", "hope", "peace", "joy", "strength", "courage", "wisdom",
        "worship", "praise", "salvation", "redemption", "mercy", "trust",
        "anxiety", "fear", "depression", "grief", "loss", "addiction",
        "marriage", "family", "children", "work", "purpose", "calling",
        "church", "community", "fellowship", "discipleship", "growth",
        "business", "leadership", "innovation", "technology", "finance",
        "scripture", "bible", "verse", "devotion", "study", "sermon",
    ]

    private func generateKeywordVector(for text: String) -> [Float] {
        let lower = text.lowercased()
        return searchKeywords.map { lower.contains($0) ? Float(1.0) : Float(0.0) }
    }

    /// Cloud Run semantic search with timeout fallback.
    func searchViaCloudRun(query: String, limit: Int) async -> [SemanticSearchResult]? {
        guard query.count >= 3 else { return nil }

        // Attempt Cloud Function call with 5s timeout
        do {
            let result = try await withThrowingTaskGroup(of: [SemanticSearchResult]?.self) { group in
                group.addTask {
                    let response = try await CloudFunctionsService.shared.call(
                        "semanticSearch",
                        data: ["query": query, "limit": limit] as [String: Any]
                    )
                    guard let items = response as? [[String: Any]] else { return nil }
                    return items.compactMap { item -> SemanticSearchResult? in
                        guard let postId = item["postId"] as? String,
                              let score = item["score"] as? Double else { return nil }
                        return SemanticSearchResult(
                            id: postId,
                            postID: postId,
                            content: item["content"] as? String ?? "",
                            authorName: item["authorName"] as? String ?? "",
                            category: item["category"] as? String ?? "",
                            relevanceScore: Float(score),
                            matchReason: item["matchReason"] as? String ?? "Semantic match"
                        )
                    }
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    return nil // Timeout
                }
                // Return first completed result
                for try await result in group {
                    group.cancelAll()
                    return result
                }
                return nil
            }
            return result
        } catch {
            return nil
        }
    }
}
