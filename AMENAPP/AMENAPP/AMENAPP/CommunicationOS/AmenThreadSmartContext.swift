import Foundation

struct AmenThreadSmartContext: Identifiable, Codable, Equatable {
    var id: String = "main"
    var threadId: String
    var topic: String?
    var summaryCount: Int
    var decisionCount: Int
    var actionCount: Int
    var questionCount: Int
    var mediaCount: Int
    var fileCount: Int
    var eventCount: Int
    var catchUpAvailable: Bool
    var generatedAt: Date?
    var staleAfter: Date?

    var hasMeaningfulContext: Bool {
        summaryCount > 0 || decisionCount > 0 || actionCount > 0 || questionCount > 0 || mediaCount > 0 || fileCount > 0 || eventCount > 0 || catchUpAvailable
    }
}
