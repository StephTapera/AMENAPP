// BereanDriveVoiceService.swift
// AMEN — Berean Drive CarPlay
//
// Voice input for CarPlay driving sessions:
//   - SFSpeechRecognizer for hands-free voice commands
//   - Routes recognized text to the appropriate Berean Drive mode
//   - Validates dictated message replies through BereanCarPlaySafetyGate
//   - All voice input is processed on-device first (privacy-first)
//
// CarPlay does not provide a dedicated voice input template for non-navigation apps.
// We use SFSpeechRecognizer triggered by a CarPlay list item tap (user initiates).

import Foundation
import Speech
import AVFoundation

// MARK: - Voice Command Types

enum BereanDriveVoiceCommand {
    case askBerean(question: String)
    case prayWithMe
    case summarizeChurchNotes
    case continueSession
    case findChurch(query: String?)
    case dictatedReply(text: String)
    case unknown(raw: String)
}

// MARK: - Voice Service

@MainActor
final class BereanDriveVoiceService: NSObject, ObservableObject {

    static let shared = BereanDriveVoiceService()

    // MARK: - State

    @Published private(set) var isListening: Bool = false
    @Published private(set) var recognizedText: String = ""
    @Published private(set) var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private override init() {
        super.init()
        authorizationStatus = SFSpeechRecognizer.authorizationStatus()
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor in
                    self.authorizationStatus = status
                    continuation.resume(returning: status == .authorized)
                }
            }
        }
    }

    // MARK: - Listening Lifecycle

    func startListening(completion: @escaping (BereanDriveVoiceCommand) -> Void) {
        guard authorizationStatus == .authorized else {
            dlog("⚠️ [BereanDriveVoice] Speech recognition not authorized")
            return
        }
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            dlog("⚠️ [BereanDriveVoice] Speech recognizer unavailable")
            return
        }
        guard !isListening else { return }

        stopListening()

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true    // Privacy: keep voice on-device

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            dlog("⚠️ [BereanDriveVoice] Audio engine start failed: \(error)")
            return
        }

        isListening = true
        recognizedText = ""

        // Auto-stop after 10 seconds to prevent runaway sessions while driving
        Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            await MainActor.run { self.stopListening() }
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }

                if let result {
                    self.recognizedText = result.bestTranscription.formattedString
                    if result.isFinal {
                        let command = self.parseCommand(from: result.bestTranscription.formattedString)
                        self.stopListening()
                        completion(command)
                    }
                }

                if let error {
                    let nsError = error as NSError
                    // Code 301 = "no speech detected" — not a real error in driving context
                    if nsError.code != 301 {
                        dlog("⚠️ [BereanDriveVoice] Recognition error: \(error.localizedDescription)")
                    }
                    if !self.recognizedText.isEmpty {
                        let command = self.parseCommand(from: self.recognizedText)
                        self.stopListening()
                        completion(command)
                    } else {
                        self.stopListening()
                    }
                }
            }
        }

        dlog("🎙️ [BereanDriveVoice] Listening started")
    }

    func stopListening() {
        guard isListening else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isListening = false
        dlog("🎙️ [BereanDriveVoice] Listening stopped")
    }

    // MARK: - Command Parsing

    func parseCommand(from text: String) -> BereanDriveVoiceCommand {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // "Explain Romans 8" / "Tell me about John 3:16" / Berean questions
        if normalized.hasPrefix("explain ") ||
           normalized.hasPrefix("tell me about ") ||
           normalized.hasPrefix("what does ") ||
           normalized.hasPrefix("who is ") ||
           normalized.hasPrefix("what is ") ||
           normalized.contains("berean") {
            return .askBerean(question: text)
        }

        // Prayer
        if normalized.contains("pray with me") ||
           normalized.contains("lead me in prayer") ||
           normalized.contains("prayer") {
            return .prayWithMe
        }

        // Church notes
        if normalized.contains("church notes") ||
           normalized.contains("summarize my notes") ||
           normalized.contains("sermon notes") {
            return .summarizeChurchNotes
        }

        // Session continuity
        if normalized.contains("continue") ||
           normalized.contains("resume") ||
           normalized.contains("where were we") {
            return .continueSession
        }

        // Church search
        if normalized.contains("find a church") ||
           normalized.contains("nearby church") ||
           normalized.contains("church near") {
            let query = text.replacingOccurrences(of: "find a church", with: "", options: .caseInsensitive)
                           .trimmingCharacters(in: .whitespacesAndNewlines)
            return .findChurch(query: query.isEmpty ? nil : query)
        }

        return .unknown(raw: text)
    }

    // MARK: - Driving-Safe Reply Validation

    /// Validates a dictated reply through the safety gate before allowing send.
    /// Returns nil when the reply is blocked; returns the safe text when OK.
    func validateDictatedReply(
        _ text: String,
        youthSafetyEnabled: Bool
    ) -> String? {
        let gate = BereanCarPlaySafetyGate.shared
        let result = gate.screenDictatedReply(text, youthSafetyEnabled: youthSafetyEnabled)
        switch result.outcome {
        case .safe:
            return text
        case .blocked, .requiresServerReview:
            dlog("🛡️ [BereanDriveSafety] Dictated reply blocked")
            return nil
        }
    }
}
