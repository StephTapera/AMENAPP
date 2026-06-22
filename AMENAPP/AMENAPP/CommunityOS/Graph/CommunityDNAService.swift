// CommunityDNAService.swift
// AMEN App — Community Around Content OS / Graph
//
// Actor that computes and persists CommunityDNAProfile.
// The profile is derived from community graph edges: topic → affinity mapping.
//
// Cache TTL: 5 minutes in-memory; Firestore is the source of truth.

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - CommunityDNAService

actor CommunityDNAService {

    static let shared = CommunityDNAService()
    private init() {}

    // MARK: Private state

    private lazy var db = Firestore.firestore()

    /// In-memory cache keyed by userId.
    private var cache: [String: (profile: CommunityDNAProfile, fetchedAt: Date)] = [:]

    /// Cache TTL in seconds.
    private let cacheTTL: TimeInterval = 5 * 60

    // MARK: - computeDNA

    /// Pure computation: maps a set of affinity scores to a full DNA profile.
    /// No Firestore I/O — safe to call from any context.
    func computeDNA(
        for userId: String,
        affinityScores: [CommunityAffinityScore]
    ) -> CommunityDNAProfile {
        // Build a lookup for O(1) score access
        let scoreMap = Dictionary(
            uniqueKeysWithValues: affinityScores.map { ($0.topic, $0) }
        )

        // Worship: .worship topic
        let worshipAffinity = scoreMap[.worship]?.score ?? 0.0

        // Bible: discipleship (bibleVerse interactions drive discipleship) + theology + apologetics
        let bibleAffinity = averaged(
            scoreMap[.discipleship]?.score,
            scoreMap[.theology]?.score,
            scoreMap[.apologetics]?.score
        )

        // Prayer: prayer topic
        let prayerAffinity = scoreMap[.prayer]?.score ?? 0.0

        // Teaching: theology + discipleship
        let teachingAffinity = averaged(
            scoreMap[.theology]?.score,
            scoreMap[.discipleship]?.score
        )

        // Recovery: recovery topic
        let recoveryAffinity = scoreMap[.recovery]?.score ?? 0.0

        // Leadership: leadership + missions (leading by going)
        let leadershipAffinity = averaged(
            scoreMap[.leadership]?.score,
            scoreMap[.missions]?.score
        )

        // topAffinities: all non-zero scores, sorted descending, capped at 10
        let topAffinities = affinityScores
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
            .prefix(10)
            .map { $0 }

        return CommunityDNAProfile(
            userId: userId,
            worshipAffinity: min(worshipAffinity, 1.0),
            bibleAffinity: min(bibleAffinity, 1.0),
            prayerAffinity: min(prayerAffinity, 1.0),
            teachingAffinity: min(teachingAffinity, 1.0),
            recoveryAffinity: min(recoveryAffinity, 1.0),
            leadershipAffinity: min(leadershipAffinity, 1.0),
            topAffinities: topAffinities,
            updatedAt: Date()
        )
    }

    // MARK: - refreshDNA

    /// Fetches the latest affinity scores from CommunityGraphService,
    /// computes a fresh DNA profile, saves it, and returns it.
    @discardableResult
    func refreshDNA(for userId: String) async throws -> CommunityDNAProfile {
        guard await CommunityOSFlagService.shared.isEnabled(.meaningGraph) else {
            dlog("[CommunityDNAService] meaningGraph flag off — skipping refreshDNA")
            return emptyProfile(for: userId)
        }

        let affinityScores = try await CommunityGraphService.shared.getAffinityScores(for: userId)
        let profile = computeDNA(for: userId, affinityScores: affinityScores)

        try await CommunityGraphService.shared.saveDNAProfile(profile)

        // Update in-memory cache
        cache[userId] = (profile: profile, fetchedAt: Date())

        let primaryTopic = profile.primaryAffinity
        let primaryName = primaryTopic?.displayName ?? "none"
        dlog("[CommunityDNAService] DNA refreshed for \(userId) — primary: \(primaryName)")
        return profile
    }

    // MARK: - getOrCreateDNA

    /// Returns the DNA profile for a user using a three-tier lookup:
    ///   1. In-memory cache (5-minute TTL)
    ///   2. Firestore stored profile
    ///   3. Fresh computation from graph edges
    func getOrCreateDNA(for userId: String) async throws -> CommunityDNAProfile {
        guard await CommunityOSFlagService.shared.isEnabled(.meaningGraph) else {
            dlog("[CommunityDNAService] meaningGraph flag off — returning empty profile")
            return emptyProfile(for: userId)
        }

        // 1. Check in-memory cache
        if let cached = cache[userId] {
            let age = Date().timeIntervalSince(cached.fetchedAt)
            if age < cacheTTL {
                dlog("[CommunityDNAService] Cache hit for \(userId) (age: \(Int(age))s)")
                return cached.profile
            }
            dlog("[CommunityDNAService] Cache expired for \(userId) (age: \(Int(age))s)")
        }

        // 2. Check Firestore
        if let storedProfile = try await CommunityGraphService.shared.getDNAProfile(for: userId) {
            cache[userId] = (profile: storedProfile, fetchedAt: Date())
            dlog("[CommunityDNAService] Firestore hit for \(userId)")
            return storedProfile
        }

        // 3. Compute fresh from graph edges
        dlog("[CommunityDNAService] No stored profile; computing fresh DNA for \(userId)")
        return try await refreshDNA(for: userId)
    }

    // MARK: - Private helpers

    /// Returns the average of up to three optional Double values,
    /// ignoring nil entries. Returns 0 if all are nil.
    nonisolated private func averaged(_ values: Double?...) -> Double {
        let present = values.compactMap { $0 }
        guard !present.isEmpty else { return 0.0 }
        return present.reduce(0, +) / Double(present.count)
    }

    private func emptyProfile(for userId: String) -> CommunityDNAProfile {
        CommunityDNAProfile(userId: userId)
    }
}
