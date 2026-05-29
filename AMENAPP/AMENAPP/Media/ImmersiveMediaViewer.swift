//
//  ImmersiveMediaViewer.swift
//  AMENAPP
//
//  Full-screen immersive photo/video viewer with:
//  - Vertical paging TabView (TikTok / Reels style)
//  - Pinch-to-zoom for photos (1x–4x clamped)
//  - Dismiss by dragging down > 100 pt
//  - Bottom overlay with author, caption, and action rail
//  - Matched geometry hero transition support
//

import SwiftUI

// MARK: - ImmersiveMediaViewer

struct ImmersiveMediaViewer: View {

    let items: [ImmersiveMediaItem]
    let startingIndex: Int
    let onDismiss: () -> Void

    @State private var currentIndex: Int
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false

    init(items: [ImmersiveMediaItem], startingIndex: Int = 0, onDismiss: @escaping () -> Void) {
        self.items = items
        self.startingIndex = startingIndex
        self.onDismiss = onDismiss
        _currentIndex = State(initialValue: startingIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    ImmersiveMediaPage(item: item)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            .offset(y: dragOffset)

            // Dismiss drag handle bar
            VStack {
                Capsule()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 36, height: 4)
                    .padding(.top, 12)
                Spacer()
            }
        }
        .statusBarHidden(true)
        .gesture(dismissDragGesture)
        .animation(.interactiveSpring(), value: dragOffset)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Media viewer")
    }

    // MARK: - Dismiss Drag Gesture

    private var dismissDragGesture: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .local)
            .onChanged { value in
                // Only allow downward drag
                if value.translation.height > 0 {
                    dragOffset = value.translation.height
                    isDragging = true
                }
            }
            .onEnded { value in
                isDragging = false
                if value.translation.height > 100 {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                        onDismiss()
                    }
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.80)) {
                        dragOffset = 0
                    }
                }
            }
    }
}

// MARK: - ImmersiveMediaPage

private struct ImmersiveMediaPage: View {

    let item: ImmersiveMediaItem

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var isVideoPlaying = true

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            // Media content
            mediaContent

            // Bottom gradient + overlay
            bottomOverlay
        }
        .ignoresSafeArea()
        .clipped()
    }

    // MARK: Media Content

    @ViewBuilder
    private var mediaContent: some View {
        switch item.type {
        case .photo:
            photoView
        case .video:
            videoView
        }
    }

    private var photoView: some View {
        AsyncImage(url: item.url) { phase in
            switch phase {
            case .empty:
                Color.black
                    .overlay(
                        ProgressView().tint(.white)
                    )
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(scale)
                    .gesture(pinchGesture)
                    .gesture(doubleTapGesture)
                    .animation(.spring(response: 0.30, dampingFraction: 0.75), value: scale)
                    .accessibilityLabel(item.caption ?? "Photo by \(item.authorName)")
            case .failure:
                Color.black
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 48))
                            .foregroundColor(.white.opacity(0.4))
                    )
            @unknown default:
                Color.black
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var videoView: some View {
        ImmersiveVideoPlayerView(url: item.url, isPlaying: $isVideoPlaying)
            .accessibilityLabel(item.caption ?? "Video by \(item.authorName)")
    }

    // MARK: Pinch to Zoom (photos only, 1x–4x)

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let proposed = lastScale * value
                scale = min(max(proposed, 1.0), 4.0)
            }
            .onEnded { _ in
                lastScale = scale
                if scale < 1.0 { scale = 1.0; lastScale = 1.0 }
            }
    }

    private var doubleTapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.75)) {
                    if scale > 1.5 {
                        scale = 1.0
                        lastScale = 1.0
                    } else {
                        scale = 2.0
                        lastScale = 2.0
                    }
                }
            }
    }

    // MARK: Bottom Overlay

    private var bottomOverlay: some View {
        LinearGradient(
            colors: [.clear, .black.opacity(0.60)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 220)
        .overlay(alignment: .bottom) {
            HStack(alignment: .bottom, spacing: 12) {
                authorCaptionStack
                Spacer()
                actionRail
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
    }

    private var authorCaptionStack: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.authorName)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .accessibilityLabel("Author: \(item.authorName)")

            if let caption = item.caption, !caption.isEmpty {
                Text(caption)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.90))
                    .lineLimit(3)
                    .accessibilityLabel("Caption: \(caption)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionRail: some View {
        VStack(spacing: 20) {
            ImmersiveActionButton(
                icon: "hands.clap.fill",
                label: "Amen",
                tint: AmenTheme.Colors.amenGold
            )
            ImmersiveActionButton(
                icon: "bubble.left",
                label: "Comment",
                tint: .white
            )
            ImmersiveActionButton(
                icon: "paperplane",
                label: "Share",
                tint: .white
            )
        }
    }
}

// MARK: - ImmersiveActionButton

private struct ImmersiveActionButton: View {
    let icon: String
    let label: String
    let tint: Color
    var count: Int = 0
    var isActive: Bool = false

    var body: some View {
        Button {
            // Action handled by parent via coordinator — placeholder
        } label: {
            VStack(spacing: 4) {
                Image(systemName: isActive ? icon : icon)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundColor(isActive ? tint : tint)
                    .frame(width: 44, height: 44)

                if count > 0 {
                    Text(compactCount)
                        .font(.caption2)
                        .foregroundColor(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(count > 0 ? "\(count)" : "")
    }

    private var compactCount: String {
        if count >= 1_000_000 { return "\(count / 1_000_000)M" }
        if count >= 1_000 { return "\(count / 1_000)K" }
        return "\(count)"
    }
}

// MARK: - ImmersiveMediaNamespace (View Modifier)

/// Applies a matchedGeometryEffect to an item for hero transitions from the feed.
struct ImmersiveMediaNamespaceModifier: ViewModifier {
    let id: String
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        content
            .matchedGeometryEffect(id: id, in: namespace)
    }
}

extension View {
    /// Attach a matched geometry hero effect keyed on an ImmersiveMediaItem ID.
    func immersiveMediaHero(id: String, in namespace: Namespace.ID) -> some View {
        modifier(ImmersiveMediaNamespaceModifier(id: id, namespace: namespace))
    }
}
