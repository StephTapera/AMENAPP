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
                    Text("Keep one primary song connected to this note.")
                        .font(.systemScaled(12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onAdd) {
                    Label(songs.isEmpty ? "Add" : "Replace", systemImage: songs.isEmpty ? "plus" : "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(ChurchNotesDesignTokens.Colors.personalTint)
            }

            if songs.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(songs.prefix(1)) { song in
                        HStack(spacing: 10) {
                            WorshipMusicPill(song: song)

                            Button {
                                onRemove(song.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.systemScaled(18, weight: .medium))
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
                        .fill(Color.primary.opacity(0.05))
                        .frame(width: 44, height: 44)
                    Image(systemName: "music.note")
                        .font(.systemScaled(16, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.7))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Attach Music")
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Search, paste Apple Music, Spotify, or YouTube, then keep one primary song.")
                        .font(.systemScaled(12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "plus.circle.fill")
                    .font(.systemScaled(20, weight: .medium))
                    .foregroundStyle(ChurchNotesDesignTokens.Colors.personalTint)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.systemBackground).opacity(0.58))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(ChurchNotesDesignTokens.Colors.neutralBorder, lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Attach music")
    }
}
