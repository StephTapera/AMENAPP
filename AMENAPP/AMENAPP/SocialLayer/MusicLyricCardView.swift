// MusicLyricCardView.swift
// AMENAPP — SocialLayer
//
// Renders a MusicTrack attachment in the feed (full layout) and in reply
// threads (compact layout). Drives synced lyric highlight from currentPlaybackMs.
//
// INTEGRATION NOTE (Phase 4 wiring):
//   Feed post card: add `if let track = post.musicTrack { MusicLyricCardView(track: track) }`
//   inside the post body VStack, below any text content.
//
//   Reply node: pass `isCompact: true` so the card uses the mini layout that
//   fits cleanly in a thread indent:
//     `MusicLyricCardView(track: track, isCompact: true, currentPlaybackMs: playbackMs)`
//
//   To drive lyric sync, subscribe to WorshipMusicService elapsed time updates
//   (e.g. via a Timer publisher) and pipe the ms value into currentPlaybackMs.
//   Example:
//     @State private var playbackMs: Int = 0
//     .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { _ in
//         if WorshipMusicService.shared.currentSong?.title == track.title {
//             // WorshipMusicService does not yet expose elapsed ms; wire when it does.
//             // For now pass 0 — lyric highlight stays at line 0 until elapsed is wired.
//         }
//     }

import SwiftUI

// MARK: - FeedMusicLyricCard

struct FeedMusicLyricCard: View {
    let track: MusicTrack
    var isCompact: Bool = false
    /// Parent feeds elapsed playback position in milliseconds; drives lyric highlight.
    var currentPlaybackMs: Int = 0

    var body: some View {
        if isCompact {
            CompactMusicCard(track: track)
        } else {
            FullMusicCard(track: track, currentPlaybackMs: currentPlaybackMs)
        }
    }
}

// MARK: - Full card

private struct FullMusicCard: View {
    let track: MusicTrack
    let currentPlaybackMs: Int

    @State private var showAllLyrics = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ──────────────────────────────────────────────────────
            HStack(alignment: .center, spacing: 12) {
                AlbumArtView(urlString: track.albumArtURL, size: 56, cornerRadius: 12)

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .lineLimit(1)

                    Text(track.artistsDisplay)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        PlayButton(track: track)
                        if track.durationMs > 0 {
                            Text("•")
                                .foregroundStyle(AmenTheme.Colors.textTertiary)
                                .font(.system(size: 12))
                            Text(formattedDuration(track.durationMs))
                                .font(.system(size: 12))
                                .foregroundStyle(AmenTheme.Colors.textTertiary)
                        }
                    }
                }

                Spacer(minLength: 0)

                ProviderBadge(provider: track.provider)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)

            // ── Lyrics section ───────────────────────────────────────────────
            if track.hasLyrics {
                Divider()
                    .overlay(AmenTheme.Colors.borderSoft)

                LyricsSection(
                    lines: track.syncedLyrics,
                    currentPlaybackMs: currentPlaybackMs,
                    showAll: $showAllLyrics
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AmenTheme.Colors.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.75)
        )
        .shadow(
            color: AmenTheme.Colors.glassDepth.opacity(0.8),
            radius: 8, x: 0, y: 2
        )
        .accessibilityElement(children: .contain)
    }

    private func formattedDuration(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Compact card

private struct CompactMusicCard: View {
    let track: MusicTrack

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            AlbumArtView(urlString: track.albumArtURL, size: 44, cornerRadius: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .lineLimit(1)
                Text(track.artistsDisplay)
                    .font(.system(size: 12))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            PlayButton(track: track)

            ProviderBadge(provider: track.provider)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AmenTheme.Colors.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.75)
        )
        .shadow(
            color: AmenTheme.Colors.glassDepth.opacity(0.8),
            radius: 8, x: 0, y: 2
        )
        .accessibilityElement(children: .contain)
    }
}

// MARK: - AlbumArtView

private struct AlbumArtView: View {
    let urlString: String?
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { asyncPhase in
                    switch asyncPhase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        placeholderView
                    case .empty:
                        shimmerRect
                    @unknown default:
                        shimmerRect
                    }
                }
            } else {
                placeholderView
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var placeholderView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(AmenTheme.Colors.amenPurple)
            Image(systemName: "music.note")
                .font(.system(size: size * 0.38, weight: .medium))
                .foregroundStyle(.white)
        }
    }

    private var shimmerRect: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(AmenTheme.Colors.shimmerBase)
            .amenSkeleton()
    }
}

// MARK: - PlayButton

private struct PlayButton: View {
    let track: MusicTrack

    @State private var isLoading = false
    @ObservedObject private var playbackState = PlaybackStateObserver.shared

    private var isActiveTrack: Bool {
        WorshipMusicService.shared.currentSong?.title == track.title
    }

    private var isPlayingThis: Bool {
        isActiveTrack && playbackState.isPlaying
    }

    var body: some View {
        Button {
            handleTap()
        } label: {
            ZStack {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.75)
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: isPlayingThis ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isPlayingThis ? AmenTheme.Colors.amenGold : AmenTheme.Colors.amenBlue)
                        .frame(width: 28, height: 28)
                }
            }
        }
        .buttonStyle(AmenPressStyle(scale: 0.88))
        .accessibilityLabel(isPlayingThis ? "Pause \(track.title)" : "Play \(track.title)")
        .disabled(isLoading)
    }

    private func handleTap() {
        let svc = WorshipMusicService.shared
        if isActiveTrack {
            svc.pauseResume()
            playbackState.sync()
        } else {
            isLoading = true
            Task {
                await svc.playSong(
                    title: track.title,
                    artist: track.artists.first ?? ""
                )
                await MainActor.run {
                    isLoading = false
                    playbackState.sync()
                }
            }
        }
    }
}

// MARK: - PlaybackStateObserver
// Lightweight observable wrapper so PlayButton refreshes when isPlaying changes.
// WorshipMusicService is not yet an ObservableObject; this polls on a timer.

@MainActor
private final class PlaybackStateObserver: ObservableObject {
    static let shared = PlaybackStateObserver()

    @Published private(set) var isPlaying: Bool = false

    private var timer: Timer?

    private init() {
        // Poll at 4 Hz — cheap enough; avoids needing to change WorshipMusicService.
        // Nonisolated closure captures `self` weakly and hops back to MainActor.
        let observer = self
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            Task { @MainActor in observer.sync() }
        }
    }

    func sync() {
        let newValue = WorshipMusicService.shared.isPlaying
        if newValue != isPlaying { isPlaying = newValue }
    }
}

// MARK: - ProviderBadge

private struct ProviderBadge: View {
    let provider: MusicTrackProvider

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(badgeColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(badgeColor.opacity(0.12))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(badgeColor.opacity(0.30), lineWidth: 0.5)
            )
    }

    private var label: String {
        switch provider {
        case .appleMusic: return "Apple Music"
        case .spotify:    return "Spotify"
        case .youtube:    return "YouTube"
        case .other:      return "Music"
        }
    }

    private var badgeColor: Color {
        switch provider {
        case .appleMusic: return AmenTheme.Colors.amenBlue
        case .spotify:    return Color(red: 0.11, green: 0.73, blue: 0.33)   // Spotify green
        case .youtube:    return Color(red: 0.86, green: 0.07, blue: 0.07)   // YouTube red
        case .other:      return AmenTheme.Colors.textTertiary
        }
    }
}

// MARK: - LyricsSection

private struct LyricsSection: View {
    let lines: [SyncedLyricLine]
    let currentPlaybackMs: Int
    @Binding var showAll: Bool

    /// Index of the currently active lyric line.
    private var activeIndex: Int? {
        guard !lines.isEmpty else { return nil }
        // Largest startTimeMs that is <= currentPlaybackMs
        var best: Int? = nil
        for (i, line) in lines.enumerated() {
            if line.startTimeMs <= currentPlaybackMs {
                best = i
            }
        }
        return best
    }

    /// Indices visible when collapsed (±2 window around active, min 5).
    private var visibleIndices: [Int] {
        guard !showAll else { return Array(lines.indices) }
        guard let active = activeIndex else {
            return Array(lines.indices.prefix(5))
        }
        let lo = max(0, active - 2)
        let hi = min(lines.count - 1, active + 2)
        return Array(lo...hi)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { idx, line in
                        if visibleIndices.contains(idx) {
                            LyricLineRow(
                                line: line,
                                isActive: activeIndex == idx
                            )
                            .id(line.id)
                        }
                    }
                }
                .onChange(of: activeIndex) { _, newActive in
                    guard let newActive, newActive < lines.count else { return }
                    withAnimation(Motion.adaptive(Motion.popToggle)) {
                        proxy.scrollTo(lines[newActive].id, anchor: .center)
                    }
                }
            }

            // Show all / collapse toggle
            if lines.count > 5 {
                Button {
                    withAnimation(Motion.adaptive(Motion.springRelease)) {
                        showAll.toggle()
                    }
                } label: {
                    Text(showAll ? "Collapse lyrics" : "Show all lyrics")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AmenTheme.Colors.amenBlue)
                        .padding(.top, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 10)
    }
}

// MARK: - LyricLineRow

private struct LyricLineRow: View {
    let line: SyncedLyricLine
    let isActive: Bool

    var body: some View {
        Text(line.text)
            .font(.system(size: 14, weight: isActive ? .bold : .regular))
            .foregroundStyle(isActive ? AmenTheme.Colors.amenGold : AmenTheme.Colors.textSecondary)
            .padding(.horizontal, isActive ? 8 : 0)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Group {
                    if isActive {
                        Capsule(style: .continuous)
                            .fill(AmenTheme.Colors.amenGold.opacity(0.12))
                            .padding(.horizontal, -4)
                    }
                }
            )
            .animation(Motion.adaptive(Motion.popToggle), value: isActive)
            .accessibilityLabel(isActive ? "Current lyric: \(line.text)" : line.text)
            .accessibilityAddTraits(isActive ? .isHeader : [])
    }
}
