// SafetyServiceImpl.swift
// AMENAPP — SafetyOS
// Real implementation of the SafetyService protocol.
// Combines keyword scanning + Firebase callable for ML-backed detection.

import Foundation
import FirebaseFunctions

final class SafetyServiceImpl: SafetyService {
    private let functions = Functions.functions()

    func scan(_ card: ContentCard, body: String) async -> [SafetyFlag] {
        var flags: [SafetyFlag] = []

        // Fast local keyword pass (no network required)
        flags.append(contentsOf: localScan(body: body, card: card))

        // Only call cloud for cards with meaningful body content
        if body.count > 20 {
            let cloudFlags = await cloudScan(cardId: card.id, body: body, sourceType: card.sourceType.rawValue)
            for flag in cloudFlags where !flags.contains(flag) {
                flags.append(flag)
            }
        }

        return flags
    }

    func suggestRedactions(for card: ContentCard, body: String) async -> [ContentRedactionSuggestion] {
        ContentPermissionEngine.redactionSuggestions(for: card)
    }

    // MARK: - Local Scan

    private func localScan(body: String, card: ContentCard) -> [SafetyFlag] {
        var flags: [SafetyFlag] = []
        let lower = body.lowercased()

        // Hard flags from card metadata
        if card.hasMinors || card.hasChildContent { flags.append(.minorPresent) }
        if card.hasLocationData { flags.append(.homeAddress) }
        if card.hasPrayerContent && card.originalAudience == .private { flags.append(.privatePrayer) }
        if card.isChurchInternal { flags.append(.churchInternal) }
        if card.isPaidContent { flags.append(.paidContent) }

        // Keyword signals
        if containsPhone(lower) { flags.append(.phoneNumber) }
        if containsMedical(lower) { flags.append(.medical) }
        if containsFinancial(lower) { flags.append(.financial) }
        if containsCrisis(lower) { flags.append(.crisisLanguage) }

        return flags
    }

    private func containsPhone(_ text: String) -> Bool {
        let phonePattern = #"\b\d{3}[-.\s]\d{3}[-.\s]\d{4}\b"#
        return text.range(of: phonePattern, options: .regularExpression) != nil
    }

    private func containsMedical(_ text: String) -> Bool {
        let terms = ["diagnosis", "cancer", "surgery", "hospital", "chemotherapy", "diabetes", "mental health", "depression", "anxiety disorder"]
        return terms.contains { text.contains($0) }
    }

    private func containsFinancial(_ text: String) -> Bool {
        let terms = ["account number", "routing number", "social security", "ssn", "bank account", "credit card number"]
        return terms.contains { text.contains($0) }
    }

    private func containsCrisis(_ text: String) -> Bool {
        let terms = ["want to die", "end my life", "suicide", "kill myself", "can't go on", "no reason to live"]
        return terms.contains { text.contains($0) }
    }

    // MARK: - Cloud Scan

    private func cloudScan(cardId: String, body: String, sourceType: String) async -> [SafetyFlag] {
        do {
            let result = try await functions.httpsCallable("contentSafetyScreen").call([
                "cardId": cardId,
                "body": String(body.prefix(2000)),  // Trim to avoid token overrun
                "sourceType": sourceType
            ])
            guard let data = result.data as? [String: Any],
                  let flagStrings = data["flags"] as? [String] else { return [] }
            return flagStrings.compactMap { SafetyFlag(rawValue: $0) }
        } catch {
            // Cloud call failure must not block the user — fall back to local-only
            return []
        }
    }
}
