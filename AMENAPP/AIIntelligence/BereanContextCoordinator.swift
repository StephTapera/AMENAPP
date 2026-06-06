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

    /// Strips prompt-injection patterns from untrusted community content (post text,
    /// captions, comments, transcripts) before embedding in Berean prompts.
    /// Wraps the sanitized value in XML delimiters so the backend can treat it as
    /// opaque data rather than instructions.
    static func sanitizeCommunityContent(_ raw: String) -> String {
        // Step 1: strip known injection sequences
        var cleaned = raw
        let injectionPatterns = [
            "\n\nIgnore previous instructions",
            "\n\nIgnore all previous",
            "<SYSTEM>",
            "</SYSTEM>",
            "</s>"
        ]
        for pattern in injectionPatterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: .caseInsensitive)
        }

        // Step 2: wrap in XML delimiters so the backend parser treats it as
        // community content, not as a system instruction.
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
