// AILVoiceNavigationController.swift
// AMENAPP — Accessibility Intelligence Layer (AIL) · Interaction Surface (A5)
//
// Hands-free voice navigation for the core read/respond loop. Listens for a small,
// fixed command vocabulary and publishes a recognized `AILVoiceCommand` that the
// hosting view binds to (open comments, summarize, reply, save, translate).
//
// PRIVACY / IRON RULES:
//   • On-device recognition is REQUESTED via `requiresOnDeviceRecognition = true`.
//     If the locale/model cannot run on-device, we simply do not start — we never
//     silently fall back to server transcription for navigation.
//   • This controller maps recognized phrases to a tiny command enum. It does NOT
//     persist or transmit transcripts, audio, timing, or any motor/input metrics
//     (C9). The recognized text lives only long enough to match a command.
//   • Gated on AILProfileService.shared.profile.voiceNavEnabled — an explicit,
//     opt-in setting. start() is a no-op while the setting is off.
//   • No vendor names appear in any user-facing string.
//   • No tier checks — accessibility is free at every tier.

import Foundation
import SwiftUI
import Speech
import AVFoundation

/// The fixed command vocabulary voice navigation can resolve to.
enum AILVoiceCommand: String, CaseIterable, Sendable {
    case openComments
    case summarize
    case reply
    case save
    case translate
    case none

    /// Spoken phrases (lowercased) that resolve to each command. Plain language,
    /// no vendor names. Kept intentionally small to stay reliable on-device.
    var phrases: [String] {
        switch self {
        case .openComments: return ["open comments", "comments", "show comments", "read comments"]
        case .summarize:    return ["summarize", "summary", "summarise", "give me a summary"]
        case .reply:        return ["reply", "respond", "comment", "write a reply"]
        case .save:         return ["save", "bookmark", "keep this", "save this"]
        case .translate:    return ["translate", "translation", "in my language"]
        case .none:         return []
        }
    }
}

/// Authorization/availability state, surfaced for a calm UI (no raw errors).
enum AILVoiceNavStatus: Sendable {
    case idle
    case listening
    case unauthorized
    case unavailable    // on-device recognition not available for this locale
    case disabled       // voiceNavEnabled is off
}

@Observable
final class AILVoiceNavigationController {

    // MARK: Published state

    /// The most recently recognized command. Reset to `.none` by the host after
    /// it acts on a command (so the same command can fire again).
    var lastCommand: AILVoiceCommand = .none

    private(set) var status: AILVoiceNavStatus = .idle

    // MARK: Speech plumbing

    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    // MARK: Init

    init(locale: Locale = Locale.current) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
    }

    // MARK: Lifecycle

    /// Begin listening. No-op unless the user opted in. Requests authorization,
    /// requires on-device recognition, and publishes commands via `lastCommand`.
    func start() {
        guard AILProfileService.shared.profile.voiceNavEnabled else {
            status = .disabled
            return
        }
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            status = .unavailable
            return
        }

        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            guard let self else { return }
            Task { @MainActor in
                switch authStatus {
                case .authorized:
                    self.beginSession()
                case .denied, .restricted, .notDetermined:
                    self.status = .unauthorized
                @unknown default:
                    self.status = .unauthorized
                }
            }
        }
    }

    /// Stop listening and tear down the audio graph. Safe to call repeatedly.
    func stop() {
        task?.cancel()
        task = nil

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        request = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        if status == .listening {
            status = .idle
        }
    }

    // MARK: - Session

    private func beginSession() {
        // Re-check the opt-in at the moment we'd actually open the microphone.
        guard AILProfileService.shared.profile.voiceNavEnabled else {
            status = .disabled
            return
        }
        guard let recognizer, recognizer.supportsOnDeviceRecognition else {
            status = .unavailable
            return
        }

        // Tear down any prior session first.
        stop()

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            status = .unavailable
            return
        }

        let newRequest = SFSpeechAudioBufferRecognitionRequest()
        newRequest.shouldReportPartialResults = true
        // IRON RULE: navigation transcription stays on-device only.
        newRequest.requiresOnDeviceRecognition = true
        request = newRequest

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak newRequest] buffer, _ in
            newRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            status = .unavailable
            return
        }

        status = .listening

        task = recognizer.recognitionTask(with: newRequest) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let phrase = result.bestTranscription.formattedString.lowercased()
                if let command = Self.match(phrase: phrase), command != .none {
                    Task { @MainActor in self.lastCommand = command }
                }
            }
            if error != nil || (result?.isFinal ?? false) {
                Task { @MainActor in self.stop() }
            }
        }
    }

    // MARK: - Matching

    /// Resolve a recognized phrase to a command. Substring match keeps it forgiving
    /// for natural speech ("can you summarize this" → .summarize). No vendor names.
    static func match(phrase: String) -> AILVoiceCommand? {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for command in AILVoiceCommand.allCases where command != .none {
            for candidate in command.phrases where trimmed.contains(candidate) {
                return command
            }
        }
        return nil
    }
}
