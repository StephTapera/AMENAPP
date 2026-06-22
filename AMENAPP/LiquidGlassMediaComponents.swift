//
//  LiquidGlassMediaComponents.swift
//  AMENAPP
//
//  Premium Liquid Glass media components for social feed
//  Calm, refined, Apple-quality aesthetic
//

import SwiftUI
import AVKit
import Combine

// MARK: - Liquid Glass Design Tokens

private extension Color {
    static let glassOverlay = Color.white.opacity(0.08)
    static let glassStroke = Color.white.opacity(0.25)
    static let glassGradientTop = Color.black.opacity(0.0)
    static let glassGradientBottom = Color.black.opacity(0.5)
    static let controlBackground = Color.black.opacity(0.3)
    static let controlStroke = Color.white.opacity(0.15)
}

private extension ShapeStyle where Self == Color {
    static var glassOverlay: Color { Color.white.opacity(0.08) }
    static var glassStroke: Color { Color.white.opacity(0.25)  }
    static var controlBackground: Color { Color.black.opacity(0.3) }
}

// MARK: - Glass Gradient Overlay

/// Subtle gradient overlay for text readability on media
struct GlassGradientOverlay: View {
    var alignment: Alignment = .bottom
    var height: CGFloat = 80
    
    var body: some View {
        LinearGradient(
            colors: alignment == .bottom
                ? [.glassGradientTop, .glassGradientBottom]
                : [.glassGradientBottom, .glassGradientTop],
            startPoint: alignment == .bottom ? .top : .bottom,
            endPoint: alignment == .bottom ? .bottom : .top
        )
        .frame(height: height)
        .allowsHitTesting(false)
    }
}

// MARK: - Glass Image View

struct GlassImageView: View {
    let url: String
    let aspectRatio: CGFloat?
    var cornerRadius: CGFloat = 20
    var showGradient: Bool = false
    var onTap: (() -> Void)? = nil
    
    @State private var imageAppeared = false
    @State private var containerWidth: CGFloat = 0
    @Namespace private var imageNamespace
    
    var body: some View {
        CachedAsyncImage(url: URL(string: url)) { image in
            imageContent(image)
                .opacity(imageAppeared ? 1.0 : 0.0)
                .scaleEffect(imageAppeared ? 1.0 : 0.96)
                .onAppear {
                    withAnimation(Motion.adaptive(.spring(response: 0.5, dampingFraction: 0.8))) {
                        imageAppeared = true
                    }
                }
        } placeholder: {
            loadingContent
        }
        // Capture the actual layout width instead of using UIScreen.main.bounds.
        // UIScreen.main.bounds does not account for safe-area insets on notched
        // or Dynamic Island devices, causing overflow on Plus/Max sizes in landscape.
        .background(
            GeometryReader { geo in
                Color.clear.onAppear { containerWidth = geo.size.width }
                           .onChange(of: geo.size.width) { _, w in containerWidth = w }
            }
        )
    }
    
    private func imageContent(_ image: Image) -> some View {
        ZStack(alignment: .bottom) {
            image
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: heightForAspectRatio)
                .clipped()
            
            // Subtle glass gradient for text readability
            if showGradient {
                GlassGradientOverlay(height: 60)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.glassStroke, lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onTapGesture {
            HapticManager.impact(style: .light)
            onTap?()
        }
    }
    
    private var loadingContent: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                ZStack {
                    Color.glassOverlay
                    ProgressView()
                        .tint(.primary.opacity(0.6))
                }
            )
            .frame(maxWidth: .infinity)
            .frame(height: heightForAspectRatio)
            .shimmerEffect()
    }
    
    private var failureContent: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(.systemGray6))
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.systemScaled(28, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("Image unavailable")
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                }
            )
            .frame(maxWidth: .infinity)
            .frame(height: heightForAspectRatio)
    }
    
    private var heightForAspectRatio: CGFloat {
        // Use the measured container width. Fall back to screen width on first layout
        // pass before GeometryReader fires (containerWidth == 0).
        let width = containerWidth > 0 ? containerWidth : ScreenMetrics.bounds.width - 32
        let ratio = aspectRatio ?? 4.0 / 3.0
        return width / ratio
    }
}

// MARK: - Glass Video Player View

struct GlassVideoPlayerView: View {
    let url: String
    let thumbnailURL: String?
    let duration: TimeInterval?
    var cornerRadius: CGFloat = 20
    var autoplay: Bool = false
    var onTap: (() -> Void)? = nil

    /// Optional IDs for media resume tracking (System 12).
    /// When provided, the video integrates with MediaSessionCoordinator.
    var postId: String? = nil
    var mediaItemId: String? = nil
    
    @StateObject private var viewModel = VideoPlayerViewModel()
    @State private var showControls = true
    @State private var videoAppeared = false
    
    var body: some View {
        ZStack {
            // Video player
            VideoPlayer(player: viewModel.player)
                .disabled(true) // Prevent default controls
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .frame(maxWidth: .infinity)
                .frame(height: 240)
            
            // Glass overlay controls
            if showControls || !viewModel.isPlaying {
                controlsOverlay
            }
            
            // Duration badge (top-right)
            if let formatted = formattedDuration {
                durationBadge(formatted)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.glassStroke, lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                showControls.toggle()
            }
            if let tap = onTap {
                HapticManager.impact(style: .light)
                tap()
            } else {
                viewModel.togglePlayPause()
            }
        }
        // Resume pill overlay (bottom-left)
        .overlay(alignment: .bottomLeading) {
            if let pId = postId, let mId = mediaItemId,
               let state = MediaSessionCoordinator.shared.resumeState(for: pId, mediaItemId: mId),
               state.isResumable, !viewModel.isPlaying {
                MediaResumePillView(state: state)
                    .padding(8)
                    .transition(.opacity)
            }
        }
        .onAppear {
            viewModel.setupPlayer(url: url)
            if let pId = postId, let mId = mediaItemId, let player = viewModel.player {
                MediaSessionCoordinator.shared.beginSession(
                    postId: pId, mediaItemId: mId,
                    surface: .feed, player: player
                )
            }
            if autoplay {
                viewModel.play()
            }
        }
        .onDisappear {
            viewModel.pause()
            if postId != nil {
                MediaSessionCoordinator.shared.endSession()
            }
        }
    }
    
    private var controlsOverlay: some View {
        ZStack {
            // Dim background
            Color.black.opacity(0.2)
            
            // Play/Pause button
            Button {
                viewModel.togglePlayPause()
                HapticManager.impact(style: .medium)
            } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Circle()
                                .fill(.glassOverlay)
                        )
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.systemScaled(22, weight: .medium))
                        .foregroundStyle(.white)
                        .offset(x: viewModel.isPlaying ? 0 : 2) // Optical centering for play icon
                }
            }
            .buttonStyle(.plain)
            
            // Mute toggle (bottom-right)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    muteButton
                        .padding(16)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .transition(.opacity)
    }
    
    private var muteButton: some View {
        Button {
            viewModel.toggleMute()
            HapticManager.impact(style: .light)
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Circle()
                            .fill(.controlBackground)
                    )
                    .frame(width: 36, height: 36)
                
                Image(systemName: viewModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.systemScaled(14, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
    }
    
    private func durationBadge(_ text: String) -> some View {
        VStack {
            HStack {
                Spacer()
                Text(text)
                    .font(AMENFont.semiBold(11))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Capsule()
                                    .fill(.controlBackground)
                            )
                    )
                    .padding(12)
            }
            Spacer()
        }
    }
    
    private var formattedDuration: String? {
        guard let dur = duration else { return nil }
        let minutes = Int(dur) / 60
        let seconds = Int(dur) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Video Player View Model

@MainActor
class VideoPlayerViewModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isPlaying = false
    @Published var isMuted = true // Default muted for autoplay
    
    func setupPlayer(url: String) {
        guard let videoURL = URL(string: url) else { return }
        player = AVPlayer(url: videoURL)
        player?.isMuted = isMuted
        
        // Loop video seamlessly
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.player?.seek(to: .zero)
                if self.isPlaying == true {
                    self.player?.play()
                }
            }
        }
    }
    
    func play() {
        player?.play()
        isPlaying = true
    }
    
    func pause() {
        player?.pause()
        isPlaying = false
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Shimmer Effect Modifier

struct LiquidGlassShimmerEffect: ViewModifier {
    @State private var isAnimating = false
    // MEDIUM FIX: Respect the system-wide Reduce Motion setting.
    // The infinite linear loop scrolls a white highlight across the view
    // continuously — this fails the WCAG 2.1 SC 2.3.3 (no essential animation)
    // criterion for users who have enabled Reduce Motion.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [
                        .clear,
                        .white.opacity(reduceMotion ? 0 : 0.15),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: isAnimating ? 400 : -400)
                .allowsHitTesting(false)
            )
            .onAppear {
                // Skip animation entirely when Reduce Motion is on; the overlay
                // is also made transparent above so no static artifact remains.
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}

extension View {
    func shimmerEffect() -> some View {
        modifier(ShimmerEffect())
    }
}
