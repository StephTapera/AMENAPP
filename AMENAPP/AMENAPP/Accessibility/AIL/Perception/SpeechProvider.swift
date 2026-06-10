// SpeechProvider.swift
// AMENAPP — Accessibility Intelligence Layer (AIL) · Perception Surface (A4)
//
// The SpeechProvider seam for C4 captions. Two capabilities:
//
//   • LIVE captions  — produced ON-DEVICE. Raw audio NEVER leaves the device.
//     We stream recognition results back as CaptionCue values as they arrive.
//   • RECORDED transcription — server ASR. This on-device provider deliberately
//     returns a not-supported error; a separate server adapter implements it.
//
// IRON RULES honored here:
//  • Fail OPEN — captions are an aid, never a gate. Callers must keep media
//    playing/visible even when this provider errors or is unauthorized.
//  • PRIVACY — on-device recognition only; `requiresOnDeviceRecognition` is set so
//    audio is processed locally and not sent to any service.
//  • NO vendor names in any user-facing string. NO tier checks. No force-unwraps.

import Foundation
import Speech
import AVFoundation

// MARK: - Errors

/// User-facing speech-provider failures. Messages are vendor-neutral and quiet —
/// the caller surfaces them as a non-blocking "captions unavailable" state.
enum SpeechProviderError: LocalizedError, Sendable {
    case notAuthorized
    case recognizerUnavailable
    case audioSessionFailed
    case onDeviceNotSupported     // recorded transcription is a separate server adapter

    var errorDescription: String? {
        switch self {
        case .notAuthorized:        return "Live captions need permission to use the microphone and speech recognition."
        case .recognizerUnavailable: return "Live captions aren't available for this language right now."
        case .audioSessionFailed:   return "Couldn't start the microphone for live captions."
        case .onDeviceNotSupported: return "This kind of transcription happens on the server, not on this device."
        }
    }
}

// MARK: - Contract

/// The capability surface the caption UI depends on. Both an on-device and a
/// server-backed adapter conform; the UI never knows which is in play.
protocol SpeechProviding: Sendable {
    /// Begin streaming live captions for `lang`. Each recognized fragment is
    /// delivered as a `CaptionCue` via `onCue`. Throws on auth/availability error.
    func startLiveCaptions(lang: String, onCue: @escaping (CaptionCue) -> Void) async throws

    /// Stop the live caption stream and release the audio engine.
    func stopLiveCaptions() async

    /// Transcribe an already-recorded asset. The on-device provider does not
    /// support this and throws `.onDeviceNotSupported`.
    func transcribeRecorded(mediaId: String, lang: String) async throws -> CaptionTrack
}

// MARK: - Apple on-device provider

/// On-device live-caption provider. Actor-isolated so the audio engine and the
/// recognition request are mutated from one place. Raw audio is processed on the
/// device only (`requiresOnDeviceRecognition = true`) and never uploaded.
actor AppleSpeechProvider: SpeechProviding {

    private let audioEngine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// Monotonic clock origin for cue timing (ms since capture started).
    private var captureStartMs: Int = 0

    init() {}

    // MARK: Live captions

    func startLiveCaptions(lang: String, onCue: @escaping (CaptionCue) -> Void) async throws {
        // Tear down any prior session first so we never double-tap the input node.
        await stopLiveCaptions()

        try await Self.requestAuthorization()

        let locale = Locale(identifier: lang)
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw SpeechProviderError.recognizerUnavailable
        }
        self.recognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // PRIVACY: force on-device recognition — raw audio never leaves the device.
        request.requiresOnDeviceRecognition = true
        self.request = request

        try configureAudioSession()

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw SpeechProviderError.audioSessionFailed
        }

        captureStartMs = Self.nowMs()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                let startMs = Int(result.bestTranscription.segments.first?.timestamp ?? 0) * 1000
                let lastSegment = result.bestTranscription.segments.last
                let endSec = (lastSegment?.timestamp ?? 0) + (lastSegment?.duration ?? 0)
                let endMs = Int(endSec * 1000)
                let cue = CaptionCue(startMs: startMs, endMs: max(endMs, startMs), text: text)
                onCue(cue)
            }
            if error != nil || (result?.isFinal ?? false) {
                Task { await self.stopLiveCaptions() }
            }
        }
    }

    func stopLiveCaptions() async {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        // Leave `recognizer` cached — it's cheap to reuse on the next start.
    }

    // MARK: Recorded transcription (not supported on-device)

    func transcribeRecorded(mediaId: String, lang: String) async throws -> CaptionTrack {
        // Server ASR is a separate adapter; on-device we explicitly do not handle it.
        throw SpeechProviderError.onDeviceNotSupported
    }

    // MARK: - Authorization

    /// Requests speech-recognition authorization. Throws `.notAuthorized` unless
    /// the user has granted it. Microphone permission is requested implicitly by
    /// the audio session on first capture.
    private static func requestAuthorization() async throws {
        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .authorized:
            return
        case .notDetermined:
            let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                SFSpeechRecognizer.requestAuthorization { newStatus in
                    continuation.resume(returning: newStatus == .authorized)
                }
            }
            if !granted { throw SpeechProviderError.notAuthorized }
        default:
            throw SpeechProviderError.notAuthorized
        }
    }

    // MARK: - Audio session

    private func configureAudioSession() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw SpeechProviderError.audioSessionFailed
        }
        #endif
    }

    private static func nowMs() -> Int {
        Int(Date().timeIntervalSince1970 * 1000)
    }
}
