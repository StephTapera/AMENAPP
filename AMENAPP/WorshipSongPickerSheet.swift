//
//  WorshipSongPickerSheet.swift
//  AMENAPP
//
//  Sheet that lets users search Apple Music, pick a worship song,
//  and attach it to a Church Note. The song is saved persistently
//  into ChurchNote.worshipSongs (Firestore) and can be played
//  any time from the note detail.
//

import SwiftUI
import AVFoundation

// MARK: - WorshipSongPickerSheet

struct WorshipSongPickerSheet: View {
    /// The note ID this sheet is attaching songs to.
    let noteId: String?
    /// Callback: called with the chosen SongInfo so the editor can save it.
    let onAdd: (WorshipSongReference) -> Void

    @State private var query = ""
    @State private var results: [WorshipSongResult] = []
    @State private var isSearching = false
    @State private var addedIDs: Set<String> = []  // musicKitID or title+artist key
    @State private var errorMessage: String?
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
                    // Search bar
                    searchBar
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 12)

                    Divider().opacity(0.2)

                    if isSearching {
                        Spacer()
                        ProgressView()
                            .tint(.purple)
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
                                        onAdd: {
                                            addSong(song)
                                        }
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
                .foregroundStyle(.purple.opacity(0.8))
                .font(.system(size: 16))

            TextField("", text: $query, prompt:
                Text("Search worship songs...").foregroundStyle(.white.opacity(0.4))
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
                        .strokeBorder(Color.purple.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - States

    private var promptState: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48))
                .foregroundStyle(.purple.opacity(0.6))
            Text("Search for a worship song")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
            Text("Search by song title or artist name")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.slash")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.3))
            Text("No results for \"\(query)\"")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
            Text("Try a different song title or artist")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange.opacity(0.8))
            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Actions

    private func performSearch() {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        errorMessage = nil
        results = []
        Task {
            do {
                let found = try await WorshipSongSearchService.search(query: query)
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

    private func addSong(_ song: WorshipSongResult) {
        addedIDs.insert(song.uniqueKey)
        let ref = WorshipSongReference(
            title: song.title,
            artist: song.artist,
            musicKitID: song.musicKitID,
            appleMusicURL: song.appleMusicURL,
            albumArtURL: song.albumArtURL
        )
        onAdd(ref)
        // Also start playback immediately so the user hears the song
        Task {
            await WorshipMusicService.shared.playSong(
                title: song.title,
                artist: song.artist,
                churchNoteId: noteId
            )
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
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.purple.opacity(0.25))
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
                                .font(.system(size: 22))
                                .foregroundStyle(.purple.opacity(0.7))
                        }
                    }
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 22))
                        .foregroundStyle(.purple.opacity(0.7))
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(song.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(song.artist)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer()

            // Add / Added button
            Button(action: onAdd) {
                if isAdded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.purple)
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

// MARK: - WorshipSongResult (search result model)

struct WorshipSongResult: Identifiable {
    let id = UUID()
    let title: String
    let artist: String
    let musicKitID: String?
    let appleMusicURL: String?
    let albumArtURL: String?

    /// Key for deduplication in the added-IDs set.
    var uniqueKey: String { musicKitID ?? "\(title)|\(artist)" }
}

// MARK: - WorshipSongSearchService

/// Thin wrapper around MusicKit catalog search.
/// Falls back to a fixed list of popular worship songs when MusicKit is unavailable.
enum WorshipSongSearchService {

    static func search(query: String) async throws -> [WorshipSongResult] {
        #if canImport(MusicKit)
        return try await searchWithMusicKit(query: query)
        #else
        return fallbackSearch(query: query)
        #endif
    }

    // MARK: Fallback (no MusicKit)

    static func fallbackSearch(query: String) -> [WorshipSongResult] {
        let catalog: [(String, String)] = [
            ("Way Maker", "Sinach"),
            ("Goodness of God", "Bethel Music"),
            ("What a Beautiful Name", "Hillsong Worship"),
            ("Oceans (Where Feet May Fail)", "Hillsong United"),
            ("Build My Life", "Housefires"),
            ("King of Kings", "Hillsong Worship"),
            ("Raise a Hallelujah", "Bethel Music"),
            ("Holy Spirit", "Francesca Battistelli"),
            ("O Come to the Altar", "Elevation Worship"),
            ("Reckless Love", "Cory Asbury"),
            ("Do It Again", "Elevation Worship"),
            ("Graves into Gardens", "Elevation Worship"),
            ("Jireh", "Elevation Worship"),
            ("Promises", "Maverick City Music"),
            ("Talking to Jesus", "Elevation Worship"),
        ]
        let q = query.lowercased()
        return catalog
            .filter { $0.0.lowercased().contains(q) || $0.1.lowercased().contains(q) }
            .map { WorshipSongResult(title: $0.0, artist: $0.1, musicKitID: nil,
                                     appleMusicURL: nil, albumArtURL: nil) }
    }
}

// MARK: - MusicKit extension

#if canImport(MusicKit)
import MusicKit

extension WorshipSongSearchService {

    static func searchWithMusicKit(query: String) async throws -> [WorshipSongResult] {
        let status = await MusicAuthorization.request()
        guard status == .authorized else {
            // Not authorized — still return a fallback list
            return fallbackSearch(query: query)
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
                albumArtURL: song.artwork?.url(width: 300, height: 300)?.absoluteString
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

    @State private var playingID: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Worship Music", systemImage: "music.note.list")
                .font(.custom("OpenSans-Bold", size: 18))
                .foregroundStyle(.white.opacity(0.9))

            VStack(spacing: 10) {
                ForEach(songs) { song in
                    WorshipSongRow(song: song, noteId: noteId, onRemove: onRemove)
                }
            }
        }
        .padding(24)
        .glassEffect(GlassEffectStyle.regular.tint(.purple), in: RoundedRectangle(cornerRadius: 24))
    }
}

// MARK: - WorshipSongRow (used in SavedWorshipSongsSection)

private struct WorshipSongRow: View {
    let song: WorshipSongReference
    let noteId: String?
    var onRemove: ((WorshipSongReference) -> Void)?

    @ObservedObject private var vm = WorshipNowPlayingViewModel.shared
    @State private var isLoading = false

    private var isCurrentSong: Bool {
        vm.currentSong?.title == song.title && vm.currentSong?.artist == song.artist
    }
    private var isPlaying: Bool { isCurrentSong && vm.isPlaying }

    var body: some View {
        HStack(spacing: 12) {
            // Album art
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.purple.opacity(0.25))
                    .frame(width: 44, height: 44)
                if let urlStr = song.albumArtURL, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFill()
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            Image(systemName: isPlaying ? "waveform" : "music.note")
                                .font(.system(size: 18))
                                .foregroundStyle(.purple)
                                .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                        }
                    }
                } else {
                    Image(systemName: isPlaying ? "waveform" : "music.note")
                        .font(.system(size: 18))
                        .foregroundStyle(.purple)
                        .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(song.artist)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer()

            // Play/pause button
            Button {
                handlePlayTap()
            } label: {
                ZStack {
                    if isLoading {
                        ProgressView().scaleEffect(0.75).tint(.white)
                    } else {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(isCurrentSong ? Color.purple : Color.white.opacity(0.7))
                    }
                }
                .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)

            // Remove button (only shown when onRemove is provided)
            if let onRemove {
                Button {
                    onRemove(song)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(isCurrentSong ? 0.12 : 0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            isCurrentSong ? Color.purple.opacity(0.5) : Color.white.opacity(0.1),
                            lineWidth: 1
                        )
                )
        )
        .animation(.spring(duration: 0.3), value: isCurrentSong)
    }

    private func handlePlayTap() {
        let svc = WorshipMusicService.shared
        if isCurrentSong {
            svc.pauseResume()
        } else {
            isLoading = true
            Task {
                await svc.playSong(title: song.title, artist: song.artist, churchNoteId: noteId)
                await MainActor.run { isLoading = false }
            }
        }
    }
}
