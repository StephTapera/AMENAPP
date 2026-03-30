//
//  FeedAPIService.swift
//  AMENAPP
//
//  Cloud Run client for server-side feed ranking.
//  Falls back to local HomeFeedAlgorithm on timeout or network error.
//

import Foundation
import FirebaseAuth

// MARK: - Request / Response types
// nonisolated so Codable conformances are usable from any actor context.

nonisolated private struct FeedRankRequest: Encodable, Sendable {
    let userId: String
    let posts: [FeedPostPayload]
    let interests: FeedInterestsPayload
    let followingIds: [String]
    let sessionCardsServed: Int
    let sessionCap: Int
}

nonisolated private struct FeedPostPayload: Encodable, Sendable {
    let id: String
    let authorId: String
    let content: String
    let category: String
    let topicTag: String?
    let amenCount: Int
    let commentCount: Int
    let createdAt: Double   // Unix timestamp
}

nonisolated private struct FeedInterestsPayload: Encodable, Sendable {
    let engagedTopics: [String: Double]
    let engagedAuthors: [String: Int]
    let preferredCategories: [String: Double]
    let onboardingGoals: [String]
}

nonisolated private struct FeedRankResponse: Decodable, Sendable {
    let rankedIds: [String]           // Ordered post IDs from server
    let sessionCapRemaining: Int?     // Cards remaining in session (server-enforced)
    let sessionExhausted: Bool?       // True when session cap is reached
}

// MARK: - FeedAPIService

/// Calls the Cloud Run feed-ranking service.
/// On any error or timeout the caller should fall back to local HomeFeedAlgorithm.
actor FeedAPIService {
    static let shared = FeedAPIService()

    // ── Replace with your deployed Cloud Run URL ──────────────────────────────
    // Example: https://amen-feed-HASH-uc.a.run.app
    // Set FEED_RANKING_URL in Config.xcconfig (or leave empty to always use local)
    private let baseURL: URL? = {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "FEED_RANKING_URL") as? String,
              !raw.isEmpty,
              let url = URL(string: raw),
              // Reject URLs with no real host (e.g. "https://rank/" produced when the
              // Info.plist variable substitution fails and only the path is present).
              let host = url.host, !host.isEmpty,
              host.contains(".") else { return nil }
        return url
    }()

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest  = 3   // 3-second hard timeout
        cfg.timeoutIntervalForResource = 5
        return URLSession(configuration: cfg)
    }()

    struct RankResult {
        let posts: [Post]
        /// Remaining session budget as reported by server (-1 = unknown/error)
        let sessionCapRemaining: Int
        /// True when server says session is exhausted
        let sessionExhausted: Bool
    }

    /// Rank posts server-side. Returns nil if Cloud Run is unavailable.
    func rankPosts(
        _ posts: [Post],
        interests: HomeFeedAlgorithm.UserInterests,
        followingIds: Set<String>,
        sessionCardsServed: Int = 0,
        sessionCap: Int = 25
    ) async -> RankResult? {
        guard let base = baseURL else { return nil }
        guard let userId = Auth.auth().currentUser?.uid else { return nil }
        guard !posts.isEmpty else { return RankResult(posts: posts, sessionCapRemaining: max(0, sessionCap - sessionCardsServed), sessionExhausted: false) }

        let url = base.appendingPathComponent("rank")

        let payload = FeedRankRequest(
            userId: userId,
            posts: posts.map { p in
                FeedPostPayload(
                    id: p.firebaseId ?? p.id.uuidString,
                    authorId: p.authorId,
                    content: p.content,
                    category: p.category.rawValue,
                    topicTag: p.topicTag,
                    amenCount: p.amenCount,
                    commentCount: p.commentCount,
                    createdAt: p.createdAt.timeIntervalSince1970
                )
            },
            interests: FeedInterestsPayload(
                engagedTopics: interests.engagedTopics,
                engagedAuthors: interests.engagedAuthors,
                preferredCategories: interests.preferredCategories,
                onboardingGoals: interests.onboardingGoals
            ),
            followingIds: Array(followingIds),
            sessionCardsServed: sessionCardsServed,
            sessionCap: sessionCap
        )

        do {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(payload)

            let (data, response) = try await session.data(for: req)

            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }

            let result = try JSONDecoder().decode(FeedRankResponse.self, from: data)

            // Re-order the original Post objects by the server's ranked ID list
            let idIndex = Dictionary(uniqueKeysWithValues: result.rankedIds.enumerated().map { ($1, $0) })
            let ordered = posts
                .filter { idIndex[$0.firebaseId ?? $0.id.uuidString] != nil }
                .sorted {
                    let a = idIndex[$0.firebaseId ?? $0.id.uuidString] ?? Int.max
                    let b = idIndex[$1.firebaseId ?? $1.id.uuidString] ?? Int.max
                    return a < b
                }

            return RankResult(
                posts: ordered,
                sessionCapRemaining: result.sessionCapRemaining ?? max(0, sessionCap - sessionCardsServed - ordered.count),
                sessionExhausted: result.sessionExhausted ?? false
            )
        } catch {
            // Timeout or network error → caller falls back to local algorithm
            return nil
        }
    }
}
