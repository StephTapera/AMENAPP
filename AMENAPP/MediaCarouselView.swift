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
    
    @State private var currentIndex = 0
    @State private var carouselAppeared = false
    @GestureState private var dragOffset: CGFloat = 0
    
    private let itemWidth: CGFloat = UIScreen.main.bounds.width - 64 // Padding + peek
    private let itemSpacing: CGFloat = 12
    private let peekAmount: CGFloat = 32
    
    var body: some View {
        VStack(spacing: 12) {
            // Carousel scroll
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: itemSpacing) {
                    ForEach(Array(media.sortedItems.enumerated()), id: \.element.id) { index, item in
                        mediaItemView(item, index: index)
                            .frame(width: itemWidth)
                    }
                }
                .padding(.horizontal, (UIScreen.main.bounds.width - itemWidth) / 2) // Center first item
            }
            .scrollTargetBehavior(.paging) // iOS 17+ snap paging
            .scrollIndicators(.hidden)
            .frame(height: 240)
            
            // Page indicators
            if media.count > 1 {
                pageIndicators
            }
        }
        .opacity(carouselAppeared ? 1 : 0)
        .offset(y: carouselAppeared ? 0 : 20)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) {
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
                    }
                )
            }
        }
        .shadow(
            color: .black.opacity(currentIndex == index ? 0.12 : 0.06),
            radius: currentIndex == index ? 16 : 8,
            y: currentIndex == index ? 8 : 4
        )
        .scaleEffect(currentIndex == index ? 1.0 : 0.94)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: currentIndex)
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
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentIndex)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Single Media Container View

/// Wrapper that intelligently displays single or multiple media
struct PostMediaContainerView: View {
    let media: PostMediaContainer
    var onMediaTap: ((PostMediaItem, Int) -> Void)? = nil
    
    @State private var showFullscreen = false
    @State private var fullscreenStartIndex = 0
    
    var body: some View {
        Group {
            if media.isSingleItem, let firstItem = media.sortedItems.first {
                singleMediaView(firstItem)
            } else if media.hasMultipleItems {
                MediaCarouselView(media: media) { tappedItem in
                    if let index = media.sortedItems.firstIndex(where: { $0.id == tappedItem.id }) {
                        fullscreenStartIndex = index
                        showFullscreen = true
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showFullscreen) {
            FullscreenMediaViewer(
                media: media,
                startIndex: fullscreenStartIndex
            )
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
                    autoplay: false
                ) {
                    fullscreenStartIndex = 0
                    showFullscreen = true
                }
            }
        }
        .padding(.horizontal, 16)
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
