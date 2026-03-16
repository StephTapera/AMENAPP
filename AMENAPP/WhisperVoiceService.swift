//
//  WhisperVoiceService.swift
//  AMENAPP
//
//  Voice-to-text using OpenAI Whisper API with:
//  - AMEN-specific faith+business domain prompt
//  - Apple SFSpeechRecognizer offline fallback
//  - Per-user daily audio cost caps (Firestore-tracked)
//  - Automatic content moderation with business-vocabulary exclusions
//  - Haptic feedback, confidence scoring, multi-language support
//  - Recording consent banner and privacy-first temp file cleanup
//
//  Usage:
//  ```
//  @StateObject private var voiceVM = WhisperVoiceViewModel()
//
//  Button(voiceVM.isRecording ? "Stop" : "Record") {
//      Task {
//          if voiceVM.isRecording { await voiceVM.stopAndTranscribe() }
//          else { await voiceVM.startRecording() }
//      }
//  }
//  .accessibilityLabel(voiceVM.isRecording ? "Stop recording" : "Start voice input")
//  .accessibilityHint("Double tap to toggle voice recording")
//  Text(voiceVM.transcript)
//  ```

import Foundation
import AVFoundation
import Speech
import FirebaseAuth
import FirebaseFirestore
import UIKit

// MARK: - Error Types

enum WhisperError: LocalizedError {
    case whisperFailed(String)
    case micPermissionDenied
    case recordingFailed(String)
    case noAudioData
    case apiKeyMissing
    case lowConfidence(transcript: String, confidence: Double)
    case dailyLimitReached
    case voiceDisabled

    var errorDescription: String? {
        switch self {
        case .whisperFailed(let msg): return "Transcription failed: \(msg)"
        case .micPermissionDenied: return "Microphone access is required for voice input."
        case .recordingFailed(let msg): return "Recording failed: \(msg)"
        case .noAudioData: return "No audio was recorded."
        case .apiKeyMissing: return "Voice service not configured."
        case .lowConfidence: return "Couldn't hear you clearly. Please try again."
        case .dailyLimitReached: return "Daily voice limit reached. Try again tomorrow."
        case .voiceDisabled: return "Voice input is not available."
        }
    }
}

// MARK: - Transcription Result

struct WhisperTranscriptionResult {
    let text: String
    let confidence: Double // 0.0–1.0 (estimated from Whisper's avg_logprob)
    let language: String
    let durationSeconds: Double
    let engine: TranscriptionEngine

    enum TranscriptionEngine: String {
        case whisper = "whisper"
        case appleOnDevice = "apple_on_device"
    }
}

// MARK: - Whisper Voice Service (Actor)

actor WhisperVoiceService {
    static let shared = WhisperVoiceService()

    // MARK: - Configuration

    /// Language code for transcription (ISO 639-1). Default "en".
    /// Whisper supports 57 languages — set this to serve Spanish, Swahili,
    /// Portuguese-speaking Christian communities without refactoring.
    var languageCode: String = "en"

    /// Minimum confidence threshold (0.0–1.0). Below this, the user is prompted to re-record.
    var confidenceThreshold: Double = 0.4

    /// Maximum audio seconds per user per day (cost control).
    /// Whisper charges ~$0.006/min. Default 300s = 5 min/day = ~$0.03/day max.
    var dailyAudioLimitSeconds: Double = 300

    // MARK: - Private State

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var tempFileURL: URL?
    private var isCurrentlyRecording = false
    private var recordingStartTime: Date?

    private var apiKey: String {
        BundleConfig.string(forKey: "OPENAI_API_KEY") ?? ""
    }

    private let db = Firestore.firestore()

    private init() {}

    // MARK: - Public API

    /// Whether voice features are enabled for this user.
    var isVoiceEnabled: Bool {
        UserDefaults.standard.bool(forKey: "isVoiceEnabled_\(Auth.auth().currentUser?.uid ?? "")") != false
        && UserDefaults.standard.object(forKey: "isVoiceEnabled_\(Auth.auth().currentUser?.uid ?? "")") != nil
        || UserDefaults.standard.object(forKey: "isVoiceEnabled_\(Auth.auth().currentUser?.uid ?? "")") == nil // default true for new users
    }

    /// Whether the user has accepted the voice recording consent.
    var hasAcceptedVoiceConsent: Bool {
        UserDefaults.standard.bool(forKey: "voiceRecordingConsentAccepted")
    }

    /// Mark voice consent as accepted.
    func acceptVoiceConsent() {
        UserDefaults.standard.set(true, forKey: "voiceRecordingConsentAccepted")
    }

    /// Request microphone permission. Returns true if granted.
    func requestMicPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Start recording audio from the microphone.
    func startRecording() async throws {
        guard !isCurrentlyRecording else { return }

        // Check daily limit
        guard await hasRemainingQuota() else {
            throw WhisperError.dailyLimitReached
        }

        // Check permission — graceful fallback to keyboard if denied
        let granted = await requestMicPermission()
        guard granted else {
            throw WhisperError.micPermissionDenied
        }

        // Configure audio session
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Create temp WAV file
        let tempDir = FileManager.default.temporaryDirectory
        let wavURL = tempDir.appendingPathComponent("whisper_\(UUID().uuidString).wav")
        tempFileURL = wavURL

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: recordingFormat.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
        ]

        let file = try AVAudioFile(forWriting: wavURL, settings: outputSettings)
        audioFile = file

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { buffer, _ in
            try? file.write(from: buffer)
        }

        engine.prepare()
        try engine.start()

        audioEngine = engine
        isCurrentlyRecording = true
        recordingStartTime = Date()
    }

    /// Stop recording and transcribe. Returns a result with text + confidence.
    /// Falls back to Apple SFSpeechRecognizer if Whisper is unavailable or quota exceeded.
    func stopAndTranscribe() async throws -> WhisperTranscriptionResult {
        guard isCurrentlyRecording else {
            throw WhisperError.noAudioData
        }

        // Stop recording
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isCurrentlyRecording = false

        let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        recordingStartTime = nil

        try? AVAudioSession.sharedInstance().setActive(false)

        guard let fileURL = tempFileURL,
              FileManager.default.fileExists(atPath: fileURL.path) else {
            throw WhisperError.noAudioData
        }

        defer {
            // PRIVACY: Always delete temp audio immediately after processing
            try? FileManager.default.removeItem(at: fileURL)
            tempFileURL = nil
            audioFile = nil
        }

        // Try Whisper API first, fall back to Apple on-device
        do {
            guard !apiKey.isEmpty else {
                throw WhisperError.apiKeyMissing
            }
            guard await hasRemainingQuota() else {
                throw WhisperError.dailyLimitReached
            }

            let result = try await callWhisperAPI(audioFileURL: fileURL, durationSeconds: duration)

            // Track usage for cost control
            await trackAudioUsage(seconds: duration)

            // Check confidence
            if result.confidence < confidenceThreshold {
                throw WhisperError.lowConfidence(transcript: result.text, confidence: result.confidence)
            }

            // Moderate before returning
            let moderated = await moderateTranscript(result.text)
            return WhisperTranscriptionResult(
                text: moderated,
                confidence: result.confidence,
                language: result.language,
                durationSeconds: duration,
                engine: .whisper
            )
        } catch let error as WhisperError where error.isRetryableWithFallback {
            // Fall back to Apple SFSpeechRecognizer (offline, free)
            let fallbackText = try await appleSpeechFallback(audioFileURL: fileURL)
            let moderated = await moderateTranscript(fallbackText)
            return WhisperTranscriptionResult(
                text: moderated,
                confidence: 0.6, // Apple doesn't expose confidence easily
                language: languageCode,
                durationSeconds: duration,
                engine: .appleOnDevice
            )
        }
    }

    /// Cancel recording without transcribing.
    func cancelRecording() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isCurrentlyRecording = false
        recordingStartTime = nil

        if let fileURL = tempFileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        tempFileURL = nil
        audioFile = nil

        try? AVAudioSession.sharedInstance().setActive(false)
    }

    var isRecording: Bool { isCurrentlyRecording }

    // MARK: - Whisper API

    private func callWhisperAPI(audioFileURL: URL, durationSeconds: Double) async throws -> WhisperTranscriptionResult {
        let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        let boundary = UUID().uuidString

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let audioData = try Data(contentsOf: audioFileURL)
        var body = Data()

        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        field("model", "whisper-1")
        field("language", languageCode)
        field("response_format", "verbose_json") // Get confidence scores

        // AMEN domain prompt
        let prompt = "business, entrepreneurship, innovation, technology, leadership, " +
            "Scripture, stewardship, calling, purpose, kingdom, biblical worldview, prayer, testimony. " +
            "AMEN is a faith-based social platform for Christians in business, tech, and culture. " +
            "Users discuss startups, career, leadership, and current events through a biblical lens. " +
            "Users may quote Scripture mid-sentence while discussing a business problem."
        field("prompt", prompt)

        // Audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"recording.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw WhisperError.whisperFailed(errorBody)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            throw WhisperError.whisperFailed("Failed to parse response")
        }

        // Extract confidence from verbose_json (avg_logprob → approximate confidence)
        let segments = json["segments"] as? [[String: Any]]
        let avgLogprob = segments?.compactMap { $0["avg_logprob"] as? Double }.reduce(0, +)
            .flatMap { total in segments.map { Double(total) / Double($0.count) } } ?? -0.5
        let confidence = max(0, min(1, 1.0 + (avgLogprob ?? -0.5))) // logprob is negative; -0 = perfect

        let detectedLang = json["language"] as? String ?? languageCode

        return WhisperTranscriptionResult(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            confidence: confidence,
            language: detectedLang,
            durationSeconds: durationSeconds,
            engine: .whisper
        )
    }

    // MARK: - Apple SFSpeechRecognizer Fallback (Offline)

    private func appleSpeechFallback(audioFileURL: URL) async throws -> String {
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: languageCode))
        guard let recognizer, recognizer.isAvailable else {
            throw WhisperError.whisperFailed("On-device speech recognition unavailable")
        }

        let speechRequest = SFSpeechURLRecognitionRequest(url: audioFileURL)
        speechRequest.shouldReportPartialResults = false
        speechRequest.requiresOnDeviceRecognition = true

        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: speechRequest) { result, error in
                if let error {
                    continuation.resume(throwing: WhisperError.whisperFailed(error.localizedDescription))
                } else if let result, result.isFinal {
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }

    // MARK: - Cost Control (Firestore-tracked)

    /// Check if user has remaining audio quota for today.
    private func hasRemainingQuota() async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        let today = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        let docId = "\(uid)_\(Int(today))"

        do {
            let doc = try await db.collection("whisperUsage").document(docId).getDocument()
            let usedSeconds = doc.data()?["totalSeconds"] as? Double ?? 0
            return usedSeconds < dailyAudioLimitSeconds
        } catch {
            return true // Allow on error (non-blocking)
        }
    }

    /// Track audio usage for cost control.
    private func trackAudioUsage(seconds: Double) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let today = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        let docId = "\(uid)_\(Int(today))"

        try? await db.collection("whisperUsage").document(docId).setData([
            "userId": uid,
            "date": today,
            "totalSeconds": FieldValue.increment(seconds),
            "requestCount": FieldValue.increment(Int64(1)),
            "updatedAt": FieldValue.serverTimestamp(),
        ], merge: true)
    }

    // MARK: - Content Moderation

    private let businessExclusions: Set<String> = [
        "disruption", "disrupt", "hustle", "grind", "fail fast", "pivot",
        "kill it", "crush it", "dominate", "attack the market", "aggressive growth",
        "burn rate", "war room", "execution", "cut", "slash", "take down",
        "competition", "fight", "battle", "struggle", "pain point", "friction",
    ]

    private func moderateTranscript(_ text: String) async -> String {
        let lowered = text.lowercased()
        let businessTermHits = businessExclusions.filter { lowered.contains($0) }.count
        let wordCount = text.split(separator: " ").count
        let businessRatio = wordCount > 0 ? Double(businessTermHits) / Double(wordCount) : 0
        let threshold = businessRatio > 0.15 ? 0.95 : 0.90

        let result = ContentRiskAnalyzer.shared.analyze(text: text, context: .post)

        if result.totalScore > threshold {
            return "[Voice message flagged for review]"
        }
        return text
    }
}

// MARK: - Error Extension

extension WhisperError {
    /// Whether this error should trigger a fallback to Apple on-device recognition.
    var isRetryableWithFallback: Bool {
        switch self {
        case .apiKeyMissing, .dailyLimitReached, .whisperFailed: return true
        default: return false
        }
    }
}

// MARK: - SwiftUI ViewModel

@MainActor
class WhisperVoiceViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var transcript = ""
    @Published var error: WhisperError?
    @Published var isTranscribing = false
    @Published var lastResult: WhisperTranscriptionResult?
    @Published var showConsentBanner = false
    @Published var needsReRecord = false

    private let service = WhisperVoiceService.shared

    /// Start recording with haptic feedback.
    func startRecording() async {
        // Check consent
        let hasConsent = await service.hasAcceptedVoiceConsent
        if !hasConsent {
            showConsentBanner = true
            return
        }

        do {
            try await service.startRecording()
            isRecording = true
            error = nil
            needsReRecord = false
            // Haptic: light tap on recording start
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch let err as WhisperError {
            error = err
            // Haptic: error pattern on failure
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        } catch {
            self.error = .recordingFailed(error.localizedDescription)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    /// Stop recording, transcribe, and moderate.
    func stopAndTranscribe() async {
        isRecording = false
        isTranscribing = true
        // Haptic: heavy impact on stop
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

        do {
            let result = try await service.stopAndTranscribe()
            transcript = result.text
            lastResult = result
            error = nil
            needsReRecord = false
        } catch let err as WhisperError {
            if case .lowConfidence(let text, _) = err {
                transcript = text // Show low-confidence text for user to edit
                needsReRecord = true
            }
            error = err
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        } catch {
            self.error = .whisperFailed(error.localizedDescription)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }

        isTranscribing = false
    }

    func cancelRecording() async {
        await service.cancelRecording()
        isRecording = false
        isTranscribing = false
    }

    /// User accepted the consent banner.
    func acceptConsent() async {
        await service.acceptVoiceConsent()
        showConsentBanner = false
        // Now start recording
        await startRecording()
    }

    /// User declined voice — graceful degrade to keyboard.
    func declineConsent() {
        showConsentBanner = false
    }
}
