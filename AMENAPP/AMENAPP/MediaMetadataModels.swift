import Foundation

enum MediaGenerationState: String, Codable, CaseIterable, Hashable {
    case notRequested
    case queued
    case generating
    case ready
    case failed
}

enum MediaTrackSource: String, Codable, CaseIterable, Hashable {
    case generated
    case userEdited
    case imported
}

struct MediaCaptionCue: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String

    init(
        id: String = UUID().uuidString,
        startTime: TimeInterval,
        endTime: TimeInterval,
        text: String
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
    }
}

enum MediaCaptionStyle: String, Codable, CaseIterable, Hashable {
    case minimal
    case standard
    case large
    case highContrast

    var title: String {
        switch self {
        case .minimal:      return "Minimal"
        case .standard:     return "Standard"
        case .large:        return "Large"
        case .highContrast: return "High Contrast"
        }
    }
}

struct MediaCaptionTrack: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let generatedTranscript: String?
    let editedTranscript: String?
    let languageCode: String?
    let style: MediaCaptionStyle?
    let displayByDefault: Bool?
    private let _source: MediaTrackSource
    let cues: [MediaCaptionCue]?
    let lastEditedAt: Date?

    var effectiveSource: MediaTrackSource { _source }

    init(
        id: String = UUID().uuidString,
        generatedTranscript: String? = nil,
        editedTranscript: String? = nil,
        languageCode: String? = nil,
        style: MediaCaptionStyle? = nil,
        displayByDefault: Bool? = nil,
        source: MediaTrackSource = .generated,
        cues: [MediaCaptionCue]? = nil,
        lastEditedAt: Date? = nil
    ) {
        self.id = id
        self.generatedTranscript = generatedTranscript
        self.editedTranscript = editedTranscript
        self.languageCode = languageCode
        self.style = style
        self.displayByDefault = displayByDefault
        self._source = source
        self.cues = cues
        self.lastEditedAt = lastEditedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, generatedTranscript, editedTranscript, languageCode, style
        case displayByDefault, _source = "source", cues, lastEditedAt
    }
}

struct MediaFrameCaption: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let frameIndex: Int
    let title: String?
    let text: String?
    let verseReference: String?
    let displayPreference: String

    init(
        id: String = UUID().uuidString,
        frameIndex: Int,
        title: String? = nil,
        text: String? = nil,
        verseReference: String? = nil,
        displayPreference: String = "default"
    ) {
        self.id = id
        self.frameIndex = frameIndex
        self.title = title
        self.text = text
        self.verseReference = verseReference
        self.displayPreference = displayPreference
    }
}

struct MediaAudioBed: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let source: String
    let title: String
    let artist: String?
    let startOffset: TimeInterval
    let trimDuration: TimeInterval?
    let volume: Double

    init(
        id: String = UUID().uuidString,
        source: String,
        title: String,
        artist: String? = nil,
        startOffset: TimeInterval = 0,
        trimDuration: TimeInterval? = nil,
        volume: Double = 0.35
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.artist = artist
        self.startOffset = startOffset
        self.trimDuration = trimDuration
        self.volume = volume
    }
}

struct MediaGenerationStatus: Codable, Equatable, Hashable {
    let mediaProcessing: MediaProcessingState
    let captions: MediaGenerationState
    let keyMoments: MediaGenerationState
    let featuredFrame: MediaGenerationState
    let lastUpdatedAt: Date
    let errorMessage: String?

    static var idle: MediaGenerationStatus {
        MediaGenerationStatus(
            mediaProcessing: .ready,
            captions: .notRequested,
            keyMoments: .notRequested,
            featuredFrame: .notRequested,
            lastUpdatedAt: Date(),
            errorMessage: nil
        )
    }
}
