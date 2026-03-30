
//
//  WorshipMusicService.swift
//  AMENAPP
//
//  Bridges MusicKit with the Dynamic Island Live Activity for worship music.
//
//  SETUP REQUIRED (one-time, in Xcode):
//  1. Target AMENAPP → Signing & Capabilities → + Capability → MusicKit
//  2. Target AMENAPP → Info tab → add NSAppleMusicUsageDescription:
//     "AMEN uses Apple Music to play worship songs in your Church Notes."
//
//  Playback strategy (requires Apple Music subscription):
//  - With subscription  → full song via ApplicationMusicPlayer
//  - Without subscription → 30-sec preview via AVPlayer + offer sheet
//  - MusicKit unavailable → Live Activity only (no audio)
//

import Foundation
import AVFoundation
import SwiftUI

@MainActor
final class WorshipMusicService {

    static let shared = WorshipMusicService()
    private init() {}

    // MARK: - State

    var currentSong: SongInfo? = nil
    var isPlaying = false

    // Preview-only player (used when user has no subscription)
    private var previewPlayer: AVPlayer?
    private var elapsedTimer: Task<Void, Never>?

    struct SongInfo: Equatable {
        let title: String
        let artist: String
        let albumArtURL: String?
        let appleMusicURL: URL?
        let previewURL: URL?
        let churchNoteId: String?
        let durationSeconds: Int
        // Raw MusicKit ID — used for full playback and library actions
        let musicKitID: String?
    }

    // MARK: - Primary API

    /// Search and play a song. Uses full playback when subscribed, preview otherwise.
    func playSong(title: String, artist: String, churchNoteId: String? = nil) async {
        #if canImport(MusicKit)
        await playSongWithMusicKit(title: title, artist: artist, churchNoteId: churchNoteId)
        #else
        // No MusicKit — still store an Apple Music search URL so the user can open the song.
        startActivityWithoutPlayback(title: title, artist: artist, churchNoteId: churchNoteId)
        #endif
    }

    /// Open the current song in the Apple Music app.
    /// Falls back to an Apple Music search URL when no direct link is available.
    func openInAppleMusic() {
        if let url = currentSong?.appleMusicURL {
            UIApplication.shared.open(url)
        } else if let song = currentSong {
            // Build an Apple Music search deep-link — works without MusicKit
            let query = "\(song.title) \(song.artist)"
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: "music://music.apple.com/search?term=\(query)") {
                UIApplication.shared.open(url, options: [:]) { opened in
                    if !opened, let webURL = URL(string: "https://music.apple.com/search?term=\(query)") {
                        UIApplication.shared.open(webURL)
                    }
                }
            }
        }
    }

    /// Build a shareable Apple Music search link for a song (no MusicKit required).
    static func appleMusicSearchURL(title: String, artist: String) -> URL? {
        let query = "\(title) \(artist)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://music.apple.com/search?term=\(query)")
    }

    // MARK: - Playback Control

    func pauseResume() {
        #if canImport(MusicKit)
        pauseResumeWithMusicKit()
        #else
        pauseResumePreview()
        #endif
    }

    func stopPlayback() {
        previewPlayer?.pause()
        previewPlayer = nil
        elapsedTimer?.cancel()
        elapsedTimer = nil
        currentSong = nil
        isPlaying = false
        #if canImport(MusicKit)
        Task { ApplicationMusicPlayer.shared.stop() }
        #endif
        Task { await LiveActivityManager.shared.endMusicActivity() }
    }

    // MARK: - Private fallback helpers

    private func startActivityWithoutPlayback(title: String, artist: String, churchNoteId: String?) {
        currentSong = SongInfo(
            title: title, artist: artist, albumArtURL: nil, appleMusicURL: nil,
            previewURL: nil, churchNoteId: churchNoteId, durationSeconds: 0, musicKitID: nil
        )
        isPlaying = false
        LiveActivityManager.shared.startMusicActivity(
            songTitle: title, artist: artist, churchNoteId: churchNoteId, totalSeconds: 0
        )
    }

    private func startPreviewPlayback(info: SongInfo) {
        stopPlayback()
        currentSong = info
        isPlaying = true

        LiveActivityManager.shared.startMusicActivity(
            songTitle: info.title,
            artist: info.artist,
            albumArtURL: info.albumArtURL,
            appleMusicURL: info.appleMusicURL,
            churchNoteId: info.churchNoteId,
            totalSeconds: info.durationSeconds
        )

        if let previewURL = info.previewURL {
            let item = AVPlayerItem(url: previewURL)
            previewPlayer = AVPlayer(playerItem: item)
            previewPlayer?.play()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(previewPlayerDidFinish),
                name: .AVPlayerItemDidPlayToEndTime,
                object: item
            )
        }

        startElapsedTimer(duration: min(info.durationSeconds, 30))
    }

    private func pauseResumePreview() {
        guard let player = previewPlayer else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
            LiveActivityManager.shared.pauseMusicActivity()
        } else {
            player.play()
            isPlaying = true
        }
    }

    @objc private func previewPlayerDidFinish() {
        Task { @MainActor in stopPlayback() }
    }

    private func startElapsedTimer(duration: Int) {
        let start = Date()
        elapsedTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { break }
                let elapsed = Int(Date().timeIntervalSince(start))
                await MainActor.run {
                    LiveActivityManager.shared.updateMusicElapsed(elapsed)
                }
                if duration > 0 && elapsed >= duration {
                    await MainActor.run { self?.stopPlayback() }
                    break
                }
            }
        }
    }
}

// MARK: - MusicKit integration

#if canImport(MusicKit)
import MusicKit

extension WorshipMusicService {

    // MARK: - Search + play

    func playSongWithMusicKit(title: String, artist: String, churchNoteId: String?) async {
        let status = await MusicAuthorization.request()

        guard status == .authorized else {
            startActivityWithoutPlayback(title: title, artist: artist, churchNoteId: churchNoteId)
            return
        }

        do {
            var request = MusicCatalogSearchRequest(term: "\(title) \(artist)", types: [Song.self])
            request.limit = 1
            let response = try await request.response()

            guard let song = response.songs.first else {
                startActivityWithoutPlayback(title: title, artist: artist, churchNoteId: churchNoteId)
                return
            }

            let info = SongInfo(
                title: song.title,
                artist: song.artistName,
                albumArtURL: song.artwork?.url(width: 300, height: 300)?.absoluteString,
                appleMusicURL: song.url,
                previewURL: song.previewAssets?.first?.url,
                churchNoteId: churchNoteId,
                durationSeconds: Int(song.duration ?? 30),
                musicKitID: song.id.rawValue
            )

            // Check subscription before attempting full playback
            let subscription = try await MusicSubscription.current
            if subscription.canPlayCatalogContent {
                await startFullPlayback(song: song, info: info)
            } else {
                // Fall back to 30-sec preview and show offer
                startPreviewPlayback(info: info)
                showSubscriptionOffer(for: song)
            }

        } catch {
            dlog("⚠️ [WorshipMusic] MusicKit search failed: \(error.localizedDescription)")
            startActivityWithoutPlayback(title: title, artist: artist, churchNoteId: churchNoteId)
        }
    }

    // MARK: - Full playback via ApplicationMusicPlayer

    private func startFullPlayback(song: Song, info: SongInfo) async {
        let player = ApplicationMusicPlayer.shared
        player.queue = [song]
        do {
            try await player.play()
            currentSong = info
            isPlaying = true
            LiveActivityManager.shared.startMusicActivity(
                songTitle: info.title,
                artist: info.artist,
                albumArtURL: info.albumArtURL,
                appleMusicURL: info.appleMusicURL,
                churchNoteId: info.churchNoteId,
                totalSeconds: info.durationSeconds
            )
            startElapsedTimer(duration: info.durationSeconds)
        } catch {
            dlog("⚠️ [WorshipMusic] Full playback failed, using preview: \(error)")
            startPreviewPlayback(info: info)
        }
    }

    private func pauseResumeWithMusicKit() {
        let player = ApplicationMusicPlayer.shared
        Task {
            if isPlaying {
                player.pause()
                isPlaying = false
                LiveActivityManager.shared.pauseMusicActivity()
            } else {
                do {
                    try await player.play()
                    isPlaying = true
                } catch {
                    pauseResumePreview()
                }
            }
        }
    }

    // MARK: - Add to Library

    /// Add the current song to the user's Apple Music library.
    func addToLibrary() async -> Bool {
        guard let idString = currentSong?.musicKitID else { return false }
        do {
            let id = MusicItemID(idString)
            var request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: id)
            request.limit = 1
            let response = try await request.response()
            guard let song = response.items.first else { return false }
            try await MusicLibrary.shared.add(song)
            return true
        } catch {
            dlog("⚠️ [WorshipMusic] addToLibrary failed: \(error)")
            return false
        }
    }

    // MARK: - Worship Playlist

    /// Create (or add to) an AMEN worship playlist with the current song.
    /// Returns the playlist name on success.
    @discardableResult
    func addCurrentSongToWorshipPlaylist(playlistName: String = "AMEN Worship") async -> Bool {
        guard let idString = currentSong?.musicKitID else { return false }
        do {
            let songId = MusicItemID(idString)
            var songReq = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: songId)
            songReq.limit = 1
            let songResp = try await songReq.response()
            guard let song = songResp.items.first else { return false }

            // Find existing playlist or create a new one
            var libraryReq = MusicLibraryRequest<Playlist>()
            libraryReq.filter(matching: \.name, equalTo: playlistName)
            let libraryResp = try await libraryReq.response()

            if let existing = libraryResp.items.first {
                try await MusicLibrary.shared.add(song, to: existing)
            } else {
                try await MusicLibrary.shared.createPlaylist(
                    name: playlistName,
                    description: "Worship songs shared in AMEN Church Notes",
                    items: [song]
                )
            }
            return true
        } catch {
            dlog("⚠️ [WorshipMusic] addToPlaylist failed: \(error)")
            return false
        }
    }

    // MARK: - Subscription offer

    private func showSubscriptionOffer(for song: Song) {
        // Post notification — WorshipNowPlayingView observes this to show MusicSubscriptionOffer
        NotificationCenter.default.post(
            name: .worshipMusicSubscriptionRequired,
            object: nil,
            userInfo: ["itemID": song.id.rawValue]
        )
    }
}

// MARK: - Notification name

extension Notification.Name {
    /// Posted when full Apple Music playback is blocked by missing subscription.
    /// UserInfo: ["itemID": String]
    static let worshipMusicSubscriptionRequired = Notification.Name("worshipMusicSubscriptionRequired")
}

#endif

// MARK: - WorshipSongCard (Embeddable in Church Notes)

/// Minimal card for a worship song reference in Church Notes.
/// Tap: play/pause via WorshipMusicService.
/// Long-press: context menu with "Open in Apple Music", "Add to Library", "Add to Worship Playlist".
struct WorshipSongCard: View {
    let title: String
    let artist: String
    var churchNoteId: String? = nil

    @State private var isLoading = false
    @State private var isPlaying = false
    @State private var isCurrentSong = false
    @State private var addedToLibrary = false
    @State private var addedToPlaylist = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray6))
                    .frame(width: 40, height: 40)
                Image(systemName: isCurrentSong && isPlaying ? "waveform" : "music.note")
                    .font(.system(size: 16))
                    .foregroundStyle(isCurrentSong ? Color.purple : Color.secondary)
                    .symbolEffect(.variableColor.iterative, isActive: isCurrentSong && isPlaying)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(artist)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                handleTap()
            } label: {
                ZStack {
                    if isLoading {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: isCurrentSong && isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(isCurrentSong ? Color.purple : Color.secondary)
                    }
                }
                .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemBackground))
        )
        .contextMenu {
            // Open in Apple Music — works without MusicKit via search URL
            Button {
                // Use card's own title/artist so this works even before tapping play
                if WorshipMusicService.shared.currentSong?.title == title {
                    WorshipMusicService.shared.openInAppleMusic()
                } else if let url = WorshipMusicService.appleMusicSearchURL(title: title, artist: artist) {
                    UIApplication.shared.open(url, options: [:]) { opened in
                        if !opened, let webURL = URL(string: url.absoluteString
                            .replacingOccurrences(of: "music://", with: "https://")) {
                            UIApplication.shared.open(webURL)
                        }
                    }
                }
            } label: {
                Label("Open in Apple Music", systemImage: "music.note")
            }

            // Share Apple Music search link — always available
            Button {
                if let url = WorshipMusicService.appleMusicSearchURL(title: title, artist: artist) {
                    let av = UIActivityViewController(
                        activityItems: ["\(title) by \(artist)", url],
                        applicationActivities: nil
                    )
                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let root = scene.windows.first?.rootViewController {
                        root.present(av, animated: true)
                    }
                }
            } label: {
                Label("Share Song Link", systemImage: "square.and.arrow.up")
            }

            #if canImport(MusicKit)
            Button {
                Task {
                    let ok = await WorshipMusicService.shared.addToLibrary()
                    if ok { addedToLibrary = true }
                }
            } label: {
                Label(addedToLibrary ? "Added to Library" : "Add to Library",
                      systemImage: addedToLibrary ? "checkmark" : "plus")
            }
            .disabled(addedToLibrary)

            Button {
                Task {
                    let ok = await WorshipMusicService.shared.addCurrentSongToWorshipPlaylist()
                    if ok { addedToPlaylist = true }
                }
            } label: {
                Label(addedToPlaylist ? "Added to Playlist" : "Add to AMEN Worship Playlist",
                      systemImage: addedToPlaylist ? "checkmark" : "music.note.list")
            }
            .disabled(addedToPlaylist)
            #endif
        }
        .onAppear { syncState() }
    }

    private func syncState() {
        let svc = WorshipMusicService.shared
        isCurrentSong = svc.currentSong?.title == title && svc.currentSong?.artist == artist
        isPlaying = isCurrentSong && svc.isPlaying
    }

    private func handleTap() {
        let svc = WorshipMusicService.shared
        if svc.currentSong?.title == title && svc.currentSong?.artist == artist {
            svc.pauseResume()
            isPlaying = svc.isPlaying
        } else {
            isLoading = true
            isCurrentSong = false
            Task {
                await svc.playSong(title: title, artist: artist, churchNoteId: churchNoteId)
                await MainActor.run {
                    isLoading = false
                    isCurrentSong = true
                    isPlaying = svc.isPlaying
                }
            }
        }
    }
}
