// MUSIC FEATURE — Agent C
import SwiftUI
import Combine

struct VinylMusicCard: View {
    let track: MusicAttachment
    let onCollapse: () -> Void

    @ObservedObject private var player = AudioPlaybackManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var discRotation: Double = 0
    @State private var discOffset: CGFloat = 0
    @State private var rotationTimer: AnyCancellable? = nil

    var body: some View {
        VStack(spacing: 20) {
            // Collapse button
            HStack {
                Spacer()
                Button(action: onCollapse) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Collapse vinyl player")
            }

            // Disc + album art stack
            ZStack {
                // Vinyl disc behind art
                ZStack {
                    Circle()
                        .fill(Color(.systemGray6))
                        .frame(width: MusicCardMetrics.vinylDiscSize,
                               height: MusicCardMetrics.vinylDiscSize)

                    // Concentric groove rings
                    Circle()
                        .fill(Color(.systemGray4).opacity(0.7))
                        .frame(width: MusicCardMetrics.vinylDiscSize * 0.85,
                               height: MusicCardMetrics.vinylDiscSize * 0.85)

                    Circle()
                        .fill(Color(.systemGray5).opacity(0.6))
                        .frame(width: MusicCardMetrics.vinylDiscSize * 0.65,
                               height: MusicCardMetrics.vinylDiscSize * 0.65)

                    Circle()
                        .fill(Color(.systemGray4).opacity(0.5))
                        .frame(width: MusicCardMetrics.vinylDiscSize * 0.45,
                               height: MusicCardMetrics.vinylDiscSize * 0.45)
                }
                .rotationEffect(.degrees(discRotation))
                .animation(
                    reduceMotion ? .none : .linear(duration: 0.016),
                    value: discRotation
                )
                .offset(x: discOffset)
                .animation(
                    reduceMotion ? .none : Motion.adaptive(Motion.springRelease),
                    value: discOffset
                )

                // Album art circle on top
                AsyncImage(url: track.albumArtURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        ZStack {
                            Circle().fill(Color(.systemGray5))
                            Image(systemName: "music.note")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: 120, height: 120)
                .clipShape(Circle())
            }
            .frame(height: MusicCardMetrics.vinylDiscSize)

            // Title + artists
            VStack(spacing: 4) {
                Text(track.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text(track.artists.joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Play / pause
            Button {
                player.togglePlay(track)
            } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .frame(width: 56, height: 56)
                    Image(systemName: isThisTrackPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isThisTrackPlaying ? "Pause" : "Play")

            // Lyrics
            if track.lyrics != nil {
                KaraokeLyricsView(track: track)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .onChange(of: player.isPlaying) { _, nowPlaying in
            handlePlaybackChange(isPlaying: nowPlaying)
        }
        .onChange(of: player.currentTrackID) { _, newID in
            let isOurTrack = newID == track.id
            if !isOurTrack {
                handlePlaybackChange(isPlaying: false)
            }
        }
        .onDisappear {
            stopRotation()
        }
    }

    private var isThisTrackPlaying: Bool {
        player.currentTrackID == track.id && player.isPlaying
    }

    private func handlePlaybackChange(isPlaying: Bool) {
        let isOurTrack = player.currentTrackID == track.id
        if isPlaying && isOurTrack {
            startDisc()
        } else {
            stopDisc()
        }
    }

    private func startDisc() {
        guard !reduceMotion else { return }
        withAnimation(Motion.adaptive(Motion.springRelease)) {
            discOffset = 60
        }
        startRotation()
    }

    private func stopDisc() {
        stopRotation()
        if reduceMotion {
            discOffset = 0
        } else {
            withAnimation(Motion.adaptive(Motion.springRelease)) {
                discOffset = 0
            }
        }
    }

    private func startRotation() {
        guard !reduceMotion else { return }
        stopRotation()
        rotationTimer = Timer.publish(every: 0.016, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                discRotation += 1.0
                if discRotation >= 360 { discRotation -= 360 }
            }
    }

    private func stopRotation() {
        rotationTimer?.cancel()
        rotationTimer = nil
    }
}
