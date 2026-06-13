// VoiceRecordingEngine.swift
// AMEN — Global Resilience System
//
// @MainActor ObservableObject that owns the full voice-note lifecycle:
// recording → on-device transcription → done/error.
//
// Recording: AVAudioEngine writes a temp .m4a via AVAudioFile.
// Transcription: SFSpeechRecognizer with requiresOnDeviceRecognition=true,
//   falling back to server-mode if on-device is unsupported for the locale.
//
// All state mutations happen on the main actor. Callers must have
// NSMicrophoneUsageDescription and NSSpeechRecognitionUsageDescription in Info.plist.

import AVFoundation
import Speech
import SwiftUI

// MARK: - VoiceRecordingEngine

@MainActor
final class VoiceRecordingEngine: ObservableObject {

    // MARK: - RecordingState

    enum RecordingState: Equatable {
        case idle
        case recording
        case transcribing
        case done
        case error(String)

        static func == (lhs: RecordingState, rhs: RecordingState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle),
                 (.recording, .recording),
                 (.transcribing, .transcribing),
                 (.done, .done):
                return true
            case (.error(let a), .error(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    // MARK: - Published State

    @Published var recordingState: RecordingState = .idle
    @Published var transcriptText: String = ""
    @Published var audioURL: URL? = nil
    @Published var duration: TimeInterval = 0
    @Published var isTranscriptAvailable: Bool = false

    // MARK: - Language / Locale

    /// Locale used for the SFSpeechRecognizer. Defaults to the device locale.
    var selectedLocale: Locale = .current

    /// All locales that SFSpeechRecognizer supports, usable directly in a Picker.
    static var supportedLocales: [Locale] {
        SFSpeechRecognizer.supportedLocales()
            .sorted { a, b in
                let aName = a.localizedString(forIdentifier: a.identifier) ?? a.identifier
                let bName = b.localizedString(forIdentifier: b.identifier) ?? b.identifier
                return aName < bName
            }
    }

    // MARK: - Private AVFoundation / Speech

    private let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var tempFileURL: URL?
    private var recordingStartTime: Date?

    // Timer for tracking duration while recording.
    private var durationTimer: Timer?

    // MARK: - startRecording()

    /// Requests microphone permission, configures AVAudioSession, starts the
    /// AVAudioEngine, and writes PCM frames to a temp .m4a file.
    ///
    /// Throws if permission is denied or the engine fails to start.
    func startRecording() async throws {
        guard recordingState == .idle else { return }

        // --- Microphone permission ---
        let micPermission = await requestMicrophonePermission()
        guard micPermission else {
            throw VoiceRecordingError.microphonePermissionDenied
        }

        // --- Audio session ---
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        // --- Temp file ---
        let tmpDir = FileManager.default.temporaryDirectory
        let fileName = "amen_voice_\(UUID().uuidString).m4a"
        let fileURL = tmpDir.appendingPathComponent(fileName)
        tempFileURL = fileURL

        // --- AVAudioFile (AAC/m4a) ---
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Use a PCM format for the tap; write as AAC via AVAudioFile settings.
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: inputFormat.sampleRate,
            AVNumberOfChannelsKey: min(inputFormat.channelCount, 2),
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let avAudioFile = try AVAudioFile(
            forWriting: fileURL,
            settings: outputSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        audioFile = avAudioFile

        // --- Install tap ---
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self, let file = self.audioFile else { return }
            do {
                try file.write(from: buffer)
            } catch {
                // Non-fatal: frame dropped; engine keeps running.
                print("[VoiceRecordingEngine] write error: \(error)")
            }
        }

        // --- Start engine ---
        audioEngine.prepare()
        try audioEngine.start()

        recordingStartTime = Date()
        recordingState = .recording

        // Start duration ticker.
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let start = self.recordingStartTime else { return }
            Task { @MainActor in
                self.duration = Date().timeIntervalSince(start)
            }
        }
    }

    // MARK: - stopRecording()

    /// Stops the AVAudioEngine, finalises the audio file, then kicks off
    /// on-device transcription.
    func stopRecording() async {
        guard recordingState == .recording else { return }

        // Stop timer.
        durationTimer?.invalidate()
        durationTimer = nil

        // Final duration snapshot.
        if let start = recordingStartTime {
            duration = Date().timeIntervalSince(start)
        }
        recordingStartTime = nil

        // Stop engine and remove tap.
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        audioFile = nil

        // Deactivate session so playback can resume system-wide.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        if let url = tempFileURL {
            audioURL = url
        }

        await transcribeLocally()
    }

    // MARK: - transcribeLocally()

    /// Attempts on-device speech recognition (requiresOnDeviceRecognition = true).
    /// If that flag is unsupported for the locale, retries without it.
    /// On success: transcriptText is populated and isTranscriptAvailable = true.
    /// On failure: isTranscriptAvailable = false and recordingState = .done (not .error)
    ///   so the user can still post audio-only.
    private func transcribeLocally() async {
        guard let fileURL = audioURL else {
            isTranscriptAvailable = false
            recordingState = .done
            return
        }

        recordingState = .transcribing

        // --- Speech permission ---
        let speechPermission = await requestSpeechPermission()
        guard speechPermission else {
            isTranscriptAvailable = false
            recordingState = .done
            return
        }

        // --- Build recogniser ---
        guard let recognizer = SFSpeechRecognizer(locale: selectedLocale),
              recognizer.isAvailable else {
            isTranscriptAvailable = false
            recordingState = .done
            return
        }

        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        request.addsPunctuation = true

        // Try on-device first.
        request.requiresOnDeviceRecognition = true

        do {
            let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SFSpeechRecognitionResult, Error>) in
                recognizer.recognitionTask(with: request) { result, error in
                    if let result, result.isFinal {
                        continuation.resume(returning: result)
                    } else if let error {
                        continuation.resume(throwing: error)
                    }
                }
            }
            transcriptText = result.bestTranscription.formattedString
            isTranscriptAvailable = true
            recordingState = .done
        } catch {
            // On-device not supported → retry without the flag.
            let nsError = error as NSError
            let isOnDeviceUnsupported =
                nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 203

            if !isOnDeviceUnsupported {
                // Try without requiresOnDeviceRecognition.
                let fallbackRequest = SFSpeechURLRecognitionRequest(url: fileURL)
                fallbackRequest.shouldReportPartialResults = false
                fallbackRequest.taskHint = .dictation
                fallbackRequest.addsPunctuation = true
                // requiresOnDeviceRecognition defaults to false.

                do {
                    let fallbackResult = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SFSpeechRecognitionResult, Error>) in
                        recognizer.recognitionTask(with: fallbackRequest) { result, error in
                            if let result, result.isFinal {
                                continuation.resume(returning: result)
                            } else if let error {
                                continuation.resume(throwing: error)
                            }
                        }
                    }
                    transcriptText = fallbackResult.bestTranscription.formattedString
                    isTranscriptAvailable = true
                    recordingState = .done
                    return
                } catch {
                    // Both paths failed — fall through to isTranscriptAvailable = false.
                    print("[VoiceRecordingEngine] Fallback transcription failed: \(error)")
                }
            }

            isTranscriptAvailable = false
            recordingState = .done
        }
    }

    // MARK: - reset()

    /// Returns the engine to idle, clearing all transient state.
    /// Safe to call from any recording state.
    func reset() {
        durationTimer?.invalidate()
        durationTimer = nil
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        audioFile = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        recordingState = .idle
        transcriptText = ""
        audioURL = nil
        duration = 0
        isTranscriptAvailable = false
        recordingStartTime = nil
        if let url = tempFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        tempFileURL = nil
    }

    // MARK: - Permission Helpers

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}

// MARK: - VoiceRecordingError

enum VoiceRecordingError: LocalizedError {
    case microphonePermissionDenied
    case engineStartFailed(String)

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access is required to record voice notes. Enable it in Settings > Privacy > Microphone."
        case .engineStartFailed(let reason):
            return "Could not start the audio engine: \(reason)"
        }
    }
}
