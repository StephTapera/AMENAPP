import Foundation

enum TrustCenterFeatureFlag: String, CaseIterable, Sendable {
    case modes = "ff.trustCenter.modes"
    case auditLog = "ff.trustCenter.auditLog"
    case sendSafely = "ff.trustCenter.sendSafely"
    case ui = "ff.trustCenter.ui"
    case escalationV2 = "ff.safety.escalationV2"
}

struct TrustCenterFeatureGate: Sendable {
    var enabledFlags: Set<TrustCenterFeatureFlag>

    static let disabled = TrustCenterFeatureGate(enabledFlags: [])

    func isEnabled(_ flag: TrustCenterFeatureFlag) -> Bool {
        enabledFlags.contains(flag)
    }
}

enum TrustCenterPostureMode: String, CaseIterable, Identifiable, Sendable {
    case grace
    case family
    case youth
    case leader
    case custom

    var id: String { rawValue }
}

enum TrustCenterVerdictLevel: String, CaseIterable, Sendable {
    case safe
    case caution
    case blocked
}

struct TrustCenterVerdict: Equatable, Sendable {
    let level: TrustCenterVerdictLevel
    let reasonCode: String
    let humanReadable: String
}

struct TrustCenterAuditEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let category: String
    let verdictLevel: TrustCenterVerdictLevel
    let actionTaken: String
    let isReversibleOrAppealable: Bool

    init(
        id: UUID = UUID(),
        timestamp: Date,
        category: String,
        verdictLevel: TrustCenterVerdictLevel,
        actionTaken: String,
        isReversibleOrAppealable: Bool
    ) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.verdictLevel = verdictLevel
        self.actionTaken = actionTaken
        self.isReversibleOrAppealable = isReversibleOrAppealable
    }
}
