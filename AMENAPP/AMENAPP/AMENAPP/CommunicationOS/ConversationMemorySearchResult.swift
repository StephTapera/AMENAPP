import Foundation

enum ConversationMemorySearchResultType: String, Codable, CaseIterable {
    case message
    case decision
    case task
    case file
    case media
    case meeting
    case person
}

struct ConversationMemorySearchResult: Identifiable, Codable, Equatable {
    var id: String
    var type: ConversationMemorySearchResultType
    var title: String
    var snippet: String
    var sourcePath: String
    var sourceMessageId: String?
    var relevanceScore: Double
}
