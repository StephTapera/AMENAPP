import Foundation

enum AmenThreadActionStatus: String, Codable, CaseIterable {
    case suggested
    case accepted
    case completed
    case dismissed
}

struct AmenThreadAction: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var description: String?
    var sourceMessageIds: [String]
    var assignedToUid: String?
    var dueDate: Date?
    var confidence: Double?
    var status: AmenThreadActionStatus
}

struct ThreadSuggestedAction: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var systemImage: String
    var intent: String
    var sourceMessageIds: [String]
}
