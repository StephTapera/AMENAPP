import Foundation

enum SmartReactionKind: String, Codable, CaseIterable, Identifiable {
    case approved
    case blocked
    case reviewing
    case thinking
    case researching
    case urgent
    case needsAttention = "needs_attention"
    case done
    case question
    case followUp = "follow_up"
    case waiting
    case aligned
    case disagree
    case resolved

    var id: String { rawValue }
}

struct SmartReaction: Identifiable, Codable, Equatable {
    var id: String
    var threadId: String
    var messageId: String
    var kind: SmartReactionKind
    var createdByUid: String
    var createdAt: Date
}

struct SmartReactionSummary: Identifiable, Codable, Equatable {
    var id: String { kind.rawValue }
    var kind: SmartReactionKind
    var count: Int
    var label: String
}
