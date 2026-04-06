import Foundation

struct CreatorSuggestion: Codable, Identifiable, Hashable {
    let id: String
    var kind: CreatorSuggestionKind
    var title: String
    var detail: String?
    var actionKey: String
    var createdAt: Date
}
