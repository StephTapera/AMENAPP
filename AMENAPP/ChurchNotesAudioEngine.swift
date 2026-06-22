//
//  ChurchNotesAudioEngine.swift
//  AMENAPP
//
//  Feature 4: Audio Recording + Transcription
//  Manages AVAudioRecorder sessions, on-device SFSpeechRecognizer transcription,
//  and Firestore persistence of sermon transcripts.
//  Post-transcription calls ClaudeService via ChurchNotesAIService to extract
//  key points, action steps, and scripture references.
//

import Foundation
import AVFoundation
import Speech
import FirebaseFirestore
import FirebaseAuth
import Combine

// MARK: - Transcript Segment

struct TranscriptSegment: Identifiable, Codable, Hashable {
    var id: String
    var timestamp: TimeInterval   // seconds from recording start
    var text: String

    init(id: String = UUID().uuidString, timestamp: TimeInterval, text: String) {
        self.id        = id
        self.timestamp = timestamp
        self.text      = text
    }
}

// MARK: - Sermon Transcript

struct SermonTranscript: Identifiable, Codable {
    var id: String
    var noteId: String
    var fullText: String
    var segments: [TranscriptSegment]
    var extractedKeyPoints: [String]
    var extractedActionSteps: [String]
    var extractedScriptureRefs: [String]
    var createdAt: Date
    var durationSeconds: Double

    init(
        id: String = UUID().uuidString,
        noteId: String,
        fullText: String,
        segments: [TranscriptSegment] = [],
        extractedKeyPoints: [String] = [],
        extractedActionSteps: [String] = [],
        extractedScriptureRefs: [String] = [],
        durationSeconds: Double = 0
    ) {
        self.id                    = id
        self.noteId                = noteId
        self.fullText              = fullText
        self.segments              = segments
        self.extractedKeyPoints    = extractedKeyPoints
        self.extractedActionSteps  = extractedActionSteps
        self.extractedScriptureRefs = extractedScriptureRefs
        self.createdAt             = Date()
        self.durationSeconds       = durationSeconds
    }

    enum CodingKeys: String, CodingKey {
        case id, noteId, fullText, segments, extractedKeyPoints,
             extractedActionSteps, extractedScriptureRefs, createdAt, durationSeconds
    }

    init(from decoder: Decoder) throws {
        let c                    = try decoder.container(keyedBy: CodingKeys.self)
        id                       = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        noteId                   = try c.decodeIfPresent(String.self, forKey: .noteId) ?? ""
        fullText                 = try c.decodeIfPresent(String.self, forKey: .fullText) ?? ""
        segments                 = try c.decodeIfPresent([TranscriptSegment].self, forKey: .segments) ?? []
        extractedKeyPoints       = try c.decodeIfPresent([String].self, forKey: .extractedKeyPoints) ?? []
        extractedActionSteps     = try c.decodeIfPresent([String].self, forKey: .extractedActionSteps) ?? []
        extractedScriptureRefs   = try c.decodeIfPresent([String].self, forKey: .extractedScriptureRefs) ?? []
        createdAt                = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        durationSeconds          = try c.decodeIfPresent(Double.self, forKey: .durationSeconds) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(noteId, forKey: .noteId)
        try c.encode(fullText, forKey: .fullText)
        try c.encode(segments, forKey: .segments)
        try c.encode(extractedKeyPoints, forKey: .extractedKeyPoints)
        try c.encode(extractedActionSteps, forKey: .extractedActionSteps)
        try c.encode(extractedScriptureRefs, forKey: .extractedScriptureRefs)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(durationSeconds, forKey: .durationSeconds)
    }
}

// MARK: - Audio Recording Session

/// Wraps AVAudioRecorder and manages WAV file creation.
final class AudioRecordingSession: NSObject {

    private var recorder: AVAudioRecorder?
    private var startTime: Date?
    private(set) var outputURL: URL?
    private(set) var isPaused = false

    // MARK: - Start

    func startRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default, options: [.allowBluetoothHFP])
        try session.setActive(true)

        let dir      = FileManager.default.temporaryDirectory
        let filename = "sermon_\(Int(Date().timeIntervalSince1970)).wav"
        let url      = dir.appendingPathComponent(filename)
        outputURL    = url

        let settings: [String: Any] = [
            AVFormatIDKey:             Int(kAudioFormatLinearPCM),
            AVSampleRateKey:           16000,
            AVNumberOfChannelsKey:     1,
            AVLinearPCMBitDepthKey:    16,
            AVLinearPCMIsFloatKey:     false,
            AVLinearPCMIsBigEndianKey: false,
            AVEncoderAudioQualityKey:  AVAudioQuality.high.rawValue
        ]

        recorder  = try AVAudioRecorder(url: url, settings: settings)
        recorder?.delegate = self
        recorder?.isMeteringEnabled = true
        recorder?.record()
        startTime = Date()
        isPaused  = false
    }

    // MARK: - Stop

    /// Stops recording and returns the output file URL.
    func stopRecording() -> URL? {
        recorder?.stop()
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return outputURL
    }

    // MARK: - Pause / Resume

    func pauseRecording() {
        recorder?.pause()
        isPaused = true
    }

    func resumeRecording() {
        recorder?.record()
        isPaused = false
    }

    // MARK: - Metering

    /// Returns the current average power in dB (-160 to 0).
    func averagePower() -> Float {
        recorder?.updateMeters()
        return recorder?.averagePower(forChannel: 0) ?? -160
    }

    // MARK: - Duration

    var elapsedSeconds: TimeInterval {
        guard let start = startTime else { return 0 }
        return Date().timeIntervalSince(start)
    }
}

extension AudioRecordingSession: AVAudioRecorderDelegate {
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error { print("[AudioRecordingSession] Encode error: \(error)") }
    }
}

// MARK: - Church Notes Audio Engine

@MainActor
final class ChurchNotesAudioEngine: NSObject, ObservableObject {
    static let shared = ChurchNotesAudioEngine()

    @Published var isRecording       = false
    @Published var isPaused          = false
    @Published var isTranscribing    = false
    @Published var elapsedSeconds    = 0
    @Published var transcript: SermonTranscript?
    @Published var lastError: Error?
    @Published var averagePower: Float = -160   // live metering for waveform

    private var session             = AudioRecordingSession()
    private var elapsedTimer: Timer?
    private var meterTimer: Timer?
    private let db                  = Firestore.firestore()

    private override init() { super.init() }

    // MARK: - Permission

    func requestMicrophonePermission() async -> Bool {
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        } else {
            return await withCheckedContinuation { cont in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    cont.resume(returning: granted)
                }
            }
        }
    }

    func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }

    // MARK: - Start Recording

    func startRecording() async throws {
        let micOK    = await requestMicrophonePermission()
        let speechOK = await requestSpeechPermission()
        guard micOK else { throw AudioEngineError.microphonePermissionDenied }
        guard speechOK else { throw AudioEngineError.speechPermissionDenied }

        session = AudioRecordingSession()
        try session.startRecording()

        isRecording    = true
        isPaused       = false
        elapsedSeconds = 0

        startTimers()
    }

    // MARK: - Stop Recording

    func stopRecording() -> URL? {
        stopTimers()
        let url      = session.stopRecording()
        isRecording  = false
        isPaused     = false
        averagePower = -160
        return url
    }

    // MARK: - Pause / Resume

    func pauseRecording() {
        session.pauseRecording()
        isPaused = true
        stopTimers()
    }

    func resumeRecording() {
        session.resumeRecording()
        isPaused = false
        startTimers()
    }

    // MARK: - Transcription

    /// On-device transcription via SFSpeechRecognizer.
    /// After transcription, calls ClaudeService to extract key points, action steps,
    /// and scripture references, then persists the full result to Firestore.
    func transcribeRecording(url: URL, noteId: String) async throws {
        isTranscribing = true
        defer { isTranscribing = false }

        let fullText: String
        let segments: [TranscriptSegment]

        do {
            (fullText, segments) = try await performOnDeviceTranscription(url: url)
        } catch {
            lastError = error
            throw error
        }

        // Extract structured insights via Claude
        var keyPoints: [String] = []
        var actionSteps: [String] = []
        var scriptureRefs: [String] = []
        do {
            keyPoints     = try await extractKeyPointsFromTranscript(fullText)
            actionSteps   = try await extractActionStepsFromTranscript(fullText)
            scriptureRefs = ChurchNotesScriptureDetector.shared.detectReferenceStrings(in: fullText)
        } catch {
            // If Claude fails, fall back to empty arrays — transcript still saved
            scriptureRefs = ChurchNotesScriptureDetector.shared.detectReferenceStrings(in: fullText)
        }

        let result = SermonTranscript(
            noteId:                noteId,
            fullText:              fullText,
            segments:              segments,
            extractedKeyPoints:    keyPoints,
            extractedActionSteps:  actionSteps,
            extractedScriptureRefs: scriptureRefs,
            durationSeconds:       session.elapsedSeconds
        )

        try await persistTranscript(result, noteId: noteId)
        transcript = result
    }

    // MARK: - Persist Transcript

    private func persistTranscript(_ transcript: SermonTranscript, noteId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AudioEngineError.notAuthenticated
        }

        let ref  = db.collection("users")
                     .document(uid)
                     .collection("churchNotes")
                     .document(noteId)
                     .collection("transcript")
                     .document(transcript.id)

        let data = try Firestore.Encoder().encode(transcript)
        try await ref.setData(data)
    }

    // MARK: - Fetch Transcript

    func fetchTranscript(for noteId: String) async throws -> SermonTranscript? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }

        let snapshot = try await db
            .collection("users")
            .document(uid)
            .collection("churchNotes")
            .document(noteId)
            .collection("transcript")
            .order(by: "createdAt", descending: true)
            .limit(to: 1)
            .getDocuments()

        return try snapshot.documents.first.map { try $0.data(as: SermonTranscript.self) }
    }

    // MARK: - On-Device Transcription

    private func performOnDeviceTranscription(url: URL) async throws -> (String, [TranscriptSegment]) {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            throw AudioEngineError.speechRecognizerUnavailable
        }

        let request                             = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition     = false   // allow server if on-device not available
        request.shouldReportPartialResults      = false
        request.taskHint                        = .dictation

        return try await withCheckedThrowingContinuation { cont in
            var called = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !called else { return }
                if let error {
                    called = true
                    cont.resume(throwing: error)
                    return
                }
                guard let result, result.isFinal else { return }
                called = true

                let fullText = result.bestTranscription.formattedString
                let segments = result.bestTranscription.segments.map { seg in
                    TranscriptSegment(
                        timestamp: seg.timestamp,
                        text: seg.substring
                    )
                }
                cont.resume(returning: (fullText, segments))
            }
        }
    }

    // MARK: - Claude Extraction Helpers

    private func extractKeyPointsFromTranscript(_ text: String) async throws -> [String] {
        let prompt = """
        Extract 3-5 key points from this sermon transcript. Return each point on its own line starting with •. Be concise.

        Transcript:
        \(text.prefix(3000))
        """
        var result = ""
        for try await chunk in ClaudeService.shared.sendMessage(prompt) {
            result += chunk
        }
        return result.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("•") }
            .map { String($0.dropFirst()).trimmingCharacters(in: .whitespaces) }
    }

    private func extractActionStepsFromTranscript(_ text: String) async throws -> [String] {
        let prompt = """
        From this sermon transcript, extract 2-4 specific action steps a believer should take this week. Return each step on its own line starting with •.

        Transcript:
        \(text.prefix(3000))
        """
        var result = ""
        for try await chunk in ClaudeService.shared.sendMessage(prompt) {
            result += chunk
        }
        return result.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("•") }
            .map { String($0.dropFirst()).trimmingCharacters(in: .whitespaces) }
    }

    // MARK: - Timers

    private func startTimers() {
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.elapsedSeconds += 1 }
        }
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.averagePower = self.session.averagePower()
            }
        }
    }

    private func stopTimers() {
        elapsedTimer?.invalidate(); elapsedTimer = nil
        meterTimer?.invalidate();   meterTimer   = nil
    }

    // MARK: - Formatted Duration

    func formattedDuration() -> String {
        let m = elapsedSeconds / 60
        let s = elapsedSeconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Errors

enum AudioEngineError: LocalizedError {
    case microphonePermissionDenied
    case speechPermissionDenied
    case speechRecognizerUnavailable
    case notAuthenticated
    case recordingFailed

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:   return "Microphone access is required to record sermons. Enable it in Settings."
        case .speechPermissionDenied:       return "Speech recognition access is required for transcription. Enable it in Settings."
        case .speechRecognizerUnavailable:  return "Speech recognition is not available on this device."
        case .notAuthenticated:             return "You must be signed in to save transcripts."
        case .recordingFailed:              return "Recording could not be started."
        }
    }
}
