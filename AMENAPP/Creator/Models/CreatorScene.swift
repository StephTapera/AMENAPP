import Foundation

struct CreatorScene: Codable, Identifiable, Hashable {
    let id: String
    let projectID: String
    var assetID: String
    var orderIndex: Int
    var startTimeMs: Int?
    var endTimeMs: Int?
    var textOverlayIDs: [String]
    var transition: CreatorTransitionType?
    var suggestedHook: String?
}
