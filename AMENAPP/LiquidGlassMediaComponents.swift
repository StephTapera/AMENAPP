//
//  LiquidGlassMediaComponents.swift
//  AMENAPP
//
//  Premium Liquid Glass media components for social feed
//  Calm, refined, Apple-quality aesthetic
//

import SwiftUI
import AVKit

// MARK: - Liquid Glass Design Tokens

private extension Color {
    static let glassOverlay = Color.white.opacity(0.08)
    static let glassStroke = Color.white.opacity(0.25)
    static let glassGradientTop = Color.black.opacity(0.0)
    static let glassGradientBottom = Color.black.opacity(0.5)
    static let controlBackground = Color.black.opacity(0.3)
    static let controlStroke = Color.white.opacity(0.15)
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
    @Namespace private var imageNamespace
    
    var body: some View {
        CachedAsyncImage(url: URL(string: url)) { phase in
            switch phase {
            case .success(let image):
                imageContent(image)
                    .opacity(imageAppeared ? 1.0 : 0.0)
                    .scaleEffect(imageAppeared ? 1.0 : 0.96)
                    .onAppear {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            imageAppeared = true
                        }
                    }
                
            case .failure:
                failureContent
                
            case .empty:
                loadingContent
                
            @unknown default:
                loadingContent
            }
        }
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
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("Image unavailable")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
            )
            .frame(maxWidth: .infinity)
            .frame(height: heightForAspectRatio)
    }
    
    private var heightForAspectRatio: CGFloat {
        let screenWidth = UIScreen.main.bounds.width - 32 // Account for padding
        let ratio = aspectRatio ?? 4.0 / 3.0
        return screenWidth / ratio
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
        .onAppear {
            viewModel.setupPlayer(url: url)
            if autoplay {
                viewModel.play()
            }
        }
        .onDisappear {
            viewModel.pause()
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
                        .font(.system(size: 22, weight: .medium))
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
                    .font(.system(size: 14, weight: .medium))
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
                    .font(.custom("OpenSans-SemiBold", size: 11))
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
            self?.player?.seek(to: .zero)
            if self?.isPlaying == true {
                self?.player?.play()
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

struct ShimmerEffect: ViewModifier {
    @State private var isAnimating = false
    
    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [
                        .clear,
                        .white.opacity(0.15),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: isAnimating ? 400 : -400)
                .allowsHitTesting(false)
            )
            .onAppear {
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
