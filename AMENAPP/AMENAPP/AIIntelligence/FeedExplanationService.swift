// FeedExplanationService.swift
// AMEN — Feed Transparency System
//
// Fetches or generates explanations for feed items.
// FAIL-CLOSED: if no explanation exists after fetch, returns nil.
// nil return means the item MUST NOT render.
//
// Conforms to FeedTransparencyProviding (SelahProtocols.swift).
// Flag gate: AMENFeatureFlags.shared.feedWhyAmISeeingThis

import SwiftUI
import FirebaseFunctions
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class FeedExplanationService: ObservableObject, FeedTransparencyProviding {

    static let shared = FeedExplanationService()

    private let db = Firestore.firestore()
    private let functions = Functions.functions()

    // In-memory cache to avoid redundant Firestore reads within a session.
    private var cache: [String: FeedExplanation] = [:]

    private init() {}

    // MARK: - FeedTransparencyProviding

    /// Returns a FeedExplanation for the given feed item, or nil if unavailable.
    /// nil means the item MUST NOT render — callers must enforce this.
    func explanation(for feedItemId: String) async -> FeedExplanation? {
        guard AMENFeatureFlags.shared.feedWhyAmISeeingThis else {
            // Flag off — explicitly return nil; items render normally without transparency layer.
            return nil
        }

        // 1. Fast path: in-memory cache.
        if let cached = cache[feedItemId] {
            return cached
        }

        // 2. Firestore cache.
        if let stored = await fetchFromFirestore(feedItemId: feedItemId) {
            cache[feedItemId] = stored
            return stored
        }

        // 3. Generate via backend.
        if let generated = await generateFromBackend(feedItemId: feedItemId) {
            cache[feedItemId] = generated
            return generated
        }

        // FAIL-CLOSED: no explanation available — item must not render.
        return nil
    }

    // MARK: - Human-Readable Reason Strings

    /// Converts FeedReasonCode values into warm, human-readable language.
    /// Context dictionary keys: "authorName", "topic", "prayerTopic", "friendName", "seasonName"
    func humanReadable(for reasons: [FeedReasonCode], context: [String: String]) -> String {
        let strings = reasons.map { reason in
            warmString(for: reason, context: context)
        }
        return strings.joined(separator: " \u{2022} ")
    }

    // MARK: - Private Helpers

    private func fetchFromFirestore(feedItemId: String) async -> FeedExplanation? {
        do {
            let doc = try await db
                .collection("feedExplanations")
                .document(feedItemId)
                .getDocument()

            guard doc.exists, let data = doc.data() else { return nil }

            let jsonData = try JSONSerialization.data(withJSONObject: data)
            return try JSONDecoder().decode(FeedExplanation.self, from: jsonData)
        } catch {
            dlog("[FeedExplanationService] Firestore fetch failed for \(feedItemId): \(error)")
            return nil
        }
    }

    private func generateFromBackend(feedItemId: String) async -> FeedExplanation? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }

        do {
            let callable = functions.httpsCallable("generateFeedExplanation")
            let result = try await callable.call(["feedItemId": feedItemId, "uid": uid])

            guard let data = result.data as? [String: Any] else { return nil }
            let jsonData = try JSONSerialization.data(withJSONObject: data)
            return try JSONDecoder().decode(FeedExplanation.self, from: jsonData)
        } catch {
            dlog("[FeedExplanationService] Backend generation failed for \(feedItemId): \(error)")
            return nil
        }
    }

    private func warmString(for code: FeedReasonCode, context: [String: String]) -> String {
        switch code {
        case .followedAuthor:
            let name = context["authorName"] ?? "someone you follow"
            return "You follow \(name)"
        case .sharedInterests:
            let topic = context["topic"] ?? "a topic you care about"
            return "This connects to your interest in \(topic)"
        case .prayerContext:
            let prayerTopic = context["prayerTopic"] ?? "something you've been praying about"
            return "You've been praying about \(prayerTopic)"
        case .friendEngaged:
            let friend = context["friendName"] ?? "someone in your community"
            return "\(friend) engaged with this"
        case .trendingInCommunity:
            return "Trending in your community"
        case .liturgicalSeason:
            let season = context["seasonName"] ?? "the current season"
            return "Relevant to the current season of \(season)"
        case .bookmarkedTopic:
            let topic = context["topic"] ?? "a topic you saved"
            return "Related to a topic you bookmarked"
        case .groupActivity:
            return "Active in a group you're part of"
        }
    }
}
