import Foundation

enum TranslationVisibilityGuard {
    private static let suppressedPrefixes = [
        "safety notice",
        "legal notice"
    ]

    private static let suppressedPhrases = [
        "account restricted",
        "enforcement action"
    ]

    static func shouldSuppressTranslation(for text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }

        if suppressedPrefixes.contains(where: { normalized.hasPrefix($0) }) {
            return true
        }

        return suppressedPhrases.contains { normalized.contains($0) }
    }
}
