// TranslationModerationBridge.swift
// AMEN App — Translation System
//
// Ensures translation does NOT create moderation blind spots.
//
// Design principles:
//   - Original text is ALWAYS the source of truth for moderation
//   - Translation-aware classifiers evaluate both original and translated
//   - Harmful content in any language is detectable
//   - Users cannot abuse translation to disguise prohibited behavior
//   - Results feed back into ContentSafetyShieldService pipeline

import Foundation
import FirebaseFirestore

// MARK: - Translation Moderation Bridge

@MainActor
final class TranslationModerationBridge {

    static let shared = TranslationModerationBridge()

    private let db = Firestore.firestore()
    private let safetyService = ContentSafetyShieldService.shared

    private init() {}

    // MARK: - Pre-Translation Safety Check

    /// Called before storing a translation. Verifies the translated text doesn't
    /// introduce new moderation issues (e.g. translation that sounds more explicit than original).
    func validateTranslation(
        originalText: String,
        translatedText: String,
        contentType: TranslatableContentType,
        contentId: String
    ) async -> TranslationModerationResult {

        // Short-circuit for trivial content
        guard originalText.count >= 10 else {
            return TranslationModerationResult(isAllowed: true, requiresReview: false, reason: nil)
        }

        // Score original text
        let originalRisk = await assessTextRisk(originalText)

        // Score translated text
        let translatedRisk = await assessTextRisk(translatedText)

        // If translation dramatically increases risk score vs original, flag for review
        let riskDelta = translatedRisk - originalRisk
        let significantEscalation = riskDelta > 25 // threshold: 25 point jump

        if significantEscalation {
            await logModerationAnomaly(
                contentId: contentId,
                contentType: contentType,
                originalRisk: originalRisk,
                translatedRisk: translatedRisk,
                reason: "Translation escalated risk score by \(Int(riskDelta)) points"
            )
            // Don't block — just flag. Human review handles edge cases.
            return TranslationModerationResult(
                isAllowed: true,
                requiresReview: true,
                reason: "Translation quality review: risk delta \(Int(riskDelta))"
            )
        }

        // Hard block if translated text itself is clearly policy-violating
        if translatedRisk >= 85 {
            await logModerationAnomaly(
                contentId: contentId,
                contentType: contentType,
                originalRisk: originalRisk,
                translatedRisk: translatedRisk,
                reason: "Translated text exceeded hard block threshold"
            )
            return TranslationModerationResult(
                isAllowed: false,
                requiresReview: false,
                reason: "Translated content violates content policy"
            )
        }

        return TranslationModerationResult(isAllowed: true, requiresReview: false, reason: nil)
    }

    // MARK: - Multilingual Moderation Check

    /// For content in a non-English language, optionally translate to English
    /// to improve classifier accuracy, then score both versions.
    /// The original text remains the source of truth.
    func runMultilingualModerationCheck(
        text: String,
        detectedLanguage: String,
        contentId: String,
        contentType: TranslatableContentType
    ) async -> MultilingualModerationResult {

        let originalRisk = await assessTextRisk(text)
        var englishRisk: Double? = nil
        var pivotTranslation: String? = nil

        // Only do pivot translation if original is non-English and non-trivial
        if detectedLanguage != "en" && text.count >= 20 {
            // Attempt lightweight translation to English for moderation pivot
            // This is separate from user-facing translation and uses a fast path
            if let english = await translateForModeration(text: text, sourceLang: detectedLanguage) {
                pivotTranslation = english
                englishRisk = await assessTextRisk(english)
            }
        }

        // Take the higher of the two risk scores (conservative)
        let effectiveRisk = max(originalRisk, englishRisk ?? 0)

        return MultilingualModerationResult(
            originalText: text,
            pivotTranslation: pivotTranslation,
            originalRiskScore: originalRisk,
            pivotRiskScore: englishRisk,
            effectiveRiskScore: effectiveRisk,
            requiresReview: effectiveRisk >= 50,
            isHardBlocked: effectiveRisk >= 90
        )
    }

    // MARK: - Abuse Detection

    /// Detects if a user is submitting many translation requests for identical/similar content
    /// to spam the system or evade per-language keyword filters.
    func checkForTranslationAbuse(userId: String) async -> Bool {
        // Check request rate for this user in the last hour
        let oneHourAgo = Timestamp(date: Date().addingTimeInterval(-3600))

        do {
            let snapshot = try await db
                .collection("translationAnalytics")
                .whereField("userId", isEqualTo: userId)
                .whereField("timestamp", isGreaterThan: oneHourAgo)
                .count
                .getAggregation(source: .server)

            let count = snapshot.count.intValue
            return count > 200 // 200 requests/hour threshold
        } catch {
            return false // Non-fatal: allow on error
        }
    }

    // MARK: - Private Helpers

    private func assessTextRisk(_ text: String) async -> Double {
        // ContentRiskAnalyzer is nonisolated — safe to call from any context.
        // It returns a ContentRiskResult with totalScore in 0.0–1.0 range;
        // we scale to 0–100 to match the thresholds used in this bridge.
        let result = ContentRiskAnalyzer.shared.analyze(text: text, context: .unknown)
        return result.totalScore * 100.0
    }

    private func translateForModeration(text: String, sourceLang: String) async -> String? {
        // Lightweight on-device translation for moderation pivot — not user-facing
        // Uses Apple Translation to avoid external API calls for moderation purposes
        guard #available(iOS 17.4, *) else { return nil }
        return try? await AppleTranslationBridge.shared.translate(
            text: String(text.prefix(500)), // truncate for speed
            from: sourceLang,
            to: "en"
        )
    }

    private func logModerationAnomaly(
        contentId: String,
        contentType: TranslatableContentType,
        originalRisk: Double,
        translatedRisk: Double,
        reason: String
    ) async {
        _ = try? await db
            .collection("translationModerationAnomalies")
            .addDocument(data: [
                "contentId": contentId,
                "contentType": contentType.rawValue,
                "originalRiskScore": originalRisk,
                "translatedRiskScore": translatedRisk,
                "reason": reason,
                "reviewedAt": NSNull(),
                "reviewedBy": NSNull(),
                "timestamp": FieldValue.serverTimestamp()
            ])
    }
}

// MARK: - Result Models

struct TranslationModerationResult {
    let isAllowed: Bool
    let requiresReview: Bool
    let reason: String?
}

struct MultilingualModerationResult {
    let originalText: String
    let pivotTranslation: String?
    let originalRiskScore: Double
    let pivotRiskScore: Double?
    let effectiveRiskScore: Double
    let requiresReview: Bool
    let isHardBlocked: Bool
}

