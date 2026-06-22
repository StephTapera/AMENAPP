import Foundation
import SwiftUI
import Combine

@MainActor
struct BereanContextCoordinator {
    static func scripturePayload(
        text: String,
        reference: String,
        translation: String,
        sourceSurface: String = "selah_scripture_reader",
        sourceId: String? = nil
    ) -> BereanContextPayload {
        BereanContextPayload(
            selectedText: text,
            surroundingText: reference,
            sourceSurface: sourceSurface,
            sourceId: sourceId ?? reference,
            contentType: .scripture,
            scriptureReference: reference,
            languageCode: "en",
            metadata: ["translation": translation]
        )
    }

    static func textPayload(
        text: String,
        contentType: BereanContextContentType,
        sourceSurface: String,
        sourceId: String? = nil,
        surroundingText: String? = nil
    ) -> BereanContextPayload {
        BereanContextPayload(
            selectedText: sanitizeCommunityContent(text),
            surroundingText: surroundingText.map { sanitizeCommunityContent($0) },
            sourceSurface: sourceSurface,
            sourceId: sourceId,
            contentType: contentType
        )
    }

    /// Appends a medical guardrail system note to the payload metadata when
    /// health/medical keywords are detected in the selected text.
    static func addMedicalGuardrail(to payload: BereanContextPayload) -> BereanContextPayload {
        let medicalKeywords = ["diagnosis", "medicine", "medication", "dosage", "treatment", "prescription", "symptom", "disease", "cancer", "diabetes", "mental health", "depression", "anxiety", "therapy"]
        let text = payload.selectedText.lowercased()
        let hasMedical = medicalKeywords.contains { text.contains($0) }
        guard hasMedical else { return payload }
        var meta = payload.metadata
        meta["medicalGuardrail"] = "true"
        meta["guardrailNote"] = "This content contains health/medical topics. Berean provides spiritual support only — not medical advice. Always consult a licensed healthcare professional."
        return BereanContextPayload(
            selectedText: payload.selectedText,
            surroundingText: payload.surroundingText,
            sourceSurface: payload.sourceSurface,
            sourceId: payload.sourceId,
            contentType: payload.contentType,
            scriptureReference: payload.scriptureReference,
            languageCode: payload.languageCode,
            metadata: meta
        )
    }

    /// Strips prompt-injection patterns from untrusted community content (post text,
    /// captions, comments, transcripts) before embedding in Berean prompts.
    /// Wraps the sanitized value in XML delimiters so the backend can treat it as
    /// opaque data rather than instructions.
    static func sanitizeCommunityContent(_ raw: String) -> String {
        var cleaned = raw

        let injectionPatterns: [String] = [
            "\n\nIgnore previous instructions",
            "\n\nIgnore all previous",
            "\nIgnore previous instructions",
            "\nIgnore all previous",
            "\t\tIgnore previous instructions",
            "\t\tIgnore all previous",
            "<SYSTEM>",
            "</SYSTEM>",
            "</s>",
            "###",
            "<|im_start|>",
            "<|im_end|>",
            "<|endoftext|>",
            "<|system|>",
            "[INST]",
            "[/INST]"
        ]
        for pattern in injectionPatterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: .caseInsensitive)
        }

        let confusableRegexPatterns: [String] = [
            // Lookalike sequences for "system" built from Unicode homoglyphs
            // Covers Cyrillic/Greek/fullwidth substitutions for s, y, t, e, m
            "[\u{0455}\u{FF53}][\u{0443}\u{FF59}][\u{0442}\u{FF54}][\u{0435}\u{FF45}][\u{043C}\u{FF4D}]",
            // Lookalike sequences for "ignore" built from Unicode homoglyphs
            "[\u{0456}\u{FF49}][\u{0261}\u{FF47}][\u{0274}\u{FF4E}][\u{FF4F}\u{03BF}][\u{0433}\u{FF52}][\u{0435}\u{FF45}]"
        ]
        for pattern in confusableRegexPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(cleaned.startIndex..., in: cleaned)
                cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
            }
        }

        return "<community_content>\(cleaned)</community_content>"
    }
}

// MARK: - Berean OS Bridge Observer
// Observes Trust OS → Berean OS signals from AmenOSBridge.
// Set up at app launch; remains alive for the session.

final class BereanOSBridgeObserver {
    static let shared = BereanOSBridgeObserver()

    // Published so views can observe crisis/support state
    @Published var isCrisisActive: Bool = false
    @Published var currentSupportState: Int = 0  // SafetySupportState.rawValue

    private var tokens: [NSObjectProtocol] = []

    private init() {
        // Trust OS → Berean OS: crisis detected
        let t1 = NotificationCenter.default.addObserver(
            forName: Notification.Name("amenOS.crisisDetected"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // INVARIANT: surface CrisisCard only — no AI, no callModel
            self?.isCrisisActive = true
        }

        // Trust OS → Berean OS: support state changed
        let t2 = NotificationCenter.default.addObserver(
            forName: Notification.Name("amenOS.supportStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            if let state = note.userInfo?["state"] as? Int {
                self?.currentSupportState = state
            }
        }

        tokens = [t1, t2]
    }

    deinit { tokens.forEach { NotificationCenter.default.removeObserver($0) } }

    // MARK: - Weekly brief context
    // Called by Cross-App Context / Chief-of-Staff agent (Berean OS Agent 7).
    // Returns a lightweight summary — no model calls here, purely from local/cached data.
    @MainActor
    func weeklyBriefContext(uid: String) async -> [String: String] {
        let streakDay = await FormationOSIntegrationService.shared.currentStreakDay(uid: uid)
        let weeklySummary = await FormationOSIntegrationService.shared.weeklyFormationSummary(uid: uid)
        return [
            "formationStreak": "\(streakDay)",
            "weeklyFormationSummary": weeklySummary,
            "uid": uid
        ]
    }
}
