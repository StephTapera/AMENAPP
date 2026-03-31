// SmartMediaCarouselView.swift
// AMEN App — Liquid Glass media carousel for post cards.
// Supports mixed photo + video. Morphing dot indicators. Smart press detection.
// iOS-only. Use GeometryReader for sizing — never UIScreen.

import SwiftUI

// MARK: - Models

struct CarouselMediaItem: Identifiable {
    let id: String
    let type: CarouselMediaType
    let thumbnailURL: String?
    let videoURL: String?
    let trustLabel: String?      // e.g. "Verified original" — nil if none
    let contextTag: String?      // e.g. "Church event", "Sermon clip"
}

enum CarouselMediaType {
    case photo, video
}

// MARK: - SmartMediaCarouselView

struct SmartMediaCarouselView: View {
    let items: [CarouselMediaItem]
    let onMediaPress: (CarouselMediaItem) -> Void

    @State private var currentIndex: Int = 0
    @GestureState private var dragOffset: CGFloat = 0
    @State private var videoProgress: CGFloat = 0.0
    @State private var isPlayingVideo: Bool = false
    @State private var showSmartActionsMenu: Bool = false

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = width * 0.72

            VStack(spacing: 10) {
                // ── Media Stage ──────────────────────────────────────────────
                ZStack(alignment: .bottom) {
                    // 1. Media background layer
                    mediaBackgroundLayer(width: width, height: height)

                    // 2. Play button for video items
                    if items[currentIndex].type == .video {
                        glassPlayButton
                    }

                    // 3. Video progress bar (video only)
                    if items[currentIndex].type == .video {
                        videoProgressBar(width: width)
                            .padding(.bottom, 52)
                            .padding(.horizontal, 12)
                    }

                    // 4. Top-left context tag pill
                    if let tag = items[currentIndex].contextTag {
                        contextTagPill(tag)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(.top, 12)
                            .padding(.leading, 12)
                    }

                    // 5. Top-right trust label pill
                    if let trust = items[currentIndex].trustLabel {
                        trustLabelPill(trust)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(.top, 12)
                            .padding(.trailing, 12)
                    }

                    // 6. Bottom controls bar
                    bottomControlsBar(width: width)
                }
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 6)
                .onLongPressGesture(minimumDuration: 0.4) {
                    onMediaPress(items[currentIndex])
                }
                .contextMenu {
                    Button {
                        onMediaPress(items[currentIndex])
                    } label: {
                        Label("Smart Actions", systemImage: "sparkles")
                    }
                    Button {
                        // Save action stub
                    } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        // Share action stub
                    } label: {
                        Label("Share Safely", systemImage: "square.and.arrow.up")
                    }
                }

                // ── Morphing dot indicators ───────────────────────────────────
                if items.count > 1 {
                    morphingDots
                }
            }
        }
    }

    // MARK: - Media Background Layer

    @ViewBuilder
    private func mediaBackgroundLayer(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            // Placeholder gradient — distinct per media type
            let gradient: LinearGradient = {
                switch items[currentIndex].type {
                case .photo:
                    return LinearGradient(
                        colors: [Color(white: 0.92), Color(white: 0.80)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                case .video:
                    return LinearGradient(
                        colors: [Color(white: 0.14), Color(white: 0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }()

            Rectangle()
                .fill(gradient)
                .frame(width: width, height: height)

            // Media type icon watermark
            Image(systemName: items[currentIndex].type == .video ? "film" : "photo")
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundStyle(
                    items[currentIndex].type == .video
                        ? Color.white.opacity(0.12)
                        : Color.black.opacity(0.10)
                )
        }
        .frame(width: width, height: height)
        .gesture(
            DragGesture()
                .updating($dragOffset) { value, state, _ in
                    state = value.translation.width
                }
                .onEnded { value in
                    let threshold = width * 0.3
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                        if value.translation.width < -threshold && currentIndex < items.count - 1 {
                            currentIndex += 1
                        } else if value.translation.width > threshold && currentIndex > 0 {
                            currentIndex -= 1
                        }
                    }
                    // Reset video state on index change
                    isPlayingVideo = false
                    videoProgress = 0.0
                }
        )
        .offset(x: CGFloat(-currentIndex) * width + dragOffset * 0.88)
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: currentIndex)
    }

    // MARK: - Glass Play Button

    private var glassPlayButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                isPlayingVideo.toggle()
            }
            if isPlayingVideo {
                startVideoProgressAnimation()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().fill(Color.white.opacity(0.55)))
                    .overlay(Circle().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
                    .frame(width: 60, height: 60)

                Image(systemName: isPlayingVideo ? "pause.fill" : "play.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.75))
                    .offset(x: isPlayingVideo ? 0 : 2)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Video Progress Bar

    @ViewBuilder
    private func videoProgressBar(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            // Track
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Color.white.opacity(0.55)))
                .frame(height: 7)

            // Progress fill
            Capsule()
                .fill(Color.black.opacity(0.55))
                .frame(width: max(8, (width - 24) * videoProgress), height: 7)
                .animation(.linear(duration: 0.1), value: videoProgress)
        }
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
    }

    // MARK: - Context Tag Pill

    private func contextTagPill(_ tag: String) -> some View {
        Text(tag)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.black.opacity(0.75))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(Color.white.opacity(0.55)))
                    .overlay(Capsule().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
            )
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    // MARK: - Trust Label Pill

    private func trustLabelPill(_ label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.black.opacity(0.6))
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.black.opacity(0.75))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Color.white.opacity(0.55)))
                .overlay(Capsule().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
        )
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    // MARK: - Bottom Controls Bar

    @ViewBuilder
    private func bottomControlsBar(width: CGFloat) -> some View {
        HStack(spacing: 10) {
            // Prev arrow
            arrowButton(systemName: "chevron.left", enabled: currentIndex > 0) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    if currentIndex > 0 {
                        currentIndex -= 1
                        isPlayingVideo = false
                        videoProgress = 0.0
                    }
                }
            }

            Spacer()

            // Smart Actions capsule
            Button {
                onMediaPress(items[currentIndex])
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Smart Actions")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.black.opacity(0.80))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(Capsule().fill(Color.white.opacity(0.55)))
                        .overlay(Capsule().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                )
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
            }
            .buttonStyle(.plain)

            Spacer()

            // Next arrow
            arrowButton(systemName: "chevron.right", enabled: currentIndex < items.count - 1) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    if currentIndex < items.count - 1 {
                        currentIndex += 1
                        isPlayingVideo = false
                        videoProgress = 0.0
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                )
        )
        .shadow(color: .black.opacity(0.07), radius: 12, x: 0, y: 4)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    // MARK: - Arrow Button

    private func arrowButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().fill(Color.white.opacity(0.55)))
                    .overlay(Circle().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
                    .frame(width: 38, height: 38)

                Image(systemName: systemName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.black.opacity(enabled ? 0.70 : 0.20))
            }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Morphing Dots

    private var morphingDots: some View {
        HStack(spacing: 5) {
            ForEach(0 ..< items.count, id: \.self) { index in
                if index == currentIndex {
                    Capsule()
                        .fill(Color.black.opacity(0.5))
                        .frame(width: 22, height: 7)
                        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: currentIndex)
                } else {
                    Circle()
                        .fill(Color.black.opacity(0.15))
                        .frame(width: 7, height: 7)
                        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: currentIndex)
                }
            }
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: currentIndex)
    }

    // MARK: - Helpers

    private func startVideoProgressAnimation() {
        videoProgress = 0.0
        withAnimation(.linear(duration: 8.0)) {
            videoProgress = 1.0
        }
    }
}

// MARK: - Preview

#if DEBUG
struct SmartMediaCarouselView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleItems: [CarouselMediaItem] = [
            CarouselMediaItem(
                id: "1",
                type: .photo,
                thumbnailURL: nil,
                videoURL: nil,
                trustLabel: "Verified original",
                contextTag: "Church event"
            ),
            CarouselMediaItem(
                id: "2",
                type: .photo,
                thumbnailURL: nil,
                videoURL: nil,
                trustLabel: nil,
                contextTag: "Sunday service"
            ),
            CarouselMediaItem(
                id: "3",
                type: .video,
                thumbnailURL: nil,
                videoURL: nil,
                trustLabel: "Verified original",
                contextTag: "Sermon clip"
            )
        ]

        SmartMediaCarouselView(items: sampleItems) { item in
            print("Media pressed: \(item.id)")
        }
        .padding()
        .background(Color(white: 0.96))
        .previewDisplayName("Smart Media Carousel")
    }
}
#endif
