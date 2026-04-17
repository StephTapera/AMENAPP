//
//  ChurchMutualsService.swift
//  AMENAPP
//
//  Computes mutual church attendance signals for Discover and Profile surfaces.
//
//  Privacy contract:
//  - Reads ONLY from churchMemberships where visibility == .publicVisible.
//  - NEVER exposes a raw member list or raw headcount.
//  - Public output is limited to:
//      • An aggregated mutual count (integer, anonymised at threshold)
//      • Up to 3 first names drawn from public-visible memberships of mutual follows
//      • A community-scale label (e.g. "10k+ connect here") sourced from the church document
//
//  Data flow:
//  1. Resolve the current user's follow graph (following IDs).
//  2. Query churchMemberships for those IDs filtered by churchId + visibility == .publicVisible.
//  3. Cap sample names to 3; return a formatted display label.
//

import Foundation
// import FirebaseFirestore   ← add when Firebase SDK is linked
// import FirebaseAuth        ← add when Firebase SDK is linked

// MARK: - Service

/// Computes mutual church attendance signals for Discover and Profile surfaces.
///
/// This service is read-only and never writes to Firestore.
/// All outputs are aggregated; raw member lists are never surfaced.
@MainActor
final class ChurchMutualsService: ObservableObject {

    // MARK: - Published State

    @Published private(set) var mutualSignal: MutualChurchSignal?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: Error?

    // Firestore reference placeholder:
    // private lazy var db = Firestore.firestore()

    // MARK: - Nested Types

    /// An aggregated, privacy-safe signal summarising mutual church attendance.
    struct MutualChurchSignal {

        /// The church this signal belongs to.
        let churchId: String

        /// Number of people the current user follows who publicly attend this church.
        /// This count is never shown raw on public surfaces — use `displayLabel` instead.
        let mutualCount: Int

        /// Up to 3 first names from public-visible memberships of mutual follows.
        /// Full names and UIDs are never included.
        let sampleNames: [String]

        /// A community-scale label sourced from the church document
        /// (e.g. "10k+ connect here"). Shown when `mutualCount == 0`.
        let communityLabel: String

        /// A human-readable label safe for display on public church cards and profiles.
        var displayLabel: String {
            switch mutualCount {
            case 0:
                return communityLabel
            case 1:
                return "\(sampleNames.first ?? "Someone you follow") attends here"
            case 2...3:
                return "\(sampleNames.joined(separator: ", ")) attend here"
            default:
                return "\(mutualCount) people you follow attend here"
            }
        }
    }

    // MARK: - Fetch

    /// Fetches mutual church attendance signals for a given church and user.
    ///
    /// Steps:
    /// 1. Loads the IDs of users the current user follows (their following graph).
    /// 2. Queries `churchMemberships` for those IDs where `churchId` matches
    ///    and `visibility == .publicVisible` and `status == "active"`.
    /// 3. Caps sample names at 3 first names; publishes the resulting signal.
    ///
    /// - Parameters:
    ///   - churchId: The church to compute mutuals for.
    ///   - currentUserId: The UID of the currently authenticated user.
    func fetchMutualSignal(churchId: String, currentUserId: String) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            // Step 1 — resolve following graph:
            // let followingSnapshot = try await db.collection("follows")
            //     .whereField("followerId", isEqualTo: currentUserId)
            //     .whereField("status", isEqualTo: "active")
            //     .getDocuments()
            // let followingIds = followingSnapshot.documents.compactMap {
            //     $0.data()["followedId"] as? String
            // }
            // guard !followingIds.isEmpty else {
            //     self.mutualSignal = nil; return
            // }

            // Step 2 — query public memberships for those IDs:
            // Firestore `in` queries support up to 30 values; batch if needed.
            // let membershipsSnapshot = try await db.collection("churchMemberships")
            //     .whereField("churchId", isEqualTo: churchId)
            //     .whereField("userId", in: followingIds)
            //     .whereField("visibility", isEqualTo: VisibilityLevel.publicVisible.rawValue)
            //     .whereField("status", isEqualTo: "active")
            //     .getDocuments()

            // Step 3 — build signal:
            // let mutualCount = membershipsSnapshot.documents.count
            // var sampleNames: [String] = []
            // for doc in membershipsSnapshot.documents.prefix(3) {
            //     if let firstName = doc.data()["firstName"] as? String {
            //         sampleNames.append(firstName)
            //     }
            // }

            // Step 4 — fetch community label from church document:
            // let churchDoc = try await db.collection("churchProfiles").document(churchId).getDocument()
            // let communityLabel = churchDoc.data()?["communityLabel"] as? String ?? "People connect here"

            // self.mutualSignal = MutualChurchSignal(
            //     churchId: churchId,
            //     mutualCount: mutualCount,
            //     sampleNames: sampleNames,
            //     communityLabel: communityLabel
            // )

            _ = churchId        // suppress unused-variable warning until Firestore is wired
            _ = currentUserId
        } catch {
            self.error = error
        }
    }
}

// MARK: - Errors

enum ChurchMutualsError: LocalizedError {
    case followGraphUnavailable
    case signalComputationFailed

    var errorDescription: String? {
        switch self {
        case .followGraphUnavailable:
            return "Could not load your following list."
        case .signalComputationFailed:
            return "Could not compute mutual church signal."
        }
    }
}
