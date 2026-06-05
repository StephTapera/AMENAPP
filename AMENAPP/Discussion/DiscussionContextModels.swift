// DiscussionContextModels.swift — AMEN App
import Foundation

enum ContextLevel: String, Codable, Comparable, CaseIterable {
    case low, medium, high, full

    static func from(score: Int) -> ContextLevel {
        switch score {
        case 0..<30:  return .low
        case 30..<60: return .medium
        case 60..<85: return .high
        default:      return .full
        }
    }

    static func < (lhs: ContextLevel, rhs: ContextLevel) -> Bool {
        let order: [ContextLevel] = [.low, .medium, .high, .full]
        return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
    }

    var label: String {
        switch self {
        case .low:    return "Just Arriving"
        case .medium: return "Getting Context"
        case .high:   return "Well Informed"
        case .full:   return "Fully Informed"
        }
    }

    var nudgeText: String {
        switch self {
        case .low:    return "Take a moment to read the post before commenting."
        case .medium: return "You're getting context — feel free to share."
        case .high:   return "You're well informed."
        case .full:   return ""
        }
    }

    var fraction: Double {
        switch self {
        case .low:    return 0.15
        case .medium: return 0.45
        case .high:   return 0.75
        case .full:   return 1.0
        }
    }
}

struct ContextScore: Sendable {
    let score: Int
    let level: ContextLevel
    var shouldNudge: Bool { level == .low || level == .medium }
    var progressFraction: Double { level.fraction }
}

struct ReadProgressReport: Sendable {
    let postId: String
    let fraction: Double
}

struct AudioProgressReport: Sendable {
    let postId: String
    let fraction: Double
}

struct CarouselProgressReport: Sendable {
    let postId: String
    let viewed: Int
    let total: Int
}
