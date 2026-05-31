// SyntheticDetectionService.swift
// AMENAPP
//
// T3 — Server-side authenticity scoring for media.
// Calls the `trustDetectSynthetic` Cloud Function and caches results in memory.

import Foundation
import FirebaseFunctions

@MainActor
final class SyntheticDetectionService {

    static let shared = SyntheticDetectionService()

    private var cache: [String: AuthenticityScore] = [:]

    private init() {}

    func assess(mediaId: String, storageUri: String) async -> AuthenticityScore? {
        guard AMENFeatureFlags.shared.syntheticMediaDetectionEnabled else {
            dlog("[SyntheticDetectionService] feature flag off — skipping assessment for \(mediaId)")
            return nil
        }

        if let cached = cache[mediaId] {
            dlog("[SyntheticDetectionService] cache hit for \(mediaId)")
            return cached
        }

        let payload: [String: Any] = [
            "mediaId": mediaId,
            "storageUri": storageUri
        ]

        do {
            let callable = Functions.functions().httpsCallable("trustDetectSynthetic")
            callable.timeoutInterval = 20
            let result = try await callable.safeCall(payload)

            guard let data = result.data as? [String: Any] else {
                dlog("[SyntheticDetectionService] unexpected response shape for \(mediaId)")
                return nil
            }

            let score = (data["score"] as? Double) ?? 0.0
            let labelRaw = (data["label"] as? String) ?? ""
            let modelVersion = (data["modelVersion"] as? String) ?? "unknown"

            let label: AuthenticityScoreLabel
            switch labelRaw {
            case "likelyAuthentic":  label = .likelyAuthentic
            case "likelySynthetic":  label = .likelySynthetic
            default:                 label = .uncertain
            }

            let rawSignals = (data["signals"] as? [[String: Any]]) ?? []
            let signals: [AuthenticitySignalRecord] = rawSignals.compactMap { dict in
                guard
                    let signal = dict["signal"] as? String,
                    let weight = dict["weight"] as? Double,
                    let description = dict["description"] as? String
                else { return nil }
                return AuthenticitySignalRecord(signal: signal, weight: weight, description: description)
            }

            let score_ = AuthenticityScore(
                mediaId: mediaId,
                score: score,
                label: label,
                signals: signals,
                computedAt: Date(),
                modelVersion: modelVersion
            )

            cache[mediaId] = score_
            dlog("[SyntheticDetectionService] assessed \(mediaId) → \(label.rawValue) (\(score))")
            return score_

        } catch {
            dlog("[SyntheticDetectionService] error assessing \(mediaId): \(error.localizedDescription)")
            return nil
        }
    }
}
