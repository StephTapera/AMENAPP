import Foundation

enum AmenThreadMediaContextStatus: String, Codable, CaseIterable {
    case pending
    case ready
    case failed
    case unavailable
}

struct AmenThreadMediaRef: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var mediaType: String
    var sourceMessageId: String?
    var sourcePath: String?
}

struct AmenThreadMediaContext: Identifiable, Codable, Equatable {
    var id: String
    var threadId: String
    var mediaId: String
    var status: AmenThreadMediaContextStatus
    var summary: String?
    var transcript: String?
    var keyMoments: [MediaMoment]
    var extractedText: String?
    var relatedMessageIds: [String]
    var suggestedActions: [ThreadSuggestedAction]
}

struct MediaMoment: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var startTime: TimeInterval?
    var endTime: TimeInterval?
    var sourceMessageId: String?
}
