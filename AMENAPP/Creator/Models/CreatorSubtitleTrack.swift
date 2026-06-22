import Foundation

struct CreatorSubtitleTrack: Codable, Identifiable, Hashable {
    let id: String
    let projectID: String
    var languageCode: String
    var style: CreatorCaptionStyle
    var segments: [CreatorSubtitleSegment]
    var createdAt: Date
}

struct CreatorSubtitleSegment: Codable, Hashable {
    var startTimeMs: Int
    var endTimeMs: Int
    var text: String
}
