//
//  MediaCarouselView.swift
//  AMENAPP
//
//  Carousel for multi-media posts with snap paging and peek preview
//  Liquid Glass aesthetic with smooth interactions
//

import SwiftUI

// MARK: - Media Carousel View

struct MediaCarouselView: View {
    let media: PostMediaContainer
    var onMediaTap: ((PostMediaItem) -> Void)? = nil

    /// Optional post ID for media resume tracking (System 12).
    var postId: String? = nil

    /// Called when the user swipes to a different item.
    var onActiveIndexChanged: ((Int) -> Void)? = nil

    @State private var currentIndex = 0
    @State private var scrolledIndex: Int? = 0
    @State private var carouselAppeared = false
    @GestureState private var dragOffset: CGFloat = 0

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let itemWidth: CGFloat = UIScreen.main.bounds.width - 64 // Padding + peek
    private let itemSpacing: CGFloat = 12
    private let peekAmount: CGFloat = 32

    // MARK: - Per-media caption for the visible slide (System 24)

    /// Returns the `perMediaCaption` string for the currently-visible carousel item,
    /// or nil if the flag is off or the caption is empty.
    private var activePerMediaCaption: String? {
        guard AMENFeatureFlags.shared.perMediaCaptionsEnabled else { return nil }
        let caption = media.sortedItems[safe: currentIndex]?.perMediaCaption
        return caption?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var body: some View {
        VStack(spacing: 12) {
            // Carousel scroll — LazyHStack so only the visible item ±1 is loaded.
            // ForEach inside a plain HStack was creating GlassImageView / GlassVideoPlayerView
            // for every item in the post at the moment the card scrolled into view, firing
            // one network image request per media item regardless of whether the user ever
            // swipes to that slide.
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: itemSpacing) {
                    ForEach(Array(media.sortedItems.enumerated()), id: \.element.id) { index, item in
                        mediaItemView(item, index: index)
                            .frame(width: itemWidth)
                            .id(index)
                    }
                }
                .padding(.horizontal, (UIScreen.main.bounds.width - itemWidth) / 2) // Center first item
            }
            .scrollTargetBehavior(.paging) // iOS 17+ snap paging
            .scrollIndicators(.hidden)
            .scrollPosition(id: $scrolledIndex)
            .onChange(of: scrolledIndex) { _, newIndex in
                let idx = newIndex ?? 0
                guard idx != currentIndex else { return }
                currentIndex = idx
                onActiveIndexChanged?(idx)
            }
            .frame(height: 240)

            // Page indicators
            if media.count > 1 {
                pageIndicators
            }

            // Per-media caption — shown below the carousel when the active slide has a caption
            if let caption = activePerMediaCaption {
                perMediaCaptionRow(caption)
            }
        }
        .opacity(carouselAppeared ? 1 : 0)
        .offset(y: carouselAppeared ? 0 : 20)
        .onAppear {
            withAnimation(Motion.adaptive(.spring(response: 0.6, dampingFraction: 0.8)).delay(0.1)) {
                carouselAppeared = true
            }
        }
    }
    
    private func mediaItemView(_ item: PostMediaItem, index: Int) -> some View {
        Group {
            switch item.type {
            case .image:
                GlassImageView(
                    url: item.url,
                    aspectRatio: item.computedAspectRatio,
                    cornerRadius: 20,
                    showGradient: false,
                    onTap: {
                        onMediaTap?(item)
                    }
                )
                
            case .video:
                GlassVideoPlayerView(
                    url: item.url,
                    thumbnailURL: item.thumbnailURL,
                    duration: item.duration,
                    cornerRadius: 20,
                    autoplay: false,
                    onTap: {
                        onMediaTap?(item)
                    },
                    postId: postId,
                    mediaItemId: item.id
                )
            }
        }
        .shadow(
            color: .black.opacity(currentIndex == index ? 0.12 : 0.06),
            radius: currentIndex == index ? 16 : 8,
            y: currentIndex == index ? 8 : 4
        )
        .scaleEffect(currentIndex == index ? 1.0 : 0.94)
        .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.8), value: currentIndex)
    }
    
    private var pageIndicators: some View {
        HStack(spacing: 6) {
            ForEach(0..<media.count, id: \.self) { index in
                Circle()
                    .fill(index == currentIndex ? Color.primary : Color.primary.opacity(0.25))
                    .frame(
                        width: index == currentIndex ? 7 : 5,
                        height: index == currentIndex ? 7 : 5
                    )
                    .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.7), value: currentIndex)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Per-Media Caption Row (feed rendering, System 24)

    /// Liquid Glass caption row shown below the carousel for the active slide's per-media caption.
    private func perMediaCaptionRow(_ caption: String) -> some View {
        Text(caption)
            .font(.subheadline)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(captionRowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
            .padding(.horizontal, 4)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.85), value: currentIndex)
            .accessibilityLabel("Caption: \(caption)")
            .accessibilityAddTraits(.isStaticText)
            .id("per-media-caption-\(currentIndex)")
    }

    @ViewBuilder
    private var captionRowBackground: some View {
        if reduceTransparency {
            Color(UIColor.secondarySystemBackground)
        } else {
            Rectangle().fill(.ultraThinMaterial)
        }
    }
}

// MARK: - Single Media Container View

/// Wrapper that intelligently displays single or multiple media
struct PostMediaContainerView: View {
    let media: PostMediaContainer
    var onMediaTap: ((PostMediaItem, Int) -> Void)? = nil

    /// Optional post ID for media resume tracking (System 12).
    var postId: String? = nil

    /// Called when the active carousel item changes (bubbles up from MediaCarouselView).
    var onActiveIndexChanged: ((Int) -> Void)? = nil

    @State private var showFullscreen = false
    @State private var fullscreenStartIndex = 0
    @ObservedObject private var flags = AMENFeatureFlags.shared

    var body: some View {
        Group {
            if media.isSingleItem, let firstItem = media.sortedItems.first {
                singleMediaView(firstItem)
            } else if media.hasMultipleItems {
                MediaCarouselView(
                    media: media,
                    onMediaTap: { tappedItem in
                        if let index = media.sortedItems.firstIndex(where: { $0.id == tappedItem.id }) {
                            fullscreenStartIndex = index
                            showFullscreen = true
                        }
                    },
                    postId: postId,
                    onActiveIndexChanged: onActiveIndexChanged
                )
            }
        }
        .fullScreenCover(isPresented: $showFullscreen) {
            if flags.liquidGlassMediaViewer {
                AMENImmersiveMediaViewer(
                    media: media,
                    startIndex: fullscreenStartIndex,
                    postId: postId
                )
            } else {
                FullscreenMediaViewer(
                    media: media,
                    startIndex: fullscreenStartIndex,
                    postId: postId
                )
            }
        }
    }
    
    private func singleMediaView(_ item: PostMediaItem) -> some View {
        Group {
            switch item.type {
            case .image:
                GlassImageView(
                    url: item.url,
                    aspectRatio: item.computedAspectRatio,
                    cornerRadius: 20,
                    showGradient: false
                ) {
                    fullscreenStartIndex = 0
                    showFullscreen = true
                }
                
            case .video:
                GlassVideoPlayerView(
                    url: item.url,
                    thumbnailURL: item.thumbnailURL,
                    duration: item.duration,
                    cornerRadius: 20,
                    autoplay: false,
                    onTap: {
                        fullscreenStartIndex = 0
                        showFullscreen = true
                    },
                    postId: postId,
                    mediaItemId: item.id
                )
            }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Private helpers (file-scoped, avoids cross-file dependency)

private extension String {
    /// Returns nil when the string is empty after whitespace-trimming.
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Collection {
    /// Safe index subscript — returns nil instead of crashing for out-of-range indices.
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Preview

#Preview("Single Image") {
    let singleImage = PostMediaContainer.singleImage("https://picsum.photos/800/600")
    return PostMediaContainerView(media: singleImage)
        .background(Color(.systemGroupedBackground))
}

#Preview("Multiple Images") {
    let multipleImages = PostMediaContainer.fromImageURLs([
        "https://picsum.photos/800/600?1",
        "https://picsum.photos/800/600?2",
        "https://picsum.photos/800/600?3"
    ])
    return PostMediaContainerView(media: multipleImages)
        .background(Color(.systemGroupedBackground))
}

#Preview("Video") {
    let video = PostMediaContainer.singleVideo(
        "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
        duration: 596
    )
    return PostMediaContainerView(media: video)
        .background(Color(.systemGroupedBackground))
}
