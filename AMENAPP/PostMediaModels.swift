//
//  PostMediaModels.swift
//  AMENAPP
//
//  Liquid Glass Media System - Data Models
//  Premium media experience for faith-centered social feed
//

import Foundation
import SwiftUI

// MARK: - Media Type

enum PostMediaType: String, Codable {
    case image
    case video
}

// MARK: - Post Media Item

struct PostMediaItem: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let type: PostMediaType
    let url: String
    let thumbnailURL: String?
    let aspectRatio: CGFloat?
    let order: Int
    
    // Video-specific metadata
    let duration: TimeInterval?
    let fileSize: Int64?
    
    // Image-specific metadata
    let width: Int?
    let height: Int?
    
    init(
        id: String = UUID().uuidString,
        type: PostMediaType,
        url: String,
        thumbnailURL: String? = nil,
        aspectRatio: CGFloat? = nil,
        order: Int = 0,
        duration: TimeInterval? = nil,
        fileSize: Int64? = nil,
        width: Int? = nil,
        height: Int? = nil
    ) {
        self.id = id
        self.type = type
        self.url = url
        self.thumbnailURL = thumbnailURL
        self.aspectRatio = aspectRatio
        self.order = order
        self.duration = duration
        self.fileSize = fileSize
        self.width = width
        self.height = height
    }
    
    /// Computed aspect ratio from width/height if not explicitly set
    var computedAspectRatio: CGFloat {
        if let ratio = aspectRatio {
            return ratio
        }
        if let w = width, let h = height, h > 0 {
            return CGFloat(w) / CGFloat(h)
        }
        // Default to 4:3 for images, 16:9 for videos
        return type == .video ? 16.0 / 9.0 : 4.0 / 3.0
    }
    
    /// Formatted duration string for videos (e.g., "1:23")
    var formattedDuration: String? {
        guard type == .video, let dur = duration else { return nil }
        let minutes = Int(dur) / 60
        let seconds = Int(dur) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Media Container

struct PostMediaContainer: Codable, Equatable {
    let items: [PostMediaItem]
    
    var isEmpty: Bool { items.isEmpty }
    var count: Int { items.count }
    var isSingleItem: Bool { items.count == 1 }
    var hasMultipleItems: Bool { items.count > 1 }
    
    var hasImages: Bool { items.contains { $0.type == .image } }
    var hasVideos: Bool { items.contains { $0.type == .video } }
    var hasMixedMedia: Bool { hasImages && hasVideos }
    
    /// Get sorted items by order
    var sortedItems: [PostMediaItem] {
        items.sorted { $0.order < $1.order }
    }
}

// MARK: - Convenience Initializers

extension PostMediaContainer {
    /// Create from legacy imageURLs array
    static func fromImageURLs(_ urls: [String]) -> PostMediaContainer {
        let items = urls.enumerated().map { index, url in
            PostMediaItem(
                type: .image,
                url: url,
                order: index
            )
        }
        return PostMediaContainer(items: items)
    }
    
    /// Create from single image URL
    static func singleImage(_ url: String) -> PostMediaContainer {
        PostMediaContainer(items: [
            PostMediaItem(type: .image, url: url, order: 0)
        ])
    }
    
    /// Create from single video URL
    static func singleVideo(_ url: String, thumbnailURL: String? = nil, duration: TimeInterval? = nil) -> PostMediaContainer {
        PostMediaContainer(items: [
            PostMediaItem(
                type: .video,
                url: url,
                thumbnailURL: thumbnailURL,
                order: 0,
                duration: duration
            )
        ])
    }
}
