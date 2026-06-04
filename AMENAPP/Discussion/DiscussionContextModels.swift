// DiscussionContextModels.swift — AMEN App
import Foundation

enum ContextLevel: String, Codable, Sendable {
    case high, moderate, low, none

    var label: String {
        switch self {
        case .high:     return "High Context"
        case .moderate: return "Moderate Context"
        case .low:      return "Low Context"
        case .none:     return ""
        }
    }
}

struct ContextScore: Codable, Sendable {
    let commentId: String
    let level: ContextLevel
    let score: Double
    let reasons: [String]
}
