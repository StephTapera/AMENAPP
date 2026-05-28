import Foundation

struct AmenThreadImportantDate: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var date: Date
    var sourceMessageIds: [String]
    var confidence: Double?
}
