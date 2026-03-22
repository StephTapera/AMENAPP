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
    
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var dragDismissOffset: CGFloat = 0
    @State private var isDraggingToDismiss = false
    @State private var showChrome = true
    
    init(media: PostMediaContainer, startIndex: Int) {
        self.media = media
        self.startIndex = startIndex
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
    
    var body: some View {
        ZStack {
            // Dark glass background
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
        CachedAsyncImage(url: URL(string: item.url)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scaleEffect(isActive ? scale : 1.0)
                    .offset(isActive ? offset : .zero)
                    .gesture(isActive ? magnificationGesture : nil)
                    .gesture(isActive ? panGesture : nil)
                
            case .failure:
                errorPlaceholder
                
            case .empty:
                loadingPlaceholder
                
            @unknown default:
                loadingPlaceholder
            }
        }
    }
    
    private func fullscreenVideoView(_ item: PostMediaItem) -> some View {
        VideoPlayerFullscreen(
            url: item.url,
            thumbnailURL: item.thumbnailURL
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
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.white.opacity(0.7))
            Text("Media unavailable")
                .font(.custom("OpenSans-Regular", size: 15))
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
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Circle()
                            .fill(Color.black.opacity(0.3))
                    )
                    .frame(width: 40, height: 40)
                
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
    }
    
    private var counterBadge: some View {
        Text("\(currentIndex + 1) / \(media.count)")
            .font(.custom("OpenSans-SemiBold", size: 13))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .fill(Color.black.opacity(0.3))
                    )
            )
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
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
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
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
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
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
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
    
    @StateObject private var viewModel = VideoPlayerViewModel()
    
    var body: some View {
        VideoPlayer(player: viewModel.player)
            .ignoresSafeArea()
            .onAppear {
                viewModel.setupPlayer(url: url)
                viewModel.play()
            }
            .onDisappear {
                viewModel.pause()
            }
    }
}
