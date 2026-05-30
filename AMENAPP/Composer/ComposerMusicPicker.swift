// ComposerMusicPicker.swift
// AMENAPP
//
// Worship-first music attachment picker for the AMEN composer.
// Reuses WorshipMusicService for all playback — no duplicate audio engine.
//
// SETUP REQUIRED (one-time, in Xcode):
//   Target AMENAPP → Signing & Capabilities → + Capability → MusicKit
//   (Same capability required by WorshipMusicService — no extra entitlement needed.)

import SwiftUI
import Combine

#if canImport(MusicKit)
import MusicKit
#endif

// MARK: - ComposerMusicProvider

@MainActor
final class ComposerMusicProvider: ObservableObject, ComposerAttachmentProvider {

    // MARK: ComposerAttachmentProvider conformance
    @Published var pendingAttachment: ComposerAttachment? = nil
    @Published var isPresented: Bool = false

    func reset() {
        pendingAttachment = nil
        isPresented = false
    }

    func attach(_ track: MusicTrack) {
        pendingAttachment = .music(track)
        isPresented = false
    }
}

// MARK: - MusicSearchResult

struct MusicSearchResult: Identifiable {
    var id: String
    var title: String
    var artists: [String]
    var albumArtURL: String?
    var previewURL: String?
    var durationMs: Int
    var provider: MusicTrackProvider

    var artistsDisplay: String { artists.joined(separator: ", ") }

    var durationFormatted: String {
        let totalSeconds = durationMs / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - MusicTrack convenience init

extension MusicTrack {
    init(from result: MusicSearchResult) {
        self.init(
            id: UUID(),
            title: result.title,
            artists: result.artists,
            albumArtURL: result.albumArtURL,
            previewURL: result.previewURL,
            fullURL: nil,
            syncedLyrics: [],
            durationMs: result.durationMs,
            provider: result.provider,
            externalId: result.id
        )
    }
}

// MARK: - Hardcoded Trending Worship Songs

private let trendingWorshipSongs: [MusicSearchResult] = [
    MusicSearchResult(
        id: "trending-1",
        title: "Way Maker",
        artists: ["Sinach"],
        albumArtURL: nil,
        previewURL: nil,
        durationMs: 292_000,
        provider: .appleMusic
    ),
    MusicSearchResult(
        id: "trending-2",
        title: "Goodness of God",
        artists: ["Bethel Music", "Jenn Johnson"],
        albumArtURL: nil,
        previewURL: nil,
        durationMs: 368_000,
        provider: .appleMusic
    ),
    MusicSearchResult(
        id: "trending-3",
        title: "Oceans (Where Feet May Fail)",
        artists: ["Hillsong UNITED"],
        albumArtURL: nil,
        previewURL: nil,
        durationMs: 507_000,
        provider: .appleMusic
    ),
    MusicSearchResult(
        id: "trending-4",
        title: "What a Beautiful Name",
        artists: ["Hillsong Worship"],
        albumArtURL: nil,
        previewURL: nil,
        durationMs: 292_000,
        provider: .appleMusic
    ),
    MusicSearchResult(
        id: "trending-5",
        title: "Graves Into Gardens",
        artists: ["Elevation Worship", "Brandon Lake"],
        albumArtURL: nil,
        previewURL: nil,
        durationMs: 321_000,
        provider: .appleMusic
    ),
    MusicSearchResult(
        id: "trending-6",
        title: "Holy Spirit",
        artists: ["Francesca Battistelli"],
        albumArtURL: nil,
        previewURL: nil,
        durationMs: 275_000,
        provider: .appleMusic
    ),
    MusicSearchResult(
        id: "trending-7",
        title: "Build My Life",
        artists: ["Pat Barrett", "Housefires"],
        albumArtURL: nil,
        previewURL: nil,
        durationMs: 278_000,
        provider: .appleMusic
    ),
    MusicSearchResult(
        id: "trending-8",
        title: "King of Kings",
        artists: ["Hillsong Worship"],
        albumArtURL: nil,
        previewURL: nil,
        durationMs: 346_000,
        provider: .appleMusic
    ),
    MusicSearchResult(
        id: "trending-9",
        title: "Reckless Love",
        artists: ["Cory Asbury", "Bethel Music"],
        albumArtURL: nil,
        previewURL: nil,
        durationMs: 323_000,
        provider: .appleMusic
    ),
    MusicSearchResult(
        id: "trending-10",
        title: "Jireh",
        artists: ["Elevation Worship", "Maverick City Music"],
        albumArtURL: nil,
        previewURL: nil,
        durationMs: 384_000,
        provider: .appleMusic
    ),
]

// MARK: - Tab Selection

private enum MusicPickerTab: CaseIterable {
    case trending
    case search

    var label: String {
        switch self {
        case .trending: return "Trending"
        case .search:   return "Search Results"
        }
    }
}

// MARK: - ComposerMusicPickerView

struct ComposerMusicPickerView: View {

    @ObservedObject var provider: ComposerMusicProvider
    @Environment(\.dismiss) private var dismiss

    @State private var searchQuery: String = ""
    @State private var selectedTab: MusicPickerTab = .trending
    @State private var searchResults: [MusicSearchResult] = []
    @State private var isSearching: Bool = false
    @State private var isMusicKitAuthorized: Bool = false
    @State private var currentlyPlayingId: String? = nil
    @State private var searchDebounceTask: Task<Void, Never>? = nil

    // Tracks which song row is "playing" to show the gold progress bar
    @State private var playingResultId: String? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // ── Drag indicator + title ──────────────────────────────
                dragHandle

                // ── Search bar ─────────────────────────────────────────
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                // ── Tab row (only when query non-empty) ─────────────────
                if !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                    tabRow
                        .padding(.bottom, 8)
                }

                // ── Song list ───────────────────────────────────────────
                songList
            }
            .background(AmenTheme.Colors.backgroundPrimary.ignoresSafeArea())
            .navigationBarHidden(true)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)  // we draw our own
        .onAppear { checkMusicKitAuthorization() }
        .onChange(of: searchQuery) { _, newValue in
            handleSearchQueryChange(newValue)
        }
    }

    // MARK: - Drag Handle + Title

    private var dragHandle: some View {
        VStack(spacing: 12) {
            Capsule()
                .fill(AmenTheme.Colors.separatorSubtle)
                .frame(width: 36, height: 4)
                .padding(.top, 10)

            HStack {
                Text("Add Music")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                Spacer()
                Button {
                    withAnimation(Motion.adaptive(Motion.springRelease)) {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                }
                .amenPress()
                .accessibilityLabel("Close music picker")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 4)
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AmenTheme.Colors.textSecondary)

            TextField("Search worship songs…", text: $searchQuery)
                .font(.system(size: 15))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit { triggerSearchNow() }
                .accessibilityLabel("Search worship songs")

            if !searchQuery.isEmpty {
                Button {
                    withAnimation(Motion.adaptive(Motion.springPress)) {
                        searchQuery = ""
                        searchResults = []
                        selectedTab = .trending
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                }
                .amenPress()
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .amenGlassInputBar()
    }

    // MARK: - Tab Row

    private var tabRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MusicPickerTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(Motion.adaptive(Motion.tabGlide)) {
                            selectedTab = tab
                        }
                    } label: {
                        Text(tab.label)
                            .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                            .foregroundStyle(
                                selectedTab == tab
                                    ? AmenTheme.Colors.textPrimary
                                    : AmenTheme.Colors.textSecondary
                            )
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(
                                        selectedTab == tab
                                            ? AmenTheme.Colors.selectedFill
                                            : Color.clear
                                    )
                            )
                    }
                    .amenPress()
                    .accessibilityLabel("\(tab.label) tab")
                    .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Song List

    @ViewBuilder
    private var songList: some View {
        let activeTab = searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
            ? MusicPickerTab.trending
            : selectedTab

        ScrollView {
            LazyVStack(spacing: 8) {
                switch activeTab {
                case .trending:
                    ForEach(Array(trendingWorshipSongs.enumerated()), id: \.element.id) { index, song in
                        ComposerMusicSongRow(
                            result: song,
                            isCurrentlyPlaying: playingResultId == song.id,
                            onPlay: { handlePlay(song) },
                            onAdd: { handleAdd(song) }
                        )
                        .staggeredReveal(index: index, baseDelay: 0.03, maxDelay: 0.18)
                        .padding(.horizontal, 16)
                    }

                case .search:
                    if isSearching {
                        ProgressView("Searching…")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                    } else if searchResults.isEmpty {
                        searchEmptyState
                    } else {
                        ForEach(Array(searchResults.enumerated()), id: \.element.id) { index, song in
                            ComposerMusicSongRow(
                                result: song,
                                isCurrentlyPlaying: playingResultId == song.id,
                                onPlay: { handlePlay(song) },
                                onAdd: { handleAdd(song) }
                            )
                            .staggeredReveal(index: index, baseDelay: 0.03, maxDelay: 0.18)
                            .padding(.horizontal, 16)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Search Empty / Unauthorized States

    @ViewBuilder
    private var searchEmptyState: some View {
        if !isMusicKitAuthorized {
            connectAppleMusicPrompt
        } else {
            VStack(spacing: 12) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 36))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
                Text("No songs found")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                Text("Try a different title or artist name.")
                    .font(.system(size: 13))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 48)
        }
    }

    private var connectAppleMusicPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note")
                .font(.system(size: 44))
                .foregroundStyle(AmenTheme.Colors.amenGold)

            Text("Connect Apple Music")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)

            Text("Allow AMEN to search Apple Music so you can attach worship songs to your posts.")
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .padding(.horizontal, 24)

            Button {
                requestMusicKitAuthorization()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "music.note")
                    Text("Connect Apple Music")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(AmenTheme.Colors.textInverse)
                .padding(.horizontal, 24)
                .padding(.vertical, 13)
                .background(
                    Capsule()
                        .fill(AmenTheme.Colors.amenGold)
                )
                .shadow(color: AmenTheme.Colors.amenGold.opacity(0.35), radius: 12, y: 4)
            }
            .amenPress()
            .accessibilityLabel("Connect Apple Music to search songs")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Actions

    private func handlePlay(_ song: MusicSearchResult) {
        let svc = WorshipMusicService.shared
        let isSameSong = svc.currentSong?.title == song.title
            && svc.currentSong?.artist == song.artistsDisplay

        if isSameSong {
            svc.pauseResume()
            playingResultId = svc.isPlaying ? song.id : nil
        } else {
            playingResultId = song.id
            Task {
                await svc.playSong(
                    title: song.title,
                    artist: song.artistsDisplay,
                    churchNoteId: nil
                )
                await MainActor.run {
                    // Sync in case service stopped it immediately (no preview URL, no sub)
                    if !svc.isPlaying { playingResultId = nil }
                }
            }
        }
    }

    private func handleAdd(_ song: MusicSearchResult) {
        let track = MusicTrack(from: song)
        provider.attach(track)
        dismiss()
    }

    // MARK: - Search Debounce

    private func handleSearchQueryChange(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else {
            searchResults = []
            selectedTab = .trending
            return
        }

        selectedTab = .search
        searchDebounceTask?.cancel()
        searchDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000) // 0.4s debounce
            guard !Task.isCancelled else { return }
            await performSearch(query: trimmed)
        }
    }

    private func triggerSearchNow() {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        searchDebounceTask?.cancel()
        Task { await performSearch(query: trimmed) }
    }

    @MainActor
    private func performSearch(query: String) async {
        #if canImport(MusicKit)
        guard isMusicKitAuthorized else { return }
        isSearching = true
        defer { isSearching = false }

        do {
            var request = MusicCatalogSearchRequest(term: query, types: [Song.self])
            request.limit = 20
            let response = try await request.response()

            searchResults = response.songs.map { song in
                MusicSearchResult(
                    id: song.id.rawValue,
                    title: song.title,
                    artists: [song.artistName],
                    albumArtURL: song.artwork?.url(width: 200, height: 200)?.absoluteString,
                    previewURL: song.previewAssets?.first?.url?.absoluteString,
                    durationMs: Int((song.duration ?? 0) * 1000),
                    provider: .appleMusic
                )
            }
        } catch {
            searchResults = []
        }
        #else
        // MusicKit unavailable — fall back to trending filter
        searchResults = trendingWorshipSongs.filter {
            $0.title.localizedCaseInsensitiveContains(query)
            || $0.artistsDisplay.localizedCaseInsensitiveContains(query)
        }
        #endif
    }

    // MARK: - MusicKit Authorization

    private func checkMusicKitAuthorization() {
        #if canImport(MusicKit)
        isMusicKitAuthorized = MusicAuthorization.currentStatus == .authorized
        #else
        isMusicKitAuthorized = false
        #endif
    }

    private func requestMusicKitAuthorization() {
        #if canImport(MusicKit)
        Task {
            let status = await MusicAuthorization.request()
            await MainActor.run {
                isMusicKitAuthorized = status == .authorized
                if isMusicKitAuthorized {
                    triggerSearchNow()
                }
            }
        }
        #endif
    }
}

// MARK: - ComposerMusicSongRow

struct ComposerMusicSongRow: View {

    let result: MusicSearchResult
    let isCurrentlyPlaying: Bool
    let onPlay: () -> Void
    let onAdd: () -> Void

    @State private var isAddPressed: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .bottom) {
            // Row content
            HStack(spacing: 12) {
                albumArt
                songInfo
                Spacer()
                playButton
                addButton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .amenGlassCard(cornerRadius: 14, shadow: false)

            // Gold progress bar for currently playing
            if isCurrentlyPlaying {
                GeometryReader { geo in
                    Rectangle()
                        .fill(AmenTheme.Colors.amenGold)
                        .frame(height: 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 2)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(Motion.adaptive(Motion.appearEase), value: isCurrentlyPlaying)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double tap to preview. Swipe for more options.")
    }

    // MARK: Album Art

    private var albumArt: some View {
        Group {
            if let urlString = result.albumArtURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        albumArtFallback
                    case .empty:
                        AmenTheme.Colors.shimmerBase
                            .amenSkeleton()
                    @unknown default:
                        albumArtFallback
                    }
                }
            } else {
                albumArtFallback
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var albumArtFallback: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AmenTheme.Colors.amenPurple.opacity(0.18))
            Image(systemName: isCurrentlyPlaying ? "waveform" : "music.note")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(
                    isCurrentlyPlaying
                        ? AmenTheme.Colors.amenGold
                        : AmenTheme.Colors.amenPurple
                )
                .symbolEffect(
                    .variableColor.iterative.reversing,
                    isActive: isCurrentlyPlaying
                )
        }
    }

    // MARK: Song Info

    private var songInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(result.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .lineLimit(1)

            Text(result.artistsDisplay)
                .font(.system(size: 12))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .lineLimit(1)

            Text(result.durationFormatted)
                .font(.system(size: 11, weight: .regular).monospacedDigit())
                .foregroundStyle(AmenTheme.Colors.textTertiary)
        }
    }

    // MARK: Play Button

    private var playButton: some View {
        Button(action: onPlay) {
            Image(systemName: isCurrentlyPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(
                    isCurrentlyPlaying
                        ? AmenTheme.Colors.amenGold
                        : AmenTheme.Colors.textSecondary
                )
                .reactionPop(isActive: isCurrentlyPlaying)
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .accessibilityLabel(isCurrentlyPlaying ? "Pause preview" : "Play preview")
    }

    // MARK: Add Button

    private var addButton: some View {
        Button(action: onAdd) {
            Text("Add")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.textInverse)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(AmenTheme.Colors.amenGold)
                )
        }
        .amenPress(scale: 0.94)
        .accessibilityLabel("Add \(result.title) to post")
    }

    // MARK: Accessibility label

    private var accessibilityLabel: String {
        "\(result.title) by \(result.artistsDisplay). \(result.durationFormatted). Add music."
    }
}
