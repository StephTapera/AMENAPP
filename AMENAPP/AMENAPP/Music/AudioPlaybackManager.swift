// MUSIC FEATURE — Agent A
import AVFoundation
import SwiftUI

@MainActor
final class AudioPlaybackManager: ObservableObject {
    static let shared = AudioPlaybackManager()

    @Published private(set) var currentTrackID: String?
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTimeMs: Int = 0

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var currentTrack: MusicAttachment?

    private init() {
        configureAudioSession()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    private func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func play(_ track: MusicAttachment) {
        stop()
        currentTrack = track
        currentTrackID = track.id
        let item = AVPlayerItem(url: track.previewURL)
        player = AVPlayer(playerItem: item)
        addTimeObserver()
        player?.play()
        isPlaying = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinish),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func togglePlay(_ track: MusicAttachment) {
        if currentTrackID == track.id && isPlaying {
            pause()
        } else {
            play(track)
        }
    }

    func seek(toMs ms: Int) {
        let time = CMTime(value: CMTimeValue(ms), timescale: 1000)
        player?.seek(to: time)
        currentTimeMs = ms
    }

    func stop() {
        removeTimeObserver()
        player?.pause()
        player = nil
        isPlaying = false
        currentTimeMs = 0
        currentTrackID = nil
        currentTrack = nil
    }

    private func addTimeObserver() {
        let interval = CMTime(value: 33, timescale: 1000) // ~30Hz
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                self.currentTimeMs = Int(time.seconds * 1000)
            }
        }
    }

    private func removeTimeObserver() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
    }

    @objc private func playerDidFinish() {
        Task { @MainActor in
            self.isPlaying = false
            self.currentTimeMs = 0
        }
    }

    @objc private func handleInterruption(notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        Task { @MainActor in
            if type == .began { self.pause() }
        }
    }
}
