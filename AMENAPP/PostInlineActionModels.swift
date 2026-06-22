import Foundation

enum PostInlineContentTokenType: String, Codable, Hashable {
    case text
    case action
}

enum PostInlineActionType: String, Codable, Hashable {
    case openDMWithPostAuthor = "open_dm_with_post_author"
}

struct PostInlineContentToken: Identifiable, Codable, Hashable {
    let id: String
    let type: PostInlineContentTokenType
    let text: String
    let start: Int?
    let end: Int?
    let actionType: PostInlineActionType?

    init(
        id: String = UUID().uuidString,
        type: PostInlineContentTokenType,
        text: String,
        start: Int? = nil,
        end: Int? = nil,
        actionType: PostInlineActionType? = nil
    ) {
        self.id = id
        self.type = type
        self.text = text
        self.start = start
        self.end = end
        self.actionType = actionType
    }
}
