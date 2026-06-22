// AmenCommunityOSViewModel.swift — AMEN App / Spiritual OS
// Community OS — production surface for space leaders.
// Gated by AppStorage flag `spiritualOS_community_os_enabled` (default OFF).
// Health score is derived locally from space engagement stats.
// Deep AI pastoral insights are written by the scheduled Cloud Function
// `generateCongregationHealthReport` to communities/{id}/insights/weekly_{weekId}
// and can be surfaced here once the communityId↔spaceId mapping is confirmed.

import Foundation
import FirebaseFirestore
import SwiftUI

// MARK: - CommunityHealthTrend

enum CommunityHealthTrend: String {
    case growing = "growing"
    case stable  = "stable"
    case declining = "declining"

    var icon: String {
        switch self {
        case .growing:   return "arrow.up.right"
        case .stable:    return "minus"
        case .declining: return "arrow.down.right"
        }
    }

    var color: Color {
        switch self {
        case .growing:   return .accentColor
        case .stable:    return .amenBlue
        case .declining: return .amenSlate
        }
    }
}

// MARK: - AmenCommunityOSViewModel

@MainActor
final class AmenCommunityOSViewModel: ObservableObject {

    // MARK: Published state

    @Published var healthScore: Int = 0
    @Published var healthTrend: CommunityHealthTrend = .stable
    @Published var weeklyActiveMembers: Int = 0
    @Published var totalMembers: Int = 0
    @Published var prayerRequestsThisWeek: Int = 0
    @Published var postsThisWeek: Int = 0
    @Published var bereanInsights: [String] = []
    @Published var topActiveMembers: [String] = []
    @Published var isLoading = false
    @Published var loadError: String? = nil

    // MARK: Feature flag

    @AppStorage("spiritualOS_community_os_enabled") var isEnabled: Bool = false

    // MARK: Private

    private let spaceId: String
    private let db = Firestore.firestore()

    // MARK: Init

    init(spaceId: String) {
        self.spaceId = spaceId
    }

    // MARK: Load

    func load() async {
        guard !spaceId.isEmpty else { return }
        isLoading = true
        loadError = nil

        // loadSpaceStats must complete first — loadHealthFromCF reads its results.
        await loadSpaceStats()
        await loadHealthFromCF()

        isLoading = false
    }

    // MARK: - Private helpers

    private func loadSpaceStats() async {
        do {
            let doc = try await db.collection("spaces").document(spaceId).getDocument()
            guard let data = doc.data() else { return }

            totalMembers = data["memberCount"] as? Int ?? 0
            weeklyActiveMembers = data["weeklyActiveUsers"] as? Int ?? 0
            postsThisWeek = data["weeklyPostCount"] as? Int ?? 0

            // Prayer count from nested field or separate collection
            prayerRequestsThisWeek = data["weeklyPrayerCount"] as? Int ?? 0

            if let topIds = data["topActiveMemberIds"] as? [String] {
                topActiveMembers = Array(topIds.prefix(5))
            }
        } catch {
            // Non-fatal — stats stay at zero defaults
        }
    }

    private func loadHealthFromCF() async {
        // Derive health score from local engagement stats.
        // `generateCongregationHealthReport` is a scheduled Cloud Function (not a
        // callable) that writes results to communities/{communityId}/insights/.
        // Until the communityId↔spaceId mapping is wired, compute the score here.
        let engagementRate = totalMembers > 0
            ? Double(weeklyActiveMembers) / Double(totalMembers)
            : 0.0
        healthScore = min(100, Int(engagementRate * 100))

        // Derive a simple trend heuristic from the engagement rate.
        // The scheduled CF writes a richer trend to Firestore; this is a local proxy.
        if engagementRate > 0.5 {
            healthTrend = .growing
        } else if engagementRate < 0.2 {
            healthTrend = .declining
        } else {
            healthTrend = .stable
        }
    }
}
