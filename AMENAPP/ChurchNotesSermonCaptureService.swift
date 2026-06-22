//
//  ChurchNotesSermonCaptureService.swift
//  AMENAPP
//
//  Silent background sermon capture with timestamp-linked paragraphs.
//  Uses AVAudioRecorder for background recording + SFSpeechRecognizer for live transcription.
//

import Foundation
import AVFoundation
import Speech
import FirebaseAuth
import FirebaseStorage
import Combine

// MARK: - Models

struct SermonCaptureSession: Codable, Identifiable {
    var id: String = UUID().uuidString
    var noteId: String
    var churchName: String?
    var speakerName: String?
    var serviceDate: Date = Date()
    var localAudioURL: String?          // local file path during capture
    var remoteAudioURL: String?         // Firebase Storage URL after upload
    var durationSeconds: Int = 0
    var isCapturing: Bool = false
    var isPaused: Bool = false
    var transcript: String?
    var timestampedParagraphs: [TimestampedParagraph] = []
    var createdAt: Date = Date()

    struct TimestampedParagraph: Codable, Identifiable {
        var id: String = UUID().uuidString
        var text: String
        var audioTimestampSeconds: Int   // where in the audio this was typed
        var detectedVerses: [String]    // auto-detected verse refs
    }
}

struct SermonCaptureState {
    var isActive: Bool = false
    var isPaused: Bool = false
    var elapsedSeconds: Int = 0
    var waveformAmplitudes: [Float] = Array(repeating: 0.3, count: 20)
    var liveTranscriptBuffer: String = ""
}

// MARK: - ChurchNotesSermonCaptureService

@MainActor
final class ChurchNotesSermonCaptureService: NSObject, ObservableObject {
    static let shared = ChurchNotesSermonCaptureService()

    @Published var captureState: SermonCaptureState = SermonCaptureState()
    @Published var currentSession: SermonCaptureSession?
    @Published var error: String?

    private var audioRecorder: AVAudioRecorder?
    private var captureTimer: Timer?

    private override init() {}

    // MARK: - Recording Control

    func startCapture(
        for noteId: String,
        churchName: String?,
        speakerName: String?
    ) async throws {
        // 1. Request microphone permission
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default, options: [.allowBluetoothHFP])
        try session.setActive(true)

        // Permission check via async/await bridge
        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
        guard granted else {
            throw SermonCaptureError.microphonePermissionDenied
        }

        // 2. Build temp file URL
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "sermon_\(noteId)_\(UUID().uuidString).m4a"
        let fileURL = tempDir.appendingPathComponent(fileName)

        // 3. Configure recorder settings (AAC, 44.1 kHz, mono)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]

        let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        recorder.isMeteringEnabled = true
        recorder.record()

        audioRecorder = recorder

        // 4. Create session
        let captureSession = SermonCaptureSession(
            noteId: noteId,
            churchName: churchName,
            speakerName: speakerName,
            serviceDate: Date(),
            localAudioURL: fileURL.path,
            isCapturing: true
        )
        currentSession = captureSession

        // 5. Start timer
        captureState = SermonCaptureState(isActive: true)
        captureTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.captureState.elapsedSeconds = Int(self.audioRecorder?.currentTime ?? 0)
                self.updateWaveform()
            }
        }

        dlog("ChurchNotesSermonCaptureService: capture started for note \(noteId)")
    }

    func pauseCapture() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }
        recorder.pause()
        captureTimer?.invalidate()
        captureTimer = nil
        captureState.isPaused = true
        captureState.isActive = false
        currentSession?.isPaused = true
        currentSession?.isCapturing = false
        dlog("ChurchNotesSermonCaptureService: capture paused")
    }

    func resumeCapture() {
        guard let recorder = audioRecorder, !recorder.isRecording else { return }
        recorder.record()
        captureState.isPaused = false
        captureState.isActive = true
        currentSession?.isPaused = false
        currentSession?.isCapturing = true

        captureTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.captureState.elapsedSeconds = Int(self.audioRecorder?.currentTime ?? 0)
                self.updateWaveform()
            }
        }
        dlog("ChurchNotesSermonCaptureService: capture resumed")
    }

    func stopCapture() async -> SermonCaptureSession? {
        captureTimer?.invalidate()
        captureTimer = nil

        guard let recorder = audioRecorder else { return nil }

        let duration = Int(recorder.currentTime)
        recorder.stop()
        audioRecorder = nil

        try? AVAudioSession.sharedInstance().setActive(false)

        captureState = SermonCaptureState()

        var finalSession = currentSession
        finalSession?.durationSeconds = duration
        finalSession?.isCapturing = false
        finalSession?.isPaused = false
        currentSession = finalSession

        dlog("ChurchNotesSermonCaptureService: capture stopped, duration \(duration)s")
        return finalSession
    }

    // MARK: - Paragraph Timestamping

    /// Links a typed paragraph to the current audio timestamp.
    func addTimestampedParagraph(_ text: String, detectedVerses: [String]) {
        let timestamp = captureState.elapsedSeconds
        let paragraph = SermonCaptureSession.TimestampedParagraph(
            text: text,
            audioTimestampSeconds: timestamp,
            detectedVerses: detectedVerses
        )
        currentSession?.timestampedParagraphs.append(paragraph)
        dlog("ChurchNotesSermonCaptureService: paragraph at \(timestamp)s — \(text.prefix(40))")
    }

    // MARK: - Post-Service Transcription

    /// Transcribes the recorded audio file using SFSpeechRecognizer.
    func transcribeAudio(session: SermonCaptureSession) async throws -> String {
        guard let localPath = session.localAudioURL else {
            throw SermonCaptureError.noAudioFile
        }
        let audioURL = URL(fileURLWithPath: localPath)

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            throw SermonCaptureError.speechRecognitionUnavailable
        }

        // Request authorization
        let authStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard authStatus == .authorized else {
            throw SermonCaptureError.speechPermissionDenied
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        request.taskHint = .dictation

        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let result, result.isFinal {
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }

    // MARK: - Upload to Firebase Storage

    /// Uploads the recorded audio to Firebase Storage and returns the download URL string.
    func uploadAudio(session: SermonCaptureSession) async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw SermonCaptureError.notAuthenticated
        }
        guard let localPath = session.localAudioURL else {
            throw SermonCaptureError.noAudioFile
        }

        let localURL = URL(fileURLWithPath: localPath)
        let storageRef = Storage.storage()
            .reference()
            .child("sermons/\(uid)/\(session.id).m4a")

        let metadata = StorageMetadata()
        metadata.contentType = "audio/mp4"

        _ = try await storageRef.putFileAsync(from: localURL, metadata: metadata)
        let downloadURL = try await storageRef.downloadURL()
        dlog("ChurchNotesSermonCaptureService: audio uploaded → \(downloadURL.absoluteString)")
        return downloadURL.absoluteString
    }

    // MARK: - Waveform

    private func updateWaveform() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)
        // Normalize: -80 dB floor → 0.0, 0 dB ceiling → 1.0
        let normalized = Float(max(0.0, min(1.0, (power + 80.0) / 80.0)))
        captureState.waveformAmplitudes.removeFirst()
        captureState.waveformAmplitudes.append(normalized)
    }
}

// MARK: - Errors

enum SermonCaptureError: LocalizedError {
    case microphonePermissionDenied
    case speechPermissionDenied
    case speechRecognitionUnavailable
    case noAudioFile
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access is required to capture sermons. Please enable it in Settings."
        case .speechPermissionDenied:
            return "Speech recognition access is required for transcription. Please enable it in Settings."
        case .speechRecognitionUnavailable:
            return "Speech recognition is not available on this device."
        case .noAudioFile:
            return "No audio recording file was found."
        case .notAuthenticated:
            return "You must be signed in to upload a recording."
        }
    }
}
