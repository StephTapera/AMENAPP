import Foundation

struct CreatorTimelineItem: Codable, Identifiable, Hashable {
    let id: String
    var sceneID: String
    var title: String
    var startTimeMs: Int
    var endTimeMs: Int
}
