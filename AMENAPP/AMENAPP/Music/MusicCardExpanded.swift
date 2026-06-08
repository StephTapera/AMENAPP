// MUSIC FEATURE — Agent C
import SwiftUI

struct MusicCardExpanded: View {
    let track: MusicAttachment
    let onCollapse: () -> Void

    @ObservedObject private var player = AudioPlaybackManager.shared
    @State private var syncEngine: LyricsSyncEngine? = nil

    var body: some View {
        VStack(spacing: 16) {
            // Top row: art + title + collapse chevron
            HStack(alignment: .top, spacing: 12) {
                AsyncImage(url: track.albumArtURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: MusicCardMetrics.albumArtMedium,
                                   height: MusicCardMetrics.albumArtMedium)
                            .clipShape(RoundedRectangle(cornerRadius: MusicCardMetrics.innerCornerRadius,
                                                       style: .continuous))
                    default:
                        ZStack {
                            RoundedRectangle(cornerRadius: MusicCardMetrics.innerCornerRadius,
                                            style: .continuous)
                                .fill(Color(.systemGray5))
                            Image(systemName: "music.note")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: MusicCardMetrics.albumArtMedium,
                               height: MusicCardMetrics.albumArtMedium)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                    Text(track.artists.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button(action: onCollapse) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Collapse player")
            }

            // Progress row
            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { Double(player.currentTimeMs) },
                        set: { player.seek(toMs: Int($0)) }
                    ),
                    in: 0...Double(max(track.durationMs, 1))
                )
                .tint(.primary)

                HStack {
                    Text(formatTime(player.currentTimeMs))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Spacer()
                    Text(formatTime(track.durationMs))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            // Play / pause button
            Button {
                player.togglePlay(track)
            } label: {
                ZStack {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
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
            .frame(maxWidth: .infinity, alignment: .center)

            // Lyrics — KaraokeLyricsView owns its own ScrollView
            if track.lyrics != nil, syncEngine != nil {
                KaraokeLyricsView(track: track)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .transition(.scale(scale: 0.95).combined(with: .opacity))
        .onAppear {
            if let lyrics = track.lyrics {
                syncEngine = LyricsSyncEngine(track: lyrics)
            }
        }
    }

    private var isThisTrackPlaying: Bool {
        player.currentTrackID == track.id && player.isPlaying
    }

    private func formatTime(_ ms: Int) -> String {
        let s = ms / 1000
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
