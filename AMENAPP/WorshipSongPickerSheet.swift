//
//  WorshipSongPickerSheet.swift
//  AMENAPP
//
//  Sheet that lets users search Apple Music or Spotify, pick a worship song,
//  and attach it to a Church Note. The song is saved persistently
//  into ChurchNote.worshipSongs (Firestore) and can be played
//  any time from the note detail.
//

import SwiftUI
import AVFoundation

// MARK: - SongSource

enum SongSource: String, CaseIterable {
    case appleMusic = "Apple Music"
    case spotify    = "Spotify"
}

// MARK: - WorshipSongPickerSheet

struct WorshipSongPickerSheet: View {
    /// The note ID this sheet is attaching songs to.
    let noteId: String?
    /// Callback: called with the chosen SongInfo so the editor can save it.
    let onAdd: (WorshipSongReference) -> Void

    @State private var query = ""
    @State private var results: [WorshipSongResult] = []
    @State private var isSearching = false
    @State private var addedIDs: Set<String> = []  // musicKitID / spotifyTrackID / title+artist key
    @State private var errorMessage: String?
    @State private var source: SongSource = .appleMusic
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                LinearGradient(
                    colors: [Color(red: 0.08, green: 0.06, blue: 0.15),
                             Color(red: 0.12, green: 0.08, blue: 0.22)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Source picker
                    Picker("Source", selection: $source) {
                        ForEach(SongSource.allCases, id: \.self) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .onChange(of: source) { _, _ in
                        results = []
                        errorMessage = nil
                        if !query.isEmpty { performSearch() }
                    }

                    // Search bar
                    searchBar
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 12)

                    Divider().opacity(0.2)

                    if isSearching {
                        Spacer()
                        ProgressView()
                            .tint(source == .spotify ? .green : .purple)
                            .scaleEffect(1.3)
                        Spacer()
                    } else if let err = errorMessage {
                        Spacer()
                        errorView(err)
                        Spacer()
                    } else if results.isEmpty && !query.isEmpty {
                        Spacer()
                        emptyState
                        Spacer()
                    } else if results.isEmpty {
                        Spacer()
                        promptState
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(results) { song in
                                    SongResultRow(
                                        song: song,
                                        isAdded: addedIDs.contains(song.uniqueKey),
                                        onAdd: { addSong(song) }
                                    )
                                }
                            }
                            .padding(16)
                        }
                    }
                }
            }
            .navigationTitle("Add Worship Song")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(source == .spotify ? Color.green.opacity(0.8) : Color.purple.opacity(0.8))
                .font(.systemScaled(16))

            TextField("", text: $query, prompt:
                Text("Search or paste music link...").foregroundStyle(.white.opacity(0.4))
            )
            .foregroundStyle(.white)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .onSubmit { performSearch() }
            .onChange(of: query) { _, newValue in
                if newValue.isEmpty { results = []; errorMessage = nil }
            }

            if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                    errorMessage = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            source == .spotify ? Color.green.opacity(0.35) : Color.purple.opacity(0.3),
                            lineWidth: 1
                        )
                )
        )
    }

    // MARK: - States

    private var promptState: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.systemScaled(48))
                .foregroundStyle(source == .spotify ? Color.green.opacity(0.6) : Color.purple.opacity(0.6))
            Text("Search for a worship song")
                .font(.systemScaled(17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
            Text("Search by song title or artist, or paste an Apple Music or Spotify link")
                .font(.systemScaled(14))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.slash")
                .font(.systemScaled(48))
                .foregroundStyle(.white.opacity(0.3))
            Text("No results for \"\(query)\"")
                .font(.systemScaled(16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
            Text("Try a different song title or artist")
                .font(.systemScaled(13))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.systemScaled(40))
                .foregroundStyle(.orange.opacity(0.8))
            Text(message)
                .font(.systemScaled(15))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Actions

    private func performSearch() {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }
        isSearching = true
        errorMessage = nil
        results = []
        let currentSource = source
        let currentQuery = trimmedQuery
        if isSupportedMusicLink(currentQuery) {
            resolveMusicLink(currentQuery)
            return
        }
        Task {
            do {
                let found: [WorshipSongResult]
                if currentSource == .spotify {
                    found = try await WorshipSongSearchService.searchSpotify(query: currentQuery)
                } else {
                    found = try await WorshipSongSearchService.search(query: currentQuery)
                }
                await MainActor.run {
                    results = found
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSearching = false
                }
            }
        }
    }

    private func isSupportedMusicLink(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        return lowercased.hasPrefix("spotify:")
            || lowercased.contains("open.spotify.com")
            || lowercased.contains("music.apple.com")
            || lowercased.contains("itunes.apple.com")
    }

    private func resolveMusicLink(_ value: String) {
        Task {
            do {
                let ref = try await ChurchNoteMusicAttachmentResolverService.shared.resolve(urlString: value)
                await MainActor.run {
                    addedIDs.insert(ref.providerID)
                    isSearching = false
                    onAdd(ref)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    isSearching = false
                }
            }
        }
    }

    private func addSong(_ song: WorshipSongResult) {
        addedIDs.insert(song.uniqueKey)
        let provider: MusicProvider = song.source == .spotify ? .spotify : .appleMusic
        let providerID: String
        let deepLinkURL: String?
        let webURL: String?

        switch song.source {
        case .spotify:
            providerID = song.spotifyTrackID ?? song.uniqueKey
            deepLinkURL = song.spotifyTrackID.map { "spotify:track:\($0)" }
            webURL = song.spotifyTrackURL
        case .appleMusic:
            providerID = song.musicKitID ?? song.uniqueKey
            deepLinkURL = song.appleMusicURL
            webURL = song.appleMusicURL
        }

        let ref = WorshipSongReference(
            provider: provider,
            entityType: .song,
            providerID: providerID,
            title: song.title,
            artist: song.artist,
            subtitle: song.artist,
            musicKitID: song.musicKitID,
            appleMusicURL: song.appleMusicURL,
            albumArtURL: song.albumArtURL,
            spotifyTrackID: song.spotifyTrackID,
            spotifyTrackURL: song.spotifyTrackURL,
            deepLinkURL: deepLinkURL,
            webURL: webURL,
            requiresSubscription: song.source == .appleMusic,
            requiresAppInstall: song.source == .spotify
        )
        onAdd(ref)
        // For Apple Music songs, start playback so the user can preview
        if song.source == .appleMusic {
            Task {
                await WorshipMusicService.shared.playSong(
                    title: song.title,
                    artist: song.artist,
                    churchNoteId: noteId
                )
            }
        }
    }
}

// MARK: - SongResultRow

private struct SongResultRow: View {
    let song: WorshipSongResult
    let isAdded: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Album art placeholder / thumbnail
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(song.source == .spotify ? Color.green.opacity(0.2) : Color.purple.opacity(0.25))
                    .frame(width: 52, height: 52)
                if let urlStr = song.albumArtURL, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                                .frame(width: 52, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        default:
                            Image(systemName: "music.note")
                                .font(.systemScaled(22))
                                .foregroundStyle(song.source == .spotify ? Color.green.opacity(0.7) : Color.purple.opacity(0.7))
                        }
                    }
                } else {
                    Image(systemName: "music.note")
                        .font(.systemScaled(22))
                        .foregroundStyle(song.source == .spotify ? Color.green.opacity(0.7) : Color.purple.opacity(0.7))
                }
                // Source badge
                SourceBadge(source: song.source)
                    .offset(x: 4, y: 4)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(song.title)
                    .font(.systemScaled(15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(song.artist)
                    .font(.systemScaled(13))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer()

            // Add / Added button
            Button(action: onAdd) {
                if isAdded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.systemScaled(28))
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.systemScaled(28))
                        .foregroundStyle(song.source == .spotify ? Color.green : Color.purple)
                }
            }
            .buttonStyle(.plain)
            .disabled(isAdded)
            .animation(.spring(duration: 0.3), value: isAdded)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            isAdded ? Color.green.opacity(0.4) : Color.white.opacity(0.1),
                            lineWidth: 1
                        )
                )
        )
    }
}

// MARK: - SourceBadge

private struct SourceBadge: View {
    let source: SongSource

    var body: some View {
        Group {
            if source == .spotify {
                Image(systemName: "s.circle.fill")
                    .font(.systemScaled(14, weight: .bold))
                    .foregroundStyle(Color.green)
                    .background(Circle().fill(Color.black).padding(-1))
            } else {
                Image(systemName: "music.note.list")
                    .font(.systemScaled(10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(3)
                    .background(Circle().fill(Color(red: 0.98, green: 0.26, blue: 0.45)))
            }
        }
    }
}

// MARK: - WorshipSongResult (search result model)

struct WorshipSongResult: Identifiable {
    let id = UUID()
    let title: String
    let artist: String
    let musicKitID: String?
    let appleMusicURL: String?
    let albumArtURL: String?
    let spotifyTrackID: String?
    let spotifyTrackURL: String?
    let source: SongSource

    init(title: String, artist: String, musicKitID: String? = nil,
         appleMusicURL: String? = nil, albumArtURL: String? = nil,
         spotifyTrackID: String? = nil, spotifyTrackURL: String? = nil,
         source: SongSource = .appleMusic) {
        self.title = title
        self.artist = artist
        self.musicKitID = musicKitID
        self.appleMusicURL = appleMusicURL
        self.albumArtURL = albumArtURL
        self.spotifyTrackID = spotifyTrackID
        self.spotifyTrackURL = spotifyTrackURL
        self.source = source
    }

    /// Key for deduplication in the added-IDs set.
    var uniqueKey: String {
        spotifyTrackID ?? musicKitID ?? "\(title)|\(artist)"
    }
}

// MARK: - WorshipSongSearchService

/// Thin wrapper around MusicKit catalog search (Apple Music) and Spotify Web API.
/// Missing provider access returns an empty result set instead of fake catalog data.
enum WorshipSongSearchService {

    static func search(query: String) async throws -> [WorshipSongResult] {
        #if canImport(MusicKit)
        return try await searchWithMusicKit(query: query)
        #else
        return []
        #endif
    }

    // MARK: - Spotify track search

    static func searchSpotify(query: String) async throws -> [WorshipSongResult] {
        let tracks = await AMENMediaService.shared.searchSpotifyTracks(query: query)
        guard !tracks.isEmpty else { return [] }
        return tracks.map { track in
            WorshipSongResult(
                title: track.name,
                artist: track.primaryArtist,
                albumArtURL: track.albumArtURL,
                spotifyTrackID: track.id,
                spotifyTrackURL: track.deepLink,
                source: .spotify
            )
        }
    }

}

// MARK: - MusicKit extension

#if canImport(MusicKit)
import MusicKit

extension WorshipSongSearchService {

    static func searchWithMusicKit(query: String) async throws -> [WorshipSongResult] {
        let status = await MusicAuthorization.request()
        guard status == .authorized else {
            return []
        }

        var req = MusicCatalogSearchRequest(term: query, types: [Song.self])
        req.limit = 15
        let response = try await req.response()

        return response.songs.compactMap { song in
            WorshipSongResult(
                title: song.title,
                artist: song.artistName,
                musicKitID: song.id.rawValue,
                appleMusicURL: song.url?.absoluteString,
                albumArtURL: song.artwork?.url(width: 300, height: 300)?.absoluteString,
                source: .appleMusic
            )
        }
    }
}
#endif

// MARK: - SavedWorshipSongsSection
// Shown in ChurchNoteDetailView when a note has saved worship songs.

struct SavedWorshipSongsSection: View {
    let songs: [WorshipSongReference]
    let noteId: String?
    var onRemove: ((WorshipSongReference) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "music.note")
                    .font(.systemScaled(10, weight: .medium))
                Text("WORSHIP")
                    .font(.systemScaled(10, weight: .semibold))
                    .tracking(1.2)
            }
            .foregroundStyle(.white.opacity(0.4))

            VStack(spacing: 6) {
                ForEach(songs) { song in
                    WorshipSongRow(song: song, noteId: noteId, onRemove: onRemove)
                }
            }
        }
    }
}

// MARK: - WorshipSongRow (used in SavedWorshipSongsSection)

private struct WorshipSongRow: View {
    let song: WorshipSongReference
    let noteId: String?
    var onRemove: ((WorshipSongReference) -> Void)?

    @Environment(\.openURL) private var openURL
    @State private var showUnavailableAlert = false

    var body: some View {
        HStack(spacing: 10) {
            artworkView

            VStack(alignment: .leading, spacing: 1) {
                Text(song.title)
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(statusLine)
                    .font(.systemScaled(11))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button { handlePlayTap() } label: {
                Image(systemName: trailingIcon)
                    .font(.systemScaled(11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)

            if let onRemove {
                Button { onRemove(song) } label: {
                    Image(systemName: "xmark")
                        .font(.systemScaled(9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.white.opacity(0.07)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .alert("Music Unavailable", isPresented: $showUnavailableAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("This attachment can’t be opened right now. Try another link or remove it from this note.")
        }
    }

    private var artworkView: some View {
        Group {
            if let urlStr = song.albumArtURL, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                    } else {
                        artFallback
                    }
                }
            } else {
                artFallback
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private var artFallback: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(Color.white.opacity(0.08))
            .overlay(
                Image(systemName: "music.note")
                    .font(.systemScaled(12))
                    .foregroundStyle(.white.opacity(0.74))
            )
    }

    private var statusLine: String {
        let base = song.subtitle ?? song.artist
        let helper = song.availabilityState.helperText
        return base.isEmpty ? helper : "\(base) · \(helper)"
    }

    private var trailingIcon: String {
        switch song.availabilityState {
        case .unavailable:
            return "exclamationmark.circle"
        case .accountRequired:
            return "lock.circle"
        case .viewOnly:
            return "arrow.up.right.circle"
        case .readyToOpen:
            return "arrow.up.right"
        }
    }

    private var preferredURL: URL? {
        guard let deepLinkURL = song.deepLinkURL, let url = URL(string: deepLinkURL) else {
            return nil
        }
        return UIApplication.shared.canOpenURL(url) ? url : nil
    }

    private var webFallbackURL: URL? {
        guard let webURL = song.webURL else { return nil }
        return URL(string: webURL)
    }

    private func handlePlayTap() {
        if let preferredURL {
            openURL(preferredURL)
        } else if let webFallbackURL {
            openURL(webFallbackURL)
        } else {
            showUnavailableAlert = true
        }
    }
}
