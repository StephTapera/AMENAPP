//
//  FullscreenMediaViewer.swift
//  AMENAPP
//
//  Immersive fullscreen media viewer with pinch zoom and swipe dismiss
//  Premium Apple-quality transitions and interactions
//

import SwiftUI
import AVKit

// MARK: - Fullscreen Media Viewer

struct FullscreenMediaViewer: View {
    let media: PostMediaContainer
    let startIndex: Int

    /// Optional post ID for media resume tracking (System 12).
    var postId: String? = nil
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var currentIndex: Int
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var dragDismissOffset: CGFloat = 0
    @State private var isDraggingToDismiss = false
    @State private var showChrome = true

    /// Decoded UIImage of the current item, used to drive the Adaptive Ambient palette.
    /// Fails closed to neutral when nil (AdaptiveColorsMode.off renders byte-identical neutral).
    @State private var ambientImage: UIImage? = nil
    
    init(media: PostMediaContainer, startIndex: Int, postId: String? = nil) {
        self.media = media
        self.startIndex = startIndex
        self.postId = postId
        _currentIndex = State(initialValue: startIndex)
    }
    
    private var dismissOpacity: Double {
        let progress = abs(dragDismissOffset) / 220.0
        return Double(max(0, 1.0 - progress))
    }
    
    private var currentItem: PostMediaItem? {
        media.sortedItems.indices.contains(currentIndex) 
            ? media.sortedItems[currentIndex]
            : nil
    }
    
    // TODO(ambient): Fuller integration — replace this hand-wired pager with
    // AdaptiveMediaViewer(items:coordinator:) by mapping media.sortedItems to
    // [AdaptiveMediaViewer.Item] (id, revision: url, image: poster, player/asset for video).
    // Deferred to keep this change additive/reversible under concurrent edits; current wiring
    // already drives the palette + glass chrome from the active item's decoded poster image.
    // TODO(ambient): Tint the AVPlayer controls + scrubber with palette.accent. The player
    // lives in the private VideoPlayerFullscreen struct, which has no palette access; rewiring
    // it (e.g. passing palette.accent in or reading @Environment(\.ambientPalette) there) is the
    // clean spot, but was left out to avoid touching the media-session lifecycle code.
    var body: some View {
        // Ambient scope: the current media item's color drives a soft palette behind the
        // black viewer. Additive + reversible; fails closed to neutral when mode == .off or
        // when the decoded UIImage is unavailable.
        AmbientScope { coordinator in
            ZStack {
                // Adaptive ambient wash (behind the dark glass). Bleeds the current media's
                // blurred color; flat neutral when intensity == 0 / Reduce Transparency.
                AdaptiveAmbientBackground(bleedImage: ambientImage, bleedHeight: 560)
                    .opacity(dismissOpacity)

                // Dark glass background (preserves dismiss fade + immersive viewing)
                backgroundView

                // Media pager
                TabView(selection: $currentIndex) {
                    ForEach(Array(media.sortedItems.enumerated()), id: \.element.id) { index, item in
                        mediaView(for: item, at: index)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .onChange(of: currentIndex) {
                    resetZoom()
                    driveAmbient(coordinator: coordinator)
                }
                .offset(y: dragDismissOffset)
                .gesture(dismissGesture)

                // Chrome overlay
                if showChrome {
                    chromeOverlay
                }
            }
            .statusBarHidden()
            .onTapGesture {
                toggleChrome()
            }
            .onTapGesture(count: 2) {
                handleDoubleTap()
            }
            .onAppear { driveAmbient(coordinator: coordinator) }
            .onDisappear { coordinator.reset(scheme: scheme, reduceMotion: reduceMotion) }
        }
    }

    /// Decode the current item's image (reusing the shared ImageCache) and feed it to the
    /// ambient coordinator. For video items the poster/thumbnail drives the palette.
    private func driveAmbient(coordinator: AmbientCoordinator) {
        guard let item = currentItem else {
            ambientImage = nil
            coordinator.drive(with: nil,
                              key: AmbientSourceKey(id: "fullscreen/empty", revision: "0"),
                              scheme: scheme, reduceMotion: reduceMotion)
            return
        }
        let key = AmbientSourceKey(id: "fullscreen/\(item.id)", revision: item.url)
        // Prefer the still URL for images; the thumbnail for videos.
        let driveURL = item.type == .video ? (item.thumbnailURL ?? item.url) : item.url
        Task {
            let img = await ImageCache.shared.loadImage(url: driveURL,
                                                        size: CGSize(width: 600, height: 600))
            await MainActor.run {
                ambientImage = img
                coordinator.drive(with: img, key: key,
                                  scheme: scheme, reduceMotion: reduceMotion)
            }
        }
    }
    
    // MARK: - Background
    
    private var backgroundView: some View {
        ZStack {
            Color.black
                .opacity(dismissOpacity)
                .ignoresSafeArea()
            
            // Subtle blur layer
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(dismissOpacity * 0.2)
                .ignoresSafeArea()
        }
    }
    
    // MARK: - Media Views
    
    private func mediaView(for item: PostMediaItem, at index: Int) -> some View {
        Group {
            switch item.type {
            case .image:
                zoomableImageView(item, isActive: index == currentIndex)
                
            case .video:
                fullscreenVideoView(item)
            }
        }
    }
    
    private func zoomableImageView(_ item: PostMediaItem, isActive: Bool) -> some View {
        CachedAsyncImage(url: URL(string: item.url)) { image in
            image
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(isActive ? scale : 1.0)
                .offset(isActive ? offset : .zero)
                .gesture(isActive ? magnificationGesture : nil)
                .gesture(isActive ? panGesture : nil)
        } placeholder: {
            loadingPlaceholder
        }
    }
    
    private func fullscreenVideoView(_ item: PostMediaItem) -> some View {
        VideoPlayerFullscreen(
            url: item.url,
            thumbnailURL: item.thumbnailURL,
            postId: postId,
            mediaItemId: item.id
        )
    }
    
    private var loadingPlaceholder: some View {
        ProgressView()
            .scaleEffect(1.5)
            .tint(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var errorPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.systemScaled(48, weight: .light))
                .foregroundStyle(.white.opacity(0.7))
            Text("Media unavailable")
                .font(AMENFont.regular(15))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Chrome Overlay
    
    private var chromeOverlay: some View {
        VStack {
            topBar
            Spacer()
            if media.count > 1 {
                bottomIndicators
            }
        }
        .opacity(dismissOpacity)
    }
    
    private var topBar: some View {
        HStack {
            closeButton
            Spacer()
            if media.count > 1 {
                counterBadge
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 56)
    }
    
    private var closeButton: some View {
        Button {
            HapticManager.impact(style: .light)
            dismiss()
        } label: {
            // Float the control in the sanctioned ambient glass primitive (tints to content).
            AdaptiveGlassContainer(shape: Circle(), tintAlpha: 0.22) {
                Image(systemName: "xmark")
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
            }
        }
        .buttonStyle(.plain)
    }

    private var counterBadge: some View {
        AdaptiveGlassContainer(tintAlpha: 0.22) {
            Text("\(currentIndex + 1) / \(media.count)")
                .font(AMENFont.semiBold(13))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
    }
    
    private var bottomIndicators: some View {
        HStack(spacing: 6) {
            ForEach(0..<media.count, id: \.self) { index in
                Circle()
                    .fill(index == currentIndex ? Color.white : Color.white.opacity(0.35))
                    .frame(
                        width: index == currentIndex ? 7 : 5,
                        height: index == currentIndex ? 7 : 5
                    )
                    .animation(.spring(response: 0.3), value: currentIndex)
            }
        }
        .padding(.bottom, 44)
    }
    
    // MARK: - Gestures
    
    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / lastScale
                lastScale = value
                let newScale = scale * delta
                scale = min(max(newScale, 1.0), 5.0)
            }
            .onEnded { _ in
                lastScale = 1.0
                if scale < 1.05 {
                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75))) {
                        resetZoom()
                    }
                }
            }
    }
    
    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1.01 else { return }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }
    
    private var dismissGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale <= 1.01 else { return }
                let verticalDominant = abs(value.translation.height) > abs(value.translation.width)
                if verticalDominant && value.translation.height > 0 {
                    isDraggingToDismiss = true
                    dragDismissOffset = value.translation.height
                }
            }
            .onEnded { value in
                guard isDraggingToDismiss else { return }
                isDraggingToDismiss = false
                if dragDismissOffset > 100 || value.velocity.height > 600 {
                    dismiss()
                } else {
                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75))) {
                        dragDismissOffset = 0
                    }
                }
            }
    }
    
    // MARK: - Actions
    
    private func toggleChrome() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showChrome.toggle()
        }
    }
    
    private func handleDoubleTap() {
        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
            if scale > 1.05 {
                resetZoom()
            } else {
                scale = 2.5
            }
        }
        HapticManager.impact(style: .medium)
    }
    
    private func resetZoom() {
        scale = 1.0
        lastScale = 1.0
        offset = .zero
        lastOffset = .zero
    }
}

// MARK: - Fullscreen Video Player

private struct VideoPlayerFullscreen: View {
    let url: String
    let thumbnailURL: String?
    var postId: String? = nil
    var mediaItemId: String? = nil
    
    @State private var player: AVPlayer?
    
    var body: some View {
        VideoPlayer(player: player)
            .ignoresSafeArea()
            .onAppear {
                setupPlayer()
            }
            .onDisappear {
                player?.pause()
                if postId != nil {
                    MediaSessionCoordinator.shared.endSession()
                }
            }
    }
    
    private func setupPlayer() {
        guard let videoURL = URL(string: url) else { return }
        player = AVPlayer(url: videoURL)

        // Integrate with media session coordinator for resume tracking
        if let pId = postId, let mId = mediaItemId, let p = player {
            MediaSessionCoordinator.shared.beginSession(
                postId: pId, mediaItemId: mId,
                surface: .fullscreen, player: p
            )
        }

        player?.play()
    }
}
