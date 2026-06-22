//
//  MediaFeedViewModel.swift
//  AMENAPP
//
//  State management for the Feed Display Mode system.
//  Precomputes filtered media collections, preserves scroll
//  positions per mode, and manages loading/error/empty states.
//

import SwiftUI
import Combine

// MARK: - Media Feed Filter

/// Secondary filter within Photos & Videos mode.
enum MediaFeedFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case photos = "Photos"
    case videos = "Videos"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .photos: return "photo"
        case .videos: return "video"
        }
    }
}

// MARK: - Media Feed State

enum MediaFeedState: Equatable {
    case idle
    case loading
    case loaded
    case empty
    case error(String)
    case privacyRestricted
}

// MARK: - Media Grid Item (Enhanced)

/// Enriched media grid item with post context for tile metadata.
struct EnrichedMediaGridItem: Identifiable, Equatable {
    let id: String
    let imageURL: String
    let allImageURLs: [String]
    let indexInPost: Int
    let postId: String
    let isCarousel: Bool
    let carouselCount: Int
    let verseReference: String?
    let postContent: String
    let postTimestamp: String
    let postType: String?
    let authorName: String?
    let authorProfileImageURL: String?
    let createdAt: Date

    /// Whether this is the first media item from its parent post.
    /// Used to avoid duplicate tiles for the same post in the grid.
    let isFirstInPost: Bool
}

// MARK: - View Model

@MainActor
final class MediaFeedViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var state: MediaFeedState = .idle
    @Published private(set) var mediaItems: [EnrichedMediaGridItem] = []
    @Published private(set) var filteredItems: [EnrichedMediaGridItem] = []
    @Published var activeFilter: MediaFeedFilter = .all

    /// Scroll anchor IDs per mode for position restoration.
    @Published var postsScrollAnchor: String?
    @Published var mediaScrollAnchor: String?

    /// Last selected feed view mode — persisted for own profile.
    @Published var lastSelectedMode: FeedViewMode = .posts

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        // Re-filter whenever the active filter changes
        $activeFilter
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.applyFilter()
            }
            .store(in: &cancellables)
    }

    // MARK: - Post Feed Ingestion

    /// Precompute media items from a Post array (own profile / main feed).
    func ingestPosts(_ posts: [Post]) {
        state = .loading
        var items: [EnrichedMediaGridItem] = []

        for post in posts {
            guard post.isMediaFeedEligible, let urls = post.imageURLs, !urls.isEmpty else { continue }
            for (index, url) in urls.enumerated() {
                items.append(EnrichedMediaGridItem(
                    id: "\(post.backendId)_\(index)",
                    imageURL: url,
                    allImageURLs: urls,
                    indexInPost: index,
                    postId: post.backendId,
                    isCarousel: post.isCarousel,
                    carouselCount: post.mediaCount,
                    verseReference: post.verseReference,
                    postContent: post.content,
                    postTimestamp: post.timeAgo,
                    postType: post.category.displayName,
                    authorName: post.authorName,
                    authorProfileImageURL: post.authorProfileImageURL,
                    createdAt: post.createdAt,
                    isFirstInPost: index == 0
                ))
            }
        }

        mediaItems = items
        applyFilter()
        state = items.isEmpty ? .empty : .loaded
    }

    /// Precompute media items from a ProfilePost array (other user's profile).
    func ingestProfilePosts(_ posts: [ProfilePost]) {
        state = .loading
        var items: [EnrichedMediaGridItem] = []

        for post in posts {
            guard post.hasMedia, let urls = post.imageURLs, !urls.isEmpty else { continue }
            for (index, url) in urls.enumerated() {
                items.append(EnrichedMediaGridItem(
                    id: "\(post.id)_\(index)",
                    imageURL: url,
                    allImageURLs: urls,
                    indexInPost: index,
                    postId: post.id,
                    isCarousel: post.isCarousel,
                    carouselCount: post.mediaCount,
                    verseReference: post.verseReference,
                    postContent: post.content,
                    postTimestamp: post.timestamp,
                    postType: post.postType?.rawValue,
                    authorName: post.authorName,
                    authorProfileImageURL: post.authorProfileImageURL,
                    createdAt: post.createdAt,
                    isFirstInPost: index == 0
                ))
            }
        }

        mediaItems = items
        applyFilter()
        state = items.isEmpty ? .empty : .loaded
    }

    /// Mark state as privacy-restricted (private profile without follow).
    func setPrivacyRestricted() {
        state = .privacyRestricted
        mediaItems = []
        filteredItems = []
    }

    /// Mark state as error.
    func setError(_ message: String) {
        state = .error(message)
    }

    // MARK: - Filtering

    private func applyFilter() {
        switch activeFilter {
        case .all:
            filteredItems = mediaItems
        case .photos:
            // Currently all legacy media is images; future-proofed for video type
            filteredItems = mediaItems
        case .videos:
            // No video support in legacy model yet — show empty
            filteredItems = []
        }
    }

    // MARK: - Mode Persistence

    private static let modeKey = "amen.feedDisplayMode.lastSelected"

    func persistMode(_ mode: FeedViewMode) {
        lastSelectedMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey)
    }

    func restoreMode() -> FeedViewMode {
        guard let raw = UserDefaults.standard.string(forKey: Self.modeKey),
              let mode = FeedViewMode(rawValue: raw) else {
            return .posts
        }
        lastSelectedMode = mode
        return mode
    }

    // MARK: - Convenience

    /// Get the first-in-post items only (one tile per post, no duplicate tiles).
    var uniquePostItems: [EnrichedMediaGridItem] {
        filteredItems.filter { $0.isFirstInPost }
    }
}
