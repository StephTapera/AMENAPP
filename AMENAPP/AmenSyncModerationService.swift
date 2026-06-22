// AmenSyncModerationService.swift
// AMEN Sync — Pre-distribution moderation layer

import Foundation

@MainActor
final class AmenSyncModerationService {
    static let shared = AmenSyncModerationService()
    private init() {}

    func moderate(
        caption: String,
        title: String,
        overlayTexts: [String],
        tags: [String]
    ) async -> SyncModerationResult {
        let allText = ([caption, title] + overlayTexts + tags)
            .filter { !$0.isEmpty }
            .joined(separator: " | ")

        guard !allText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return SyncModerationResult(passed: true, blocked: false, score: 0, notes: [])
        }

        let prompt = """
        Review this faith-based social content for safety before distribution.
        Be permissive with genuine religious expression, prayer, scripture, and testimony.
        Only flag content inappropriate for a mainstream church community.

        Content: \(allText)

        Check for: harassment, explicit content, dangerous health claims, exploitative manipulation.

        Respond JSON: {"passed":true,"blocked":false,"score":0.05,"notes":[]}
        score is 0.0 (safe) to 1.0 (harmful).
        """

        let raw = try? await ClaudeService.shared.sendMessageSync(prompt, mode: .scholar)
        return parseModerationResult(from: raw ?? "")
    }

    private func parseModerationResult(from raw: String) -> SyncModerationResult {
        let cleaned = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        struct RawResult: Decodable {
            let passed: Bool?
            let blocked: Bool?
            let score: Double?
            let notes: [String]?
        }

        if let data = cleaned.data(using: .utf8),
           let result = try? JSONDecoder().decode(RawResult.self, from: data) {
            return SyncModerationResult(
                passed: result.passed ?? true,
                blocked: result.blocked ?? false,
                score: result.score ?? 0.0,
                notes: result.notes ?? []
            )
        }
        return SyncModerationResult(passed: true, blocked: false, score: 0, notes: [])
    }

    /// Quick local keyword pre-check (before AI call)
    func quickLocalCheck(text: String) -> Bool {
        let blockedPatterns = ["hate", "kill", "explicit", "nsfw"]
        let lowered = text.lowercased()
        return !blockedPatterns.contains { lowered.contains($0) }
    }
}
