//
//  BereanVoice.swift
//  AMENAPP
//
//  Voice interaction for Berean AI:
//  - Voice input: On-device Speech framework for hands-free questions
//  - Voice output: AVSpeechSynthesizer for verse readings and devotionals
//  - Accessibility: Full VoiceOver support
//

import Foundation
import Speech
import AVFoundation
import Combine

// MARK: - Voice State

enum VoiceInputState {
    case idle
    case listening
    case processing
    case error(String)
}

enum VoiceOutputState {
    case idle
    case speaking
    case paused
}

// MARK: - Voice Service

@MainActor
final class BereanVoice: ObservableObject {
    static let shared = BereanVoice()

    // Input
    @Published var inputState: VoiceInputState = .idle
    @Published var transcript: String = ""
    @Published var isListening = false

    // Output
    @Published var outputState: VoiceOutputState = .idle
    @Published var isSpeaking = false
    @Published var speechProgress: Double = 0.0

    // Permissions
    @Published var speechPermissionGranted = false
    @Published var microphonePermissionGranted = false

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private var synthesizerDelegate: SpeechDelegate?

    // Settings
    private let preferredLocale = Locale(identifier: "en-US")
    private let speechRate: Float = 0.48  // Slightly slower for Bible reading
    private let speechPitch: Float = 1.0
    private let speechVolume: Float = 1.0

    private init() {
        speechRecognizer = SFSpeechRecognizer(locale: preferredLocale)
        synthesizerDelegate = SpeechDelegate(voice: self)
        synthesizer.delegate = synthesizerDelegate
    }

    // MARK: - Permissions

    func requestPermissions() async -> Bool {
        // Speech recognition permission
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        speechPermissionGranted = speechStatus == .authorized

        // Microphone permission
        if #available(iOS 17.0, *) {
            microphonePermissionGranted = await AVAudioApplication.requestRecordPermission()
        } else {
            microphonePermissionGranted = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }

        return speechPermissionGranted && microphonePermissionGranted
    }

    // MARK: - Voice Input (Speech-to-Text)

    /// Start listening for voice input
    func startListening() async throws {
        guard speechPermissionGranted, microphonePermissionGranted else {
            inputState = .error("Microphone or speech permission not granted")
            return
        }

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            inputState = .error("Speech recognition not available")
            return
        }

        // Cancel any existing task
        stopListening()

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else {
            inputState = .error("Failed to create recognition request")
            return
        }

        request.shouldReportPartialResults = true

        // For on-device recognition (privacy + speed)
        if #available(iOS 13, *) {
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }
        }

        // Start recognition task
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self else { return }

                if let result = result {
                    self.transcript = result.bestTranscription.formattedString

                    if result.isFinal {
                        self.inputState = .processing
                        self.isListening = false
                    }
                }

                if let error = error {
                    self.inputState = .error(error.localizedDescription)
                    self.isListening = false
                    self.stopListening()
                }
            }
        }

        // Start audio engine
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        inputState = .listening
        isListening = true
        transcript = ""

        print("🎤 BereanVoice: Listening started")
    }

    /// Stop listening and finalize transcript
    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        if isListening {
            inputState = transcript.isEmpty ? .idle : .processing
            isListening = false
        }

        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false)

        print("🎤 BereanVoice: Listening stopped")
    }

    /// Get the final transcript and reset
    func finalizeTranscript() -> String {
        let result = transcript
        transcript = ""
        inputState = .idle
        return result
    }

    // MARK: - Voice Output (Text-to-Speech)

    /// Speak text aloud (for verse readings, devotionals, answers)
    func speak(_ text: String, rate: Float? = nil) {
        // Stop any current speech
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = rate ?? speechRate
        utterance.pitchMultiplier = speechPitch
        utterance.volume = speechVolume

        // Use a warm, clear voice
        if let premiumVoice = AVSpeechSynthesisVoice(identifier: "com.apple.voice.premium.en-US.Ava") {
            utterance.voice = premiumVoice
        }

        // Configure audio session for playback
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("⚠️ BereanVoice: Audio session error: \(error.localizedDescription)")
        }

        outputState = .speaking
        isSpeaking = true
        speechProgress = 0.0

        synthesizer.speak(utterance)
        print("🔊 BereanVoice: Speaking \(text.prefix(50))...")
    }

    /// Speak a Bible verse with appropriate pacing
    func speakVerse(_ verseText: String, reference: String) {
        let fullText = "\(reference). \(verseText)"
        speak(fullText, rate: 0.42)  // Slower for verse reading
    }

    /// Speak a devotional
    func speakDevotional(_ devotional: Devotional) {
        let text = """
        \(devotional.title).

        \(devotional.scripture).

        \(devotional.content)

        Prayer: \(devotional.prayer)
        """
        speak(text, rate: 0.45)
    }

    /// Pause speech
    func pauseSpeech() {
        if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .word)
            outputState = .paused
            isSpeaking = false
        }
    }

    /// Resume speech
    func resumeSpeech() {
        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
            outputState = .speaking
            isSpeaking = true
        }
    }

    /// Stop speech
    func stopSpeech() {
        synthesizer.stopSpeaking(at: .immediate)
        outputState = .idle
        isSpeaking = false
        speechProgress = 0.0

        try? AVAudioSession.sharedInstance().setActive(false)
    }

    // MARK: - Speech Delegate

    fileprivate func didFinishSpeaking() {
        outputState = .idle
        isSpeaking = false
        speechProgress = 1.0

        try? AVAudioSession.sharedInstance().setActive(false)
    }

    fileprivate func didUpdateProgress(_ progress: Double) {
        speechProgress = progress
    }
}

// MARK: - Speech Synthesizer Delegate

private class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
    private weak var voice: BereanVoice?

    init(voice: BereanVoice) {
        self.voice = voice
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            voice?.didFinishSpeaking()
        }
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        let progress = Double(characterRange.location + characterRange.length) /
            Double(utterance.speechString.count)
        Task { @MainActor in
            voice?.didUpdateProgress(progress)
        }
    }
}
