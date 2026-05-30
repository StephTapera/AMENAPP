// AmenMediaPlaybackCoordinator.swift
// AMENAPP
//
// @MainActor ObservableObject singleton that drives AVPlayer for nativeAudio
// and nativeVideo transports. Publishes playback state at 30 Hz for UI updates.
//
// Relationship with VisibilityPlaybackManager:
//   • VisibilityPlaybackManager owns feed-level visibility gating (70% threshold,
//     single-video autoplay). It calls play()/pause() closures on individual cells.
//   • AmenMediaPlaybackCoordinator owns the actual AVPlayer instance, transport
//     commands, and continuous currentTimeMs publishing for lyric/chapter sync.
//   • The two can coexist: VisibilityPlaybackManager's play closure should call
//     AmenMediaPlaybackCoordinator.shared.play(_:) when the cell appears.
//
// For youtubeEmbed and external transports no AVPlayer is created; the
// coordinator tracks logical active state only.
//
// Usage:
//   @StateObject private var coordinator = AmenMediaPlaybackCoordinator.shared
//   coordinator.play(attachment)
//   coordinator.seek(toMs: 30_000)

import AVFoundation
import Combine
import Foundation

// MARK: - AmenMediaPlaybackCoordinator

@MainActor
final class AmenMediaPlaybackCoordinator: ObservableObject {

    // MARK: Singleton

    static let shared = AmenMediaPlaybackCoordinator()

    // MARK: Published State

    /// The `id` of the attachment currently loaded (playing or paused), or nil.
    @Published private(set) var activeAttachmentID: String?

    /// Whether the active attachment is currently playing.
    @Published private(set) var isPlaying: Bool = false

    /// Current playback position in milliseconds (updated at ~30 Hz).
    @Published private(set) var currentTimeMs: Int = 0

    /// Whether the player is muted (default: true to respect ambient-sound policy).
    @Published private(set) var isMuted: Bool = true

    /// Total duration of the loaded item in milliseconds. 0 until known.
    @Published private(set) var durationMs: Int = 0

    // MARK: Private State

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var itemStatusObservation: NSKeyValueObservation?
    private var interruptionObserver: AnyCancellable?
    private var routeChangeObserver: AnyCancellable?
    private var activeAttachment: AmenMediaAttachment?

    // MARK: Init

    private init() {
        configureAudioSession()
        observeAudioSessionInterruptions()
        observeRouteChanges()
    }

    // MARK: - Public Transport API

    /// Loads and plays `attachment`, stopping any currently active playback first.
    func play(_ attachment: AmenMediaAttachment) {
        // If this attachment is already active and paused, just resume.
        if activeAttachmentID == attachment.id {
            player?.play()
            isPlaying = true
            return
        }

        // Stop whatever is currently playing.
        stop()

        activeAttachment = attachment
        activeAttachmentID = attachment.id
        isPlaying = false
        currentTimeMs = 0
        durationMs = 0

        guard let playable = attachment.playable else {
            // Non-playable attachment (article, book, etc.) — just track active state.
            isPlaying = true
            return
        }

        switch playable.transport {
        case .nativeAudio, .nativeVideo:
            loadAVPlayer(playable: playable)
        case .youtubeEmbed, .external:
            // No AVPlayer for these — the view layer handles presentation.
            isPlaying = true
        }
    }

    /// Pauses the active player without clearing the active attachment.
    func pause() {
        player?.pause()
        isPlaying = false
    }

    /// Toggles play/pause for `attachment`. If `attachment` is not currently
    /// active, it becomes the active attachment and begins playing.
    func togglePlay(_ attachment: AmenMediaAttachment) {
        if activeAttachmentID == attachment.id {
            if isPlaying {
                pause()
            } else {
                player?.play()
                isPlaying = true
            }
        } else {
            play(attachment)
        }
    }

    /// Seeks the active player to the given millisecond position.
    func seek(toMs ms: Int) {
        guard let player else {
            currentTimeMs = ms
            return
        }
        let targetTime = CMTime(value: CMTimeValue(ms), timescale: 1_000)
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.currentTimeMs = ms
            }
        }
    }

    /// Sets the muted state on the underlying player.
    func setMuted(_ muted: Bool) {
        isMuted = muted
        player?.isMuted = muted
    }

    /// Stops playback and releases all resources.
    func stop() {
        removeTimeObserver()
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        player?.pause()
        player = nil
        activeAttachmentID = nil
        activeAttachment = nil
        isPlaying = false
        currentTimeMs = 0
        durationMs = 0
    }

    // MARK: - State Query

    /// Returns true when `attachment` is the currently active item.
    func isActive(_ attachment: AmenMediaAttachment) -> Bool {
        activeAttachmentID == attachment.id
    }

    // MARK: - AVPlayer Setup

    private func loadAVPlayer(playable: AmenPlayableInfo) {
        guard let urlString = playable.mediaURL,
              let url = URL(string: urlString) else {
            return
        }

        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.isMuted = isMuted
        player = newPlayer

        // Observe item status to know when duration becomes available.
        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] playerItem, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if playerItem.status == .readyToPlay {
                    let durationSeconds = playerItem.duration.seconds
                    if durationSeconds.isFinite {
                        self.durationMs = Int(durationSeconds * 1_000)
                    }
                    // Seek to stored start position if non-zero.
                    if playable.startMs > 0 {
                        self.seek(toMs: playable.startMs)
                    }
                    newPlayer.play()
                    self.isPlaying = true
                }
            }
        }

        // Periodic time observer at 30 Hz (every ~33 ms).
        let interval = CMTime(value: 1, timescale: 30)
        timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self, self.isPlaying else { return }
                let ms = Int(time.seconds * 1_000)
                self.currentTimeMs = ms
            }
        }
    }

    // MARK: - Audio Session

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Non-fatal: audio session configuration may fail in simulator or extension targets.
#if DEBUG
            print("[AmenMediaPlaybackCoordinator] AVAudioSession setup failed: \(error)")
#endif
        }
    }

    // MARK: - Interruption Handling

    private func observeAudioSessionInterruptions() {
        interruptionObserver = NotificationCenter.default
            .publisher(for: AVAudioSession.interruptionNotification)
            .sink { [weak self] notification in
                Task { @MainActor [weak self] in
                    self?.handleInterruption(notification)
                }
            }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            // System interrupted us (phone call, Siri, etc.) — reflect paused state.
            isPlaying = false
        case .ended:
            // Resume only if the system allows it.
            let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                player?.play()
                isPlaying = true
            }
        @unknown default:
            break
        }
    }

    // MARK: - Route Change Handling

    private func observeRouteChanges() {
        routeChangeObserver = NotificationCenter.default
            .publisher(for: AVAudioSession.routeChangeNotification)
            .sink { [weak self] notification in
                Task { @MainActor [weak self] in
                    self?.handleRouteChange(notification)
                }
            }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        // Standard iOS behaviour: pause when headphones are unplugged.
        if reason == .oldDeviceUnavailable {
            pause()
        }
    }

    // MARK: - Cleanup Helpers

    private func removeTimeObserver() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
    }
}
