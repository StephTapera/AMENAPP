//
//  ImmersiveVideoPlayer.swift
//  AMENAPP
//
//  AVPlayer wrapper for full-screen video playback.
//  - Autoplay on appear, loops, muted by default (ambient audio session)
//  - Tap to toggle play/pause with a fading overlay icon
//

import SwiftUI
import AVKit
import AVFoundation

// MARK: - ImmersiveVideoPlayer (UIViewControllerRepresentable)

struct ImmersiveVideoPlayer: UIViewControllerRepresentable {

    let url: URL
    @Binding var isPlaying: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isPlaying: $isPlaying)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        // Configure audio session to respect silent/ringer switch
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)

        let player = AVPlayer(url: url)
        player.isMuted = true
        player.actionAtItemEnd = .none

        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill

        context.coordinator.player = player
        context.coordinator.attachLoopObserver(to: player)

        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        guard let player = context.coordinator.player else { return }
        if isPlaying {
            player.play()
        } else {
            player.pause()
        }
    }

    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.teardown()
    }

    // MARK: Coordinator

    final class Coordinator: NSObject {
        @Binding var isPlaying: Bool
        var player: AVPlayer?
        private var loopObserver: NSObjectProtocol?

        init(isPlaying: Binding<Bool>) {
            _isPlaying = isPlaying
        }

        func attachLoopObserver(to player: AVPlayer) {
            loopObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { [weak player] _ in
                player?.seek(to: .zero)
                player?.play()
            }
            // Auto-start
            player.play()
            isPlaying = true
        }

        func teardown() {
            player?.pause()
            if let obs = loopObserver {
                NotificationCenter.default.removeObserver(obs)
                loopObserver = nil
            }
            player = nil
        }
    }
}

// MARK: - ImmersiveVideoPlayerView

/// SwiftUI wrapper that adds a tap-to-toggle play/pause overlay.
struct ImmersiveVideoPlayerView: View {

    let url: URL
    @Binding var isPlaying: Bool

    @State private var showControl: Bool = false
    @State private var controlTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            ImmersiveVideoPlayer(url: url, isPlaying: $isPlaying)
                .ignoresSafeArea()

            // Tap gesture overlay
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    isPlaying.toggle()
                    flashControl()
                }
                .accessibilityLabel(isPlaying ? "Pause video" : "Play video")
                .accessibilityAddTraits(.isButton)

            // Play / pause icon badge
            if showControl {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
                    .transition(.opacity.combined(with: .scale(scale: 0.80)))
                    .allowsHitTesting(false)
            }
        }
        .onDisappear {
            isPlaying = false
        }
    }

    private func flashControl() {
        controlTask?.cancel()
        withAnimation(.easeIn(duration: 0.15)) {
            showControl = true
        }
        controlTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) {
                    showControl = false
                }
            }
        }
    }
}
