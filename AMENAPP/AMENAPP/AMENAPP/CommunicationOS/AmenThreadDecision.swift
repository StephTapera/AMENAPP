import Foundation

enum AmenThreadDecisionStatus: String, Codable, CaseIterable {
    case proposed
    case confirmed
    case reversed
    case outdated
}

struct AmenThreadDecision: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var summary: String
    var sourceMessageIds: [String]
    var decidedByUid: String?
    var confirmedByUids: [String]
    var status: AmenThreadDecisionStatus
    var decidedAt: Date?
    var confidence: Double?
}
