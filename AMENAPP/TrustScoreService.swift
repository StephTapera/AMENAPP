//
//  TrustScoreService.swift
//  AMENAPP
//
//  Trust-based scoring service (Feature 8).
//  Computes a 0–100 trust score for a given author UID based on:
//    • Mutual follow relationship with the current viewer
//    • Church-verified / trusted-tier status (from Firestore users doc)
//    • Positive engagement history (from HomeFeedAlgorithm.userInterests.engagedAuthors)
//
//  Scores are cached for 5 minutes to avoid Firestore read storms.
//  All cache reads/writes run on the MainActor; Firestore fetches are async.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - Trust Tier

enum ContentTrustTier: String, Codable {
    case standard = "standard"
    case trusted  = "trusted"
    case leader   = "leader"

    var baseScore: Double {
        switch self {
        case .standard: return 0
        case .trusted:  return 10
        case .leader:   return 20
        }
    }
}

// MARK: - Trust Signals

struct TrustSignals {
    let isMutualFollow:   Bool
    let isChurchVerified: Bool
    let trustTier:        ContentTrustTier
    let engagementCount:  Int   // from HomeFeedAlgorithm.userInterests.engagedAuthors

    var score: Double {
        var s = 0.0
        if isMutualFollow    { s += 30 }
        if isChurchVerified  { s += 25 }
        s += min(20, Double(engagementCount) * 2)
        s += trustTier.baseScore
        return min(100, s)
    }
}

// MARK: - TrustScoreService

@MainActor
final class ContentTrustScoreService {
    static let shared = ContentTrustScoreService()
    private init() {}

    // Cache: authorUid → (score, timestamp)
    private var cache: [String: (score: Double, fetchedAt: Date)] = [:]
    private let cacheTTL: TimeInterval = 300  // 5 minutes

    // MARK: - Public API

    /// Returns the cached score for an author if available, otherwise 0.
    /// Kicks off a background refresh so the next call is warmer.
    func getCachedScore(for authorId: String) -> Double {
        if let entry = cache[authorId],
           Date().timeIntervalSince(entry.fetchedAt) < cacheTTL {
            return entry.score
        }
        // Cache miss or stale — refresh in background
        Task { await refreshScore(for: authorId) }
        return 0
    }

    /// Returns the trust score, fetching from Firestore if necessary.
    func score(for authorId: String) async -> Double {
        if let entry = cache[authorId],
           Date().timeIntervalSince(entry.fetchedAt) < cacheTTL {
            return entry.score
        }
        return await refreshScore(for: authorId)
    }

    // MARK: - Private

    @discardableResult
    private func refreshScore(for authorId: String) async -> Double {
        guard let currentUserId = Auth.auth().currentUser?.uid,
              currentUserId != authorId else {
            // Own posts get max trust
            cache[authorId] = (score: 100, fetchedAt: Date())
            return 100
        }

        async let followState   = FollowStateManager.shared.getState(for: authorId)
        async let firestoreData = fetchFirestoreSignals(authorId: authorId)

        let (state, fsData) = await (followState, firestoreData)

        let engagementCount = HomeFeedAlgorithm.shared.userInterests
            .engagedAuthors[authorId] ?? 0

        let signals = TrustSignals(
            isMutualFollow:   state == .mutualFollow,
            isChurchVerified: fsData.isChurchVerified,
            trustTier:        fsData.trustTier,
            engagementCount:  engagementCount
        )

        let score = signals.score
        cache[authorId] = (score: score, fetchedAt: Date())
        return score
    }

    private struct FirestoreSignals {
        let isChurchVerified: Bool
        let trustTier: ContentTrustTier
    }

    private func fetchFirestoreSignals(authorId: String) async -> FirestoreSignals {
        do {
            let doc = try await Firestore.firestore()
                .collection("users")
                .document(authorId)
                .getDocument()
            let data = doc.data() ?? [:]
            let verified  = data["isChurchVerified"] as? Bool ?? false
            let tierRaw   = data["trustTier"] as? String ?? "standard"
            let tier      = ContentTrustTier(rawValue: tierRaw) ?? .standard
            return FirestoreSignals(isChurchVerified: verified, trustTier: tier)
        } catch {
            return FirestoreSignals(isChurchVerified: false, trustTier: .standard)
        }
    }

    // MARK: - Cache Management

    /// Invalidate cache entry for a specific author (e.g., after follow/unfollow)
    func invalidate(for authorId: String) {
        cache.removeValue(forKey: authorId)
    }

    /// Clear entire cache (called on sign-out)
    func clearAll() {
        cache.removeAll()
    }
}
