import Foundation
import NaturalLanguage

/// Detects prayer intent in messages USER RECEIVES.
/// Runs on-device only. Gated on ConsentEdge.messagesToPrayer.
/// E2EE/Tier-S threads: classifier runs device-only, prayer object defaults to Tier-S.
@MainActor
final class MessagePrayerBridge: ObservableObject {
    static let shared = MessagePrayerBridge()

    // Dedupe: don't re-prompt for the same thread+excerpt
    private var seenPhrases: Set<String> = []

    private init() {}

    /// Analyze a received message for prayer intent.
    /// Returns a suggestion if detected, nil otherwise.
    func analyze(
        message: String,
        threadID: String,
        senderName: String,
        threadTier: TierCeiling = .p,
        threadIsE2EE: Bool = false
    ) -> PrayerSuggestion? {
        guard ContextIntelligenceFlags.messagePrayer else { return nil }
        guard ConsentStore.shared.isEnabled(.messagesToPrayer) else { return nil }

        let hasPrayerIntent = detectPrayerIntent(in: message)
        guard hasPrayerIntent else { return nil }

        // Dedupe
        let excerpt = String(message.prefix(60))
        guard !seenPhrases.contains(excerpt) else { return nil }
        seenPhrases.insert(excerpt)

        return PrayerSuggestion(
            threadID: threadID,
            senderName: senderName,
            excerpt: excerpt,
            suggestedTitle: "Pray for \(senderName)",
            tierCeiling: threadIsE2EE ? .s : threadTier
        )
    }

    private func detectPrayerIntent(in text: String) -> Bool {
        let lower = text.lowercased()
        // Keyword heuristic — lightweight, no network required
        let prayerPhrases = [
            "pray for", "prayer", "please pray", "keep me in", "in your prayers",
            "could use prayer", "pray with me", "lift up", "intercede"
        ]
        return prayerPhrases.contains { lower.contains($0) }
    }
}

struct PrayerSuggestion: Identifiable {
    let id = UUID()
    let threadID: String
    let senderName: String
    let excerpt: String
    let suggestedTitle: String
    let tierCeiling: TierCeiling
}
