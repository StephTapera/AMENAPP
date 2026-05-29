// BereanTranscriptionService.swift
// AMEN App — Berean Multimodal Foundation (Agent 0)
//
// On-device Speech transcription with a swappable provider abstraction.
// Default: Apple Speech on-device (SFSpeechRecognizer, requiresOnDeviceRecognition = true)
// — the most privacy-preserving option, no audio leaves the device.
//
// POLICY DECISION: transcription provider is controlled by Remote Config key
// "berean_transcription_provider" = "apple_on_device" (default) | "cloud_stt"
// Switch to "cloud_stt" only for languages not supported on-device.

import Foundation
import Speech
import AVFoundation

// MARK: - Transcript

struct BereanTranscript: Equatable {
    let text: String
    let confidence: Double    // 0–1
    let locale: Locale
    let provider: String
    let processedAt: Date

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

// MARK: - Provider Protocol

protocol BereanTranscriptionProvider: Sendable {
    var identifier: String { get }
    func transcribe(audioURL: URL, locale: Locale) async throws -> BereanTranscript
}

// MARK: - Errors

enum BereanTranscriptionError: Error, LocalizedError {
    case notAuthorized
    case recognizerUnavailable(String)
    case recognitionFailed(String)
    case noResult

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Speech recognition permission is required. Enable it in Settings > Privacy."
        case .recognizerUnavailable(let locale):
            return "Speech recognition is not available for \(locale)."
        case .recognitionFailed(let msg):
            return "Transcription failed: \(msg)"
        case .noResult:
            return "No speech was detected in the recording."
        }
    }
}

// MARK: - Apple On-Device Provider (default)

final class AppleOnDeviceTranscriptionProvider: BereanTranscriptionProvider {
    let identifier = "apple_on_device"

    func transcribe(audioURL: URL, locale: Locale) async throws -> BereanTranscript {
        let status = SFSpeechRecognizer.authorizationStatus()
        guard status == .authorized else {
            throw BereanTranscriptionError.notAuthorized
        }

        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw BereanTranscriptionError.recognizerUnavailable(locale.identifier)
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.requiresOnDeviceRecognition = true  // Privacy: audio never leaves device
        request.shouldReportPartialResults = false
        request.addsPunctuation = true

        return try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !resumed else { return }
                if let error = error {
                    resumed = true
                    continuation.resume(throwing: BereanTranscriptionError.recognitionFailed(error.localizedDescription))
                    return
                }
                guard let result, result.isFinal else { return }
                resumed = true
                let segments = result.bestTranscription.segments
                let avgConf = segments.isEmpty ? 0.0
                    : Double(segments.map(\.confidence).reduce(0, +)) / Double(segments.count)
                continuation.resume(returning: BereanTranscript(
                    text: result.bestTranscription.formattedString,
                    confidence: avgConf,
                    locale: locale,
                    provider: "apple_on_device",
                    processedAt: Date()
                ))
            }
        }
    }
}

// MARK: - Service

@MainActor
final class BereanTranscriptionService: ObservableObject {

    static let shared = BereanTranscriptionService()

    @Published private(set) var isTranscribing = false
    @Published private(set) var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = SFSpeechRecognizer.authorizationStatus()

    // Swappable provider — Remote Config or tests can replace this
    var provider: any BereanTranscriptionProvider = AppleOnDeviceTranscriptionProvider()

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        authorizationStatus = status
        return status == .authorized
    }

    // MARK: - Transcription

    /// Transcribe an audio file. Returns transcript text.
    /// Callers must pass the transcript through prePublishSafetyScan before publishing.
    func transcribe(audioURL: URL, locale: Locale = .current) async throws -> BereanTranscript {
        guard AMENFeatureFlags.shared.bereanOnDeviceTranscriptionEnabled else {
            // Feature flag off — return stub; backend will transcribe server-side
            return BereanTranscript(text: "", confidence: 0, locale: locale, provider: "disabled", processedAt: Date())
        }

        isTranscribing = true
        defer { isTranscribing = false }

        return try await provider.transcribe(audioURL: audioURL, locale: locale)
    }
}
