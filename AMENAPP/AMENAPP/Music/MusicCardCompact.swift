// MUSIC FEATURE — Agent C
import SwiftUI

struct MusicCardCompact: View {
    let track: MusicAttachment
    let onExpand: () -> Void

    @ObservedObject private var player = AudioPlaybackManager.shared
    @State private var isPressed = false

    var isThisTrackPlaying: Bool {
        player.currentTrackID == track.id && player.isPlaying
    }

    var body: some View {
        HStack(spacing: 12) {
            // Album art
            AsyncImage(url: track.albumArtURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: MusicCardMetrics.albumArtSmall,
                               height: MusicCardMetrics.albumArtSmall)
                        .clipShape(RoundedRectangle(cornerRadius: MusicCardMetrics.innerCornerRadius,
                                                   style: .continuous))
                default:
                    ZStack {
                        RoundedRectangle(cornerRadius: MusicCardMetrics.innerCornerRadius,
                                        style: .continuous)
                            .fill(Color(.systemGray5))
                        Image(systemName: "music.note")
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: MusicCardMetrics.albumArtSmall,
                           height: MusicCardMetrics.albumArtSmall)
                }
            }

            // Title + artists
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text(track.artists.joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Play / pause button
            Button {
                player.togglePlay(track)
            } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 36, height: 36)
                    Image(systemName: isThisTrackPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isThisTrackPlaying ? "Pause" : "Play")
        }
        .padding(.horizontal, 12)
        .frame(height: MusicCardMetrics.compactHeight)
        .background(
            RoundedRectangle(cornerRadius: MusicCardMetrics.cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: MusicCardMetrics.cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(Motion.adaptive(Motion.springPress), value: isPressed)
        .accessibilityLabel("\(track.title) by \(track.artists.joined(separator: ", "))")
        .accessibilityHint("Double-tap to expand")
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed { isPressed = true }
                }
                .onEnded { _ in
                    isPressed = false
                    onExpand()
                }
        )
    }
}
