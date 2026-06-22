// ScriptureIntelligenceDetectionService.swift
// AMEN Capabilities v1 — Scripture detection state manager (Wave 1: Lane E)
//
// Manages debounced scripture reference detection via the scripture_detectReferences callable.
// Detection is debounced 800 ms and any in-flight task is cancelled on each new call.
//
// Flag gate: AMENFeatureFlags.shared.scriptureIntelligenceEnabled
//   OFF → clears detections, no network call.
//
// Callable pattern follows CapabilityRegistryStore (JSONSerialization → JSONDecoder pipeline).

import Foundation
import FirebaseFunctions
import FirebaseAuth

// MARK: - ScriptureIntelligenceDetectionService

@MainActor
final class ScriptureIntelligenceDetectionService: ObservableObject {

    // MARK: - Published State

    @Published private(set) var detections: [ScriptureRef] = []
    @Published private(set) var isDetecting = false

    // MARK: - Private

    private var detectionTask: Task<Void, Never>?
    private let functions = Functions.functions(region: "us-central1")

    // MARK: - Public API

    /// Called on every block-commit. Debounced 800 ms. Cancels any in-flight detection.
    /// No-op when `scriptureIntelligenceEnabled` is OFF — clears existing detections.
    func detectReferences(in blocks: [(blockId: String, text: String)]) {
        guard AMENFeatureFlags.shared.scriptureIntelligenceEnabled else {
            detections = []
            return
        }

        detectionTask?.cancel()
        detectionTask = Task { [weak self] in
            // 800 ms debounce
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            await self?.performDetection(blocks: blocks)
        }
    }

    /// Called when the user taps a detected reference. Fetches verse text for the given
    /// translation via the scripture_getVerses callable.
    /// Throws on network failure or an unexpected response shape.
    func getVerse(ref: ScriptureRef, translation: BibleTranslation) async throws -> VerseCard {
        let params: [String: Any] = [
            "osisRefs": [ref.osisRef],
            "translation": translation.rawValue
        ]

        let result = try await functions
            .httpsCallable("scripture_getVerses")
            .call(params)

        guard
            let data = result.data as? [String: Any],
            let versesRaw = data["verses"] as? [[String: Any]],
            let firstRaw = versesRaw.first,
            let jsonData = try? JSONSerialization.data(withJSONObject: firstRaw)
        else {
            throw ScriptureServiceError.unexpectedResponse
        }

        return try JSONDecoder().decode(VerseCard.self, from: jsonData)
    }

    // MARK: - Private Helpers

    private func performDetection(blocks: [(blockId: String, text: String)]) async {
        guard Auth.auth().currentUser != nil else { return }

        isDetecting = true
        defer { isDetecting = false }

        let blocksPayload = blocks.map { ["blockId": $0.blockId, "text": $0.text] }

        do {
            let result = try await functions
                .httpsCallable("scripture_detectReferences")
                .call(["blocks": blocksPayload])

            // Abort write if cancelled while waiting for the response
            guard !Task.isCancelled else { return }

            guard
                let data = result.data as? [String: Any],
                let detectionsRaw = data["detections"] as? [[String: Any]]
            else {
                return
            }

            let decoded: [ScriptureRef] = detectionsRaw.compactMap { dict in
                guard let jsonData = try? JSONSerialization.data(withJSONObject: dict) else {
                    return nil
                }
                return try? JSONDecoder().decode(ScriptureRef.self, from: jsonData)
            }

            // Only write result if still not cancelled
            guard !Task.isCancelled else { return }
            detections = decoded

        } catch {
            // Network or decoding failure — leave existing detections in place
        }
    }
}

// MARK: - ScriptureServiceError

enum ScriptureServiceError: LocalizedError {
    case unexpectedResponse
    case flagDisabled

    var errorDescription: String? {
        switch self {
        case .unexpectedResponse:
            return "The scripture service returned an unexpected response."
        case .flagDisabled:
            return "Scripture Intelligence is not currently available."
        }
    }
}
