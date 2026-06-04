// MeaningRecommendationEngine.swift
// AMEN App — Community Around Content OS / Platform Layer
//
// Recommends communities, content, churches, and people based on the Meaning Graph —
// spiritual affinity and community health, NOT raw engagement metrics.
//
// Feature flag: CommunityOSFlag.meaningGraph

import Foundation
import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - MeaningRecommendationEngine

actor MeaningRecommendationEngine {

    // MARK: Singleton

    static let shared = MeaningRecommendationEngine()

    // MARK: Private

    private let db = Firestore.firestore()

    // MARK: - recommendCommunities

    /// Fetches the user's DNA profile, queries communityNodes matching top affinity topics,
    /// returns up to 8 communities ordered by healthScore (not memberCount).
    func recommendCommunities(for userId: String) async throws -> [CommunityNode] {
        guard await CommunityOSFlagService.shared.isEnabled(.meaningGraph) else {
            dlog("[MeaningRecommendationEngine] Flag meaningGraph is off — skipping community recommendations")
            return []
        }

        let dnaProfile = try await fetchDNAProfile(userId: userId)
        let topTopics = topAffinityTopics(from: dnaProfile, limit: 5)

        guard !topTopics.isEmpty else {
            // Fall back to growing communities when user has no affinity data yet
            return try await findGrowingCommunities(limit: 8)
        }

        let topicRawValues = topTopics.map { $0.rawValue }

        // Firestore array-contains-any limited to 10 values
        let snapshot = try await db
            .collection("communityNodes")
            .whereField("affinityTopics", arrayContainsAny: Array(topicRawValues.prefix(10)))
            .limit(to: 30)
            .getDocuments()

        let nodes = snapshot.documents.compactMap { doc -> CommunityNode? in
            CommunityNode(from: doc.data())
        }

        // Sort by healthScore (not memberCount) and return top 8
        let sorted = nodes
            .filter { $0.isActive }
            .sorted { $0.healthScore > $1.healthScore }
        return Array(sorted.prefix(8))
    }

    // MARK: - recommendContent

    /// Fetches content objects whose themes overlap with the user's top affinities,
    /// ordered by communityScore.
    func recommendContent(for userId: String, limit: Int) async throws -> [ContentObject] {
        guard await CommunityOSFlagService.shared.isEnabled(.meaningGraph) else {
            dlog("[MeaningRecommendationEngine] Flag meaningGraph is off — skipping content recommendations")
            return []
        }

        let safeLimit = max(1, min(limit, 50))
        let dnaProfile = try await fetchDNAProfile(userId: userId)
        let topTopics = topAffinityTopics(from: dnaProfile, limit: 5)

        guard !topTopics.isEmpty else { return [] }

        let themeTerms = topTopics.map { $0.displayName.lowercased() }

        // Query using themes array-contains-any
        let snapshot = try await db
            .collection("contentObjects")
            .whereField("themes", arrayContainsAny: Array(themeTerms.prefix(10)))
            .order(by: "communityScore", descending: true)
            .limit(to: safeLimit)
            .getDocuments()

        return snapshot.documents.compactMap { doc -> ContentObject? in
            ContentObject(from: doc.data())
        }
    }

    // MARK: - findPeopleWithSharedMeaning

    /// Returns userIds of people with high CommunityAffinityScore overlap.
    /// Used for mentor / community matching — NOT as a follow suggestion.
    /// Limit: 10 results.
    func findPeopleWithSharedMeaning(userId: String) async throws -> [String] {
        guard await CommunityOSFlagService.shared.isEnabled(.meaningGraph) else {
            dlog("[MeaningRecommendationEngine] Flag meaningGraph is off — skipping people matching")
            return []
        }

        let dnaProfile = try await fetchDNAProfile(userId: userId)
        let topTopics = topAffinityTopics(from: dnaProfile, limit: 3)

        guard !topTopics.isEmpty else { return [] }

        let topicRawValues = topTopics.map { $0.rawValue }

        // Query the communityGraph collection for users sharing these affinity topics
        let snapshot = try await db
            .collection("communityGraph")
            .whereField("topic", in: Array(topicRawValues.prefix(10)))
            .whereField("score", isGreaterThanOrEqualTo: 0.6)
            .limit(to: 30)
            .getDocuments()

        // Deduplicate userIds, excluding the requesting user, and limit to 10
        var seen = Set<String>()
        seen.insert(userId)
        var results: [String] = []

        for doc in snapshot.documents {
            guard let uid = doc.data()["userId"] as? String else { continue }
            guard !seen.contains(uid) else { continue }
            seen.insert(uid)
            results.append(uid)
            if results.count >= 10 { break }
        }

        dlog("[MeaningRecommendationEngine] Found \(results.count) people with shared meaning for \(userId)")
        return results
    }

    // MARK: - recommendChurches

    /// Returns churchIds whose content themes match the user's DNA profile.
    /// Location filter is stubbed — Firestore geoqueries require a separate implementation.
    func recommendChurches(for userId: String, location: String?) async throws -> [String] {
        guard await CommunityOSFlagService.shared.isEnabled(.meaningGraph) else {
            dlog("[MeaningRecommendationEngine] Flag meaningGraph is off — skipping church recommendations")
            return []
        }

        let dnaProfile = try await fetchDNAProfile(userId: userId)
        let topTopics = topAffinityTopics(from: dnaProfile, limit: 5)

        guard !topTopics.isEmpty else { return [] }

        let themeTerms = topTopics.map { $0.rawValue }

        // Location stub: a full geo query requires a GeoHash range or a dedicated Cloud Function.
        if let location = location {
            dlog("[MeaningRecommendationEngine] Location filter '\(location)' stubbed — full geo query not yet implemented")
        }

        // Base query on content theme affinity. Location narrowing is deferred to server-side.
        let query: Query = db
            .collection("churches")
            .whereField("contentThemes", arrayContainsAny: Array(themeTerms.prefix(10)))
            .limit(to: 20)

        let snapshot = try await query.getDocuments()
        return snapshot.documents.map { $0.documentID }
    }

    // MARK: - findGrowingCommunities

    /// Queries communities ordered by recent activity (lastActiveAt desc),
    /// filters to health >= .growing, does NOT order by member count.
    func findGrowingCommunities(limit: Int) async throws -> [CommunityNode] {
        guard await CommunityOSFlagService.shared.isEnabled(.meaningGraph) else {
            dlog("[MeaningRecommendationEngine] Flag meaningGraph is off — skipping growing communities query")
            return []
        }

        let safeLimit = max(1, min(limit, 50))

        let snapshot = try await db
            .collection("communityNodes")
            .order(by: "lastActiveAt", descending: true)
            .limit(to: safeLimit * 3)  // over-fetch to allow health filtering
            .getDocuments()

        let nodes = snapshot.documents.compactMap { doc -> CommunityNode? in
            CommunityNode(from: doc.data())
        }

        // Filter to communities with health score >= growing threshold (0.45)
        let filtered = nodes.filter { $0.healthScore >= 0.45 }
        return Array(filtered.prefix(safeLimit))
    }

    // MARK: - Private helpers

    /// Fetches (or constructs a default) CommunityDNAProfile for the given userId.
    private func fetchDNAProfile(userId: String) async throws -> CommunityDNAProfile {
        let snapshot = try await db
            .collection("communityDNAProfiles")
            .document(userId)
            .getDocument()

        guard snapshot.exists, let data = snapshot.data() else {
            // Return a zero-signal profile so callers can handle gracefully
            return CommunityDNAProfile(userId: userId)
        }

        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()

        let rawAffinities = data["topAffinities"] as? [[String: Any]] ?? []
        let topAffinities: [CommunityAffinityScore] = rawAffinities.compactMap { raw -> CommunityAffinityScore? in
            guard
                let uid = raw["userId"] as? String,
                let topicRaw = raw["topic"] as? String,
                let topic = CommunityAffinityTopic(rawValue: topicRaw),
                let score = raw["score"] as? Double
            else { return nil }
            let signals = raw["signals"] as? [String] ?? []
            let affinityUpdatedAt = (raw["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
            return CommunityAffinityScore(userId: uid, topic: topic, score: score, signals: signals, updatedAt: affinityUpdatedAt)
        }

        return CommunityDNAProfile(
            userId: userId,
            worshipAffinity: data["worshipAffinity"] as? Double ?? 0.0,
            bibleAffinity: data["bibleAffinity"] as? Double ?? 0.0,
            prayerAffinity: data["prayerAffinity"] as? Double ?? 0.0,
            teachingAffinity: data["teachingAffinity"] as? Double ?? 0.0,
            recoveryAffinity: data["recoveryAffinity"] as? Double ?? 0.0,
            leadershipAffinity: data["leadershipAffinity"] as? Double ?? 0.0,
            topAffinities: topAffinities,
            updatedAt: updatedAt
        )
    }

    /// Returns the top N affinity topics from a DNA profile, sorted by score descending.
    private func topAffinityTopics(from profile: CommunityDNAProfile, limit: Int) -> [CommunityAffinityTopic] {
        let sorted = profile.topAffinities
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0.topic }
        return Array(sorted)
    }
}
