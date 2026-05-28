import Foundation

struct CatchUpDigest: Identifiable, Codable, Equatable {
    var id: String
    var threadId: String
    var newMessageCount: Int
    var changedSince: String
    var keyUpdates: [String]
    var decisions: [AmenThreadDecision]
    var questions: [AmenThreadQuestion]
    var tasks: [AmenThreadAction]
    var mentions: [ThreadMention]
    var media: [AmenThreadMediaRef]
    var recommendedFirstAction: String?
    var generatedAt: Date
}

struct ThreadMention: Identifiable, Codable, Equatable {
    var id: String
    var uid: String
    var sourceMessageId: String
    var createdAt: Date?
}
