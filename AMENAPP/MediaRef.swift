// MediaRef.swift
// AMENAPP
// Media reference model for universal content nodes.

import Foundation

enum MediaRefType: String, Codable, CaseIterable {
    case image
    case video
    case audio
    case unknown
}

enum MediaTranscriptStatus: String, Codable, CaseIterable {
    case notRequested
    case pending
    case ready
    case failed
}

enum MediaCaptionStatus: String, Codable, CaseIterable {
    case notRequested
    case pending
    case ready
    case failed
}

enum MediaProcessingState: String, Codable, CaseIterable {
    case queued
    case uploading
    case processing
    case ready
    case partial
    case failed
}

struct MediaRef: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var mediaId: String?
    var type: MediaRefType
    var url: String?
    var thumbnailURL: String?
    var storagePath: String?
    var width: Int?
    var height: Int?
    var duration: Double?
    var caption: String?
    var altText: String?
    var coverFrameTime: Double?
    var voiceoverURL: String?
    var processingState: MediaProcessingState?
    var transcriptStatus: MediaTranscriptStatus?
    var captionStatus: MediaCaptionStatus?
    var localFileURL: String?

    init(
        id: String = UUID().uuidString,
        mediaId: String? = nil,
        type: MediaRefType,
        url: String? = nil,
        thumbnailURL: String? = nil,
        storagePath: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        duration: Double? = nil,
        caption: String? = nil,
        altText: String? = nil,
        coverFrameTime: Double? = nil,
        voiceoverURL: String? = nil,
        processingState: MediaProcessingState? = nil,
        transcriptStatus: MediaTranscriptStatus? = nil,
        captionStatus: MediaCaptionStatus? = nil,
        localFileURL: String? = nil
    ) {
        self.id = id
        self.mediaId = mediaId
        self.type = type
        self.url = url
        self.thumbnailURL = thumbnailURL
        self.storagePath = storagePath
        self.width = width
        self.height = height
        self.duration = duration
        self.caption = caption
        self.altText = altText
        self.coverFrameTime = coverFrameTime
        self.voiceoverURL = voiceoverURL
        self.processingState = processingState
        self.transcriptStatus = transcriptStatus
        self.captionStatus = captionStatus
        self.localFileURL = localFileURL
    }
}
