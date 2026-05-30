// ComposerMusicPickerSheet.swift
// AMENAPP — SocialLayer
//
// INTEGRATION NOTE (Phase 4 — add to CreatePostView):
//
//   1. Add state at the top of CreatePostView:
//        @State private var showMusicPicker = false
//
//   2. Add a toolbar button (or attachment-bar icon) inside the view body,
//      e.g. in the composer's bottom action bar:
//        Button {
//            showMusicPicker = true
//        } label: {
//            Image(systemName: "music.note")
//                .font(.system(size: 20, weight: .semibold))
//                .foregroundStyle(draft.musicTrack == nil
//                    ? AmenTheme.Colors.textSecondary
//                    : AmenTheme.Colors.amenGold)
//        }
//        .accessibilityLabel(draft.musicTrack == nil ? "Add music" : "Change music")
//
//   3. Attach the sheet modifier to CreatePostView (or its outermost container):
//        .sheet(isPresented: $showMusicPicker) {
//            ComposerMusicPickerSheet { track in
//                draft.musicTrack = track
//                // Optionally also push a ComposerAttachment:
//                // draft.attachments.removeAll { $0.kind == .music }
//                // draft.attachments.append(.music(track))
//            }
//        }

import SwiftUI

// MARK: - Trending Worship placeholder data

/// Five well-known contemporary worship songs used as the "Trending Worship" placeholder list.
/// In a production build these would come from a Firestore-backed trending service.
private struct TrendingWorshipSeed: Identifiable {
    let id: UUID
    let title: String
    let artist: String
    let durationMs: Int
    let albumArtURL: String?

    var durationDisplay: String {
        let totalSeconds = durationMs / 1000
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

private let trendingWorshipSeeds: [TrendingWorshipSeed] = [
    TrendingWorshipSeed(
        id: UUID(),
        title: "Goodness of God",
        artist: "Bethel Music",
        durationMs: 347_000,
        albumArtURL: nil
    ),
    TrendingWorshipSeed(
        id: UUID(),
        title: "Way Maker",
        artist: "Sinach",
        durationMs: 390_000,
        albumArtURL: nil
    ),
    TrendingWorshipSeed(
        id: UUID(),
        title: "Graves Into Gardens",
        artist: "Elevation Worship",
        durationMs: 318_000,
        albumArtURL: nil
    ),
    TrendingWorshipSeed(
        id: UUID(),
        title: "Battle Belongs",
        artist: "Phil Wickham",
        durationMs: 279_000,
        albumArtURL: nil
    ),
    TrendingWorshipSeed(
        id: UUID(),
        title: "Build My Life",
        artist: "Housefires",
        durationMs: 302_000,
        albumArtURL: nil
    ),
]

// MARK: - ComposerMusicPickerSheet

/// A sheet that lets the user search for and attach a `MusicTrack` to a `ComposerDraft`.
///
/// Wraps `WorshipMusicService` for live 30-second previews via MusicKit / AVPlayer,
/// and surfaces `AmenMusicPickerSheet`'s search-bar UX pattern via composition rather
/// than duplication.
///
/// Present from CreatePostView — see INTEGRATION NOTE at the top of this file.
struct ComposerMusicPickerSheet: View {

    // MARK: - Callback

    /// Called when the user taps "Attach". Receives the resolved `MusicTrack` ready for
    /// insertion into `ComposerDraft.musicTrack` or `ComposerDraft.attachments`.
    let onAttach: (MusicTrack) -> Void

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var selectedSeed: TrendingWorshipSeed? = nil
    @State private var playingId: UUID? = nil          // which row is previewing
    @State private var loadingId: UUID? = nil          // which row is loading

    // MARK: - Filtered list

    private var filteredSeeds: [TrendingWorshipSeed] {
        guard !debouncedQuery.isEmpty else { return trendingWorshipSeeds }
        return trendingWorshipSeeds.filter {
            $0.title.localizedCaseInsensitiveContains(debouncedQuery)
            || $0.artist.localizedCaseInsensitiveContains(debouncedQuery)
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            grabberHandle
            headerRow
            searchBar
            Divider()
                .foregroundStyle(AmenTheme.Colors.separatorSubtle)
                .padding(.top, 2)
            trackList
            if selectedSeed != nil {
                attachBar
            }
        }
        .background(.ultraThinMaterial)
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(32)
        .onDisappear {
            // Stop any active preview when the sheet is dismissed.
            if playingId != nil {
                WorshipMusicService.shared.stopPlayback()
                playingId = nil
            }
        }
    }

    // MARK: - Grabber

    private var grabberHandle: some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(AmenTheme.Colors.separator)
            .frame(width: 36, height: 4)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .accessibilityHidden(true)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle().fill(AmenTheme.Colors.surfaceChip)
                    )
            }
            .buttonStyle(AmenPressStyle(scale: 0.92))
            .accessibilityLabel("Close")

            Spacer()

            Text("Add Music")
                .font(AMENFont.semiBold(17))
                .foregroundStyle(AmenTheme.Colors.textPrimary)

            Spacer()

            // Balance the X button
            Color.clear.frame(width: 28, height: 28)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AmenTheme.Colors.textTertiary)
                .font(.system(size: 15))
                .accessibilityHidden(true)
            TextField("Search worship songs", text: $searchText)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .font(AMENFont.regular(15))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onChange(of: searchText) { _, newValue in
                    debounceTask?.cancel()
                    debounceTask = Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        guard !Task.isCancelled else { return }
                        await MainActor.run { debouncedQuery = newValue }
                    }
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    debouncedQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AmenTheme.Colors.surfaceInput)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Track list

    @ViewBuilder
    private var trackList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if filteredSeeds.isEmpty {
                    emptyState
                } else {
                    sectionHeader(debouncedQuery.isEmpty ? "Trending Worship" : "Results")
                    ForEach(filteredSeeds) { seed in
                        ComposerMusicTrackRow(
                            seed: seed,
                            isSelected: selectedSeed?.id == seed.id,
                            isPlaying: playingId == seed.id,
                            isLoading: loadingId == seed.id,
                            onSelect: {
                                withAnimation(Motion.adaptive(Motion.springPress)) {
                                    selectedSeed = seed
                                }
                            },
                            onPreview: { handlePreviewTap(seed) }
                        )
                    }
                }
            }
            .padding(.bottom, selectedSeed != nil ? 100 : 24)
        }
    }

    private func sectionHeader(_ label: String) -> some View {
        Text(label)
            .font(AMENFont.semiBold(13))
            .foregroundStyle(AmenTheme.Colors.textTertiary)
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note")
                .font(.system(size: 36))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
            Text("No results")
                .font(AMENFont.regular(15))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Attach bar

    private var attachBar: some View {
        VStack(spacing: 0) {
            Divider().foregroundStyle(AmenTheme.Colors.separatorSubtle)
            HStack(spacing: 12) {
                if let seed = selectedSeed {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(seed.title)
                            .font(AMENFont.semiBold(14))
                            .foregroundStyle(AmenTheme.Colors.textPrimary)
                            .lineLimit(1)
                        Text(seed.artist)
                            .font(AMENFont.regular(12))
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }

                Button {
                    guard let seed = selectedSeed else { return }
                    // Stop preview before attaching
                    if playingId != nil {
                        WorshipMusicService.shared.stopPlayback()
                        playingId = nil
                    }
                    let track = seed.asMusicTrack(from: WorshipMusicService.shared.currentSong)
                    onAttach(track)
                    dismiss()
                } label: {
                    Text("Attach")
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 11)
                        .background(
                            Capsule()
                                .fill(AmenTheme.Colors.amenGold)
                        )
                }
                .buttonStyle(AmenPressStyle(scale: 0.96))
                .accessibilityLabel("Attach selected track")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(AmenTheme.Colors.surfaceElevated.opacity(0.95))
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Preview handling

    private func handlePreviewTap(_ seed: TrendingWorshipSeed) {
        let svc = WorshipMusicService.shared
        if playingId == seed.id {
            // Tap again → stop
            svc.stopPlayback()
            playingId = nil
        } else {
            // Stop whatever was playing, start new preview
            if playingId != nil { svc.stopPlayback() }
            playingId = nil
            loadingId = seed.id
            Task {
                await svc.playSong(title: seed.title, artist: seed.artist)
                await MainActor.run {
                    loadingId = nil
                    playingId = seed.id
                }
            }
        }
    }
}

// MARK: - ComposerMusicTrackRow

private struct ComposerMusicTrackRow: View {
    let seed: TrendingWorshipSeed
    let isSelected: Bool
    let isPlaying: Bool
    let isLoading: Bool
    let onSelect: () -> Void
    let onPreview: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPressed = false

    var body: some View {
        HStack(spacing: 12) {
            albumArtView
            trackInfoView
            Spacer(minLength: 0)
            previewButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected
                    ? AmenTheme.Colors.amenGold.opacity(0.12)
                    : Color.clear
                )
                .animation(Motion.adaptive(Motion.springPress), value: isSelected)
                .padding(.horizontal, 8)
        )
        .contentShape(Rectangle())
        .scaleEffect(reduceMotion ? 1 : (isPressed ? 0.97 : 1))
        .animation(
            reduceMotion ? nil : Motion.adaptive(Motion.springPress),
            value: isPressed
        )
        ._onButtonGesture(pressing: { isPressed = $0 }, perform: {})
        .onTapGesture { onSelect() }
        // Accessibility: announce full label on the row, with preview hint on the button
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(seed.title), \(seed.artist)")
    }

    // MARK: Album art

    private var albumArtView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            AmenTheme.Colors.amenPurple.opacity(0.7),
                            AmenTheme.Colors.amenBlue.opacity(0.5),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 44, height: 44)

            if let urlString = seed.albumArtURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    default:
                        musicNotePlaceholder
                    }
                }
            } else {
                musicNotePlaceholder
            }

            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(AmenTheme.Colors.amenGold, lineWidth: 2)
                    .frame(width: 44, height: 44)
            }
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }

    private var musicNotePlaceholder: some View {
        Image(systemName: "music.note")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white.opacity(0.85))
    }

    // MARK: Track info

    private var trackInfoView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(seed.title)
                .font(AMENFont.semiBold(15))
                .foregroundStyle(
                    isSelected
                        ? AmenTheme.Colors.amenGold
                        : AmenTheme.Colors.textPrimary
                )
                .lineLimit(1)
            HStack(spacing: 4) {
                Text(seed.artist)
                    .font(AMENFont.regular(13))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .lineLimit(1)
                Text("·")
                    .font(AMENFont.regular(13))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
                Text(seed.durationDisplay)
                    .font(AMENFont.regular(13))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
            }
        }
    }

    // MARK: Preview button

    private var previewButton: some View {
        Button {
            onPreview()
        } label: {
            ZStack {
                Circle()
                    .fill(
                        isSelected
                            ? AmenTheme.Colors.amenGold.opacity(0.18)
                            : AmenTheme.Colors.surfaceChip
                    )
                    .frame(width: 36, height: 36)

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.75)
                        .tint(AmenTheme.Colors.textSecondary)
                } else {
                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(
                            isPlaying
                                ? AmenTheme.Colors.amenGold
                                : AmenTheme.Colors.textPrimary
                        )
                        .reactionPop(isActive: isPlaying)
                }
            }
            .frame(width: 44, height: 44)       // minimum tap target
        }
        .buttonStyle(AmenPressStyle(scale: 0.92))
        .accessibilityLabel(seed.title + ", " + seed.artist)
        .accessibilityHint(isPlaying ? "Stop preview" : "Play preview")
    }
}

// MARK: - TrendingWorshipSeed → MusicTrack conversion

private extension TrendingWorshipSeed {

    /// Converts a `TrendingWorshipSeed` into a `MusicTrack` ready for `ComposerDraft`.
    /// If `WorshipMusicService` loaded richer metadata during a preview (album art URL,
    /// preview URL, Apple Music URL, MusicKit ID), that data is merged in.
    ///
    /// - Parameter liveInfo: Pass `WorshipMusicService.shared.currentSong` so that
    ///   MusicKit-resolved URLs and IDs are captured when the user previewed the track.
    func asMusicTrack(from liveInfo: WorshipMusicService.SongInfo?) -> MusicTrack {
        // Use live info only when it matches this seed (title + artist guard)
        let matched = liveInfo.flatMap { info -> WorshipMusicService.SongInfo? in
            guard info.title.localizedCaseInsensitiveCompare(title) == .orderedSame,
                  info.artist.localizedCaseInsensitiveCompare(artist) == .orderedSame
            else { return nil }
            return info
        }

        return MusicTrack(
            id: UUID(),
            title: matched?.title ?? title,
            artists: [matched?.artist ?? artist],
            albumArtURL: matched?.albumArtURL,
            previewURL: matched?.previewURL?.absoluteString,
            fullURL: matched?.appleMusicURL?.absoluteString,
            syncedLyrics: [],
            durationMs: matched.map { $0.durationSeconds * 1000 } ?? durationMs,
            provider: .appleMusic,
            externalId: matched?.musicKitID
        )
    }
}
