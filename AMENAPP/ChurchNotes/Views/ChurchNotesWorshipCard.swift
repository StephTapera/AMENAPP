import SwiftUI

struct ChurchNotesWorshipCard: View {
    let songs: [WorshipSongReference]
    let onAdd: () -> Void
    let onRemove: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Music")
                        .font(.systemScaled(18, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Keep one primary song connected to this note.")
                        .font(.systemScaled(13))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onAdd) {
                    Label(songs.isEmpty ? "Add" : "Replace", systemImage: songs.isEmpty ? "plus" : "arrow.triangle.2.circlepath")
                        .font(.systemScaled(13, weight: .semibold))
                        .foregroundStyle(ChurchNotesDesignTokens.Colors.personalTint)
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .amenLiquidGlassCapsuleSurface(isSelected: false)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(songs.isEmpty ? "Add music" : "Replace music")
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
                                Image(systemName: "xmark")
                                    .font(.systemScaled(13, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 38, height: 38)
                                    .amenLiquidGlassCapsuleSurface(isSelected: false)
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
                Image(systemName: "music.note")
                    .font(.systemScaled(18, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.72))
                    .frame(width: 54, height: 54)
                    .amenLiquidGlassCapsuleSurface(isSelected: false)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Attach Music")
                        .font(.systemScaled(15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Search, paste Apple Music, Spotify, or YouTube, then keep one primary song.")
                        .font(.systemScaled(13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "plus")
                    .font(.systemScaled(17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(ChurchNotesDesignTokens.Colors.personalTint, in: Capsule(style: .continuous))
            }
            .padding(14)
            .amenLiquidGlassCapsuleSurface(isSelected: false)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Attach music")
    }
}
