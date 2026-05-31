// TranscriptionService.swift
// AMEN Universal Accessibility Engine — A1 Transcription & Captioning
// Phase 2: Transcription via Firebase callable proxy.

import Foundation
import FirebaseFirestore
import FirebaseFunctions
import FirebaseAuth

// MARK: - Models

struct WordTiming: Codable {
    let word: String
    let startMs: Int
    let endMs: Int
}

struct TranscriptChapter: Codable {
    let title: String
    let startMs: Int
    let summary: String
}

struct TranscriptionResult: Codable {
    let mediaId: String
    let fullText: String
    let wordTimings: [WordTiming]
    let chapters: [TranscriptChapter]
    let nonSpeechAnnotations: [String]  // e.g. "[soft piano]", "[congregation singing]"
    let language: String
    let aiContribution: C2PAAIContribution
}

// MARK: - TranscriptionService

actor TranscriptionService {
    static let shared = TranscriptionService()

    private let functions = Functions.functions()
    private let db = Firestore.firestore()

    private init() {}

    // MARK: - Transcribe

    /// Calls the `a11yTranscribeProxy` Firebase callable and returns a structured TranscriptionResult.
    /// No-ops (throws) when the feature flag is off.
    func transcribe(mediaId: String, audioURL: URL? = nil) async throws -> TranscriptionResult {
        guard await TrustAccessibilityFeatureFlags.shared.a11yTranscribeEnabled else {
            throw TranscriptionError.featureDisabled
        }

        let callable = functions.httpsCallable(TrustA11yCallable.a11yTranscribeProxy.rawValue)
        var params: [String: Any] = ["mediaId": mediaId]
        if let url = audioURL {
            params["audioURL"] = url.absoluteString
        }

        let result: HTTPSCallableResult
        do {
            result = try await callable.call(params)
        } catch let error as NSError {
            throw TranscriptionError.callableFailed(underlyingMessage: error.localizedDescription)
        }

        guard let data = result.data as? [String: Any] else {
            throw TranscriptionError.malformedResponse("Root data is not a dictionary")
        }

        return try parseTranscriptionResult(from: data, mediaId: mediaId)
    }

    // MARK: - Fetch Cached Transcript

    /// Reads a cached TranscriptionResult from Firestore at `transcripts/{mediaId}`.
    /// Returns nil when no document exists.
    func fetchCachedTranscript(mediaId: String) async throws -> TranscriptionResult? {
        let docRef = db.collection("transcripts").document(mediaId)
        let snapshot = try await docRef.getDocument()
        guard snapshot.exists, let rawData = snapshot.data() else {
            return nil
        }
        // Re-encode via JSONSerialization so we can decode with JSONDecoder.
        let jsonData = try JSONSerialization.data(withJSONObject: rawData)
        let result = try JSONDecoder().decode(TranscriptionResult.self, from: jsonData)
        return result
    }

    // MARK: - Private Parsing

    private func parseTranscriptionResult(from data: [String: Any], mediaId: String) throws -> TranscriptionResult {
        let fullText = data["fullText"] as? String ?? ""
        let language = data["language"] as? String ?? "en"

        // Word timings
        let wordTimingsRaw = data["wordTimings"] as? [[String: Any]] ?? []
        let wordTimings: [WordTiming] = wordTimingsRaw.compactMap { item in
            guard
                let word = item["word"] as? String,
                let startMs = item["startMs"] as? Int,
                let endMs = item["endMs"] as? Int
            else { return nil }
            return WordTiming(word: word, startMs: startMs, endMs: endMs)
        }

        // Chapters
        let chaptersRaw = data["chapters"] as? [[String: Any]] ?? []
        let chapters: [TranscriptChapter] = chaptersRaw.compactMap { item in
            guard
                let title = item["title"] as? String,
                let startMs = item["startMs"] as? Int,
                let summary = item["summary"] as? String
            else { return nil }
            return TranscriptChapter(title: title, startMs: startMs, summary: summary)
        }

        // Non-speech annotations
        let nonSpeechAnnotations = data["nonSpeechAnnotations"] as? [String] ?? []

        // AI contribution
        let model = data["model"] as? String ?? "whisper-large-v3"
        let jobId = data["jobId"] as? String ?? UUID().uuidString
        let aiContribution = C2PAAIContribution(
            type: .transcription,
            model: model,
            jobId: jobId,
            timestamp: Date(),
            humanEdited: false
        )

        return TranscriptionResult(
            mediaId: mediaId,
            fullText: fullText,
            wordTimings: wordTimings,
            chapters: chapters,
            nonSpeechAnnotations: nonSpeechAnnotations,
            language: language,
            aiContribution: aiContribution
        )
    }
}

// MARK: - Errors

enum TranscriptionError: LocalizedError {
    case featureDisabled
    case callableFailed(underlyingMessage: String)
    case malformedResponse(String)

    var errorDescription: String? {
        switch self {
        case .featureDisabled:
            return "Transcription is not available right now."
        case .callableFailed(let msg):
            return "Transcription request failed: \(msg)"
        case .malformedResponse(let detail):
            return "Unexpected transcription response: \(detail)"
        }
    }
}
