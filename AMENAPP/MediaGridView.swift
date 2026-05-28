//
//  MediaGridView.swift
//  AMENAPP
//
//  3-column media grid for profile "Photos & Videos" tab.
//  Filters user posts that contain images, displays thumbnails,
//  and opens FullscreenMediaViewer on tap.
//

import SwiftUI
import FirebaseAuth

// MARK: - Media Grid Item

/// Lightweight model representing one media thumbnail in the grid.
struct MediaGridItem: Identifiable {
    let id: String // post UUID string
    let imageURL: String
    let allImageURLs: [String] // all images from the same post
    let indexInPost: Int // which image within the post
}

// MARK: - Media Grid View

struct MediaGridView: View {
    /// Pre-computed media items extracted from posts.
    let mediaItems: [MediaGridItem]

    @State private var selectedMedia: PostMediaContainer?
    @State private var selectedIndex: Int = 0
    @State private var showViewer = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    /// Initialize from precomputed media items.
    init(items: [MediaGridItem], sourceContext: MediaSourceContext = .profile) {
        self.mediaItems = items
    }

    /// Initialize from Post array (own profile).
    init(posts: [Post]) {
        var items: [MediaGridItem] = []
        for post in posts {
            guard let urls = post.imageURLs, !urls.isEmpty else { continue }
            for (index, url) in urls.enumerated() {
                items.append(MediaGridItem(
                    id: "\(post.id.uuidString)_\(index)",
                    imageURL: url,
                    allImageURLs: urls,
                    indexInPost: index
                ))
            }
        }
        self.mediaItems = items
    }

    /// Initialize from ProfilePost array (other user's profile).
    init(profilePosts: [ProfilePost]) {
        var items: [MediaGridItem] = []
        for post in profilePosts {
            guard let urls = post.imageURLs, !urls.isEmpty else { continue }
            for (index, url) in urls.enumerated() {
                items.append(MediaGridItem(
                    id: "\(post.id)_\(index)",
                    imageURL: url,
                    allImageURLs: urls,
                    indexInPost: index
                ))
            }
        }
        self.mediaItems = items
    }

    var body: some View {
        if mediaItems.isEmpty {
            emptyState
        } else {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(mediaItems) { item in
                    mediaThumbnail(item)
                }
            }
            .padding(.horizontal, 2)
            .padding(.top, 4)
            .padding(.bottom, 20)
            .fullScreenCover(isPresented: $showViewer) {
                if let media = selectedMedia {
                    FullscreenMediaViewer(media: media, startIndex: selectedIndex)
                }
            }
        }
    }

    // MARK: - Thumbnail Cell

    private func mediaThumbnail(_ item: MediaGridItem) -> some View {
        Button {
            selectedMedia = PostMediaContainer.fromImageURLs(item.allImageURLs)
            selectedIndex = item.indexInPost
            showViewer = true
        } label: {
            CachedAsyncImage(
                url: URL(string: item.imageURL),
                size: CGSize(width: 200, height: 200)
            ) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Rectangle()
                    .fill(Color.black.opacity(0.04))
                    .overlay(
                        Image(systemName: "photo")
                            .font(.systemScaled(20))
                            .foregroundStyle(Color(white: 0.55))
                    )
            }
            .frame(minHeight: 120)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.72))
                    .overlay(
                        Circle()
                            .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.04), radius: 10, y: 4)
                    .frame(width: 72, height: 72)

                Image(systemName: "photo.on.rectangle.angled")
                    .font(.systemScaled(28))
                    .foregroundStyle(Color(white: 0.55))
            }

            VStack(spacing: 6) {
                Text("No photos or videos yet")
                    .font(AMENFont.semiBold(16))
                    .foregroundStyle(Color(white: 0.10))

                Text("Posts with media will appear here")
                    .font(AMENFont.regular(13))
                    .foregroundStyle(Color(white: 0.55))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}
