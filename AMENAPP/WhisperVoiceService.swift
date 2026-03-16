//
//  WhisperVoiceService.swift
//  AMENAPP
//
//  Voice-to-text using OpenAI Whisper API with automatic content moderation.
//  Records audio via AVAudioEngine, sends to Whisper for transcription,
//  then pipes the result through ContentSafetyShieldService for moderation.
//
//  Usage example:
//  ```
//  @StateObject private var voiceVM = WhisperVoiceViewModel()
//
//  Button(voiceVM.isRecording ? "Stop" : "Record") {
//      Task {
//          if voiceVM.isRecording {
//              await voiceVM.stopAndTranscribe()
//          } else {
//              await voiceVM.startRecording()
//          }
//      }
//  }
//  Text(voiceVM.transcript)
//  ```

import Foundation
import AVFoundation

// MARK: - Error Types

enum WhisperError: LocalizedError {
    case whisperFailed(String)
    case micPermissionDenied
    case recordingFailed(String)
    case noAudioData
    case apiKeyMissing

    var errorDescription: String? {
        switch self {
        case .whisperFailed(let msg): return "Transcription failed: \(msg)"
        case .micPermissionDenied: return "Microphone access is required for voice input."
        case .recordingFailed(let msg): return "Recording failed: \(msg)"
        case .noAudioData: return "No audio was recorded."
        case .apiKeyMissing: return "Whisper API key not configured."
        }
    }
}

// MARK: - Whisper Voice Service (Actor)

actor WhisperVoiceService {
    static let shared = WhisperVoiceService()

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var tempFileURL: URL?
    private var isCurrentlyRecording = false

    private var apiKey: String {
        BundleConfig.string(forKey: "OPENAI_API_KEY") ?? ""
    }

    private init() {}

    // MARK: - Public API

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

        // Check permission
        let granted = await requestMicPermission()
        guard granted else {
            throw WhisperError.micPermissionDenied
        }

        // Configure audio session
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        // Set up audio engine
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Create temp file for recording
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("whisper_recording_\(UUID().uuidString).m4a")
        tempFileURL = fileURL

        // Create output file (WAV format for Whisper compatibility)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: recordingFormat.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
        ]

        let wavURL = tempDir.appendingPathComponent("whisper_recording_\(UUID().uuidString).wav")
        tempFileURL = wavURL

        let file = try AVAudioFile(forWriting: wavURL, settings: outputSettings)
        audioFile = file

        // Install tap on input node
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { buffer, _ in
            try? file.write(from: buffer)
        }

        engine.prepare()
        try engine.start()

        audioEngine = engine
        isCurrentlyRecording = true
    }

    /// Stop recording and send audio to Whisper API for transcription.
    /// The transcribed text is automatically moderated before being returned.
    func stopAndTranscribe() async throws -> String {
        guard isCurrentlyRecording else {
            throw WhisperError.noAudioData
        }

        // Stop recording
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isCurrentlyRecording = false

        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false)

        guard let fileURL = tempFileURL,
              FileManager.default.fileExists(atPath: fileURL.path) else {
            throw WhisperError.noAudioData
        }

        // Send to Whisper API
        let transcript = try await callWhisperAPI(audioFileURL: fileURL)

        // Clean up temp file
        try? FileManager.default.removeItem(at: fileURL)
        tempFileURL = nil
        audioFile = nil

        // Moderate the transcribed text through content safety
        let moderatedTranscript = await moderateTranscript(transcript)

        return moderatedTranscript
    }

    /// Cancel recording without transcribing.
    func cancelRecording() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isCurrentlyRecording = false

        // Clean up temp file
        if let fileURL = tempFileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        tempFileURL = nil
        audioFile = nil

        try? AVAudioSession.sharedInstance().setActive(false)
    }

    var isRecording: Bool {
        isCurrentlyRecording
    }

    // MARK: - Private: Whisper API Call

    private func callWhisperAPI(audioFileURL: URL) async throws -> String {
        guard !apiKey.isEmpty else {
            throw WhisperError.apiKeyMissing
        }

        let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!

        // Build multipart form data
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let audioData = try Data(contentsOf: audioFileURL)

        var body = Data()

        // Add model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)

        // Add language hint
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("en\r\n".data(using: .utf8)!)

        // AMEN-specific Whisper prompt: helps the model handle faith + business context switching.
        // Users may quote Scripture mid-sentence while discussing a business problem —
        // the transcription needs to handle context-switching between professional and biblical language.
        let whisperPrompt = "business, entrepreneurship, innovation, technology, leadership, " +
            "Scripture, stewardship, calling, purpose, kingdom, biblical worldview, prayer, testimony. " +
            "AMEN is a faith-based social platform for Christians in business, tech, and culture. " +
            "Users discuss startups, career, leadership, and current events through a biblical lens."
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(whisperPrompt)\r\n".data(using: .utf8)!)

        // Add audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"recording.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WhisperError.whisperFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw WhisperError.whisperFailed("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        // Parse response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            throw WhisperError.whisperFailed("Failed to parse transcription response")
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private: Content Moderation

    /// Business/tech terms that should NOT be flagged as negative sentiment.
    /// AMEN covers faith-integrated topics across business, tech, and culture —
    /// "disruption," "hustle," "grind," "fail fast" are normal vocabulary.
    private let businessExclusions: Set<String> = [
        "disruption", "disrupt", "hustle", "grind", "fail fast", "pivot",
        "kill it", "crush it", "dominate", "attack the market", "aggressive growth",
        "burn rate", "war room", "execution", "cut", "slash", "take down",
        "competition", "fight", "battle", "struggle", "pain point", "friction",
    ]

    /// Run the transcribed text through ContentRiskAnalyzer for safety.
    /// Uses a higher threshold (0.90) because business/tech debate language
    /// can read as aggressive to a generic toxicity model.
    private func moderateTranscript(_ text: String) async -> String {
        // Pre-pass: skip moderation if text is primarily business vocabulary
        let lowered = text.lowercased()
        let businessTermHits = businessExclusions.filter { lowered.contains($0) }.count
        let wordCount = text.split(separator: " ").count
        let businessRatio = wordCount > 0 ? Double(businessTermHits) / Double(wordCount) : 0

        // If >15% of words are business terms, raise threshold significantly
        let threshold = businessRatio > 0.15 ? 0.95 : 0.90

        let result = ContentRiskAnalyzer.shared.analyze(text: text, context: .post)

        if result.totalScore > threshold {
            print("⚠️ Whisper transcript flagged by moderation (score: \(result.totalScore), threshold: \(threshold))")
            return "[Voice message flagged for review]"
        }

        return text
    }
}

// MARK: - SwiftUI ViewModel

@MainActor
class WhisperVoiceViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var transcript = ""
    @Published var error: WhisperError?
    @Published var isTranscribing = false

    private let service = WhisperVoiceService.shared

    func startRecording() async {
        do {
            try await service.startRecording()
            isRecording = true
            error = nil
        } catch let err as WhisperError {
            error = err
        } catch {
            self.error = .recordingFailed(error.localizedDescription)
        }
    }

    func stopAndTranscribe() async {
        isRecording = false
        isTranscribing = true

        do {
            let text = try await service.stopAndTranscribe()
            transcript = text
            error = nil
        } catch let err as WhisperError {
            error = err
        } catch {
            self.error = .whisperFailed(error.localizedDescription)
        }

        isTranscribing = false
    }

    func cancelRecording() async {
        await service.cancelRecording()
        isRecording = false
        isTranscribing = false
    }
}
