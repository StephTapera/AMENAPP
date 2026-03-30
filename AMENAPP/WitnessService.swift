// WitnessService.swift
// AMENAPP — Witness Network service layer

import Foundation
import FirebaseFirestore
import FirebaseFunctions

// MARK: - WitnessService

final class WitnessService {

    static let shared = WitnessService()
    private init() {}

    private let db = Firestore.firestore()
    private let functions = Functions.functions()

    // MARK: - Fetch Testimonies

    /// Fetches the most recent testimonies, ordered newest-first.
    func fetchRecentTestimonies(limit: Int = 20) async throws -> [Testimony] {
        let snap = try await db.collection("testimonies")
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: Testimony.self) }
    }

    /// Fetches testimonies matching a specific theme tag.
    func fetchTestimonies(byTheme theme: String, limit: Int = 10) async throws -> [Testimony] {
        let snap = try await db.collection("testimonies")
            .whereField("aiThemes", arrayContains: theme)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: Testimony.self) }
    }

    // MARK: - Submit Testimony

    /// Saves a new testimony to Firestore. AI tagging is handled server-side.
    func submitTestimony(_ testimony: Testimony) async throws -> String {
        let ref = try db.collection("testimonies").addDocument(from: testimony)
        return ref.documentID
    }

    // MARK: - Impact Report

    /// Increments the impactReports counter on a testimony.
    func reportImpact(testimonyId: String) async throws {
        try await db.collection("testimonies").document(testimonyId)
            .updateData(["impactReports": FieldValue.increment(Int64(1))])
    }

    // MARK: - Prayer Requests

    /// Submits a prayer request. Returns the new document ID.
    func submitPrayerRequest(_ request: PrayerRequest) async throws -> String {
        let ref = try db.collection("prayerRequests").addDocument(from: request)
        return ref.documentID
    }

    /// Fetches the current user's prayer requests.
    func fetchMyPrayerRequests(userId: String) async throws -> [PrayerRequest] {
        let snap = try await db.collection("prayerRequests")
            .whereField("userId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .limit(to: 20)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: PrayerRequest.self) }
    }

    // MARK: - AI Matching

    /// Scores the relevance of a testimony for a given user context using Claude via bereanChatProxy.
    /// Returns nil if the AI call fails — callers should handle gracefully.
    // COST NOTE: one call per testimony-user pair at match time. Cache results in aiMatchedTestimonies.
    func matchTestimony(_ testimony: Testimony, to context: UserPrayerContext) async -> TestimonyMatchResult? {
        let system = """
        You are a compassionate AI matching testimonies to people who need them most.
        You are embedded in AMEN, a faith-centered community platform.
        You approach every user with dignity, grace, and care.
        You never shame or condescend. Speak truth with kindness.
        """

        let user = """
        TESTIMONY:
        \(testimony.content)

        USER CONTEXT (current prayer focus and spiritual state):
        \(context.toPromptString())

        TASK:
        1. Score the relevance of this testimony to this user (0.0 to 1.0)
        2. Identify the 2–3 specific sentences most relevant to them
        3. Write a one-sentence bridge ("This testimony might speak to you because…")
        4. Identify the primary scripture theme this testimony carries

        Respond ONLY in valid JSON:
        {
          "relevanceScore": 0.0,
          "keyMoments": ["sentence 1", "sentence 2"],
          "bridge": "...",
          "scriptureTheme": "..."
        }
        """

        guard let result = try? await functions.httpsCallable("bereanChatProxy")
            .call(["systemPrompt": system, "userMessage": user, "maxTokens": 300]),
              let dict = result.data as? [String: Any],
              let text = dict["text"] as? String,
              let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        return TestimonyMatchResult(
            relevanceScore: json["relevanceScore"] as? Double ?? 0.0,
            keyMoments: json["keyMoments"] as? [String] ?? [],
            bridge: json["bridge"] as? String ?? "",
            scriptureTheme: json["scriptureTheme"] as? String ?? ""
        )
    }

    /// Fetches top matching testimonies for a user context, scored via AI.
    /// Falls back to recency-ordered results if AI is unavailable.
    func fetchMatchedTestimonies(for context: UserPrayerContext, limit: Int = 10) async -> [Testimony] {
        guard let candidates = try? await fetchRecentTestimonies(limit: 30) else { return [] }

        // Score each testimony in parallel
        var scored: [(testimony: Testimony, score: Double)] = []
        await withTaskGroup(of: (Testimony, Double).self) { group in
            for testimony in candidates {
                group.addTask {
                    let match = await self.matchTestimony(testimony, to: context)
                    return (testimony, match?.relevanceScore ?? 0.0)
                }
            }
            for await pair in group {
                scored.append((testimony: pair.0, score: pair.1))
            }
        }

        return scored
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0.testimony }
    }
}
