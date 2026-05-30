// TrendingTopicService.swift
// AMENAPP — SocialLayer
//
// Fetches trending topics from Firestore, applies faith-safe filtering,
// and lazily enriches each topic with a Berean AI summary via the
// `bereanTrendingSummary` Firebase callable.
//
// Contract type: DiscoverTopic (ComposerContract.swift) — NOT redefined here.
// Never call Anthropic SDK directly — all AI is routed through Firebase callable.

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

// MARK: - TrendingTopicService

@MainActor
final class TrendingTopicService: ObservableObject {

    // MARK: Singleton

    static let shared = TrendingTopicService()
    private init() {}

    // MARK: Published state

    @Published var topics: [DiscoverTopic] = []
    @Published var isLoading = false
    @Published var error: Error? = nil

    // MARK: Private deps

    private lazy var db = Firestore.firestore()
    private lazy var functions = Functions.functions()

    // MARK: - loadTrendingTopics

    /// Fetches the `topics` Firestore collection ordered by `postCount` descending,
    /// limit 20. Applies faith-safe filter (isEdifying != false, isFlagged != true).
    /// Does NOT call fetchAISummary here — summaries are loaded lazily on-display.
    func loadTrendingTopics() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        do {
            let snapshot = try await db
                .collection("topics")
                .order(by: "postCount", descending: true)
                .limit(to: 20)
                .getDocuments(source: .default)

            let parsed: [DiscoverTopic] = snapshot.documents.compactMap { doc in
                let data = doc.data()

                // Faith-safe filter: silently exclude non-edifying or flagged content.
                let isEdifying = data["isEdifying"] as? Bool ?? true   // absent = edifying by default
                let isFlagged  = data["isFlagged"]  as? Bool ?? false
                guard isEdifying, !isFlagged else { return nil }

                let key         = data["key"]         as? String ?? doc.documentID
                let displayName = data["title"] as? String
                               ?? data["name"]  as? String
                               ?? key
                let postCount   = data["postCount"]   as? Int    ?? 0
                let thumbnail   = data["thumbnailURL"] as? String

                return DiscoverTopic(
                    id: doc.documentID,
                    key: key,
                    displayName: displayName,
                    postCount: postCount,
                    aiSummary: nil,         // populated lazily by fetchAISummary
                    thumbnailURL: thumbnail,
                    isFollowing: false      // follow state resolved separately if needed
                )
            }

            topics = parsed
        } catch {
            self.error = error
            dlog("TrendingTopicService: loadTrendingTopics failed — \(error.localizedDescription)")
        }

        isLoading = false
    }

    // MARK: - fetchAISummary

    /// Lazily fetches a Berean AI summary for the given topic and patches it
    /// back into `topics`. Calls the `bereanTrendingSummary` Firebase callable.
    ///
    /// If the callable doesn't exist or fails, falls back to a faith-aligned stub.
    ///
    /// - Important: NEVER calls Anthropic SDK directly. All AI goes through Firebase callable.
    func fetchAISummary(for topicId: String) async {
        guard let index = topics.firstIndex(where: { $0.id == topicId }) else { return }

        // Already have a summary — no-op.
        if topics[index].aiSummary != nil { return }

        let topic = topics[index]

        // 1. Collect up to 5 recent post snippets for this topic.
        let snippets = await fetchPostSnippets(for: topicId, limit: 5)

        // 2. Call Firebase callable. Fall back to stub if unavailable.
        let summary: String

        // TODO: Deploy `bereanTrendingSummary` Cloud Function.
        //       Payload: { topicKey: String, postSnippets: [String] }
        //       Response: { summary: String }
        do {
            let callable = functions.httpsCallable("bereanTrendingSummary")
            let payload: [String: Any] = [
                "topicKey":     topic.key,
                "postSnippets": snippets
            ]
            let result = try await callable.call(payload)
            if let data = result.data as? [String: Any],
               let aiText = data["summary"] as? String,
               !aiText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                summary = aiText
            } else {
                summary = Self.fallbackSummary(for: topic)
            }
        } catch {
            // Callable not yet deployed or transient failure — use stub.
            dlog("TrendingTopicService: bereanTrendingSummary callable unavailable — \(error.localizedDescription)")
            summary = Self.fallbackSummary(for: topic)
        }

        // 3. Patch the summary back into the published array.
        if let currentIndex = topics.firstIndex(where: { $0.id == topicId }) {
            topics[currentIndex].aiSummary = summary
        }
    }

    // MARK: - followTopic / unfollowTopic

    /// Writes `users/{uid}/followedTopics/{topicId}` to record a follow.
    func followTopic(_ topicId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await db
                .collection("users").document(uid)
                .collection("followedTopics").document(topicId)
                .setData(["followedAt": FieldValue.serverTimestamp()], merge: true)
            patchIsFollowing(topicId: topicId, value: true)
        } catch {
            dlog("TrendingTopicService: followTopic failed — \(error.localizedDescription)")
        }
    }

    /// Deletes `users/{uid}/followedTopics/{topicId}` to record an unfollow.
    func unfollowTopic(_ topicId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await db
                .collection("users").document(uid)
                .collection("followedTopics").document(topicId)
                .delete()
            patchIsFollowing(topicId: topicId, value: false)
        } catch {
            dlog("TrendingTopicService: unfollowTopic failed — \(error.localizedDescription)")
        }
    }

    // MARK: - Private helpers

    /// Fetches up to `limit` recent post content snippets tagged with `topicId`.
    private func fetchPostSnippets(for topicId: String, limit: Int) async -> [String] {
        do {
            let snap = try await db
                .collection("posts")
                .whereField("topicTag", isEqualTo: topicId)
                .order(by: "createdAt", descending: true)
                .limit(to: limit)
                .getDocuments(source: .default)

            return snap.documents.compactMap { doc in
                let content = doc.data()["content"] as? String ?? doc.data()["text"] as? String
                guard let text = content, !text.isEmpty else { return nil }
                // Truncate to ~200 chars to keep callable payload lean.
                return String(text.prefix(200))
            }
        } catch {
            dlog("TrendingTopicService: fetchPostSnippets failed — \(error.localizedDescription)")
            return []
        }
    }

    /// Faith-aligned fallback summary when Berean callable is unavailable.
    private static func fallbackSummary(for topic: DiscoverTopic) -> String {
        "Believers are discussing \(topic.displayName) with faith and reflection."
    }

    /// Patches `isFollowing` on a topic by ID without a full reload.
    private func patchIsFollowing(topicId: String, value: Bool) {
        if let index = topics.firstIndex(where: { $0.id == topicId }) {
            topics[index].isFollowing = value
        }
    }
}
