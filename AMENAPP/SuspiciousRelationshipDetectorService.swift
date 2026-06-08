import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import SwiftUI

enum RelationshipRiskFlag: String, Codable {
    case rapidEscalation
    case privacySeeking
    case isolationAttempt
    case giftOffering
    case ageDiscrepancySuspected
}

enum RelationshipAction: String, Codable {
    case none, warnUser, blockAndReport, escalateToTrust
}

struct RelationshipRiskReport {
    let riskScore: Double
    let flags: [RelationshipRiskFlag]
    let recommendedAction: RelationshipAction
}

@MainActor final class SuspiciousRelationshipDetectorService: ObservableObject {
    static let shared = SuspiciousRelationshipDetectorService()
    private init() {}

    func analyzeConversation(
        conversationId: String,
        participantIds: [String]
    ) async throws -> RelationshipRiskReport {
        guard AMENFeatureFlags.shared.suspiciousRelationshipDetectorEnabled else {
            return RelationshipRiskReport(riskScore: 0.0, flags: [], recommendedAction: .none)
        }
        dlog("[SuspiciousRelationshipDetectorService] analyzeConversation id=\(conversationId)")
        let payload: [String: Any] = [
            "conversationId": conversationId,
            "participantIds": participantIds
        ]
        do {
            let result = try await Functions.functions().httpsCallable("analyzeRelationshipRisk").call(payload)
            guard let data = result.data as? [String: Any] else {
                throw NSError(domain: "SuspiciousRelationshipDetector", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }
            let riskScore = data["riskScore"] as? Double ?? 0.0
            let flagRaws = data["flags"] as? [String] ?? []
            let flags = flagRaws.compactMap { RelationshipRiskFlag(rawValue: $0) }
            let actionRaw = data["recommendedAction"] as? String ?? "none"
            let recommendedAction = RelationshipAction(rawValue: actionRaw) ?? .none
            return RelationshipRiskReport(riskScore: riskScore, flags: flags, recommendedAction: recommendedAction)
        } catch {
            dlog("[SuspiciousRelationshipDetectorService] analyzeConversation error: \(error)")
            throw error
        }
    }
}
