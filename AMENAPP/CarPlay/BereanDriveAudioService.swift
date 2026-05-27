// BereanDriveAudioService.swift
// AMEN — Berean Drive CarPlay
//
// Manages audio for CarPlay driving sessions:
//   - AVAudioSession configuration for CarPlay routing
//   - Local TTS via AVSpeechSynthesizer for spoken Berean/prayer responses
//   - MPNowPlayingInfoCenter updates so the car head unit shows session metadata
//   - Audio interruption handling (phone calls, navigation, Siri)
//
// Requires UIBackgroundModes: audio in Info.plist.
// Requires CarPlay audio entitlement for CPNowPlayingTemplate integration.

import Foundation
import AVFoundation
import MediaPlayer

@MainActor
final class BereanDriveAudioService: NSObject, ObservableObject {

    static let shared = BereanDriveAudioService()

    // MARK: - State

    @Published private(set) var isSpeaking: Bool = false
    @Published private(set) var isAudioSessionActive: Bool = false

    private let synthesizer = AVSpeechSynthesizer()
    private var currentUtterance: AVSpeechUtterance?
    private var completionHandler: (() -> Void)?

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Audio Session Lifecycle

    func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // .playback allows audio over CarPlay speaker.
            // .mixWithOthers is NOT set — Berean Drive takes audio focus for spoken responses.
            // .duckOthers lowers background audio (music) while Berean speaks.
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            isAudioSessionActive = true
            registerForAudioInterruptions()
            dlog("🎧 [BereanDrive] Audio session activated for CarPlay")
        } catch {
            dlog("⚠️ [BereanDrive] Audio session activation failed: \(error.localizedDescription)")
        }
    }

    func deactivateAudioSession() {
        stopSpeaking()
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            isAudioSessionActive = false
            clearNowPlayingInfo()
            dlog("🎧 [BereanDrive] Audio session deactivated")
        } catch {
            dlog("⚠️ [BereanDrive] Audio session deactivation failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Text-to-Speech

    /// Speaks the given text aloud via the car's speakers.
    /// The completion handler is called after speaking finishes or is cancelled.
    func speak(_ text: String, completion: (() -> Void)? = nil) {
        guard !text.isEmpty else {
            completion?()
            return
        }

        // Safety check: never speak text longer than the driving-safe limit
        let safeSpeech = BereanDriveResponsePolicy.truncateForDriving(text)

        stopSpeaking()
        completionHandler = completion

        let utterance = AVSpeechUtterance(string: safeSpeech)
        utterance.voice = preferredVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92   // Slightly slower for driving clarity
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.2

        currentUtterance = utterance
        isSpeaking = true

        if !isAudioSessionActive { activateAudioSession() }
        synthesizer.speak(utterance)
        dlog("🔊 [BereanDrive] Speaking \(safeSpeech.count) characters")
    }

    func stopSpeaking() {
        guard isSpeaking else { return }
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        currentUtterance = nil
        completionHandler?()
        completionHandler = nil
    }

    func pauseSpeaking() {
        synthesizer.pauseSpeaking(at: .word)
    }

    func resumeSpeaking() {
        synthesizer.continueSpeaking()
    }

    // MARK: - Now Playing Info (car head unit display)

    func updateNowPlayingInfo(
        title: String,
        subtitle: String,
        mode: BereanDriveMode,
        isPlaying: Bool = true
    ) {
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = title
        info[MPMediaItemPropertyArtist] = subtitle
        info[MPMediaItemPropertyAlbumTitle] = "Berean Drive"
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue

        if let artwork = artworkForMode(mode) {
            info[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Remote Command Center (play/pause from car controls)

    func configureRemoteCommands(
        onPlay: @escaping () -> Void,
        onPause: @escaping () -> Void,
        onSkipForward: @escaping () -> Void
    ) {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.skipForwardCommand.isEnabled = true
        center.skipForwardCommand.preferredIntervals = [30]

        center.playCommand.addTarget { _ in onPlay(); return .success }
        center.pauseCommand.addTarget { _ in onPause(); return .success }
        center.skipForwardCommand.addTarget { _ in onSkipForward(); return .success }
    }

    func disableRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.skipForwardCommand.removeTarget(nil)
    }

    // MARK: - Audio Interruption Handling

    private func registerForAudioInterruptions() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        Task { @MainActor in
            switch type {
            case .began:
                // Phone call, Siri, navigation — pause Berean
                self.pauseSpeaking()
                dlog("🎧 [BereanDrive] Audio interrupted — pausing")
            case .ended:
                let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    self.resumeSpeaking()
                    dlog("🎧 [BereanDrive] Audio interruption ended — resuming")
                }
            @unknown default:
                break
            }
        }
    }

    // MARK: - Helpers

    private func preferredVoice() -> AVSpeechSynthesisVoice? {
        // Prefer Siri-quality English voice when available
        let preferredIdentifiers = [
            "com.apple.voice.enhanced.en-US.Ava",
            "com.apple.voice.enhanced.en-US.Samantha",
            "com.apple.ttsbundle.siri_female_en-US_compact"
        ]
        for identifier in preferredIdentifiers {
            if let voice = AVSpeechSynthesisVoice(identifier: identifier) {
                return voice
            }
        }
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    private func artworkForMode(_ mode: BereanDriveMode) -> MPMediaItemArtwork? {
        guard let image = UIImage(systemName: mode.systemImageName) else { return nil }
        return MPMediaItemArtwork(boundsSize: CGSize(width: 300, height: 300)) { _ in image }
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension BereanDriveAudioService: AVSpeechSynthesizerDelegate {

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.currentUtterance = nil
            let handler = self.completionHandler
            self.completionHandler = nil
            handler?()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.currentUtterance = nil
            self.completionHandler = nil
        }
    }
}
