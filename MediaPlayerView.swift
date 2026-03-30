// MediaPlayerView.swift — Full-screen media player for Christian Media

import SwiftUI
import AVKit
import WebKit

// MARK: - YouTube Player (WKWebView wrapper)
struct YouTubePlayerView: UIViewRepresentable {
    let url: URL?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.backgroundColor = .black
        webView.isOpaque = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard let url = url else { return }
        let request = URLRequest(url: url)
        webView.load(request)
    }
}

// MARK: - AVPlayer Custom Wrapper
struct AVPlayerControllerWrapper: View {
    let item: MediaItem
    @ObservedObject var vm: ChristianMediaViewModel

    @State private var player: AVPlayer?
    @State private var currentTime: Double = 0
    @State private var totalDuration: Double = 1
    @State private var timeObserverToken: Any?
    @State private var isDragging = false

    private let accentPurple = Color(red: 0.49, green: 0.23, blue: 0.93)
    private let speedOptions: [(label: String, value: Float)] = [
        ("0.75×", 0.75), ("1×", 1.0), ("1.25×", 1.25), ("1.5×", 1.5), ("2×", 2.0)
    ]

    var body: some View {
        VStack(spacing: 20) {
            // Album art / thumbnail placeholder
            AsyncImage(url: URL(string: item.thumbnailURL)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Color(hex: item.dominantColor)
                        .overlay(
                            Image(systemName: "headphones")
                                .font(.system(size: 48))
                                .foregroundStyle(.white.opacity(0.5))
                        )
                }
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal)

            // Time labels
            HStack {
                Text(formatTime(currentTime))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatTime(totalDuration))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            // Seek slider
            Slider(value: Binding(
                get: { isDragging ? currentTime : currentTime },
                set: { newValue in
                    currentTime = newValue
                    let seekTime = CMTime(seconds: newValue, preferredTimescale: 600)
                    player?.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
                    vm.updateProgress(newValue / max(totalDuration, 1))
                }
            ), in: 0...max(totalDuration, 1))
            .tint(accentPurple)
            .padding(.horizontal)

            // Skip + Play/Pause controls
            HStack(spacing: 40) {
                // 15s back
                Button {
                    skip(by: -15)
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "gobackward.15")
                            .font(.system(size: 22))
                        Text("15s")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.primary)
                }

                // Play/Pause
                Button {
                    vm.togglePlayback()
                    if vm.isPlaying {
                        player?.play()
                        player?.rate = vm.playbackSpeed
                    } else {
                        player?.pause()
                    }
                } label: {
                    Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 32))
                        .frame(width: 60, height: 60)
                        .background(accentPurple)
                        .foregroundStyle(.white)
                        .clipShape(Circle())
                }

                // 30s forward
                Button {
                    skip(by: 30)
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "goforward.30")
                            .font(.system(size: 22))
                        Text("30s")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.primary)
                }
            }

            // Playback speed
            HStack(spacing: 8) {
                ForEach(speedOptions, id: \.value) { option in
                    Button(option.label) {
                        vm.playbackSpeed = option.value
                        if vm.isPlaying {
                            player?.rate = option.value
                        }
                    }
                    .font(.system(size: 12, weight: vm.playbackSpeed == option.value ? .bold : .regular))
                    .foregroundStyle(vm.playbackSpeed == option.value ? accentPurple : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        vm.playbackSpeed == option.value
                        ? accentPurple.opacity(0.12)
                        : Color.clear
                    )
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal)
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            teardownPlayer()
        }
    }

    private func setupPlayer() {
        guard let url = URL(string: item.contentURL) else {
            dlog("MediaPlayerView: Invalid audio URL — \(item.contentURL)")
            return
        }
        let avPlayer = AVPlayer(url: url)
        self.player = avPlayer
        vm.player = avPlayer

        if vm.isPlaying {
            avPlayer.play()
            avPlayer.rate = vm.playbackSpeed
        }

        // Observe duration
        Task {
            if let asset = avPlayer.currentItem?.asset {
                do {
                    let duration = try await asset.load(.duration)
                    await MainActor.run {
                        totalDuration = duration.seconds.isFinite ? duration.seconds : 1
                    }
                } catch {
                    dlog("MediaPlayerView: Could not load asset duration — \(error.localizedDescription)")
                }
            }
        }

        // Time observer
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverToken = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            if !isDragging {
                currentTime = time.seconds
                vm.updateProgress(time.seconds / max(totalDuration, 1))
            }
        }
    }

    private func teardownPlayer() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
        }
        player?.pause()
        player = nil
        vm.player = nil
    }

    private func skip(by seconds: Double) {
        guard let player = player else { return }
        let newTime = max(0, min(currentTime + seconds, totalDuration))
        let seekTime = CMTime(seconds: newTime, preferredTimescale: 600)
        player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = newTime
        vm.updateProgress(newTime / max(totalDuration, 1))
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let totalSeconds = Int(seconds)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Main Player View
struct MediaPlayerView: View {
    @ObservedObject var vm: ChristianMediaViewModel
    @Environment(\.dismiss) var dismiss

    @State private var showBereanSheet = false
    @State private var descriptionExpanded = false

    private let accentPurple = Color(red: 0.49, green: 0.23, blue: 0.93)

    var body: some View {
        NavigationStack {
            if let item = vm.currentItem {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // MARK: Player
                        playerSection(item: item)

                        // MARK: Metadata
                        VStack(alignment: .leading, spacing: 12) {
                            // Title
                            Text(item.title)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.primary)
                                .padding(.top, 16)

                            // Channel + Subscribe
                            HStack {
                                Text(item.channelOrShow)
                                    .font(.system(size: 15))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Subscribe") {
                                    dlog("MediaPlayerView: Subscribe tapped for \(item.channelOrShow)")
                                }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(accentPurple)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .overlay(
                                    Capsule().strokeBorder(accentPurple, lineWidth: 1)
                                )
                            }

                            // Scripture reference
                            if let scripture = item.scriptureRef {
                                Button {
                                    showBereanSheet = true
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "book.fill")
                                            .font(.system(size: 12))
                                        Text(scripture)
                                            .font(.system(size: 13, weight: .medium))
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 11))
                                    }
                                    .foregroundStyle(accentPurple)
                                    .padding(10)
                                    .background(accentPurple.opacity(0.10))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                            }

                            // Description
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.channelOrShow + " — " + item.type.label)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .lineLimit(descriptionExpanded ? nil : 8)

                                Button(descriptionExpanded ? "Show less" : "Show more") {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        descriptionExpanded.toggle()
                                    }
                                }
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(accentPurple)
                            }

                            Divider()

                            // More from channel
                            moreFromChannel(item: item)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .navigationTitle(item.channelOrShow)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .sheet(isPresented: $showBereanSheet) {
                    if let scripture = item.scriptureRef {
                        BereanAIAssistantView(
                            initialQuery: "I'm watching: \(item.title) by \(item.author). Scripture reference: \(scripture). Give me context and commentary."
                        )
                    }
                }
            } else {
                ContentUnavailableView("Nothing Playing", systemImage: "play.slash")
            }
        }
    }

    // MARK: - Player Section

    @ViewBuilder
    private func playerSection(item: MediaItem) -> some View {
        if item.sourceType == .youtube, let embedURL = item.youtubeEmbedURL {
            YouTubePlayerView(url: embedURL)
                .frame(height: 220)
                .frame(maxWidth: .infinity)
                .background(Color.black)
        } else {
            AVPlayerControllerWrapper(item: item, vm: vm)
                .padding(.vertical, 8)
        }
    }

    // MARK: - More From Channel

    @ViewBuilder
    private func moreFromChannel(item: MediaItem) -> some View {
        let related = vm.items
            .filter { $0.channelOrShow == item.channelOrShow && $0.id != item.id }
            .prefix(5)

        if !related.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("More from \(item.channelOrShow)")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)

                ForEach(Array(related)) { relatedItem in
                    relatedRow(relatedItem)
                }
            }
            .padding(.top, 8)
        }
    }

    private func relatedRow(_ relatedItem: MediaItem) -> some View {
        HStack(spacing: 10) {
            AsyncImage(url: URL(string: relatedItem.thumbnailURL)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Color(hex: relatedItem.dominantColor)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(relatedItem.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text("\(relatedItem.author) · \(relatedItem.duration)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                vm.play(relatedItem)
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(accentPurple)
                    .frame(width: 30, height: 30)
                    .background(accentPurple.opacity(0.12))
                    .clipShape(Circle())
            }
        }
    }
}

