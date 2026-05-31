// VoiceNavigationService.swift
// AMEN Universal Accessibility Engine — A7 Voice Navigation
// On-device speech recognition only. No audio leaves the device.

import Foundation
import Speech
import AVFoundation

@MainActor
final class VoiceNavigationService: ObservableObject {
    static let shared = VoiceNavigationService()

    // MARK: - Published State

    @Published private(set) var isListening: Bool = false
    @Published private(set) var lastCommand: VoiceCommand?
    @Published private(set) var commandToast: String?

    // MARK: - Voice Commands

    enum VoiceCommand: String {
        case openComments      = "open comments"
        case readTopResponse   = "read the top response"
        case scrollDown        = "scroll down"
        case scrollUp          = "scroll up"
        case goBack            = "go back"
        case openBerean        = "open berean"
        case likePost          = "like"
        case sharePost         = "share"
        case unknown
    }

    // MARK: - Private State

    private let recognizer: SFSpeechRecognizer? = {
        let r = SFSpeechRecognizer(locale: Locale.current)
        r?.defaultTaskHint = .confirmation
        return r
    }()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var toastTask: Task<Void, Never>?

    private init() {}

    // MARK: - Public API

    /// Requests speech permission and starts on-device recognition.
    /// No-ops if `a11yNavigationEnabled` is off.
    func startListening() async {
        guard TrustAccessibilityFeatureFlags.shared.a11yNavigationEnabled else { return }
        guard !isListening else { return }

        let authorized = await requestSpeechPermission()
        guard authorized else { return }

        do {
            try startAudioSession()
            try startRecognition()
            isListening = true
        } catch {
            isListening = false
        }
    }

    /// Stops the recognition session and resets state.
    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
    }

    // MARK: - Private Helpers

    private func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func startAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func startRecognition() throws {
        // Cancel any in-flight task.
        recognitionTask?.cancel()
        recognitionTask = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        // Privacy: on-device only — audio never leaves the device.
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        recognitionRequest = request

        guard let recognizer, recognizer.isAvailable else {
            throw VoiceNavigationError.recognizerUnavailable
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let transcript = result.bestTranscription.formattedString
                let command = self.parseCommand(transcript)
                if command != .unknown {
                    Task { @MainActor in
                        self.lastCommand = command
                        self.showToast(for: command)
                        self.stopListening()
                    }
                }
            }
            if error != nil {
                Task { @MainActor in
                    self.stopListening()
                }
            }
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    private func parseCommand(_ transcript: String) -> VoiceCommand {
        let lower = transcript.lowercased()
        let ordered: [VoiceCommand] = [
            .openComments,
            .readTopResponse,
            .scrollDown,
            .scrollUp,
            .goBack,
            .openBerean,
            .likePost,
            .sharePost
        ]
        for command in ordered {
            if lower.contains(command.rawValue) {
                return command
            }
        }
        return .unknown
    }

    private func showToast(for command: VoiceCommand) {
        let label: String
        switch command {
        case .openComments:    label = "Opening comments"
        case .readTopResponse: label = "Reading top response"
        case .scrollDown:      label = "Scrolling down"
        case .scrollUp:        label = "Scrolling up"
        case .goBack:          label = "Going back"
        case .openBerean:      label = "Opening Berean"
        case .likePost:        label = "Liked"
        case .sharePost:       label = "Sharing"
        case .unknown:         return
        }
        commandToast = label
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.commandToast = nil }
        }
    }
}

// MARK: - Errors

private enum VoiceNavigationError: Error {
    case recognizerUnavailable
}
