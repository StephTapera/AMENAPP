import Foundation

// MARK: - MediaCaptionCue

struct MediaCaptionCue: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var startTime: TimeInterval
    var endTime: TimeInterval
    var text: String

    init(id: String = UUID().uuidString, startTime: TimeInterval, endTime: TimeInterval, text: String) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
    }
}

// MARK: - MediaKeyMoment

struct MediaKeyMoment: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var timestamp: TimeInterval
    var label: String
    var kind: MediaKeyMomentKind
    var source: String?
    var sortOrder: Int?

    init(
        id: String = UUID().uuidString,
        timestamp: TimeInterval,
        label: String,
        kind: MediaKeyMomentKind,
        source: String? = nil,
        sortOrder: Int? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.label = label
        self.kind = kind
        self.source = source
        self.sortOrder = sortOrder
    }

    static func fallbackMoments(for duration: TimeInterval) -> [MediaKeyMoment] {
        let segments: [(TimeInterval, String, MediaKeyMomentKind)] = [
            (0, "Opening", .teaching),
            (duration * 0.25, "Key Message", .teaching),
            (duration * 0.5, "Scripture", .scripture),
            (duration * 0.75, "Prayer", .prayer),
            (max(0, duration - 10), "Reflection", .reflection)
        ]
        return segments.map { timestamp, label, kind in
            MediaKeyMoment(timestamp: timestamp, label: label, kind: kind, source: "generated")
        }
    }
}

// MARK: - MediaFrameCaption

struct MediaFrameCaption: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var frameIndex: Int
    var title: String?
    var text: String?
    var verseReference: String?
    var displayPreference: String?

    init(
        id: String = UUID().uuidString,
        frameIndex: Int,
        title: String? = nil,
        text: String? = nil,
        verseReference: String? = nil,
        displayPreference: String? = nil
    ) {
        self.id = id
        self.frameIndex = frameIndex
        self.title = title
        self.text = text
        self.verseReference = verseReference
        self.displayPreference = displayPreference
    }
}

// MARK: - MediaCaptionTrack

struct MediaCaptionTrack: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var generatedTranscript: String?
    var editedTranscript: String?
    var languageCode: String?
    var style: MediaCaptionStyle?
    var displayByDefault: Bool?
    var source: MediaTrackSource
    var cues: [MediaCaptionCue]?
    var lastEditedAt: Date?

    var effectiveSource: MediaTrackSource { source }

    init(
        id: String = UUID().uuidString,
        generatedTranscript: String? = nil,
        editedTranscript: String? = nil,
        languageCode: String? = nil,
        style: MediaCaptionStyle? = nil,
        displayByDefault: Bool? = nil,
        source: MediaTrackSource = .aiGenerated,
        cues: [MediaCaptionCue]? = nil,
        lastEditedAt: Date? = nil
    ) {
        self.id = id
        self.generatedTranscript = generatedTranscript
        self.editedTranscript = editedTranscript
        self.languageCode = languageCode
        self.style = style
        self.displayByDefault = displayByDefault
        self.source = source
        self.cues = cues
        self.lastEditedAt = lastEditedAt
    }
}

// MARK: - MediaAudioBed

struct MediaAudioBed: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var source: String
    var title: String
    var artist: String?
    var startOffset: TimeInterval
    var trimDuration: TimeInterval?
    var volume: Double

    init(
        id: String = UUID().uuidString,
        source: String,
        title: String,
        artist: String? = nil,
        startOffset: TimeInterval = 0,
        trimDuration: TimeInterval? = nil,
        volume: Double = 1.0
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

// MARK: - MediaGenerationStatus

struct MediaGenerationStatus: Codable, Equatable, Hashable {
    var mediaProcessing: MediaProcessingState
    var captions: MediaGenerationState
    var keyMoments: MediaGenerationState
    var featuredFrame: MediaGenerationState
    var lastUpdatedAt: Date
    var errorMessage: String?

    init(
        mediaProcessing: MediaProcessingState = .ready,
        captions: MediaGenerationState = .notRequested,
        keyMoments: MediaGenerationState = .notRequested,
        featuredFrame: MediaGenerationState = .ready,
        lastUpdatedAt: Date = Date(),
        errorMessage: String? = nil
    ) {
        self.mediaProcessing = mediaProcessing
        self.captions = captions
        self.keyMoments = keyMoments
        self.featuredFrame = featuredFrame
        self.lastUpdatedAt = lastUpdatedAt
        self.errorMessage = errorMessage
    }

    static let `default` = MediaGenerationStatus()
}

// MARK: - MediaAudioAttachment

struct MediaAudioAttachment: Codable, Equatable, Hashable {
    var id: String
    var source: String
    var title: String
    var artist: String?
    var startOffset: TimeInterval
    var trimDuration: TimeInterval?
    var volume: Double

    init(
        id: String = UUID().uuidString,
        source: String,
        title: String,
        artist: String? = nil,
        startOffset: TimeInterval = 0,
        trimDuration: TimeInterval? = nil,
        volume: Double = 1.0
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.artist = artist
        self.startOffset = startOffset
        self.trimDuration = trimDuration
        self.volume = volume
    }

    var asMediaAudioBed: MediaAudioBed {
        MediaAudioBed(
            id: id, source: source, title: title, artist: artist,
            startOffset: startOffset, trimDuration: trimDuration, volume: volume
        )
    }
}

// MARK: - PerMediaCaptionMetadataSheet

import SwiftUI

struct PerMediaCaptionMetadataSheet: View {
    let route: PerMediaCaptionEditorRoute
    @Binding var draft: FrameCaptionDraft
    var onGenerateAltText: (() -> Void)? = nil
    var isGeneratingAltText: Bool = false
    var onSave: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Caption") {
                    TextField("Alt text", text: $draft.altText)
                    TextField("Reflection prompt", text: $draft.reflectionPrompt)
                }
                if isGeneratingAltText {
                    Section { ProgressView("Generating alt text…") }
                }
            }
            .navigationTitle(route.kind.rawValue.capitalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel?() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave?() }
                }
                if let onGenerateAltText {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Generate Alt Text", action: onGenerateAltText)
                    }
                }
            }
        }
    }
}
