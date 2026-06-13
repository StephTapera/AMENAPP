// AudioFeedCard.swift
// AMEN — Global Resilience System
// Audio post card with inline mini-player, scrubber, deferred low-data load,
// and a collapsible on-device-AI transcript section.

import SwiftUI
import AVKit

// MARK: - AudioFeedCard

struct AudioFeedCard: View {

    // MARK: Parameters

    let audioURL: URL
    let transcript: String?
    let duration: TimeInterval
    let speakerName: String
    let estimatedDataKb: Int

    // MARK: Environment

    @ObservedObject private var lowDataManager = LowDataModeManager.shared

    // MARK: Private State

    /// Nil until the user explicitly loads audio in low-data mode, or
    /// immediately initialised in normal mode.
    @State private var player: AVPlayer?

    /// Controls play/pause UI state; driven by AVPlayer observation.
    @State private var isPlaying: Bool = false

    /// Current playback position in seconds.
    @State private var currentTime: Double = 0

    /// Whether the user has explicitly requested audio load in low-data mode.
    @State private var audioLoaded: Bool = false

    /// Whether the transcript section is expanded.
    @State private var transcriptExpanded: Bool = true

    /// Scrubbing flag — suppresses time observer updates while user drags.
    @State private var isScrubbing: Bool = false

    /// Timer publisher used to poll playback position.
    @State private var timeObserverToken: Any?

    // MARK: Computed

    private var isLowData: Bool {
        lowDataManager.isEffectiveLowData
    }

    private var shouldShowPlayer: Bool {
        !isLowData || audioLoaded
    }

    private var formattedDuration: String {
        formatTime(duration)
    }

    private var formattedCurrentTime: String {
        formatTime(currentTime)
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardContent
        }
        .glassEffect()
        .onDisappear {
            player?.pause()
            removeTimeObserver()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Audio post by \(speakerName)")
    }

    // MARK: Card Content

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            speakerHeader
            playerSection
            if transcript != nil {
                Divider()
                    .padding(.horizontal, -16)
                transcriptSection
            }
        }
        .padding(16)
    }

    // MARK: Speaker Header

    private var speakerHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "mic.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 16, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(speakerName)
                    .font(.headline)
                    .foregroundStyle(.primary)

                HStack(spacing: 4) {
                    Image(systemName: "waveform")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Audio · \(formattedDuration)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isLowData && !audioLoaded {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }
        }
    }

    // MARK: Player Section

    @ViewBuilder
    private var playerSection: some View {
        if shouldShowPlayer {
            miniPlayer
        } else {
            loadAudioButton
        }
    }

    // MARK: Mini Player

    private var miniPlayer: some View {
        VStack(spacing: 10) {
            // Scrubber
            Slider(
                value: $currentTime,
                in: 0...max(duration, 1),
                onEditingChanged: { editing in
                    isScrubbing = editing
                    if !editing {
                        seek(to: currentTime)
                    }
                }
            )
            .tint(.accentColor)
            .accessibilityLabel("Playback position")
            .accessibilityValue("\(formattedCurrentTime) of \(formattedDuration)")

            // Time labels
            HStack {
                Text(formattedCurrentTime)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formattedDuration)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            // Play / Pause
            HStack {
                Spacer()
                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.accentColor)
                        .symbolEffect(.bounce, value: isPlaying)
                }
                .accessibilityLabel(isPlaying ? "Pause" : "Play")
                Spacer()
            }
        }
        .onAppear {
            if player == nil {
                initPlayer()
            }
        }
    }

    // MARK: Load Audio Button (low-data deferred)

    private var loadAudioButton: some View {
        Button {
            audioLoaded = true
            initPlayer()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.circle")
                    .font(.title3)
                Text("Play audio (≈\(estimatedDataKb)KB)")
                    .font(.subheadline)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .foregroundStyle(Color.accentColor)
        }
        .accessibilityLabel("Play audio, approximately \(estimatedDataKb) kilobytes")
    }

    // MARK: Transcript Section

    @ViewBuilder
    private var transcriptSection: some View {
        if let text = transcript {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        transcriptExpanded.toggle()
                    }
                } label: {
                    HStack {
                        Label("Transcript", systemImage: "text.bubble")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: transcriptExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel(transcriptExpanded ? "Collapse transcript" : "Expand transcript")

                if transcriptExpanded {
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity.combined(with: .move(edge: .top)))

                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("Transcribed by on-device AI")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    // MARK: AVPlayer Helpers

    private func initPlayer() {
        let avPlayer = AVPlayer(url: audioURL)
        player = avPlayer
        attachTimeObserver(to: avPlayer)
    }

    private func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    private func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func attachTimeObserver(to avPlayer: AVPlayer) {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserverToken = avPlayer.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [self] time in
            guard !isScrubbing else { return }
            currentTime = time.seconds
            // Sync play state with player status
            isPlaying = avPlayer.timeControlStatus == .playing
        }
    }

    private func removeTimeObserver() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
    }

    // MARK: Formatting

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let minutes = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("With transcript — normal mode") {
    AudioFeedCard(
        audioURL: URL(string: "https://example.com/sermon.m4a")!,
        transcript: "Brothers and sisters, today we explore the gift of peace that surpasses all understanding. Paul's letter to the Philippians reminds us that in every circumstance, through prayer and thanksgiving, we can present our anxieties to God.",
        duration: 724,
        speakerName: "Pastor Marcus Webb",
        estimatedDataKb: 1800
    )
    .padding()
}

#Preview("No transcript — low data") {
    AudioFeedCard(
        audioURL: URL(string: "https://example.com/devotional.m4a")!,
        transcript: nil,
        duration: 183,
        speakerName: "Sister Kezia Okafor",
        estimatedDataKb: 460
    )
    .padding()
    .environment(\.colorScheme, .dark)
}
#endif
