import Foundation

@MainActor
final class AmenAIConsentStore: ObservableObject {
    static let shared = AmenAIConsentStore()

    private let defaults = UserDefaults.standard
    private let prefix = "amen_ai_sensitive_client_consent_"
    private let fabricPrefix = "amen_fabric_privacy_"

    private init() {}

    func hasConsent(for taskType: AmenAITaskType) -> Bool {
        defaults.bool(forKey: key(for: taskType))
    }

    func grantConsent(for taskType: AmenAITaskType) {
        defaults.set(true, forKey: key(for: taskType))
    }

    func revokeConsent(for taskType: AmenAITaskType) {
        defaults.removeObject(forKey: key(for: taskType))
    }

    func revokeAllSensitiveClientAIConsent() {
        for taskType in AmenAITaskType.allCases {
            defaults.removeObject(forKey: key(for: taskType))
        }
    }

    func hasFabricConsent(for scope: AmenFabricConsentScope) -> Bool {
        defaults.bool(forKey: fabricKey(for: scope))
    }

    func setFabricConsent(_ isEnabled: Bool, for scope: AmenFabricConsentScope) {
        defaults.set(isEnabled, forKey: fabricKey(for: scope))
    }

    func revokeAllFabricConsent() {
        for scope in AmenFabricConsentScope.allCases {
            defaults.removeObject(forKey: fabricKey(for: scope))
        }
    }

    private func key(for taskType: AmenAITaskType) -> String {
        prefix + taskType.rawValue
    }

    private func fabricKey(for scope: AmenFabricConsentScope) -> String {
        fabricPrefix + scope.rawValue
    }
}

enum AmenFabricConsentScope: String, CaseIterable, Identifiable, Hashable {
    case emotionalContext
    case wellnessSignals
    case relationshipSafety
    case personalization
    case reputationService
    case safetyEscalation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .emotionalContext: return "Emotional context"
        case .wellnessSignals: return "Wellness signals"
        case .relationshipSafety: return "Relationship safety"
        case .personalization: return "Personalized recommendations"
        case .reputationService: return "Service reputation"
        case .safetyEscalation: return "Safety escalation"
        }
    }
}
