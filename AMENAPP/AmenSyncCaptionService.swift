// AmenSyncCaptionService.swift
// AMEN Sync — AI Caption Generation per platform

import Foundation

@MainActor
final class AmenSyncCaptionService {
    static let shared = AmenSyncCaptionService()
    private init() {}

    func generateSuggestions(
        masterCaption: String,
        scripture: String?,
        platforms: [SyncPlatform],
        tags: [String]
    ) async -> [SyncCaptionSuggestion] {
        let prompt = """
        Generate platform-aware caption variants for faith-based social content.
        Master caption: "\(masterCaption)"
        \(scripture.map { "Scripture: \($0)" } ?? "")
        Tags: \(tags.joined(separator: ", "))

        Generate 6 caption variants with different tones. Preserve faith language naturally.
        Never generate clickbait or manipulative urgency.
        Keep each concise and human.

        Respond in JSON: {"suggestions":[{"text":"...","tone":"devotional|uplifting|teaching|bold|conversational|professional","hashtags":["faith"]}]}
        """

        let raw = try? await ClaudeService.shared.sendMessageSync(prompt, mode: .scholar)
        return parseSuggestions(from: raw ?? "")
    }

    func adaptCaption(_ caption: String, for platform: SyncPlatform) async -> String {
        let maxLen = platform.maxCaptionLength
        if caption.count <= maxLen { return caption }

        let prompt = """
        Shorten this caption to under \(maxLen) characters while preserving its meaning and tone.
        Caption: "\(caption)"
        Platform: \(platform.displayName)

        Return only the shortened caption text, nothing else.
        """

        let result = try? await ClaudeService.shared.sendMessageSync(prompt, mode: .scholar)
        let trimmed = (result ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.count > maxLen {
            return String(caption.prefix(maxLen - 3)) + "..."
        }
        return trimmed
    }

    func generateHashtags(for caption: String, platform: SyncPlatform) async -> [String] {
        guard platform.supportsHashtags else { return [] }

        let prompt = """
        Generate 5-8 relevant hashtags for this faith-based content.
        Caption: "\(caption)"
        Platform: \(platform.displayName)

        Return only hashtags as JSON array: ["faith","amen","blessed"]
        No # prefix, lowercase only.
        """

        let raw = try? await ClaudeService.shared.sendMessageSync(prompt, mode: .scholar)
        let cleaned = (raw ?? "")
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let data = cleaned.data(using: .utf8),
           let tags = try? JSONDecoder().decode([String].self, from: data) {
            return tags
        }
        return ["faith", "amen", "blessed"]
    }

    private func parseSuggestions(from raw: String) -> [SyncCaptionSuggestion] {
        let cleaned = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        struct RawSuggestion: Decodable {
            let text: String
            let tone: String?
            let hashtags: [String]?
        }
        struct RawResult: Decodable {
            let suggestions: [RawSuggestion]
        }

        if let data = cleaned.data(using: .utf8),
           let result = try? JSONDecoder().decode(RawResult.self, from: data) {
            return result.suggestions.map { s in
                SyncCaptionSuggestion(
                    text: s.text,
                    tone: CaptionTone(rawValue: s.tone ?? "conversational") ?? .conversational,
                    platformFit: nil,
                    hashtags: s.hashtags ?? []
                )
            }
        }

        // Fallback suggestions
        return [
            SyncCaptionSuggestion(text: "Grateful for this moment. Sharing what God is doing. 🙏", tone: .devotional, platformFit: nil, hashtags: ["faith", "blessed"]),
            SyncCaptionSuggestion(text: "He is faithful — always has been, always will be.", tone: .uplifting, platformFit: nil, hashtags: ["faithful", "amen"]),
            SyncCaptionSuggestion(text: "Something I've been learning lately:", tone: .teaching, platformFit: nil, hashtags: ["faith", "growth"]),
        ]
    }
}
