import SwiftUI

struct ChurchNotesWorshipCard: View {
    let songs: [WorshipSongReference]
    let onAdd: () -> Void
    let onRemove: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Music")
                        .font(.systemScaled(17, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Attach one meaningful song or album without overpowering the note.")
                        .font(.systemScaled(12, weight: .regular))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(songs.isEmpty ? "Attach Music" : "Replace music", action: onAdd)
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(Color.amenGoldText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(Color.amenGold.opacity(0.10))
                            .overlay(Capsule().strokeBorder(Color.amenGold.opacity(0.35), lineWidth: 1))
                    )
                    .buttonStyle(.plain)
            }

            if songs.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(songs) { song in
                        HStack(spacing: 10) {
                            WorshipMusicPill(song: song)

                            Button {
                                onRemove(song.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove music attachment")
                        }
                    }
                }
            }
        }
        .padding(18)
        .churchNotesGlassCard()
    }

    private var emptyState: some View {
        Button(action: onAdd) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.05))
                        .frame(width: 44, height: 44)
                    Image(systemName: "music.note")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.7))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Attach Music")
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Paste an Apple Music or Spotify song or album link.")
                        .font(.systemScaled(12, weight: .regular))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.amenGold)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.58))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Attach music")
    }
}
