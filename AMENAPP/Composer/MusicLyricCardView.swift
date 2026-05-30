// MusicLyricCardView.swift
// AMENAPP
//
// Music Lyric Card — Threads-style synced-lyric card for the AMEN composer,
// feed post cards, and the attachment strip chip.
//
// Depends on:
//   - ComposerContract.swift  → MusicTrack, SyncedLyricLine, MusicTrackProvider
//   - WorshipMusicService.swift → WorshipMusicService.shared.playSong / pauseResume
//   - AmenTheme.swift          → color tokens, .amenCard(), .amenPress()
//   - Motion.swift             → Motion.adaptive, Motion.appearEase, Motion.springPress

import SwiftUI

// MARK: - MusicLyricCardViewModel

@Observable
@MainActor
final class MusicLyricCardViewModel {

    // MARK: Public state

    var track: MusicTrack
    var isPlaying: Bool = false
    var currentPositionMs: Int = 0
    var activeLyricId: UUID? = nil

    // MARK: Private

    private var timer: Timer?

    // MARK: Init

    init(track: MusicTrack) {
        self.track = track
    }

    deinit {
        // Timer is an NSObject — invalidation is safe from any context.
        timer?.invalidate()
    }

    // MARK: Playback control

    func play() {
        guard !isPlaying else { return }
        isPlaying = true
        // Kick off the system timer on the main run loop.
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        // Delegate audio to WorshipMusicService (async — fire and forget).
        let title = track.title
        let artist = track.artistsDisplay
        Task {
            await WorshipMusicService.shared.playSong(title: title, artist: artist, churchNoteId: nil)
        }
    }

    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        timer?.invalidate()
        timer = nil
        WorshipMusicService.shared.pauseResume()
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    /// Called every 200 ms while playing. Advances position and resolves the active lyric.
    func tick() {
        currentPositionMs += 200

        // Find the lyric line whose window contains the current position.
        let active = track.syncedLyrics.first {
            $0.startTimeMs <= currentPositionMs && currentPositionMs < $0.endTimeMs
        }
        withAnimation(Motion.adaptive(Motion.springPress)) {
            activeLyricId = active?.id
        }

        // Auto-stop at track end when duration is known.
        if track.durationMs > 0 && currentPositionMs >= track.durationMs {
            reset()
        }
    }

    func reset() {
        isPlaying = false
        timer?.invalidate()
        timer = nil
        currentPositionMs = 0
        withAnimation(Motion.adaptive(Motion.appearEase)) {
            activeLyricId = nil
        }
    }
}

// MARK: - LyricLineView

struct LyricLineView: View {

    let line: SyncedLyricLine
    /// Whether this line is the currently-playing lyric.
    let isActive: Bool
    /// Whether this line is in the "future" (after the active line) — rendered dimmer.
    let isFuture: Bool

    var body: some View {
        Text(line.text)
            .font(isActive ? .body.weight(.bold) : .body)
            .foregroundStyle(
                isActive
                    ? AmenTheme.Colors.textPrimary
                    : isFuture
                        ? AmenTheme.Colors.textSecondary
                        : AmenTheme.Colors.textPrimary.opacity(0.85)
            )
            .padding(.horizontal, isActive ? 4 : 0)
            .padding(.vertical, isActive ? 2 : 0)
            .background(
                Group {
                    if isActive {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(AmenTheme.Colors.amenGold.opacity(0.25))
                    }
                }
            )
            .animation(Motion.adaptive(Motion.springPress), value: isActive)
            .accessibilityLabel(line.text + (isActive ? ", current lyric" : ""))
    }
}

// MARK: - MusicLyricCardView

struct MusicLyricCardView: View {

    let track: MusicTrack
    var compact: Bool = false

    @State private var vm: MusicLyricCardViewModel

    init(track: MusicTrack, compact: Bool = false) {
        self.track = track
        self.compact = compact
        // @Observable — use plain init; no @StateObject wrapper needed.
        self._vm = State(initialValue: MusicLyricCardViewModel(track: track))
    }

    var body: some View {
        Group {
            if compact {
                compactCard
            } else {
                expandedCard
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(track.title) by \(track.artistsDisplay). " +
            "\(vm.isPlaying ? "Playing" : "Paused"). " +
            "Double-tap to toggle playback."
        )
    }

    // MARK: Compact card (for feed post)

    private var compactCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top row — album art + metadata + play button
            HStack(spacing: 12) {
                albumArt(size: 56, cornerRadius: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.headline)
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .lineLimit(1)
                    Text(track.artistsDisplay)
                        .font(.caption)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                playPauseButton(size: 36)
            }

            // Preview lyrics — first 2 lines only
            if track.hasLyrics {
                let previewLines = Array(track.syncedLyrics.prefix(2))
                let activeIndex = previewLines.firstIndex { $0.id == vm.activeLyricId }

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(previewLines.enumerated()), id: \.element.id) { idx, line in
                        LyricLineView(
                            line: line,
                            isActive: line.id == vm.activeLyricId,
                            isFuture: activeIndex.map { idx > $0 } ?? false
                        )
                    }
                }
            }
        }
        .padding(12)
        .amenCard(cornerRadius: 14)
    }

    // MARK: Expanded card (lyric detail)

    private var expandedCard: some View {
        VStack(spacing: 0) {
            // Album art
            albumArt(size: 120, cornerRadius: 16)
                .padding(.top, 24)
                .shadow(color: AmenTheme.Colors.shadowCard, radius: 18, x: 0, y: 8)

            // Title + artist
            VStack(spacing: 4) {
                Text(track.title)
                    .font(.title2.bold())
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(track.artistsDisplay)
                    .font(.subheadline)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
            }
            .padding(.top, 16)
            .padding(.horizontal, 24)

            // Large play/pause button
            playPauseButton(size: 56)
                .padding(.top, 20)

            // Synced lyric scroll
            if track.hasLyrics {
                lyricScrollView
                    .frame(maxHeight: 320)
                    .padding(.top, 20)
            }

            // Footer
            Text("♫  Music · Try it")
                .font(.caption)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .padding(.top, 16)
                .padding(.bottom, 24)
        }
        .amenCard(cornerRadius: 20)
    }

    // MARK: Lyric scroll

    private var lyricScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    // Determine the index of the active lyric so we can classify future lines.
                    let activeIndex: Int? = track.syncedLyrics.firstIndex { $0.id == vm.activeLyricId }

                    ForEach(Array(track.syncedLyrics.enumerated()), id: \.element.id) { idx, line in
                        LyricLineView(
                            line: line,
                            isActive: line.id == vm.activeLyricId,
                            isFuture: activeIndex.map { idx > $0 } ?? false
                        )
                        .id(line.id)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .onChange(of: vm.activeLyricId) { _, newId in
                guard let id = newId else { return }
                withAnimation(Motion.adaptive(Motion.appearEase)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    // MARK: Shared sub-views

    @ViewBuilder
    private func albumArt(size: CGFloat, cornerRadius: CGFloat) -> some View {
        Group {
            if let urlString = track.albumArtURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(1, contentMode: .fill)
                    case .failure:
                        albumArtPlaceholder
                    case .empty:
                        albumArtPlaceholder
                            .amenSkeleton()
                    @unknown default:
                        albumArtPlaceholder
                    }
                }
            } else {
                albumArtPlaceholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var albumArtPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 0)
                .fill(AmenTheme.Colors.backgroundSecondary)
            Image(systemName: "music.note")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
        }
    }

    private func playPauseButton(size: CGFloat) -> some View {
        Button {
            vm.togglePlay()
        } label: {
            ZStack {
                Circle()
                    .fill(AmenTheme.Colors.amenBlue)
                    .frame(width: size, height: size)
                Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(.white)
                    // Subtle offset on "play" to optically center the triangle.
                    .offset(x: vm.isPlaying ? 0 : size * 0.03)
            }
        }
        .amenPress()
        .animation(Motion.adaptive(Motion.springPress), value: vm.isPlaying)
        .accessibilityLabel(vm.isPlaying ? "Pause" : "Play")
        .accessibilityHint("Toggles music playback")
    }
}

// MARK: - MusicLyricAttachmentChip

/// Compact pill for the attachment strip in the composer.
/// Shows a music-note icon + truncated track title.
/// Tapping opens a sheet with the compact `MusicLyricCardView`.
struct MusicLyricAttachmentChip: View {

    let track: MusicTrack
    @State private var showCard = false

    var body: some View {
        Button {
            showCard = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "note.text")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.amenBlue)
                Text(track.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(AmenTheme.Colors.amenBlue.opacity(0.10))
            )
            .overlay(
                Capsule()
                    .strokeBorder(AmenTheme.Colors.amenBlue.opacity(0.22), lineWidth: 0.75)
            )
        }
        .amenPress()
        .accessibilityLabel("Music: \(track.title)")
        .accessibilityHint("Tap to preview lyrics")
        .sheet(isPresented: $showCard) {
            // Compact card inside a small detent sheet.
            NavigationStack {
                MusicLyricCardView(track: track, compact: true)
                    .padding()
                    .navigationTitle("Now Playing")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showCard = false }
                        }
                    }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Compact — with lyrics") {
    let track = MusicTrack(
        title: "Great Is Thy Faithfulness",
        artists: ["Sovereign Grace Music"],
        albumArtURL: nil,
        syncedLyrics: [
            SyncedLyricLine(startTimeMs: 0,    endTimeMs: 3000,  text: "Great is thy faithfulness"),
            SyncedLyricLine(startTimeMs: 3000, endTimeMs: 6000,  text: "O God my Father"),
            SyncedLyricLine(startTimeMs: 6000, endTimeMs: 9000,  text: "There is no shadow"),
            SyncedLyricLine(startTimeMs: 9000, endTimeMs: 12000, text: "Of turning with thee"),
        ],
        durationMs: 12000
    )
    MusicLyricCardView(track: track, compact: true)
        .padding()
}

#Preview("Expanded — no lyrics") {
    let track = MusicTrack(
        title: "How Great Thou Art",
        artists: ["Hillsong Worship", "Various Artists"],
        albumArtURL: nil,
        durationMs: 240_000
    )
    MusicLyricCardView(track: track, compact: false)
        .padding()
}

#Preview("Attachment Chip") {
    let track = MusicTrack(
        title: "Oceans (Where Feet May Fail)",
        artists: ["Hillsong UNITED"]
    )
    HStack {
        MusicLyricAttachmentChip(track: track)
    }
    .padding()
}
#endif
