import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import SwiftUI

enum WellbeingImpact: String, Codable {
    case uplifting, neutral, draining, distressing
}

@MainActor final class WellbeingFeedRankingService: ObservableObject {
    static let shared = WellbeingFeedRankingService()
    private init() {}

    @Published private(set) var currentWellbeingScore: Double = 1.0

    func applyWellbeingBoosts(to postIds: [String], userWellbeingScore: Double) async throws -> [String] {
        guard AMENFeatureFlags.shared.wellbeingFeedRankingEnabled else { return postIds }
        dlog("[WellbeingFeedRankingService] applyWellbeingBoosts count=\(postIds.count) score=\(userWellbeingScore)")
        let payload: [String: Any] = [
            "postIds": postIds,
            "userWellbeingScore": userWellbeingScore
        ]
        do {
            let result = try await Functions.functions().httpsCallable("applyWellbeingBoosts").call(payload)
            guard let data = result.data as? [String: Any],
                  let reranked = data["rankedPostIds"] as? [String] else {
                return postIds
            }
            return reranked
        } catch {
            dlog("[WellbeingFeedRankingService] applyWellbeingBoosts error: \(error)")
            throw error
        }
    }

    func reportPostImpact(postId: String, impact: WellbeingImpact) async {
        guard AMENFeatureFlags.shared.wellbeingFeedRankingEnabled else { return }
        dlog("[WellbeingFeedRankingService] reportPostImpact postId=\(postId) impact=\(impact.rawValue)")
        let payload: [String: Any] = ["postId": postId, "impact": impact.rawValue]
        do {
            try await Functions.functions().httpsCallable("reportPostWellbeingImpact").call(payload)
        } catch {
            dlog("[WellbeingFeedRankingService] reportPostImpact error: \(error)")
        }
    }

    func refreshWellbeingScore() async {
        guard AMENFeatureFlags.shared.wellbeingFeedRankingEnabled else { return }
        dlog("[WellbeingFeedRankingService] refreshWellbeingScore")
        do {
            let result = try await Functions.functions().httpsCallable("getUserWellbeingScore").call([:])
            if let data = result.data as? [String: Any],
               let score = data["score"] as? Double {
                currentWellbeingScore = score
            }
        } catch {
            dlog("[WellbeingFeedRankingService] refreshWellbeingScore error: \(error)")
        }
    }
}
