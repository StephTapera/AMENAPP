//
//  MutualContextService.swift
//  AMENAPP
//
//  Aggregates social context signals between the current viewer and a profile owner.
//  Signals: mutual followers, shared interests/topics, shared church.
//  Used by MutualContextRow for compact "Followed by X and N others" display.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Models

/// A ranked social context signal between the viewer and a profile owner.
enum MutualContextSignalType: Equatable {
    case mutualFollowers(connections: [MutualConnection], totalCount: Int)
    case sharedChurch(name: String)
    case sharedInterests(topics: [String])
}

struct MutualContextSignal: Identifiable, Equatable {
    let id = UUID()
    let type: MutualContextSignalType
    /// Higher = more relevant. Used for sorting.
    let relevanceScore: Double

    static func == (lhs: MutualContextSignal, rhs: MutualContextSignal) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Service

@MainActor
final class MutualContextService {

    static let shared = MutualContextService()
    private init() {}

    private lazy var db = Firestore.firestore()

    /// Fetch all context signals between the viewer and `profileUID`.
    /// Returns signals sorted by relevance (highest first).
    func fetchContextSignals(profileUID: String) async -> [MutualContextSignal] {
        guard let viewerUID = Auth.auth().currentUser?.uid,
              viewerUID != profileUID else { return [] }

        // Run all signal fetches concurrently
        async let mutualsSignal = fetchMutualFollowersSignal(profileUID: profileUID)
        async let churchSignal = fetchSharedChurchSignal(viewerUID: viewerUID, profileUID: profileUID)
        async let interestsSignal = fetchSharedInterestsSignal(viewerUID: viewerUID, profileUID: profileUID)

        var signals: [MutualContextSignal] = []

        if let signal = await mutualsSignal {
            signals.append(signal)
        }
        if let signal = await churchSignal {
            signals.append(signal)
        }
        if let signal = await interestsSignal {
            signals.append(signal)
        }

        // Sort by relevance descending
        signals.sort { $0.relevanceScore > $1.relevanceScore }
        return signals
    }

    // MARK: - Private Signal Fetchers

    private func fetchMutualFollowersSignal(profileUID: String) async -> MutualContextSignal? {
        let mutuals = await MutualsService.shared.fetchMutuals(profileUID: profileUID, limit: 8)
        guard !mutuals.isEmpty else { return nil }

        let totalCount = mutuals.count

        // Mutual followers are the strongest context signal
        let score = min(1.0, Double(totalCount) * 0.15 + 0.3)

        return MutualContextSignal(
            type: .mutualFollowers(connections: mutuals, totalCount: totalCount),
            relevanceScore: score
        )
    }

    private func fetchSharedChurchSignal(viewerUID: String, profileUID: String) async -> MutualContextSignal? {
        do {
            // Fetch both user docs concurrently
            async let viewerDoc = db.collection(FirebaseManager.CollectionPath.users).document(viewerUID).getDocument()
            async let profileDoc = db.collection(FirebaseManager.CollectionPath.users).document(profileUID).getDocument()

            let viewerData = try await viewerDoc.data()
            let profileData = try await profileDoc.data()

            guard let viewerChurch = viewerData?["churchName"] as? String,
                  let profileChurch = profileData?["churchName"] as? String,
                  !viewerChurch.isEmpty, !profileChurch.isEmpty,
                  viewerChurch.lowercased() == profileChurch.lowercased() else {
                return nil
            }

            return MutualContextSignal(
                type: .sharedChurch(name: profileChurch),
                relevanceScore: 0.7
            )
        } catch {
            dlog("MutualContextService: failed to fetch church data: \(error)")
            return nil
        }
    }

    private func fetchSharedInterestsSignal(viewerUID: String, profileUID: String) async -> MutualContextSignal? {
        do {
            // Fetch both user docs concurrently
            async let viewerDoc = db.collection(FirebaseManager.CollectionPath.users).document(viewerUID).getDocument()
            async let profileDoc = db.collection(FirebaseManager.CollectionPath.users).document(profileUID).getDocument()

            let viewerData = try await viewerDoc.data()
            let profileData = try await profileDoc.data()

            let viewerInterests = Set((viewerData?["interests"] as? [String] ?? []).map { $0.lowercased() })
            let viewerTopics = Set((viewerData?["profileTopics"] as? [String] ?? []).map { $0.lowercased() })
            let profileInterests = Set((profileData?["interests"] as? [String] ?? []).map { $0.lowercased() })
            let profileTopics = Set((profileData?["profileTopics"] as? [String] ?? []).map { $0.lowercased() })

            let allViewer = viewerInterests.union(viewerTopics)
            let allProfile = profileInterests.union(profileTopics)
            let shared = allViewer.intersection(allProfile)

            guard !shared.isEmpty else { return nil }

            // Capitalize first letter for display
            let displayTopics = Array(shared.prefix(3)).map { $0.capitalized }
            let score = min(0.6, Double(shared.count) * 0.1 + 0.1)

            return MutualContextSignal(
                type: .sharedInterests(topics: displayTopics),
                relevanceScore: score
            )
        } catch {
            dlog("MutualContextService: failed to fetch interests data: \(error)")
            return nil
        }
    }
}
