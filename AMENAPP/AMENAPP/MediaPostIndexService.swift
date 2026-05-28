//
//  MediaPostIndexService.swift
//  AMENAPP
//
//  Reads the denormalized users/{userId}/mediaPosts/{postId} index
//  written by the mediaPostIndex Cloud Functions.
//
//  Replaces direct "posts" collection scans for profile media tabs with
//  cheap paginated subcollection reads. The index is backend-maintained
//  and always consistent with moderation state and visibility changes.
//
//  Usage (own profile):
//      let service = MediaPostIndexService(userId: uid, viewerOwns: true)
//      await service.loadFirstPage()
//      // service.indexDocs → [MediaPostIndexDoc]
//
//  Usage (other user's profile — viewer must be a follower for private posts):
//      let service = MediaPostIndexService(userId: targetUid, viewerOwns: false)
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

// MARK: - Media Index Document

/// Lightweight model decoded from users/{userId}/mediaPosts/{postId}.
/// Mirrors the schema written by mediaPostIndex.ts.
struct MediaPostIndexDoc: Identifiable, Decodable, Equatable {
    let id: String                       // = postId
    let postId: String
    let authorId: String
    let visibility: String               // "everyone" | "followers" | "community"
    let mediaItems: [IndexMediaItem]
    let primaryThumbnailURL: String
    let primaryMediaType: String         // "image" | "video"
    let mediaCount: Int
    let isCarousel: Bool
    let caption: String
    let verseReference: String?
    let churchNoteId: String?
    let isChurchShare: Bool
    let sharedChurchId: String?
    let category: String
    let createdAt: Date
    let isHidden: Bool
    let moderationState: String          // "clean" | "flagged" | "removed" | "quarantined"
    let status: String                   // "published" | "publishing" | "draft"

    // MARK: Manual decode (Firestore Timestamp → Date)

    enum CodingKeys: String, CodingKey {
        case postId, authorId, visibility, mediaItems
        case primaryThumbnailURL, primaryMediaType, mediaCount, isCarousel
        case caption, verseReference, churchNoteId, isChurchShare, sharedChurchId
        case category, createdAt, isHidden, moderationState, status
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        postId           = try c.decode(String.self, forKey: .postId)
        id               = postId
        authorId         = try c.decode(String.self, forKey: .authorId)
        visibility       = try c.decodeIfPresent(String.self, forKey: .visibility) ?? "everyone"
        mediaItems       = try c.decodeIfPresent([IndexMediaItem].self, forKey: .mediaItems) ?? []
        primaryThumbnailURL = try c.decodeIfPresent(String.self, forKey: .primaryThumbnailURL) ?? ""
        primaryMediaType = try c.decodeIfPresent(String.self, forKey: .primaryMediaType) ?? "image"
        mediaCount       = try c.decodeIfPresent(Int.self, forKey: .mediaCount) ?? 1
        isCarousel       = try c.decodeIfPresent(Bool.self, forKey: .isCarousel) ?? false
        caption          = try c.decodeIfPresent(String.self, forKey: .caption) ?? ""
        verseReference   = try c.decodeIfPresent(String.self, forKey: .verseReference)
        churchNoteId     = try c.decodeIfPresent(String.self, forKey: .churchNoteId)
        isChurchShare    = try c.decodeIfPresent(Bool.self, forKey: .isChurchShare) ?? false
        sharedChurchId   = try c.decodeIfPresent(String.self, forKey: .sharedChurchId)
        category         = try c.decodeIfPresent(String.self, forKey: .category) ?? "general"
        isHidden         = try c.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        moderationState  = try c.decodeIfPresent(String.self, forKey: .moderationState) ?? "clean"
        status           = try c.decodeIfPresent(String.self, forKey: .status) ?? "published"
        createdAt        = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    // MARK: Convenience

    var mediaType: PostMediaType {
        primaryMediaType == "video" ? .video : .image
    }

    var allThumbnailURLs: [String] {
        mediaItems.map { $0.thumbnailURL ?? $0.url }
    }
}

// MARK: - Index Media Item

struct IndexMediaItem: Decodable, Equatable {
    let id: String
    let type: String
    let url: String
    let thumbnailURL: String?
    let aspectRatio: Double?
    let order: Int
    let duration: Double?
    let width: Int?
    let height: Int?

    var postMediaType: PostMediaType { type == "video" ? .video : .image }
    var computedAspectRatio: CGFloat {
        if let r = aspectRatio { return CGFloat(r) }
        if let w = width, let h = height, h > 0 { return CGFloat(w) / CGFloat(h) }
        return type == "video" ? 16.0 / 9.0 : 4.0 / 3.0
    }
}

// MARK: - Filter

enum MediaPostIndexFilter: String, CaseIterable, Identifiable {
    case all    = "All"
    case photos = "Photos"
    case videos = "Videos"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all:    return "square.grid.2x2"
        case .photos: return "photo"
        case .videos: return "video"
        }
    }
}

// MARK: - Service

/// Async/await paginated reader for users/{userId}/mediaPosts.
@MainActor
final class MediaPostIndexService: ObservableObject {

    // MARK: Published State

    @Published private(set) var docs: [MediaPostIndexDoc] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasMore = true
    @Published var activeFilter: MediaPostIndexFilter = .all

    // MARK: Config

    let userId: String
    /// True when the current viewer is looking at their own profile.
    let viewerOwns: Bool

    private let pageSize: Int = 30
    private var lastSnapshot: DocumentSnapshot?
    private let db = Firestore.firestore()

    // MARK: Init

    init(userId: String, viewerOwns: Bool) {
        self.userId = userId
        self.viewerOwns = viewerOwns
    }

    // MARK: - Computed

    var filtered: [MediaPostIndexDoc] {
        switch activeFilter {
        case .all:    return docs
        case .photos: return docs.filter { $0.primaryMediaType == "image" }
        case .videos: return docs.filter { $0.primaryMediaType == "video" }
        }
    }

    // MARK: - Pagination

    /// Load the first page (resets all state). Call on appear / pull-to-refresh.
    func loadFirstPage() async {
        guard !isLoading else { return }
        docs = []
        lastSnapshot = nil
        hasMore = true
        errorMessage = nil
        await fetchNextPage()
    }

    /// Load the next page for infinite scroll. No-op if already loading or exhausted.
    func loadNextPageIfNeeded(trigger: MediaPostIndexDoc) async {
        guard hasMore, !isLoading else { return }
        guard let last = docs.last, last.id == trigger.id else { return }
        await fetchNextPage()
    }

    // MARK: - Private

    private func fetchNextPage() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let collection = db
                .collection("users")
                .document(userId)
                .collection("mediaPosts")

            var query: Query = collection
                .whereField("isHidden", isEqualTo: false)
                .whereField("status", isEqualTo: "published")
                .order(by: "createdAt", descending: true)
                .limit(to: pageSize)

            if let cursor = lastSnapshot {
                query = query.start(afterDocument: cursor)
            }

            let snapshot = try await query.getDocuments()
            let fetched = snapshot.documents.compactMap { doc -> MediaPostIndexDoc? in
                try? doc.data(as: MediaPostIndexDoc.self)
            }

            lastSnapshot = snapshot.documents.last
            hasMore = fetched.count == pageSize
            docs.append(contentsOf: fetched)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - MediaPostIndexDoc → MediaGridItem conversion

extension MediaPostIndexDoc {
    /// Convert to the MediaGridItem model used by MediaGridView.
    /// Produces one MediaGridItem per media item in the post (for carousel expansion).
    func toGridItems() -> [MediaGridItem] {
        guard !mediaItems.isEmpty else {
            // Fallback: single item from primary fields
            return [MediaGridItem(
                id: "\(postId)_0",
                imageURL: primaryThumbnailURL,
                allImageURLs: [primaryThumbnailURL],
                indexInPost: 0
            )]
        }
        let sorted = mediaItems.sorted { $0.order < $1.order }
        let allURLs = sorted.compactMap { $0.thumbnailURL ?? $0.url }
        return sorted.enumerated().map { index, item in
            MediaGridItem(
                id: "\(postId)_\(index)",
                imageURL: item.thumbnailURL ?? item.url ?? "",
                allImageURLs: allURLs,
                indexInPost: index
            )
        }
    }

    /// Convert to the EnrichedMediaGridItem model used by MediaDetailView.
    func toEnrichedGridItem(indexInPost: Int = 0) -> EnrichedMediaGridItem {
        let sorted = mediaItems.sorted { $0.order < $1.order }
        let allURLs = sorted.map { $0.thumbnailURL ?? $0.url }

        return EnrichedMediaGridItem(
            id: "\(postId)_\(indexInPost)",
            imageURL: allURLs.first ?? primaryThumbnailURL,
            allImageURLs: allURLs.isEmpty ? [primaryThumbnailURL] : allURLs,
            indexInPost: indexInPost,
            postId: postId,
            isCarousel: isCarousel,
            carouselCount: mediaCount,
            verseReference: verseReference,
            postContent: caption,
            postTimestamp: createdAt.timeAgoString(),
            postType: category,
            authorId: authorId,
            authorName: nil,   // hydrated by caller from user doc cache
            authorProfileImageURL: nil,
            createdAt: createdAt,
            isFirstInPost: indexInPost == 0
        )
    }
}

// MARK: - Date helper

private extension Date {
    func timeAgoString() -> String {
        let seconds = Int(-timeIntervalSinceNow)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86400 { return "\(seconds / 3600)h" }
        if seconds < 604800 { return "\(seconds / 86400)d" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }
}
