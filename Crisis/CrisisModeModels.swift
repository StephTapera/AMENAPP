import Foundation
import FirebaseFirestore

enum CrisisIndicatorType: String, Codable {
    case frequentAccess, searchKeywords, postContent, supportGroupJoin, wellnessToolFreq
    var displayName: String {
        switch self {
        case .frequentAccess: return "Frequent Access"
        case .searchKeywords: return "Search Keywords"
        case .postContent: return "Post Content"
        case .supportGroupJoin: return "Support Group Activity"
        case .wellnessToolFreq: return "Wellness Tool Usage"
        }
    }
}

enum CrisisSeverity: Int, Codable, Comparable {
    case low = 1, medium = 2, high = 3
    var displayName: String { switch self { case .low: return "Low"; case .medium: return "Medium"; case .high: return "High" } }
    static func < (lhs: CrisisSeverity, rhs: CrisisSeverity) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum CrisisLevel: String, Codable {
    case low, moderate, high, imminent
    var displayName: String { rawValue.capitalized }
}

struct CrisisIndicator: Identifiable, Codable {
    @DocumentID var id: String?
    var type: CrisisIndicatorType
    var detectedAt: Timestamp?
    var severity: CrisisSeverity
    var addressed: Bool
    var escalatedAt: Timestamp?
}

struct SupportStatus: Codable {
    var lastCrisisDetectionAt: Timestamp?
    var recentIndicators: Int
    var optedIntoProactiveSupport: Bool
    var sensitiveContact: String?
}
