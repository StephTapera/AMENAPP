import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import SwiftUI

enum EngagementRank: String, Codable {
    case exemplary, good, average, low, flagged
}

struct EngagementQualityScore {
    let postId: String
    let qualityScore: Double
    let meaningfulInteractions: Int
    let shallowInteractions: Int
    let rank: EngagementRank
}

@MainActor final class EngagementQualityRankingService: ObservableObject {
    static let shared = EngagementQualityRankingService()
    private init() {}

    func scoreEngagementQuality(postId: String) async throws -> EngagementQualityScore {
        guard AMENFeatureFlags.shared.engagementQualityRankingEnabled else {
            return EngagementQualityScore(
                postId: postId,
                qualityScore: 0.5,
                meaningfulInteractions: 0,
                shallowInteractions: 0,
                rank: .average
            )
        }
        dlog("[EngagementQualityRankingService] scoreEngagementQuality postId=\(postId)")
        let payload: [String: Any] = ["postId": postId]
        do {
            let result = try await Functions.functions().httpsCallable("scoreEngagementQuality").call(payload)
            guard let data = result.data as? [String: Any] else {
                throw NSError(domain: "EngagementQualityRanking", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }
            let qualityScore = data["qualityScore"] as? Double ?? 0.5
            let meaningfulInteractions = data["meaningfulInteractions"] as? Int ?? 0
            let shallowInteractions = data["shallowInteractions"] as? Int ?? 0
            let rankRaw = data["rank"] as? String ?? "average"
            let rank = EngagementRank(rawValue: rankRaw) ?? .average
            return EngagementQualityScore(
                postId: postId,
                qualityScore: qualityScore,
                meaningfulInteractions: meaningfulInteractions,
                shallowInteractions: shallowInteractions,
                rank: rank
            )
        } catch {
            dlog("[EngagementQualityRankingService] scoreEngagementQuality error: \(error)")
            throw error
        }
    }
}
