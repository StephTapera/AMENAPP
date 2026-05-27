import Foundation

enum AmenThreadQuestionStatus: String, Codable, CaseIterable {
    case open
    case answered
    case stale
}

struct AmenThreadQuestion: Identifiable, Codable, Equatable {
    var id: String
    var question: String
    var askedByUid: String?
    var sourceMessageId: String
    var answeredByMessageId: String?
    var status: AmenThreadQuestionStatus
    var confidence: Double?
}
