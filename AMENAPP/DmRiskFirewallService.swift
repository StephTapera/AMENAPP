import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import SwiftUI

enum DmRiskLevel: String, Codable {
    case low, medium, high, critical
}

struct DmRiskDecision {
    let riskLevel: DmRiskLevel
    let shouldBlock: Bool
    let warningMessage: String?
}

@MainActor final class DmRiskFirewallService: ObservableObject {
    static let shared = DmRiskFirewallService()
    private init() {}

    @Published private(set) var blockedSenderIds: Set<String> = []

    func evaluateRisk(
        message: String,
        senderId: String,
        recipientId: String
    ) async throws -> DmRiskDecision {
        guard AMENFeatureFlags.shared.dmRiskFirewallEnabled else {
            return DmRiskDecision(riskLevel: .low, shouldBlock: false, warningMessage: nil)
        }
        dlog("[DmRiskFirewallService] evaluateRisk sender=\(senderId) recipient=\(recipientId)")
        let payload: [String: Any] = [
            "message": message,
            "senderId": senderId,
            "recipientId": recipientId
        ]
        do {
            let result = try await Functions.functions().httpsCallable("evaluateDmRisk").call(payload)
            guard let data = result.data as? [String: Any] else {
                throw NSError(domain: "DmRiskFirewall", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }
            let levelRaw = data["riskLevel"] as? String ?? "low"
            let riskLevel = DmRiskLevel(rawValue: levelRaw) ?? .low
            let shouldBlock = data["shouldBlock"] as? Bool ?? false
            let warningMessage = data["warningMessage"] as? String
            if shouldBlock {
                blockedSenderIds.insert(senderId)
            }
            return DmRiskDecision(riskLevel: riskLevel, shouldBlock: shouldBlock, warningMessage: warningMessage)
        } catch {
            dlog("[DmRiskFirewallService] evaluateRisk error: \(error)")
            throw error
        }
    }

    func reportAbuse(senderId: String, reason: String) async throws {
        guard AMENFeatureFlags.shared.dmRiskFirewallEnabled else { return }
        dlog("[DmRiskFirewallService] reportAbuse sender=\(senderId) reason=\(reason)")
        let payload: [String: Any] = ["senderId": senderId, "reason": reason]
        do {
            _ = try await Functions.functions().httpsCallable("reportDmAbuse").call(payload)
            blockedSenderIds.insert(senderId)
        } catch {
            dlog("[DmRiskFirewallService] reportAbuse error: \(error)")
            throw error
        }
    }
}
