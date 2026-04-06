import Foundation

struct CreatorLayer: Codable, Identifiable, Hashable {
    let id: String
    var projectID: String
    var kind: CreatorLayerKind
    var orderIndex: Int
    var payloadRef: String?
}
