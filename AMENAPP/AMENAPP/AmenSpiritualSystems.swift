import SwiftUI
import Foundation

// MARK: - Shared Models

enum AmenSpiritualPresenceState: String, Codable, CaseIterable, Identifiable {
    case reflecting
    case praying
    case reading
    case resting
    case seeking
    case available

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reflecting: "Reflecting"
        case .praying: "Praying"
        case .reading: "Reading"
        case .resting: "Resting"
        case .seeking: "Seeking"
        case .available: "Available"
        }
    }

    var icon: String {
        switch self {
        case .reflecting: "moon.stars"
        case .praying: "hands.sparkles"
        case .reading: "book.closed"
        case .resting: "bed.double"
        case .seeking: "sparkle.magnifyingglass"
        case .available: "circle"
        }
    }
}

enum AmenSpiritualPresenceVisibility: String, Codable, CaseIterable {
    case privateOnly = "private_only"
    case mutuals = "mutuals"
    case everyone = "everyone"
}

enum AmenSilentReactionType: String, Codable, CaseIterable, Identifiable {
    case prayed
    case encouraged
    case reflected
    case grateful
    case stoodWithYou

    var id: String { rawValue }

    var title: String {
        switch self {
        case .prayed: "Prayed"
        case .encouraged: "Encouraged"
        case .reflected: "Reflected"
        case .grateful: "Grateful"
        case .stoodWithYou: "Stood With You"
        }
    }

    var icon: String {
        switch self {
        case .prayed: "hands.sparkles"
        case .encouraged: "heart"
        case .reflected: "sparkles"
        case .grateful: "sun.max"
        case .stoodWithYou: "person.2"
        }
    }
}

enum AmenThreadLifecycleState: String, Codable, CaseIterable {
    case active
    case dormant
    case revived
    case answered
    case followUpNeeded

    var displayName: String {
        switch self {
        case .active: return "Active"
        case .dormant: return "Dormant"
        case .revived: return "Revived"
        case .answered: return "Answered"
        case .followUpNeeded: return "Follow-up needed"
        }
    }
}

enum SpiritualPriorityInboxLoadState: Equatable {
    case loading
    case empty
    case loaded([AmenSpiritualPriorityItem])
    case error(String)
}

enum AmenComposeIntentKind: String, Codable, CaseIterable {
    case encouragement
    case correction
    case prayer
    case testimony
    case confession
    case venting
    case question
    case scriptureReflection
    case unknown
}

struct AmenComposeSuggestion: Identifiable, Equatable, Codable {
    let id: String
    let title: String
    let detail: String
    let actionTitle: String
    let replacementText: String?
    let reason: String
}

struct AmenComposeAnalysis: Equatable {
    let intent: AmenComposeIntentKind
    let suggestions: [AmenComposeSuggestion]
    let shouldShowDiscernmentGate: Bool
    let discernmentTitle: String?
    let discernmentMessage: String?
}

struct AmenSilentReactionSummary: Equatable, Codable {
    let summaryText: String
    let reactionTypes: [AmenSilentReactionType]
}

struct AmenThreadLifecycleDescriptor: Equatable, Codable {
    let state: AmenThreadLifecycleState
    let title: String
    let message: String
}

struct AmenSpiritualPriorityItem: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let reasonChips: [String]
    let priorityScore: Double
}

struct AmenThreadSummoningResult: Identifiable, Equatable, Codable {
    let id: String
    let title: String
    let subtitle: String
    let reason: String
    let sourceType: String
}

struct AmenContextualMemoryLayer: Equatable, Codable {
    let scriptureReferences: [String]
    let relatedPostIds: [String]
    let relatedPrayerIds: [String]
    let savedNoteIds: [String]
    let bereanInsightIds: [String]
}

struct AmenPresenceSelection: Codable, Equatable {
    let selectedState: AmenSpiritualPresenceState
    let visibility: AmenSpiritualPresenceVisibility
}

// MARK: - Analyzer

@MainActor
final class AmenSpiritualSystemsService: ObservableObject {
    static let shared = AmenSpiritualSystemsService()

    private init() {}

    func analyzeComposer(text: String) -> AmenComposeAnalysis {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        let intent: AmenComposeIntentKind
        if containsAny(lower, ["pray for", "please pray", "need prayer", "praying for"]) {
            intent = .prayer
        } else if containsAny(lower, ["god brought me", "i was lost", "testimony", "thankful", "grateful"]) {
            intent = .testimony
        } else if containsAny(lower, ["forgive me", "i was wrong", "repent", "i sinned", "confession"]) {
            intent = .confession
        } else if containsAny(lower, ["psalm ", "john ", "romans ", "proverbs ", "matthew ", "scripture", "bible says"]) {
            intent = .scriptureReflection
        } else if containsAny(lower, ["should i", "what should i do", "can someone help", "?"]) {
            intent = .question
        } else if containsAny(lower, ["you should", "you always", "you never", "shut up", "ashamed", "fake christian"]) {
            intent = .correction
        } else if containsAny(lower, ["i hate", "angry", "furious", "venting"]) {
            intent = .venting
        } else if containsAny(lower, ["encourage", "god loves you", "you are not alone", "keep going"]) {
            intent = .encouragement
        } else {
            intent = .unknown
        }

        var suggestions: [AmenComposeSuggestion] = []

        if containsAny(lower, ["ashamed", "fake christian", "worthless", "disgusting", "shut up", "idiot", "you always", "you never"]) {
            suggestions.append(
                AmenComposeSuggestion(
                    id: "soften",
                    title: "Consider softening this",
                    detail: "Correction usually lands better when it carries grace.",
                    actionTitle: "Rewrite gently",
                    replacementText: "I disagree, but I want to respond with care. Can we talk through this?",
                    reason: "Detected shame or escalation language."
                )
            )
        }

        if intent == .scriptureReflection && !containsAny(lower, [":"]) {
            suggestions.append(
                AmenComposeSuggestion(
                    id: "scripture_context",
                    title: "Add scripture context",
                    detail: "A reference or short context note can help readers receive this well.",
                    actionTitle: "Add context",
                    replacementText: nil,
                    reason: "Possible scripture reflection detected."
                )
            )
        }

        if intent == .venting || containsAny(lower, ["angry", "frustrated", "before i respond"]) {
            suggestions.append(
                AmenComposeSuggestion(
                    id: "clarify",
                    title: "Clarify before posting",
                    detail: "A small pause can help make the point without escalation.",
                    actionTitle: "Pause and pray",
                    replacementText: nil,
                    reason: "Emotionally intense phrasing detected."
                )
            )
        }

        if intent == .testimony || intent == .prayer {
            suggestions.append(
                AmenComposeSuggestion(
                    id: "prayer_turn",
                    title: intent == .prayer ? "Keep this prayerful" : "Turn this into a prayer",
                    detail: "You can keep the post as-is or add a prayerful close.",
                    actionTitle: "Apply",
                    replacementText: intent == .prayer ? "Please pray with me about this." : "God, thank You for bringing me this far. Keep leading me in humility.",
                    reason: "Prayer or testimony language detected."
                )
            )
        }

        let shouldGate = containsAny(lower, [
            "ashamed", "fake christian", "god hates you", "worthless",
            "shut up", "idiot", "i hate you", "you always", "you never",
            "manipulate", "if you loved god", "if you were really a christian"
        ])

        let gateMessage: String?
        if containsAny(lower, ["ashamed", "fake christian", "god hates you", "worthless"]) {
            gateMessage = "This may land as shame instead of correction."
        } else if containsAny(lower, ["shut up", "idiot", "i hate you", "you always", "you never"]) {
            gateMessage = "This may escalate conflict."
        } else if containsAny(lower, ["if you loved god", "if you were really a christian", "manipulate"]) {
            gateMessage = "This may feel spiritually coercive."
        } else {
            gateMessage = nil
        }

        return AmenComposeAnalysis(
            intent: intent,
            suggestions: suggestions,
            shouldShowDiscernmentGate: shouldGate,
            discernmentTitle: shouldGate ? "Discernment Moment" : nil,
            discernmentMessage: gateMessage
        )
    }

    func lifecycleDescriptor(for post: Post) -> AmenThreadLifecycleDescriptor? {
        let lower = post.content.lowercased()
        if post.isAnsweredPrayer || post.prayerStatus == "answered" || containsAny(lower, ["answered prayer", "god answered", "praise report"]) {
            return AmenThreadLifecycleDescriptor(
                state: .answered,
                title: "Answered prayer",
                message: "This thread carries an answered-prayer moment."
            )
        }
        if post.category == .prayer || containsAny(lower, ["pray for me", "need prayer", "please pray"]) {
            return AmenThreadLifecycleDescriptor(
                state: .followUpNeeded,
                title: "Worth revisiting",
                message: "This prayer may be worth following up on."
            )
        }
        if post.threadId != nil && post.threadPostCount > 1 {
            return AmenThreadLifecycleDescriptor(
                state: .active,
                title: "Living thread",
                message: "This conversation is still unfolding."
            )
        }
        if containsAny(lower, ["revisited", "coming back to this", "still reflecting"]) {
            return AmenThreadLifecycleDescriptor(
                state: .revived,
                title: "Revisited",
                message: "This thread was brought back into view with new context."
            )
        }
        return nil
    }

    func silentReactionSummary(for post: Post, isAuthor: Bool) -> AmenSilentReactionSummary? {
        guard isAuthor else { return nil }

        var phrases: [String] = []
        var types: [AmenSilentReactionType] = []

        if post.prayTapsCount > 0 {
            phrases.append(post.prayTapsCount > 1 ? "A few people prayed with this" : "Someone prayed with this")
            types.append(.prayed)
        }
        if post.encouragedCount > 0 {
            phrases.append(post.encouragedCount > 1 ? "A few people found this encouraging" : "Someone found this encouraging")
            types.append(.encouraged)
        }
        if post.savesCount > 0 {
            phrases.append(post.savesCount > 1 ? "A few people wanted to revisit this" : "Someone wanted to revisit this")
            types.append(.reflected)
        }

        guard !phrases.isEmpty else { return nil }
        return AmenSilentReactionSummary(summaryText: phrases.joined(separator: " • "), reactionTypes: types)
    }

    func buildPriorityItems(from notifications: [GroupedNotification]) -> [AmenSpiritualPriorityItem] {
        notifications.map { item in
            let lowerText = "\(item.title) \(item.subtitle ?? "")".lowercased()
            let urgencyScore = containsAny(lowerText, ["prayer", "help", "urgent", "follow up", "check in"]) ? 1.0 : 0.35
            let relationshipScore = item.totalActorCount > 1 ? 0.7 : 0.45
            let spiritualDepthScore = containsAny(lowerText, ["scripture", "berean", "prayer", "testimony", "encourag"]) ? 0.9 : 0.4
            let followUpNeedScore = containsAny(lowerText, ["reply", "update", "prayer", "check in"]) ? 0.85 : 0.2
            let scriptureScore = containsAny(lowerText, ["scripture", "verse", "berean"]) ? 0.9 : 0.15
            let recencyScore = item.timeBucket == .today || item.timeBucket == .needsAttention ? 1.0 : 0.35
            let priorityScore =
                urgencyScore * 0.30 +
                relationshipScore * 0.20 +
                spiritualDepthScore * 0.20 +
                followUpNeedScore * 0.15 +
                scriptureScore * 0.10 +
                recencyScore * 0.05

            var chips: [String] = []
            if containsAny(lowerText, ["prayer"]) { chips.append("Prayer follow-up") }
            if containsAny(lowerText, ["encourag"]) { chips.append("Encouragement needed") }
            if containsAny(lowerText, ["scripture", "verse", "berean"]) { chips.append("Scripture match") }
            if containsAny(lowerText, ["answer", "update"]) == false { chips.append("Unresolved") }
            if item.timeBucket == .today || item.timeBucket == .needsAttention { chips.append("Recently revived") }

            return AmenSpiritualPriorityItem(
                id: item.id,
                title: item.title,
                subtitle: item.subtitle ?? "Meaningful spiritual activity worth revisiting.",
                reasonChips: Array(chips.prefix(3)),
                priorityScore: priorityScore
            )
        }
        .sorted { $0.priorityScore > $1.priorityScore }
    }

    func parseThreadSummoningQuery(_ text: String) -> Bool {
        let lower = text.lowercased()
        return containsAny(lower, [
            "show prayers", "follow up", "find posts where someone asked for help",
            "unanswered prayer", "encouragement i saved", "find help", "summon threads"
        ])
    }

    func localThreadSummoningResults(query: String, notifications: [GroupedNotification]) -> [AmenThreadSummoningResult] {
        let lower = query.lowercased()
        return notifications.compactMap { item in
            let haystack = "\(item.title) \(item.subtitle ?? "")".lowercased()
            guard lower.split(separator: " ").contains(where: { token in haystack.contains(token) }) else { return nil }
            return AmenThreadSummoningResult(
                id: item.id,
                title: item.title,
                subtitle: item.subtitle ?? "",
                reason: containsAny(haystack, ["prayer", "help"]) ? "Matched a help or prayer-related phrase." : "Matched your natural-language query.",
                sourceType: "notification"
            )
        }
    }

    func contextualMemoryLayer(for post: Post) async -> AmenContextualMemoryLayer {
        let scriptureRefs = post.verseReference.map { [$0] } ?? []
        let relatedPrayerIds = post.linkedPrayerRequestId.map { [$0] } ?? []
        let noteIds = Array(AmenLibraryMemoryService.shared.snapshot.notedBookIds.prefix(3))
        let chatMemoryIds = ChatMemoryService.shared.memoryItems.prefix(3).map(\.id)
        return AmenContextualMemoryLayer(
            scriptureReferences: scriptureRefs,
            relatedPostIds: post.threadId != nil ? [post.firebaseId ?? post.id.uuidString] : [],
            relatedPrayerIds: relatedPrayerIds,
            savedNoteIds: noteIds,
            bereanInsightIds: Array(chatMemoryIds)
        )
    }

    private func containsAny(_ text: String, _ patterns: [String]) -> Bool {
        patterns.contains { text.contains($0) }
    }
}

// MARK: - Cloud Helper

@MainActor
final class AmenSpiritualCloudService {
    static let shared = AmenSpiritualCloudService()

    private init() {}

    func updatePresence(state: AmenPresenceSelection) async {
        try? await CloudFunctionsService.shared.updatePresenceState(
            selectedState: state.selectedState.rawValue,
            visibility: state.visibility.rawValue
        )
    }

    func addSilentReaction(sourceId: String, sourceType: String, reactionType: AmenSilentReactionType) async {
        try? await CloudFunctionsService.shared.addSilentReaction(
            sourceId: sourceId,
            sourceType: sourceType,
            reactionType: reactionType.rawValue
        )
    }

    func getSilentReactionSummary(sourceId: String, sourceType: String) async -> AmenSilentReactionSummary? {
        try? await CloudFunctionsService.shared.getSilentReactionSummary(sourceId: sourceId, sourceType: sourceType)
    }

    func getPriorityInbox() async -> [AmenSpiritualPriorityItem] {
        (try? await CloudFunctionsService.shared.getSpiritualPriorityInbox()) ?? []
    }

    func summonThreads(query: String) async -> [AmenThreadSummoningResult] {
        (try? await CloudFunctionsService.shared.summonThreads(query: query)) ?? []
    }
}

// MARK: - Components

struct IntentComposeAssistantBar: View {
    let analysis: AmenComposeAnalysis
    let onApplySuggestion: (AmenComposeSuggestion) -> Void
    let onDismissSuggestion: (AmenComposeSuggestion) -> Void
    let onWhy: (AmenComposeSuggestion) -> Void

    var body: some View {
        if !analysis.suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if analysis.intent != .unknown {
                    Text("Intent: \(analysis.intent.label)")
                        .font(AMENFont.semiBold(12))
                        .foregroundStyle(.secondary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(analysis.suggestions) { suggestion in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(suggestion.title)
                                    .font(AMENFont.semiBold(12))
                                    .foregroundStyle(.primary)
                                Text(suggestion.detail)
                                    .font(AMENFont.regular(12))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                HStack(spacing: 8) {
                                    glassAction(suggestion.actionTitle) { onApplySuggestion(suggestion) }
                                    glassAction("Dismiss", secondary: true) { onDismissSuggestion(suggestion) }
                                    glassAction("Why?", secondary: true) { onWhy(suggestion) }
                                }
                            }
                            .padding(12)
                            .frame(width: 250, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.7)))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.8)
                            )
                        }
                    }
                }
            }
        }
    }

    private func glassAction(_ title: String, secondary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(AMENFont.semiBold(11))
            .foregroundStyle(secondary ? .secondary : Color(uiColor: .systemBackground))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(secondary ? Color(.systemGray6) : Color.primary)
            )
            .buttonStyle(.plain)
    }
}

struct DiscernmentGateSheet: View {
    let title: String
    let message: String
    let rewrite: String?
    let onEdit: () -> Void
    let onRewrite: () -> Void
    let onPause: () -> Void
    let onSendAnyway: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.primary)
            Text(message)
                .font(AMENFont.semiBold(15))
                .foregroundStyle(.primary)
            Text("Your words are still yours. Amen is offering a pause before they reach someone else.")
                .font(AMENFont.regular(14))
                .foregroundStyle(.secondary)

            if let rewrite, !rewrite.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Suggested")
                        .font(AMENFont.semiBold(11))
                        .foregroundStyle(.secondary)
                    Text("“\(rewrite)”")
                        .font(AMENFont.regular(14))
                        .foregroundStyle(.primary)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.systemGray6)))
            }

            VStack(spacing: 10) {
                gateButton("Edit", filled: true, action: onEdit)
                gateButton("Rewrite gently", filled: false, action: onRewrite)
                gateButton("Pause and pray", filled: false, action: onPause)
                gateButton("Send anyway", filled: false, action: onSendAnyway)
            }
        }
        .padding(24)
        .background(Color(.systemBackground))
    }

    private func gateButton(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(AMENFont.semiBold(14))
                .foregroundStyle(filled ? Color(.systemBackground) : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Capsule().fill(filled ? Color.primary : Color(.systemGray6)))
        }
        .buttonStyle(.plain)
    }
}

struct LivingThreadBadge: View {
    let descriptor: AmenThreadLifecycleDescriptor

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: descriptor.icon)
                .font(.system(size: 11, weight: .semibold))
            Text(descriptor.title)
                .font(AMENFont.semiBold(11))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color(.systemGray6)))
        .accessibilityLabel(descriptor.title)
    }
}

struct ThreadLifecycleStrip: View {
    let descriptor: AmenThreadLifecycleDescriptor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                LivingThreadBadge(descriptor: descriptor)
                Text(descriptor.message)
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.systemGray6)))
        }
        .buttonStyle(.plain)
    }
}

struct SilentReactionBar: View {
    let onTap: (AmenSilentReactionType) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AmenSilentReactionType.allCases) { reaction in
                    Button {
                        onTap(reaction)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: reaction.icon)
                                .font(.system(size: 11, weight: .semibold))
                            Text(reaction.title)
                                .font(AMENFont.semiBold(11))
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color(.systemGray6)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(reaction.title)
                }
            }
        }
    }
}

struct SilentReactionSummaryView: View {
    let summary: AmenSilentReactionSummary

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(summary.summaryText)
                .font(AMENFont.regular(12))
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel(summary.summaryText)
    }
}

struct PresenceStatePill: View {
    let state: AmenSpiritualPresenceState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: state.icon)
                .font(.system(size: 10, weight: .medium))
            Text(state.title)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(.black.opacity(0.6))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color(.systemGray6)))
    }
}

struct ContextualMemoryLayerSheet: View {
    let layer: AmenContextualMemoryLayer
    let sourceTitle: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(sourceTitle)
                    .font(.system(size: 22, weight: .semibold))
                memorySection("Scripture", items: layer.scriptureReferences, emptyText: "No scripture linked yet.")
                memorySection("Related prayers/posts", items: layer.relatedPrayerIds + layer.relatedPostIds, emptyText: "No related follow-ups yet.")
                memorySection("Saved notes", items: layer.savedNoteIds, emptyText: "No saved notes connected yet.")
                memorySection("Berean insight", items: layer.bereanInsightIds, emptyText: "No Berean insight connected yet.")
            }
            .padding(24)
        }
        .background(Color(.systemBackground))
    }

    private func memorySection(_ title: String, items: [String], emptyText: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AMENFont.semiBold(13))
                .foregroundStyle(.secondary)
            if items.isEmpty {
                Text(emptyText)
                    .font(AMENFont.regular(13))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.systemGray6)))
                }
            }
        }
    }
}

struct SpiritualPriorityInboxView: View {
    let items: [AmenSpiritualPriorityItem]
    let onTap: (AmenSpiritualPriorityItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Spiritual Priority Inbox")
                    .font(AMENFont.bold(14))
                    .foregroundStyle(.primary)
                Spacer()
                Text("Meaning over recency")
                    .font(AMENFont.regular(11))
                    .foregroundStyle(.secondary)
            }

            ForEach(items.prefix(3)) { item in
                Button {
                    onTap(item)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.title)
                            .font(AMENFont.semiBold(14))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(item.subtitle)
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(item.reasonChips, id: \.self) { chip in
                                    Text(chip)
                                        .font(AMENFont.semiBold(10))
                                        .foregroundStyle(.primary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        .background(Capsule().fill(Color(.systemGray6)))
                                }
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct ThreadSummoningSearchView: View {
    let results: [AmenThreadSummoningResult]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Summoned threads")
                .font(AMENFont.semiBold(13))
                .foregroundStyle(.secondary)

            if results.isEmpty {
                Text("No matching threads yet.")
                    .font(AMENFont.regular(13))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(results) { result in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.title)
                            .font(AMENFont.semiBold(13))
                            .foregroundStyle(.primary)
                        Text(result.subtitle)
                            .font(AMENFont.regular(12))
                            .foregroundStyle(.secondary)
                        Text(result.reason)
                            .font(AMENFont.regular(11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.systemGray6)))
                }
            }
        }
    }
}

private extension AmenComposeIntentKind {
    var label: String {
        switch self {
        case .encouragement: "Encouragement"
        case .correction: "Correction"
        case .prayer: "Prayer"
        case .testimony: "Testimony"
        case .confession: "Confession"
        case .venting: "Venting"
        case .question: "Question"
        case .scriptureReflection: "Scripture reflection"
        case .unknown: "Unclear"
        }
    }
}

private extension AmenThreadLifecycleDescriptor {
    var icon: String {
        switch state {
        case .active: "circle.grid.2x2"
        case .dormant: "pause.circle"
        case .revived: "arrow.clockwise.circle"
        case .answered: "checkmark.circle"
        case .followUpNeeded: "bell.badge"
        }
    }
}
