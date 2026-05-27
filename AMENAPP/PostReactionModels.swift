import Foundation

struct PostReaction: Codable, Equatable {
    var emoji: String
    var userId: String
    var createdAt: Date
}

typealias ReactionCounts = [String: Int]

enum ReactionEmoji: CaseIterable {
    case pray
    case heart
    case dove
    case strong
    case praise

    var character: String {
        switch self {
        case .pray:   return "🙏"
        case .heart:  return "❤️"
        case .dove:   return "🕊️"
        case .strong: return "💪"
        case .praise: return "🙌"
        }
    }
}
