import SwiftUI

struct ChurchNotesWorshipCard: View {
    let songs: [WorshipSongReference]
    let onAdd: () -> Void
    let onRemove: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Worship Songs", systemImage: "music.note")
                Spacer()
                Button("Add", action: onAdd)
            }
            if songs.isEmpty {
                Text("No songs added yet")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(songs) { song in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title).font(.system(size: 14, weight: .medium))
                            Text(song.artist).font(.system(size: 12)).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button {
                            onRemove(song.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .churchNotesGlassCard()
    }
}
