import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import SwiftUI

enum DogpileAction: String, Codable {
    case none, rateLimit, hideFromTarget, notifyModerators
}

struct DogpileAssessment {
    let isPileOn: Bool
    let attackingAccountCount: Int
    let recommendedAction: DogpileAction
}

@MainActor final class DogpileDetectionService: ObservableObject {
    static let shared = DogpileDetectionService()
    private init() {}

    @Published private(set) var activeThreats: [String: DogpileAssessment] = [:]

    func assessPileOnRisk(
        targetUserId: String,
        interactionType: String,
        contentId: String
    ) async throws -> DogpileAssessment {
        guard AMENFeatureFlags.shared.dogpileDetectionEnabled else {
            return DogpileAssessment(isPileOn: false, attackingAccountCount: 0, recommendedAction: .none)
        }
        dlog("[DogpileDetectionService] assessPileOnRisk target=\(targetUserId) type=\(interactionType)")
        let payload: [String: Any] = [
            "targetUserId": targetUserId,
            "interactionType": interactionType,
            "contentId": contentId
        ]
        do {
            let result = try await Functions.functions().httpsCallable("assessDogpileRisk").call(payload)
            guard let data = result.data as? [String: Any] else {
                throw NSError(domain: "DogpileDetection", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }
            let isPileOn = data["isPileOn"] as? Bool ?? false
            let attackingAccountCount = data["attackingAccountCount"] as? Int ?? 0
            let actionRaw = data["recommendedAction"] as? String ?? "none"
            let recommendedAction = DogpileAction(rawValue: actionRaw) ?? .none
            let assessment = DogpileAssessment(
                isPileOn: isPileOn,
                attackingAccountCount: attackingAccountCount,
                recommendedAction: recommendedAction
            )
            if isPileOn {
                activeThreats[targetUserId] = assessment
            } else {
                activeThreats.removeValue(forKey: targetUserId)
            }
            return assessment
        } catch {
            dlog("[DogpileDetectionService] assessPileOnRisk error: \(error)")
            throw error
        }
    }
}
