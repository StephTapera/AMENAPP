//
//  PostImagesView.swift
//  AMENAPP
//
//  Displays one or more images attached to a post.
//  Tap any image → full-screen pager viewer (Threads-style).
//

import SwiftUI

// MARK: - Post Images View (inline feed)

struct PostImagesView: View {
    let imageURLs: [String]

    @State private var viewerVisible = false
    @State private var viewerStartIndex = 0

    var body: some View {
        Group {
            if imageURLs.count == 1 {
                singleImage(imageURLs[0], index: 0)
            } else if imageURLs.count > 1 {
                scrollingImages
            }
        }
        .fullScreenCover(isPresented: $viewerVisible) {
            FullScreenPostImageView(
                imageURLs: imageURLs,
                startIndex: viewerStartIndex
            )
        }
    }

    // MARK: Single image

    private func singleImage(_ urlString: String, index: Int) -> some View {
        CachedAsyncImage(url: URL(string: urlString)) { image in
            image
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .contentShape(RoundedRectangle(cornerRadius: 12))
                .onTapGesture {
                    guard !imageURLs.isEmpty else { return }
                    viewerStartIndex = index
                    viewerVisible = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
        } placeholder: {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .overlay(ProgressView())
        }
    }

    // MARK: Multi-image horizontal scroll

    private var scrollingImages: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(imageURLs.enumerated()), id: \.offset) { index, urlString in
                    CachedAsyncImage(url: URL(string: urlString)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 200, height: 160)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                            .onTapGesture {
                                viewerStartIndex = index
                                viewerVisible = true
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.systemGray6))
                            .frame(width: 200, height: 160)
                            .overlay(ProgressView())
                    }
                }
            }
        }
    }
}

// MARK: - Full Screen Post Image Viewer

struct FullScreenPostImageView: View {
    let imageURLs: [String]
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

    init(imageURLs: [String], startIndex: Int) {
        self.imageURLs = imageURLs
        self.startIndex = startIndex
        _currentIndex = State(initialValue: startIndex)
    }

    private var dismissOpacity: Double {
        let progress = abs(dragDismissOffset) / 220.0
        return Double(max(0, 1.0 - progress))
    }

    var body: some View {
        ZStack {
            // Background dims as user drags to dismiss
            Color.black
                .opacity(dismissOpacity)
                .ignoresSafeArea()

            // Pager — TabView for swipe between images
            TabView(selection: $currentIndex) {
                ForEach(Array(imageURLs.enumerated()), id: \.offset) { index, urlString in
                    ZoomableImageCell(urlString: urlString,
                                     scale: index == currentIndex ? $scale : .constant(1.0),
                                     lastScale: index == currentIndex ? $lastScale : .constant(1.0),
                                     offset: index == currentIndex ? $offset : .constant(.zero),
                                     lastOffset: index == currentIndex ? $lastOffset : .constant(.zero))
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onChange(of: currentIndex) {
                // Reset zoom when switching pages
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    scale = 1.0
                    lastScale = 1.0
                    offset = .zero
                    lastOffset = .zero
                }
            }
            .offset(y: dragDismissOffset)
            .gesture(
                // Drag-down-to-dismiss (only when not zoomed)
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
            )

            // Chrome overlay (close + counter)
            if showChrome {
                VStack {
                    HStack {
                        // Close button
                        Button { dismiss() } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.55))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "xmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 20)
                        .padding(.top, 56)

                        Spacer()

                        // Image counter (only when multiple)
                        if imageURLs.count > 1 {
                            Text("\(currentIndex + 1) / \(imageURLs.count)")
                                .font(.custom("OpenSans-SemiBold", size: 13))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.55))
                                )
                                .padding(.trailing, 20)
                                .padding(.top, 56)
                        }
                    }
                    Spacer()

                    // Dot indicators (multiple images)
                    if imageURLs.count > 1 {
                        HStack(spacing: 6) {
                            ForEach(0..<imageURLs.count, id: \.self) { i in
                                Circle()
                                    .fill(i == currentIndex ? Color.white : Color.white.opacity(0.35))
                                    .frame(width: i == currentIndex ? 7 : 5,
                                           height: i == currentIndex ? 7 : 5)
                                    .animation(.spring(response: 0.25), value: currentIndex)
                            }
                        }
                        .padding(.bottom, 44)
                    }
                }
                .opacity(dismissOpacity)
            }
        }
        .statusBarHidden()
        .onTapGesture {
            // Single tap toggles chrome
            withAnimation(.easeInOut(duration: 0.18)) {
                showChrome.toggle()
            }
        }
        .onTapGesture(count: 2) {
            // Double tap: zoom in or reset
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                if scale > 1.05 {
                    scale = 1.0; lastScale = 1.0
                    offset = .zero; lastOffset = .zero
                } else {
                    scale = 2.5
                }
            }
        }
    }
}

// MARK: - Zoomable Image Cell

private struct ZoomableImageCell: View {
    let urlString: String
    @Binding var scale: CGFloat
    @Binding var lastScale: CGFloat
    @Binding var offset: CGSize
    @Binding var lastOffset: CGSize

    var body: some View {
        CachedAsyncImage(url: URL(string: urlString)) { image in
            image
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(magnificationGesture)
                .gesture(panGesture)
        } placeholder: {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

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
                if scale < 1.0 {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        scale = 1.0; offset = .zero; lastOffset = .zero
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
}
