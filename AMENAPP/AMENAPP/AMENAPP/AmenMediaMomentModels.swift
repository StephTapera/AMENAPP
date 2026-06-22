import Foundation

enum MediaMomentAnchorType: String, Codable, CaseIterable, Hashable {
    case timestamp
    case frame
    case captionCue
    case verseMoment
    case keyMoment
}

struct MediaMomentAnchor: Codable, Equatable, Hashable {
    let postId: String
    let mediaId: String
    let timestamp: Double?
    let frameIndex: Int?
    let anchorType: MediaMomentAnchorType
    let cueId: String?
    let momentId: String?
    let title: String?
    let verseReference: String?

    init(
        postId: String,
        mediaId: String,
        timestamp: Double? = nil,
        frameIndex: Int? = nil,
        anchorType: MediaMomentAnchorType,
        cueId: String? = nil,
        momentId: String? = nil,
        title: String? = nil,
        verseReference: String? = nil
    ) {
        self.postId = postId
        self.mediaId = mediaId
        self.timestamp = timestamp
        self.frameIndex = frameIndex
        self.anchorType = anchorType
        self.cueId = cueId
        self.momentId = momentId
        self.title = title
        self.verseReference = verseReference
    }

    var displayLabel: String {
        if let title, !title.isEmpty {
            return title
        }
        switch anchorType {
        case .timestamp:
            if let timestamp {
                return "Moment \(Self.timestampLabel(for: timestamp))"
            }
            return "Moment"
        case .frame:
            if let frameIndex {
                return "Frame \(frameIndex + 1)"
            }
            return "Frame"
        case .captionCue:
            return "Caption cue"
        case .verseMoment:
            return verseReference ?? "Verse moment"
        case .keyMoment:
            return "Key moment"
        }
    }

    private static func timestampLabel(for timestamp: Double) -> String {
        let totalSeconds = max(Int(timestamp.rounded()), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct VerseLinkedMoment: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let momentId: String
    let reference: String
    let displayText: String
    let verseId: String?
    let frameIndex: Int?
    let timestamp: Double?

    init(
        id: String = UUID().uuidString,
        momentId: String,
        reference: String,
        displayText: String,
        verseId: String? = nil,
        frameIndex: Int? = nil,
        timestamp: Double? = nil
    ) {
        self.id = id
        self.momentId = momentId
        self.reference = reference
        self.displayText = displayText
        self.verseId = verseId
        self.frameIndex = frameIndex
        self.timestamp = timestamp
    }
}

enum MediaPresentationMode: String, Codable, CaseIterable, Hashable {
    case standard
    case testimony
    case teaching
    case prayer
    case reflection
}

enum SavedMomentSource: String, Codable, CaseIterable, Hashable {
    case moment
    case captionCue
    case manualSave
    case verseMoment
    case frame
}

struct SavedMoment: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let postId: String
    let mediaId: String
    let timestamp: Double?
    let frameIndex: Int?
    let label: String
    let source: SavedMomentSource
    let verseReference: String?
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        postId: String,
        mediaId: String,
        timestamp: Double? = nil,
        frameIndex: Int? = nil,
        label: String,
        source: SavedMomentSource,
        verseReference: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.postId = postId
        self.mediaId = mediaId
        self.timestamp = timestamp
        self.frameIndex = frameIndex
        self.label = label
        self.source = source
        self.verseReference = verseReference
        self.createdAt = createdAt
    }
}

struct SharedMomentTarget: Codable, Equatable, Hashable {
    let postId: String
    let mediaIndex: Int
    let mediaId: String?
    let timestamp: Double?
    let frameIndex: Int?
    let momentId: String?

    init(
        postId: String,
        mediaIndex: Int = 0,
        mediaId: String? = nil,
        timestamp: Double? = nil,
        frameIndex: Int? = nil,
        momentId: String? = nil
    ) {
        self.postId = postId
        self.mediaIndex = mediaIndex
        self.mediaId = mediaId
        self.timestamp = timestamp
        self.frameIndex = frameIndex
        self.momentId = momentId
    }
}

struct RelatedMoment: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let postId: String
    let mediaId: String
    let label: String
    let kind: MediaKeyMomentKind?
    let verseReference: String?
    let presentationMode: MediaPresentationMode
    let timestamp: Double?
    let frameIndex: Int?
}

struct ChurchNoteExtractionPayload: Codable, Equatable, Hashable {
    let postId: String
    let mediaId: String
    let timestamp: Double?
    let frameIndex: Int?
    let sourceText: String?
    let verseReference: String?
    let sourceLabel: String
}

enum AmenMediaContextLayer: String, CaseIterable, Hashable {
    case social
    case meaning
}

enum AmenMediaPresenceChromeState: Hashable {
    case standard
    case quiet
    case reflection
}
