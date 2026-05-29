//
//  ImmersiveMediaModels.swift
//  AMENAPP
//
//  Shared model types for the immersive photo/video viewer and capture flow.
//  These are standalone — no dependency on existing PostCard or feed models.
//

import Foundation
import UIKit

// MARK: - ImmersiveMediaType

enum ImmersiveMediaType: Equatable, Hashable {
    case photo
    case video
}

// MARK: - ImmersiveMediaItem

/// A fully-resolved, ready-to-display media item used by ImmersiveMediaViewer.
struct ImmersiveMediaItem: Identifiable, Hashable {
    let id: String
    let type: ImmersiveMediaType
    let url: URL
    let thumbnailURL: URL?
    let caption: String?
    let authorName: String
    let authorId: String
    /// width / height — defaults to 9/16 for video, 1.0 for photo.
    let aspectRatio: CGFloat

    init(
        id: String,
        type: ImmersiveMediaType,
        url: URL,
        thumbnailURL: URL? = nil,
        caption: String? = nil,
        authorName: String,
        authorId: String,
        aspectRatio: CGFloat? = nil
    ) {
        self.id = id
        self.type = type
        self.url = url
        self.thumbnailURL = thumbnailURL
        self.caption = caption
        self.authorName = authorName
        self.authorId = authorId
        self.aspectRatio = aspectRatio ?? (type == .video ? 9.0 / 16.0 : 1.0)
    }
}

// MARK: - ImmersiveCapturedItem

/// A locally-captured or picker-selected item waiting to be uploaded and posted.
struct ImmersiveCapturedItem: Identifiable {
    let id: UUID
    let type: ImmersiveMediaType
    var image: UIImage?
    var videoURL: URL?
    /// Duration in seconds — non-nil for video items.
    var duration: TimeInterval?
    var caption: String = ""

    init(
        id: UUID = UUID(),
        type: ImmersiveMediaType,
        image: UIImage? = nil,
        videoURL: URL? = nil,
        duration: TimeInterval? = nil,
        caption: String = ""
    ) {
        self.id = id
        self.type = type
        self.image = image
        self.videoURL = videoURL
        self.duration = duration
        self.caption = caption
    }

    /// Returns a best-effort thumbnail: the captured UIImage, or nil for video items
    /// that have not yet generated a thumbnail.
    var thumbnailImage: UIImage? { image }
}
