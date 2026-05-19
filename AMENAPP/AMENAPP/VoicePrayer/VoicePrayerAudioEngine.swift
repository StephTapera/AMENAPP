// VoicePrayerAudioEngine.swift
// AMEN App — Voice Prayer & Testimony Comments
//
// AVFoundation recording engine for voice prayer comments.
// Enforces type-specific duration limits, produces real-time
// waveform samples for UI rendering, and provides preview playback.
// All duration limits mirror the backend validation in voicePrayerComments.ts.

import Foundation
import AVFoundation
import Combine

@MainActor
final class VoicePrayerAudioEngine: NSObject, ObservableObject {

    // MARK: - State

    enum RecordingState {
        case idle
        case requestingPermission
        case recording
        case paused
        case finishedRecording
        case playingPreview
        case uploading
        case processing
        case error(String)
    }

    @Published private(set) var state: RecordingState = .idle
    @Published private(set) var elapsedSeconds: Double = 0
    @Published private(set) var waveformSamples: [Float] = Array(repeating: 0.1, count: 60)
    @Published private(set) var recordedFileURL: URL?
    @Published private(set) var isNearLimit: Bool = false
    @Published private(set) var playbackProgress: Double = 0

    // MARK: - Config

    private(set) var commentType: VoiceCommentType = .prayer

    var maxDuration: Double { commentType.maxDurationSeconds }
    var warningThreshold: Double { commentType.warningThresholdSeconds }

    // MARK: - Private

    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var recordingTimer: AnyCancellable?
    private var playbackTimer: AnyCancellable?
    private var waveformSampleCount = 60
    private var currentSamples: [Float] = Array(repeating: 0.1, count: 60)

    // MARK: - Setup

    func configure(for type: VoiceCommentType) {
        commentType = type
        reset()
    }

    // MARK: - Permission

    func requestPermissionAndStart() async {
        state = .requestingPermission
        let granted: Bool
        if #available(iOS 17.0, *) {
            granted = await AVAudioApplication.requestRecordPermission()
        } else {
            granted = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { ok in
                    continuation.resume(returning: ok)
                }
            }
        }
        if granted {
            startRecording()
        } else {
            state = .error("Microphone access is required to record a voice prayer. Enable it in Settings.")
        }
    }

    // MARK: - Recording

    func startRecording() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)

            let url = makeRecordingURL()
            let settings: [String: Any] = [
                AVFormatIDKey:            Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey:          44100,
                AVNumberOfChannelsKey:    1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
                AVEncoderBitRateKey:      64000
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            recorder.record()
            audioRecorder = recorder
            recordedFileURL = url
            elapsedSeconds = 0
            state = .recording
            startTimer()
        } catch {
            state = .error("Could not start recording: \(error.localizedDescription)")
        }
    }

    func pauseRecording() {
        guard case .recording = state else { return }
        audioRecorder?.pause()
        stopTimer()
        state = .paused
    }

    func resumeRecording() {
        guard case .paused = state else { return }
        audioRecorder?.record()
        state = .recording
        startTimer()
    }

    func stopRecording() {
        audioRecorder?.stop()
        stopTimer()
        state = .finishedRecording
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func cancelRecording() {
        audioRecorder?.stop()
        if let url = recordedFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        stopTimer()
        reset()
    }

    func reRecord() {
        if let url = recordedFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordedFileURL = nil
        elapsedSeconds = 0
        waveformSamples = Array(repeating: 0.1, count: waveformSampleCount)
        currentSamples = waveformSamples
        state = .idle
    }

    // MARK: - Playback Preview

    func playPreview() {
        guard let url = recordedFileURL, case .finishedRecording = state else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.play()
            audioPlayer = player
            state = .playingPreview
            startPlaybackTimer(duration: player.duration)
        } catch {
            state = .error("Playback failed: \(error.localizedDescription)")
        }
    }

    func stopPreview() {
        audioPlayer?.stop()
        audioPlayer = nil
        playbackTimer?.cancel()
        playbackTimer = nil
        playbackProgress = 0
        state = .finishedRecording
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Upload state forwarding (called by VoicePrayerUploadService)

    func markUploading() { state = .uploading }
    func markProcessing() { state = .processing }
    func markFinishedRecording() { state = .finishedRecording }
    func markError(_ message: String) { state = .error(message) }

    // MARK: - Helpers

    func reset() {
        audioRecorder?.stop()
        audioPlayer?.stop()
        stopTimer()
        playbackTimer?.cancel()
        recordedFileURL = nil
        elapsedSeconds = 0
        playbackProgress = 0
        isNearLimit = false
        waveformSamples = Array(repeating: 0.1, count: waveformSampleCount)
        currentSamples = waveformSamples
        state = .idle
    }

    var durationMs: Int {
        Int(elapsedSeconds * 1000)
    }

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    var isPaused: Bool {
        if case .paused = state { return true }
        return false
    }

    var isPlayingPreview: Bool {
        if case .playingPreview = state { return true }
        return false
    }

    var isFinished: Bool {
        if case .finishedRecording = state { return true }
        return false
    }

    var hasRecording: Bool {
        recordedFileURL != nil && elapsedSeconds > 0.5
    }

    // MARK: - Timer

    private func startTimer() {
        recordingTimer = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    private func stopTimer() {
        recordingTimer?.cancel()
        recordingTimer = nil
    }

    private func tick() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }
        elapsedSeconds = recorder.currentTime
        isNearLimit = elapsedSeconds >= warningThreshold
        updateWaveform(recorder: recorder)

        // Enforce hard duration limit
        if elapsedSeconds >= maxDuration {
            stopRecording()
        }
    }

    private func updateWaveform(recorder: AVAudioRecorder) {
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)
        // Convert dBFS (-160 to 0) to normalized 0–1
        let normalized = max(0, (power + 80) / 80)
        let sample = Float(max(0.05, min(1.0, normalized)))
        currentSamples.removeFirst()
        currentSamples.append(sample)
        waveformSamples = currentSamples
    }

    private func startPlaybackTimer(duration: TimeInterval) {
        playbackTimer = Timer.publish(every: 0.05, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let player = self.audioPlayer else { return }
                self.playbackProgress = player.currentTime / duration
            }
    }

    private func makeRecordingURL() -> URL {
        let temp = FileManager.default.temporaryDirectory
        return temp.appendingPathComponent("voice_prayer_\(UUID().uuidString).m4a")
    }

    // MARK: - File size guard (25 MB)

    var recordedFileSizeBytes: Int64 {
        guard let url = recordedFileURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else { return 0 }
        return size
    }

    var exceedsMaxFileSize: Bool {
        recordedFileSizeBytes > 25 * 1024 * 1024
    }
}

// MARK: - AVAudioRecorderDelegate

extension VoicePrayerAudioEngine: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            if !flag {
                self?.state = .error("Recording did not complete successfully.")
            }
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor [weak self] in
            self?.state = .error("Recording encode error: \(error?.localizedDescription ?? "unknown")")
        }
    }
}

// MARK: - AVAudioPlayerDelegate

extension VoicePrayerAudioEngine: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.playbackProgress = flag ? 1.0 : 0
            self?.playbackTimer?.cancel()
            self?.state = .finishedRecording
        }
    }
}
