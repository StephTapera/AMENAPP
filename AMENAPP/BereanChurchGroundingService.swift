import Foundation
import FirebaseFunctions

@MainActor
final class BereanChurchGroundingService {
    static let shared = BereanChurchGroundingService()

    private lazy var functions = Functions.functions()

    private init() {}

    func answerChurchQuestion(churchId: String, question: String, userPreferences: [String: String] = [:]) async throws -> GroundedChurchAnswer {
        let callable = functions.httpsCallable("generateGroundedChurchAnswer")
        let result = try await callable.call([
            "churchId": churchId,
            "question": question,
            "userPreferences": userPreferences,
        ])

        guard
            let root = result.data as? [String: Any],
            let response = root["response"] as? String
        else {
            return fallbackAnswer()
        }

        let confidenceValue = root["confidence"] as? Double ?? 0.2
        let sources = makeSources(from: root["sources"])
        let confidence = ChurchConfidenceMetadata(
            confidence: confidenceValue,
            level: confidenceLevel(from: root["confidenceLevel"] as? String, fallback: confidenceValue),
            sources: sources,
            note: root["note"] as? String ?? fallbackNote(for: confidenceValue),
            updatedAt: nil
        )

        return GroundedChurchAnswer(
            response: response,
            confidence: confidence,
            sources: sources,
            fallbackMessage: root["fallbackMessage"] as? String
        )
    }

    private func fallbackAnswer() -> GroundedChurchAnswer {
        let confidence = ChurchConfidenceMetadata(
            confidence: 0.1,
            level: .low,
            sources: [],
            note: "This has not yet been confirmed by the church.",
            updatedAt: nil
        )

        return GroundedChurchAnswer(
            response: "I do not have enough verified information yet.",
            confidence: confidence,
            sources: [],
            fallbackMessage: "This appears based on public church metadata."
        )
    }

    private func makeSources(from raw: Any?) -> [ChurchGroundingSource] {
        guard let values = raw as? [[String: Any]] else { return [] }
        return values.compactMap { entry in
            guard
                let id = entry["id"] as? String,
                let title = entry["title"] as? String,
                let typeRaw = entry["type"] as? String,
                let type = ChurchGroundingSourceType(rawValue: typeRaw)
            else {
                return nil
            }

            return ChurchGroundingSource(
                id: id,
                type: type,
                title: title,
                detail: entry["detail"] as? String,
                url: entry["url"] as? String,
                verified: entry["verified"] as? Bool ?? false,
                updatedAt: nil
            )
        }
    }

    private func confidenceLevel(from raw: String?, fallback: Double) -> ChurchConfidenceLevel {
        if let raw, let level = ChurchConfidenceLevel(rawValue: raw) {
            return level
        }

        switch fallback {
        case ..<0.35:
            return .low
        case ..<0.7:
            return .medium
        case ..<0.9:
            return .high
        default:
            return .verified
        }
    }

    private func fallbackNote(for confidence: Double) -> String {
        confidence < 0.35 ? "This has not yet been confirmed by the church." : "This appears based on public church metadata."
    }
}
