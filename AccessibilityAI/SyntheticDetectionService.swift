// SyntheticDetectionService.swift
// AMEN Trust Layer — T3 Synthetic Detection
// Calls Firebase callable `trustDetectSynthetic` and enforces disclosure for AI-generated media.

import Foundation
import FirebaseFirestore
import FirebaseFunctions
import FirebaseAuth

// MARK: - Synthetic Detection Service

actor SyntheticDetectionService {
    static let shared = SyntheticDetectionService()
    private init() {}

    // MARK: - Detection Result

    enum DetectionResult {
        case confirmedSynthetic(confidence: Double)
        case likelySynthetic(confidence: Double)
        case unverified
        case likelyAuthentic(confidence: Double)

        var isSynthetic: Bool {
            switch self {
            case .confirmedSynthetic, .likelySynthetic:
                return true
            default:
                return false
            }
        }
    }

    // MARK: - Detect

    /// Calls `trustDetectSynthetic` and returns a DetectionResult.
    /// No-ops if `syntheticDetectionEnabled` is false.
    func detect(mediaId: String, mimeType: String) async throws -> DetectionResult {
        let flags = await TrustAccessibilityFeatureFlags.shared.syntheticDetectionEnabled
        guard flags else { return .unverified }

        let callable = Functions.functions().httpsCallable(TrustA11yCallable.trustDetectSynthetic.rawValue)
        let params: [String: Any] = ["mediaId": mediaId, "mimeType": mimeType]

        do {
            let result = try await callable.call(params)
            guard let data = result.data as? [String: Any] else {
                return .unverified
            }
            let verdict = data["verdict"] as? String ?? ""
            let confidence = data["confidence"] as? Double ?? 0.0

            switch verdict {
            case "confirmed_synthetic":
                return .confirmedSynthetic(confidence: confidence)
            case "likely_synthetic":
                return .likelySynthetic(confidence: confidence)
            case "likely_authentic":
                return .likelyAuthentic(confidence: confidence)
            default:
                return .unverified
            }
        } catch let error as FunctionsErrorCode {
            print("[SyntheticDetectionService] Firebase Functions error: \(error)")
            return .unverified
        } catch {
            print("[SyntheticDetectionService] Unexpected error during detection: \(error)")
            return .unverified
        }
    }

    // MARK: - Enforce Disclosure

    /// If the result is synthetic, updates provenance state and flags the media in Firestore.
    /// No-ops if `syntheticDetectionEnabled` is false.
    func enforceDisclosure(mediaId: String, result: DetectionResult) async throws {
        let flags = await TrustAccessibilityFeatureFlags.shared.syntheticDetectionEnabled
        guard flags, result.isSynthetic else { return }

        // Update provenance via ProvenanceCredentialService
        await ProvenanceCredentialService.shared.updateState(for: mediaId, state: .aiGenerated)

        // Flag the media in Firestore as synthetic and undiscoverable
        let db = Firestore.firestore()
        let flagData: [String: Any] = [
            "synthetic": true,
            "discoverable": false,
            "flaggedAt": Timestamp()
        ]
        do {
            try await db.collection("mediaFlags").document(mediaId).setData(flagData, merge: true)
        } catch {
            print("[SyntheticDetectionService] Firestore write failed for mediaId \(mediaId): \(error)")
        }
    }
}
