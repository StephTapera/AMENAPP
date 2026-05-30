import SwiftUI

// MARK: - Sample Data

private struct SampleTrack {
    let id: String
    let title: String
    let artists: [String]
    let duration: String
    let artColor: Color
}

private let sampleTracks: [SampleTrack] = [
    SampleTrack(
        id: "track-1",
        title: "Design (Spontaneous / Live)",
        artists: ["UPPERROOM", "Eniola Abioye", "Oscar G."],
        duration: "8:42",
        artColor: AmenTheme.Colors.amenBlue
    ),
    SampleTrack(
        id: "track-2",
        title: "For Christ Alone",
        artists: ["2819 Worship"],
        duration: "12:59",
        artColor: Color(red: 0.60, green: 0.38, blue: 0.08)
    ),
    SampleTrack(
        id: "track-3",
        title: "I'll Be Ready",
        artists: ["Tiffany Hudson"],
        duration: "6:38",
        artColor: Color(red: 0.62, green: 0.46, blue: 0.32)
    ),
    SampleTrack(
        id: "track-4",
        title: "Celebrate",
        artists: ["Ryan Ofei"],
        duration: "2:55",
        artColor: Color(red: 0.24, green: 0.56, blue: 0.28)
    ),
    SampleTrack(
        id: "track-5",
        title: "Room",
        artists: ["Tiffany Hudson", "John Wilds"],
        duration: "7:04",
        artColor: Color(red: 0.32, green: 0.14, blue: 0.44)
    ),
    SampleTrack(
        id: "track-6",
        title: "Slow Me Down",
        artists: ["Charles Weems"],
        duration: "5:49",
        artColor: Color(red: 0.08, green: 0.14, blue: 0.36)
    ),
    SampleTrack(
        id: "track-7",
        title: "I Will Follow",
        artists: ["Charles Weems"],
        duration: "4:37",
        artColor: Color(red: 0.12, green: 0.44, blue: 0.44)
    ),
    SampleTrack(
        id: "track-8",
        title: "Jesus Be The Name (feat. Tiffany H...)",
        artists: ["Elevation Worship"],
        duration: "8:59",
        artColor: Color(red: 0.78, green: 0.28, blue: 0.10)
    ),
]

// MARK: - AmenMusicPickerSheet

struct AmenMusicPickerSheet: View {
    @Binding var selectedMusic: AmenMediaAttachment?
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?

    private var filteredTracks: [SampleTrack] {
        guard !debouncedQuery.isEmpty else { return sampleTracks }
        return sampleTracks.filter {
            $0.title.localizedCaseInsensitiveContains(debouncedQuery)
            || $0.artists.joined(separator: " ").localizedCaseInsensitiveContains(debouncedQuery)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            grabberHandle
            titleRow
            searchBar
            Divider()
                .foregroundStyle(AmenTheme.Colors.separatorSubtle)
            trackList
        }
        .background(AmenTheme.Colors.backgroundPrimary)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(24)
    }

    // MARK: Sub-views

    private var grabberHandle: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(AmenTheme.Colors.separator)
            .frame(width: 36, height: 4)
            .padding(.top, 10)
            .padding(.bottom, 6)
    }

    private var titleRow: some View {
        Text("Music")
            .font(.title3)
            .fontWeight(.semibold)
            .foregroundStyle(AmenTheme.Colors.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 12)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AmenTheme.Colors.textTertiary)
                .font(.system(size: 15))
            TextField("Search music", text: $searchText)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .font(.subheadline)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: searchText) { _, newValue in
                    debounceTask?.cancel()
                    debounceTask = Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        guard !Task.isCancelled else { return }
                        debouncedQuery = newValue
                    }
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AmenTheme.Colors.surfaceInput)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var trackList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if filteredTracks.isEmpty {
                    emptyState
                } else {
                    sectionHeader("Trending")
                    ForEach(filteredTracks, id: \.id) { track in
                        AmenMusicRowView(
                            track: track,
                            onSelect: {
                                selectedMusic = track.asAttachment()
                                dismiss()
                            }
                        )
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }

    private func sectionHeader(_ label: String) -> some View {
        Text(label)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(AmenTheme.Colors.textPrimary)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.system(size: 36))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
            Text("No results")
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - AmenMusicRowView

private struct AmenMusicRowView: View {
    let track: SampleTrack
    let onSelect: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var coordinator = AmenMediaPlaybackCoordinator.shared
    @State private var isPressed = false

    private var attachment: AmenMediaAttachment { track.asAttachment() }
    private var isActive: Bool { coordinator.isActive(attachment) }
    private var isPlaying: Bool { isActive && coordinator.isPlaying }

    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack(spacing: 12) {
                albumArt
                trackInfo
                Spacer(minLength: 0)
                playPauseButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(reduceMotion ? 1 : (isPressed ? 0.97 : 1))
        .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.75), value: isPressed)
        ._onButtonGesture(pressing: { isPressed = $0 }, perform: {})
    }

    private var albumArt: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(track.artColor)
            Text(String(track.title.prefix(1)))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(width: 52, height: 52)
        .accessibilityHidden(true)
    }

    private var trackInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(track.title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .lineLimit(1)
            Text("\(track.artists.first ?? "") · \(track.duration)")
                .font(.caption)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .lineLimit(1)
        }
    }

    private var playPauseButton: some View {
        Button {
            coordinator.togglePlay(attachment)
        } label: {
            ZStack {
                Circle()
                    .fill(AmenTheme.Colors.surfaceChip)
                    .frame(width: 36, height: 36)
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
    }
}

// MARK: - SampleTrack → AmenMediaAttachment

private extension SampleTrack {
    func asAttachment() -> AmenMediaAttachment {
        AmenMediaAttachment(
            id: id,
            kind: .music,
            sourceURL: nil,
            title: title,
            subtitle: "\(artists.first ?? "") · \(duration)",
            thumbnailURL: nil,
            accentHex: nil,
            musicDetails: AmenMusicDetails(
                artists: artists,
                albumArtURL: nil,
                displayMode: .compact
            )
        )
    }
}
