import Foundation

final class AmenContextualReactionEngine {
    static let shared = AmenContextualReactionEngine()

    private init() {}

    func analyzeText(_ text: String) -> [AmenContextualReactionResult] {
        let normalized = normalize(text)
        guard !normalized.isEmpty else { return [] }

        var results: [AmenContextualReactionResult] = []

        if containsAny(normalized, patterns: ["pray for me", "praying for you", "please pray", "need prayer"]) {
            results.append(
                AmenContextualReactionResult(
                    id: "prayer-phrase",
                    triggerType: .prayerPhrase,
                    effectType: .prayerGlow,
                    title: "Prayer detected",
                    microcopy: "Prayer glow",
                    priority: 100,
                    durationMs: 1000,
                    shouldReturnToNormalState: true
                )
            )
        }

        if containsScriptureReference(normalized) {
            results.append(
                AmenContextualReactionResult(
                    id: "scripture-reference",
                    triggerType: .scriptureReference,
                    effectType: .scriptureShimmer,
                    title: "Scripture detected",
                    microcopy: "Living Word shimmer",
                    priority: 90,
                    durationMs: 900,
                    shouldReturnToNormalState: true
                )
            )
        }

        if containsAny(normalized, patterns: ["god brought me back", "testimony", "i was lost", "jesus saved me"]) {
            results.append(
                AmenContextualReactionResult(
                    id: "testimony-phrase",
                    triggerType: .testimonyPhrase,
                    effectType: .amenPulse,
                    title: "Testimony moment",
                    microcopy: "Amen pulse",
                    priority: 80,
                    durationMs: 900,
                    shouldReturnToNormalState: true
                )
            )
        }

        if containsAny(normalized, patterns: ["thank god", "grateful", "praise god"]) {
            results.append(
                AmenContextualReactionResult(
                    id: "gratitude-phrase",
                    triggerType: .gratitudePhrase,
                    effectType: .gratitudeBloom,
                    title: "Gratitude moment",
                    microcopy: "Gratitude bloom",
                    priority: 70,
                    durationMs: 850,
                    shouldReturnToNormalState: true
                )
            )
        }

        return results.sorted { lhs, rhs in
            if lhs.priority == rhs.priority {
                return lhs.id < rhs.id
            }
            return lhs.priority > rhs.priority
        }
    }

    func reactionForLike(contentText: String, contentType: AmenContentType) -> AmenContextualReactionResult? {
        let normalized = normalize(contentText)

        if let seasonal = seasonalReaction(for: Date()) {
            return seasonal
        }

        if contentType == .testimonyPost || containsAny(normalized, patterns: ["testimony", "i was lost", "jesus saved me"]) {
            return AmenContextualReactionResult(
                id: "like-testimony",
                triggerType: .like,
                effectType: .heartMorph,
                title: "Testimony liked",
                microcopy: "Amen pulse",
                priority: 100,
                durationMs: 900,
                shouldReturnToNormalState: true
            )
        }

        if containsAny(normalized, patterns: ["thank god", "grateful", "praise god"]) {
            return AmenContextualReactionResult(
                id: "like-gratitude",
                triggerType: .like,
                effectType: .gratitudeBloom,
                title: "Gratitude liked",
                microcopy: "Gratitude bloom",
                priority: 90,
                durationMs: 850,
                shouldReturnToNormalState: true
            )
        }

        if containsAny(normalized, patterns: ["pray for me", "please pray", "need prayer"]) || contentType == .prayerPost {
            return AmenContextualReactionResult(
                id: "like-prayer",
                triggerType: .like,
                effectType: .amenPulse,
                title: "Prayer liked",
                microcopy: "Prayer moment",
                priority: 85,
                durationMs: 900,
                shouldReturnToNormalState: true
            )
        }

        return AmenContextualReactionResult(
            id: "like-default",
            triggerType: .like,
            effectType: .amenPulse,
            title: "Liked",
            microcopy: "Amen",
            priority: 10,
            durationMs: 850,
            shouldReturnToNormalState: true
        )
    }

    func reactionForSave(contentText: String) -> AmenContextualReactionResult? {
        let normalized = normalize(contentText)
        guard containsScriptureReference(normalized) else { return nil }

        return AmenContextualReactionResult(
            id: "save-scripture",
            triggerType: .save,
            effectType: .saveForStudyChip,
            title: "Save for study",
            microcopy: "Saved for study",
            priority: 100,
            durationMs: 1400,
            shouldReturnToNormalState: true
        )
    }

    func reactionForShare(contentText: String) -> AmenContextualReactionResult? {
        let normalized = normalize(contentText)
        guard containsAny(normalized, patterns: ["pray for me", "please pray", "need prayer", "grieving", "passed away"]) else {
            return nil
        }

        return AmenContextualReactionResult(
            id: "share-care",
            triggerType: .share,
            effectType: .shareWithCareChip,
            title: "Share with care",
            microcopy: "Share with care",
            priority: 100,
            durationMs: 1500,
            shouldReturnToNormalState: true
        )
    }

    func seasonalReaction(for date: Date) -> AmenContextualReactionResult? {
        guard let theme = AmenSeasonalReactionTheme.current(for: date) else { return nil }

        return AmenContextualReactionResult(
            id: "seasonal-\(theme.id)",
            triggerType: theme.triggerType,
            effectType: theme.effectType,
            title: theme.title,
            microcopy: theme.microcopy,
            priority: 110,
            durationMs: 1000,
            shouldReturnToNormalState: true
        )
    }

    func reactionRingResult() -> AmenContextualReactionResult {
        AmenContextualReactionResult(
            id: "hidden-reaction-ring",
            triggerType: .longPress,
            effectType: .hiddenReactionRing,
            title: "Hidden reactions",
            microcopy: "Choose a reaction",
            priority: 120,
            durationMs: 1200,
            shouldReturnToNormalState: true
        )
    }

    private func normalize(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func containsAny(_ text: String, patterns: [String]) -> Bool {
        patterns.contains(where: text.contains)
    }

    private func containsScriptureReference(_ text: String) -> Bool {
        let commonReferences = [
            "psalm 139", "john 3:16", "romans 8", "proverbs 3:5", "matthew 6"
        ]

        if containsAny(text, patterns: commonReferences) {
            return true
        }

        let regex = #"(?i)\b(?:psalm|john|romans|proverbs|matthew)\s\d+(?::\d+(?:-\d+)?)?\b"#
        return text.range(of: regex, options: .regularExpression) != nil
    }
}
