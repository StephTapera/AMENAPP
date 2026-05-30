import Foundation
import FirebaseFirestore

// MARK: - Media Metadata Enums

enum MediaGenerationState: String, Codable, Equatable {
    case notRequested = "not_requested"
    case queued       = "queued"
    case generating   = "generating"
    case ready        = "ready"
    case failed       = "failed"
}

enum MediaProcessingState: String, Codable, Equatable {
    case uploading  = "uploading"
    case queued     = "queued"
    case processing = "processing"
    case ready      = "ready"
    case partial    = "partial"
    case failed     = "failed"
}

enum MediaKeyMomentKind: String, Codable, CaseIterable {
    case prayer        = "prayer"
    case scripture     = "scripture"
    case testimony     = "testimony"
    case teaching      = "teaching"
    case reflection    = "reflection"
    case callToAction  = "callToAction"
    case worship       = "worship"
    case mainPoint     = "mainPoint"

    var title: String {
        switch self {
        case .prayer:       return "Prayer"
        case .scripture:    return "Scripture"
        case .testimony:    return "Testimony"
        case .teaching:     return "Teaching"
        case .reflection:   return "Reflection"
        case .callToAction: return "Call to Action"
        case .worship:      return "Worship"
        case .mainPoint:    return "Main Point"
        }
    }
}

enum MediaCaptionModerationState: String, Codable, Equatable, Hashable {
    case notRequired = "not_required"
    case pending     = "pending"
    case approved    = "approved"
    case rejected    = "rejected"
    case removed     = "removed"
}

enum MediaTrackSource: String, Codable, Equatable {
    case userEdited  = "user_edited"
    case aiGenerated = "ai_generated"
    case imported    = "imported"
    case generated   = "generated"
}

enum MediaCaptionStyle: String, Codable, CaseIterable {
    case minimal  = "minimal"
    case standard = "standard"
    case bold     = "bold"
    case cinematic = "cinematic"

    var title: String {
        switch self {
        case .minimal:   return "Minimal"
        case .standard:  return "Standard"
        case .bold:      return "Bold"
        case .cinematic: return "Cinematic"
        }
    }
}

// MARK: - Per-Media Caption Editor Route

struct PerMediaCaptionEditorRoute: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case scripture
        case reflection
        case altText
    }
    let index: Int
    let kind: Kind
    var id: String { "\(index)-\(kind.rawValue)" }
}

struct VideoCaptionCueDraft: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var startTime: TimeInterval
    var endTime: TimeInterval
    var text: String

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

    var asCue: MediaCaptionCue {
        MediaCaptionCue(id: id, startTime: startTime, endTime: endTime, text: text)
    }
}

struct KeyMomentDraft: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var timestamp: TimeInterval
    var label: String
    var kind: MediaKeyMomentKind
    var source: MediaTrackSource

    init(
        id: String = UUID().uuidString,
        timestamp: TimeInterval,
        label: String,
        kind: MediaKeyMomentKind,
        source: MediaTrackSource = .userEdited
    ) {
        self.id = id
        self.timestamp = timestamp
        self.label = label
        self.kind = kind
        self.source = source
    }

    var asMoment: MediaKeyMoment {
        MediaKeyMoment(
            id: id,
            timestamp: timestamp,
            label: label,
            kind: kind,
            source: source.rawValue
        )
    }
}

struct FrameCaptionDraft: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var frameIndex: Int
    var title: String
    var text: String
    var verseReference: String
    var isFeatured: Bool
    var altText: String
    var reflectionPrompt: String
    var scriptureRefs: [String]
    var captionModerationState: MediaCaptionModerationState

    init(
        id: String = UUID().uuidString,
        frameIndex: Int,
        title: String = "",
        text: String = "",
        verseReference: String = "",
        isFeatured: Bool = false,
        altText: String = "",
        reflectionPrompt: String = "",
        scriptureRefs: [String] = [],
        captionModerationState: MediaCaptionModerationState = .notRequired
    ) {
        self.id = id
        self.frameIndex = frameIndex
        self.title = title
        self.text = text
        self.verseReference = verseReference
        self.isFeatured = isFeatured
        self.altText = altText
        self.reflectionPrompt = reflectionPrompt
        self.scriptureRefs = scriptureRefs
        self.captionModerationState = captionModerationState
    }

    var asFrameCaption: MediaFrameCaption {
        MediaFrameCaption(
            id: id,
            frameIndex: frameIndex,
            title: title.nilIfEmpty,
            text: text.nilIfEmpty,
            verseReference: verseReference.nilIfEmpty,
            displayPreference: "default"
        )
    }
}

struct VideoMetadataDraft: Codable, Equatable, Hashable {
    var captionsEnabledByDefault: Bool
    var captionStyle: MediaCaptionStyle
    var captionGenerationState: MediaGenerationState
    var keyMomentsGenerationState: MediaGenerationState
    var processingState: MediaProcessingState
    var captionLanguageCode: String
    var captionCues: [VideoCaptionCueDraft]
    var keyMoments: [KeyMomentDraft]
    var featuredFrameTime: TimeInterval
    var audioBedTitle: String
    var audioBedArtist: String
    var audioBedSource: String
    var audioBedVolume: Double
    var userEdited: Bool

    init(
        captionsEnabledByDefault: Bool = true,
        captionStyle: MediaCaptionStyle = .minimal,
        captionGenerationState: MediaGenerationState = .queued,
        keyMomentsGenerationState: MediaGenerationState = .queued,
        processingState: MediaProcessingState = .processing,
        captionLanguageCode: String = "en",
        captionCues: [VideoCaptionCueDraft] = [],
        keyMoments: [KeyMomentDraft] = [],
        featuredFrameTime: TimeInterval = 0,
        audioBedTitle: String = "",
        audioBedArtist: String = "",
        audioBedSource: String = "",
        audioBedVolume: Double = 0.35,
        userEdited: Bool = false
    ) {
        self.captionsEnabledByDefault = captionsEnabledByDefault
        self.captionStyle = captionStyle
        self.captionGenerationState = captionGenerationState
        self.keyMomentsGenerationState = keyMomentsGenerationState
        self.processingState = processingState
        self.captionLanguageCode = captionLanguageCode
        self.captionCues = captionCues
        self.keyMoments = keyMoments
        self.featuredFrameTime = featuredFrameTime
        self.audioBedTitle = audioBedTitle
        self.audioBedArtist = audioBedArtist
        self.audioBedSource = audioBedSource
        self.audioBedVolume = audioBedVolume
        self.userEdited = userEdited
    }

    var transcriptText: String {
        captionCues
            .map(\.text)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")
    }

    var captionTrack: MediaCaptionTrack? {
        let transcript = transcriptText.nilIfEmpty
        guard transcript != nil || !captionCues.isEmpty else { return nil }
        return MediaCaptionTrack(
            generatedTranscript: captionGenerationState == .ready ? transcript : nil,
            editedTranscript: userEdited ? transcript : nil,
            languageCode: captionLanguageCode,
            style: captionStyle,
            displayByDefault: captionsEnabledByDefault,
            source: userEdited ? .userEdited : .generated,
            cues: captionCues.map(\.asCue),
            lastEditedAt: userEdited ? Date() : nil
        )
    }

    var persistedKeyMoments: [MediaKeyMoment] {
        keyMoments.enumerated().map { index, draft in
            MediaKeyMoment(
                id: draft.id,
                timestamp: draft.timestamp,
                label: draft.label,
                kind: draft.kind,
                source: draft.source.rawValue,
                sortOrder: index
            )
        }
    }

    var audioBed: MediaAudioBed? {
        guard let title = audioBedTitle.nilIfEmpty,
              let source = audioBedSource.nilIfEmpty else { return nil }
        return MediaAudioBed(
            source: source,
            title: title,
            artist: audioBedArtist.nilIfEmpty,
            startOffset: 0,
            trimDuration: nil,
            volume: audioBedVolume
        )
    }

    var generationStatus: MediaGenerationStatus {
        MediaGenerationStatus(
            mediaProcessing: processingState,
            captions: captionGenerationState,
            keyMoments: keyMomentsGenerationState,
            featuredFrame: .ready,
            lastUpdatedAt: Date(),
            errorMessage: nil
        )
    }
}

struct CreatePostMediaMetadataDraft: Codable, Equatable, Hashable {
    var videoDraft: VideoMetadataDraft?
    var frameCaptions: [FrameCaptionDraft]
    var featuredFrameIndex: Int
    var draftUpdatedAt: Date
    var audioAttachment: MediaAudioAttachment?

    init(
        videoDraft: VideoMetadataDraft? = nil,
        frameCaptions: [FrameCaptionDraft] = [],
        featuredFrameIndex: Int = 0,
        draftUpdatedAt: Date = Date(),
        audioAttachment: MediaAudioAttachment? = nil
    ) {
        self.videoDraft = videoDraft
        self.frameCaptions = frameCaptions
        self.featuredFrameIndex = featuredFrameIndex
        self.draftUpdatedAt = draftUpdatedAt
        self.audioAttachment = audioAttachment
    }

    mutating func syncForImages(count: Int) {
        guard count >= 0 else { return }
        var updated = frameCaptions.filter { $0.frameIndex < count }
        for index in 0..<count where !updated.contains(where: { $0.frameIndex == index }) {
            updated.append(FrameCaptionDraft(frameIndex: index, isFeatured: index == featuredFrameIndex))
        }
        updated.sort { $0.frameIndex < $1.frameIndex }
        frameCaptions = updated.enumerated().map { offset, item in
            var mutable = item
            mutable.frameIndex = offset
            mutable.isFeatured = offset == featuredFrameIndex
            return mutable
        }
        if frameCaptions.isEmpty {
            featuredFrameIndex = 0
        } else {
            featuredFrameIndex = min(featuredFrameIndex, max(frameCaptions.count - 1, 0))
        }
        draftUpdatedAt = Date()
    }

    mutating func syncForWitnessVideo(duration: TimeInterval?) {
        guard videoDraft == nil else { return }
        let cues = Self.defaultCaptionCues(for: duration ?? 45)
        let moments = Self.defaultKeyMoments(for: duration ?? 45)
        videoDraft = VideoMetadataDraft(
            captionsEnabledByDefault: true,
            captionStyle: .minimal,
            captionGenerationState: cues.isEmpty ? .notRequested : .ready,
            keyMomentsGenerationState: moments.isEmpty ? .notRequested : .ready,
            processingState: .ready,
            captionLanguageCode: "en",
            captionCues: cues,
            keyMoments: moments,
            featuredFrameTime: min(duration ?? 0, 1.0),
            userEdited: false
        )
        draftUpdatedAt = Date()
    }

    mutating func markEdited() {
        draftUpdatedAt = Date()
        if videoDraft != nil {
            videoDraft?.userEdited = true
        }
    }

    func frameCaption(for index: Int) -> FrameCaptionDraft? {
        frameCaptions.first(where: { $0.frameIndex == index })
    }

    private static func defaultCaptionCues(for duration: TimeInterval) -> [VideoCaptionCueDraft] {
        let totalDuration = max(duration, 15)
        let segmentCount = min(max(Int(totalDuration / 12), 2), 5)
        let cueLength = totalDuration / Double(segmentCount)
        return (0..<segmentCount).map { index in
            let start = Double(index) * cueLength
            let end = min(start + cueLength, totalDuration)
            let kind = ["Opening", "Main point", "Verse", "Prayer", "Reflection"][min(index, 4)]
            return VideoCaptionCueDraft(
                startTime: start,
                endTime: end,
                text: "\(kind) cue"
            )
        }
    }

    private static func defaultKeyMoments(for duration: TimeInterval) -> [KeyMomentDraft] {
        MediaKeyMoment.fallbackMoments(for: max(duration, 30)).map {
            KeyMomentDraft(
                id: $0.id,
                timestamp: $0.timestamp,
                label: $0.label,
                kind: $0.kind,
                source: .generated
            )
        }
    }
}

@MainActor
final class MediaMetadataPersistenceService {
    static let shared = MediaMetadataPersistenceService()

    private let db = Firestore.firestore()

    private init() {}

    func persistMetadataMirror(
        postId: String,
        authorId: String,
        mediaItems: [PostMediaItem]
    ) async throws {
        let postRef = db.collection("posts").document(postId)

        for item in mediaItems {
            let mediaMetaRef = postRef.collection("mediaMeta").document(item.id)
            try await mediaMetaRef.setData(mediaMetaDocument(for: item, authorId: authorId), merge: true)

            if let captionTrack = item.captionTrack {
                try await mediaMetaRef
                    .collection("captionTracks")
                    .document(captionTrack.id)
                    .setData(captionTrackDocument(for: captionTrack), merge: true)
            }

            for moment in item.resolvedKeyMoments {
                try await mediaMetaRef
                    .collection("keyMoments")
                    .document(moment.id)
                    .setData(keyMomentDocument(for: moment), merge: true)
            }
        }
    }

    private func mediaMetaDocument(for item: PostMediaItem, authorId: String) -> [String: Any] {
        [
            "mediaId": item.id,
            "authorId": authorId,
            "type": item.type.rawValue,
            "width": item.width as Any,
            "height": item.height as Any,
            "duration": item.duration as Any,
            "thumbnailURL": item.thumbnailURL as Any,
            "previewURL": item.previewURL ?? item.thumbnailURL as Any,
            "originalURL": item.originalURL ?? item.url,
            "featuredFrameTime": item.featuredFrameTime as Any,
            "featuredFrameIndex": item.frameCaptionMetadata?.frameIndex as Any,
            "processingState": item.generationStatus.mediaProcessing.rawValue,
            "captionsGenerationState": item.generationStatus.captions.rawValue,
            "keyMomentsGenerationState": item.generationStatus.keyMoments.rawValue,
            "featuredFrameGenerationState": item.generationStatus.featuredFrame.rawValue,
            "frameCaption": item.effectiveFrameCaption as Any,
            "audioBed": audioBedDocument(for: item.audioBed),
            "userEditedMetadata": item.userEditedMetadata ?? false,
            "updatedAt": Timestamp(date: Date())
        ]
    }

    private func captionTrackDocument(for track: MediaCaptionTrack) -> [String: Any] {
        [
            "captionTrackId": track.id,
            "language": track.languageCode as Any,
            "source": track.effectiveSource.rawValue,
            "selectedCaptionStyle": track.style?.rawValue as Any,
            "displayByDefault": track.displayByDefault ?? false,
            "generatedTranscript": track.generatedTranscript as Any,
            "editedTranscript": track.editedTranscript as Any,
            "segments": (track.cues ?? []).map {
                [
                    "cueId": $0.id,
                    "startTime": $0.startTime,
                    "endTime": $0.endTime,
                    "text": $0.text
                ]
            },
            "lastEditedAt": track.lastEditedAt.map(Timestamp.init(date:)) as Any
        ]
    }

    private func keyMomentDocument(for moment: MediaKeyMoment) -> [String: Any] {
        [
            "momentId": moment.id,
            "time": moment.timestamp,
            "label": moment.label,
            "kind": moment.kind.rawValue,
            "source": moment.source as Any,
            "sortOrder": moment.sortOrder as Any
        ]
    }

    private func audioBedDocument(for audioBed: MediaAudioBed?) -> [String: Any]? {
        guard let audioBed else { return nil }
        return [
            "audioBedId": audioBed.id,
            "source": audioBed.source,
            "title": audioBed.title,
            "artist": audioBed.artist as Any,
            "startOffset": audioBed.startOffset,
            "trimDuration": audioBed.trimDuration as Any,
            "volume": audioBed.volume
        ]
    }
}

private extension String {
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
