// AmenCommunityOSViewModel.swift — AMEN App / Spiritual OS
// Community OS — production surface for space leaders.
// Gated by AppStorage flag `spiritualOS_community_os_enabled` (default OFF).
// Calls `computeCommunityHealth` Cloud Function for AI-driven pastoral insights.

import Foundation
import FirebaseFirestore
import FirebaseFunctions
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
    private let functions = Functions.functions()

    // MARK: Init

    init(spaceId: String) {
        self.spaceId = spaceId
    }

    // MARK: Load

    func load() async {
        guard !spaceId.isEmpty else { return }
        isLoading = true
        loadError = nil

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadSpaceStats() }
            group.addTask { await self.loadHealthFromCF() }
        }

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
        let payload: [String: Any] = ["spaceId": spaceId]
        do {
            let result = try await functions
                .httpsCallable("computeCommunityHealth")
                .call(payload)

            guard let data = result.data as? [String: Any] else { return }

            healthScore = data["healthScore"] as? Int ?? 0

            if let trendRaw = data["trend"] as? String,
               let trend = CommunityHealthTrend(rawValue: trendRaw) {
                healthTrend = trend
            }

            if let insights = data["insights"] as? [String] {
                bereanInsights = Array(insights.prefix(4))
            }
        } catch {
            // CF not yet deployed — fall back to local heuristic score
            let engagementRate = totalMembers > 0
                ? Double(weeklyActiveMembers) / Double(totalMembers)
                : 0.0
            healthScore = min(100, Int(engagementRate * 100))
        }
    }
}
