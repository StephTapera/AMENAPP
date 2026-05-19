// BereanSourceGroundingService.swift
// AMENAPP
// Validates that Berean responses are grounded in authoritative scripture + commentary.
// Wraps the linkBereanContext / unlinkBereanContext callables and provides
// local citation validation.

import Foundation
import FirebaseFunctions
import Combine

struct BereanContextLink: Identifiable {
    let id: String
    let sessionId: String
    let linkedEntityType: String
    let linkedEntityId: String
    let notes: String?
    let linkedAt: Date
}

@MainActor
final class BereanSourceGroundingService: ObservableObject {
    static let shared = BereanSourceGroundingService()

    private let functions = Functions.functions()

    // MARK: - Context Linking

    func linkContext(
        sessionId: String,
        entityType: String,
        entityId: String,
        notes: String? = nil
    ) async throws {
        guard AMENFeatureFlags.shared.bereanContextBridgeEnabled else { return }
        var payload: [String: Any] = [
            "sessionId": sessionId,
            "linkedEntityType": entityType,
            "linkedEntityId": entityId
        ]
        if let notes { payload["notes"] = notes }
        _ = try await functions.httpsCallable("linkBereanContext").call(payload)
    }

    func unlinkContext(linkId: String) async throws {
        _ = try await functions.httpsCallable("unlinkBereanContext").call([
            "linkId": linkId
        ])
    }

    // MARK: - Local Citation Validation

    /// Returns true if the text contains at least one valid Bible citation (e.g., "John 3:16").
    func hasBibleCitation(_ text: String) -> Bool {
        let pattern = #"(\b\d?\s?[A-Za-z]+\s+\d+:\d+(-\d+)?\b)"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    /// Extracts all verse references from a Berean response.
    func extractVerseReferences(from text: String) -> [String] {
        let pattern = #"(\b\d?\s?[A-Za-z]+\s+\d+:\d+(-\d+)?\b)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }

    // MARK: - Safety Classification

    func classifySafety(text: String) async throws -> (safetyClass: String, userMessage: String?) {
        guard AMENFeatureFlags.shared.bereanSafetyClassifierEnabled else {
            return ("safe", nil)
        }
        let result = try await functions.httpsCallable("classifyBereanSafety").call([
            "text": text
        ])
        let data = result.data as? [String: Any] ?? [:]
        return (
            safetyClass: data["safetyClass"] as? String ?? "safe",
            userMessage: data["userMessage"] as? String
        )
    }
}
