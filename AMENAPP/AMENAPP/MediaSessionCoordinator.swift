// MediaSessionCoordinator.swift
// AMENAPP
//
// Singleton coordinator for video playback continuity.
// Tracks the active video session, caches playback states in-memory,
// snapshots position periodically, and debounces Firestore sync.
//
// Local-first: never blocks playback on network.

import Foundation
import AVFoundation
import Combine

@MainActor
final class MediaSessionCoordinator: ObservableObject {

    static let shared = MediaSessionCoordinator()

    // MARK: - Published State

    @Published private(set) var activePostId: String?
    @Published private(set) var activeMediaItemId: String?
    @Published private(set) var activeSurface: MediaSurface = .feed

    // MARK: - In-Memory Cache

    /// Keyed by composite ID (postId_mediaItemId)
    private var stateCache: [String: MediaPlaybackState] = [:]

    /// Position observer for the active player
    private var timeObserverToken: Any?
    private weak var observedPlayer: AVPlayer?

    /// Debounce timer for Firestore writes
    private var syncTimer: Timer?
    private let syncInterval: TimeInterval = 10.0

    private init() {}

    // MARK: - Begin / End Session

    /// Call when a video starts playing. Attaches position observer.
    func beginSession(
        postId: String,
        mediaItemId: String,
        surface: MediaSurface,
        player: AVPlayer
    ) {
        if let oldId = activePostId,
           let oldMediaId = activeMediaItemId,
           !(oldId == postId && oldMediaId == mediaItemId) {
            snapshotCurrentPosition()
            detachObserver()
        }

        activePostId = postId
        activeMediaItemId = mediaItemId
        activeSurface = surface

        attachPositionObserver(to: player)
        startSyncTimer()

        let key = "\(postId)_\(mediaItemId)"
        if let cached = stateCache[key], cached.isResumable {
            let targetTime = CMTime(seconds: cached.positionSeconds, preferredTimescale: 600)
            player.seek(to: targetTime)
        }
    }

    /// Call when a video stops or disappears.
    func endSession() {
        snapshotCurrentPosition()
        detachObserver()
        stopSyncTimer()

        activePostId = nil
        activeMediaItemId = nil
    }

    /// Handoff between surfaces (e.g. feed → fullscreen).
    func handoff(to surface: MediaSurface) {
        activeSurface = surface
    }

    // MARK: - Query

    func resumeState(for postId: String, mediaItemId: String) -> MediaPlaybackState? {
        let key = "\(postId)_\(mediaItemId)"
        return stateCache[key]
    }

    func preloadResumeStates() async {
        let states = await MediaResumeService.shared.loadRecent()
        for state in states {
            stateCache[state.id] = state
        }
    }

    // MARK: - Position Observer

    private func attachPositionObserver(to player: AVPlayer) {
        detachObserver()
        observedPlayer = player

        let interval = CMTime(seconds: 1.0, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                self?.handleTimeUpdate(seconds: time.seconds)
            }
        }
    }

    private func detachObserver() {
        if let token = timeObserverToken, let player = observedPlayer {
            player.removeTimeObserver(token)
        }
        timeObserverToken = nil
        observedPlayer = nil
    }

    private func handleTimeUpdate(seconds: Double) {
        guard let postId = activePostId,
              let mediaItemId = activeMediaItemId else { return }

        let key = "\(postId)_\(mediaItemId)"
        let duration = observedPlayer?.currentItem?.duration.seconds ?? 0

        var state = stateCache[key] ?? MediaPlaybackState(
            postId: postId,
            mediaItemId: mediaItemId,
            positionSeconds: 0,
            durationSeconds: duration,
            completed: false,
            lastPlayedAt: Date()
        )

        state.positionSeconds = seconds
        state.durationSeconds = duration > 0 ? duration : state.durationSeconds
        state.lastPlayedAt = Date()

        if duration > 0 && seconds / duration >= 0.95 {
            state.completed = true
        }

        stateCache[key] = state
    }

    // MARK: - Sync

    private func snapshotCurrentPosition() {
        guard let postId = activePostId,
              let mediaItemId = activeMediaItemId else { return }

        let key = "\(postId)_\(mediaItemId)"
        guard let state = stateCache[key] else { return }

        Task {
            await MediaResumeService.shared.save(state)
        }
    }

    private func startSyncTimer() {
        stopSyncTimer()
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.snapshotCurrentPosition()
            }
        }
    }

    private func stopSyncTimer() {
        syncTimer?.invalidate()
        syncTimer = nil
    }
}
