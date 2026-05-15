import SwiftUI
import Foundation

enum AmenSafetyLane: String, Codable, CaseIterable {
    case green
    case blue
    case amber
    case red

    var accessibilityLabel: String {
        switch self {
        case .green: "Aligned"
        case .blue: "Context helpful"
        case .amber: "Needs discernment"
        case .red: "Serious concern"
        }
    }
}

enum AmenTriggerType: String, Codable, CaseIterable {
    case scriptureReference
    case prayerRequest
    case testimony
    case gratitude
    case wisdomPrompt
    case repentance
    case grief
    case encouragement
    case shameTone
    case conflictTone
    case lustTrigger
    case comparisonTrigger
    case vanityTrigger
    case outrageTrigger
    case vulnerablePersonConcern
    case selfHarmConcern
    case harassmentConcern
    case misinformationConcern
    case unknown
}

enum AmenTriggerSource: String, Codable {
    case localHeuristic
    case serverSafetyOS
    case merged
}

enum AmenDiscernmentAction: String, Codable, CaseIterable, Hashable {
    case postAnyway
    case editWithGrace
    case saveDraft
    case pauseAndPray
    case rewriteGently
    case addContext
    case openScripture
    case joinPrayer
    case keepAsText
    case cancel

    var title: String {
        switch self {
        case .postAnyway: "Post anyway"
        case .editWithGrace: "Edit with grace"
        case .saveDraft: "Save draft"
        case .pauseAndPray: "Pause and pray"
        case .rewriteGently: "Rewrite gently"
        case .addContext: "Add context"
        case .openScripture: "Open Scripture"
        case .joinPrayer: "Join prayer"
        case .keepAsText: "Keep as text"
        case .cancel: "Cancel"
        }
    }
}

enum AmenReactionType: String, Codable, CaseIterable, Hashable {
    case amen
    case praying
    case encouraged
    case wisdom
    case praiseGod
    case heart

    var title: String {
        switch self {
        case .amen: "Amen"
        case .praying: "Praying"
        case .encouraged: "Encouraged"
        case .wisdom: "Wisdom"
        case .praiseGod: "Praise God"
        case .heart: "Heart"
        }
    }

    var symbolName: String {
        switch self {
        case .amen: "hands.sparkles"
        case .praying: "sparkles"
        case .encouraged: "sun.max"
        case .wisdom: "book.closed"
        case .praiseGod: "hands.clap"
        case .heart: "heart"
        }
    }
}

enum AmenReactionEffectType: String, Codable, CaseIterable {
    case amenPulse
    case prayerThreadGlow
    case livingWordShimmer
    case peaceSlowdown
    case gratitudeBloom
    case discernmentPause
    case scriptureCapsule
    case none
}

struct AmenTriggerResult: Identifiable, Codable, Equatable {
    let id: String
    let type: AmenTriggerType
    let lane: AmenSafetyLane
    let title: String
    let message: String
    let recommendedActions: [AmenDiscernmentAction]
    let priority: Int
    let confidence: Double
    let source: AmenTriggerSource
    let shouldShowDiscernmentSheet: Bool
    let shouldApplyVisualEffect: Bool
}

struct AmenReactionEffectPolicy: Codable, Equatable {
    let effectType: AmenReactionEffectType
    let triggerType: AmenTriggerType?
    let lane: AmenSafetyLane
    let durationMs: Int
    let intensity: Double
    let microcopy: String
    let shouldRespectReducedMotion: Bool
}

enum AmenSurfaceType: String, Codable {
    case post
    case comment
    case reply
    case directMessagePreview
    case quotePost
    case profileBio
}

@MainActor
final class AmenLocalTriggerEngine {
    static let shared = AmenLocalTriggerEngine()

    private init() {}

    func analyze(text: String, surface: AmenSurfaceType) -> [AmenTriggerResult] {
        let normalized = normalize(text)
        guard !normalized.isEmpty else { return [] }

        var results: [AmenTriggerResult] = []

        if containsScripture(in: normalized) {
            results.append(
                AmenTriggerResult(
                    id: "scripture",
                    type: .scriptureReference,
                    lane: .green,
                    title: "Scripture detected",
                    message: "Amen found a possible Scripture reference.",
                    recommendedActions: [.openScripture, .addContext, .keepAsText],
                    priority: 45,
                    confidence: 0.88,
                    source: .localHeuristic,
                    shouldShowDiscernmentSheet: false,
                    shouldApplyVisualEffect: true
                )
            )
        }

        if containsAny(normalized, patterns: [
            "pray for me", "please pray", "need prayer", "prayer request",
            "keep me in prayer", "praying for you"
        ]) {
            results.append(
                AmenTriggerResult(
                    id: "prayer",
                    type: .prayerRequest,
                    lane: .green,
                    title: "Prayer detected",
                    message: "This sounds like a prayer request.",
                    recommendedActions: [.joinPrayer, .keepAsText],
                    priority: 52,
                    confidence: 0.92,
                    source: .localHeuristic,
                    shouldShowDiscernmentSheet: false,
                    shouldApplyVisualEffect: true
                )
            )
        }

        if containsAny(normalized, patterns: [
            "god brought me back", "i was lost", "i came back to god",
            "jesus saved me", "this is my testimony", "testimony"
        ]) {
            results.append(
                AmenTriggerResult(
                    id: "testimony",
                    type: .testimony,
                    lane: .green,
                    title: "Testimony moment",
                    message: "This may encourage someone through testimony.",
                    recommendedActions: [.postAnyway],
                    priority: 40,
                    confidence: 0.81,
                    source: .localHeuristic,
                    shouldShowDiscernmentSheet: false,
                    shouldApplyVisualEffect: true
                )
            )
        }

        if containsAny(normalized, patterns: ["grateful to god", "thankful for god", "praise god", "so thankful"]) {
            results.append(
                AmenTriggerResult(
                    id: "gratitude",
                    type: .gratitude,
                    lane: .green,
                    title: "Gratitude moment",
                    message: "This carries gratitude or praise.",
                    recommendedActions: [.postAnyway],
                    priority: 28,
                    confidence: 0.76,
                    source: .localHeuristic,
                    shouldShowDiscernmentSheet: false,
                    shouldApplyVisualEffect: true
                )
            )
        }

        if containsAny(normalized, patterns: [
            "need wisdom", "help me discern", "should i", "what should i do",
            "before i respond", "is this wise"
        ]) {
            results.append(
                AmenTriggerResult(
                    id: "wisdom",
                    type: .wisdomPrompt,
                    lane: .blue,
                    title: "Discernment moment",
                    message: "This sounds like a wisdom prompt.",
                    recommendedActions: [.pauseAndPray, .postAnyway],
                    priority: 54,
                    confidence: 0.8,
                    source: .localHeuristic,
                    shouldShowDiscernmentSheet: false,
                    shouldApplyVisualEffect: true
                )
            )
        }

        if containsAny(normalized, patterns: [
            "i need to repent", "i was wrong", "forgive me", "conviction", "i sinned"
        ]) {
            results.append(
                AmenTriggerResult(
                    id: "repentance",
                    type: .repentance,
                    lane: .blue,
                    title: "Repentance moment",
                    message: "This sounds like repentance or confession.",
                    recommendedActions: [.postAnyway],
                    priority: 30,
                    confidence: 0.78,
                    source: .localHeuristic,
                    shouldShowDiscernmentSheet: false,
                    shouldApplyVisualEffect: false
                )
            )
        }

        if containsAny(normalized, patterns: [
            "i lost someone", "passed away", "grieving", "funeral", "mourning", "my grandmother passed away"
        ]) {
            results.append(
                AmenTriggerResult(
                    id: "grief",
                    type: .grief,
                    lane: .blue,
                    title: "Handle with care",
                    message: "This carries grief or loss.",
                    recommendedActions: [.joinPrayer, .postAnyway],
                    priority: 58,
                    confidence: 0.9,
                    source: .localHeuristic,
                    shouldShowDiscernmentSheet: false,
                    shouldApplyVisualEffect: true
                )
            )
        }

        if containsAny(normalized, patterns: [
            "god loves you", "you are not alone", "keep going", "thankful for you", "encouraged"
        ]) {
            results.append(
                AmenTriggerResult(
                    id: "encouragement",
                    type: .encouragement,
                    lane: .green,
                    title: "Encouragement",
                    message: "This may strengthen someone.",
                    recommendedActions: [.postAnyway],
                    priority: 25,
                    confidence: 0.72,
                    source: .localHeuristic,
                    shouldShowDiscernmentSheet: false,
                    shouldApplyVisualEffect: false
                )
            )
        }

        if containsAny(normalized, patterns: [
            "you should be ashamed", "fake christian", "god hates you", "worthless", "disgusting"
        ]) {
            results.append(
                AmenTriggerResult(
                    id: "shame",
                    type: .shameTone,
                    lane: .amber,
                    title: "Discernment moment",
                    message: "This may land as shame instead of correction.",
                    recommendedActions: [.editWithGrace, .saveDraft, .postAnyway],
                    priority: 100,
                    confidence: 0.95,
                    source: .localHeuristic,
                    shouldShowDiscernmentSheet: surface != .profileBio,
                    shouldApplyVisualEffect: true
                )
            )
        }

        if containsAny(normalized, patterns: [
            "shut up", "idiot", "i hate you", "you always", "you never"
        ]) {
            results.append(
                AmenTriggerResult(
                    id: "conflict",
                    type: .conflictTone,
                    lane: .amber,
                    title: "Peace check",
                    message: "This may escalate conflict.",
                    recommendedActions: [.rewriteGently, .pauseAndPray, .postAnyway],
                    priority: 96,
                    confidence: 0.93,
                    source: .localHeuristic,
                    shouldShowDiscernmentSheet: true,
                    shouldApplyVisualEffect: true
                )
            )
        }

        if containsAny(normalized, patterns: ["compare my life", "everyone else has", "wish i looked like", "why am i not enough"]) {
            results.append(
                AmenTriggerResult(
                    id: "comparison",
                    type: .comparisonTrigger,
                    lane: .amber,
                    title: "Comparison trigger",
                    message: "This may carry comparison language.",
                    recommendedActions: [.pauseAndPray, .postAnyway],
                    priority: 34,
                    confidence: 0.64,
                    source: .localHeuristic,
                    shouldShowDiscernmentSheet: false,
                    shouldApplyVisualEffect: false
                )
            )
        }

        return results
            .sorted { lhs, rhs in
                if lhs.priority == rhs.priority {
                    return lhs.title < rhs.title
                }
                return lhs.priority > rhs.priority
            }
    }

    func recommendedReactions(for triggers: [AmenTriggerResult]) -> [AmenReactionType] {
        if triggers.contains(where: { $0.type == .prayerRequest || $0.type == .grief }) {
            return [.praying, .amen, .encouraged, .heart]
        }
        if triggers.contains(where: { $0.type == .scriptureReference }) {
            return [.wisdom, .amen, .heart]
        }
        if triggers.contains(where: { $0.type == .testimony || $0.type == .gratitude }) {
            return [.amen, .praiseGod, .encouraged, .heart]
        }
        if triggers.contains(where: { $0.type == .wisdomPrompt }) {
            return [.wisdom, .praying, .amen]
        }
        return [.amen, .heart, .encouraged]
    }

    func suggestedRewrite(for trigger: AmenTriggerResult, originalText: String) -> String? {
        switch trigger.type {
        case .shameTone:
            return "I disagree, but I want to respond with care. Can we talk through this?"
        case .conflictTone:
            return "I want to slow down and respond clearly. Can we work through this without escalating?"
        case .wisdomPrompt:
            return "I need wisdom before I respond, and I want to choose my words carefully."
        case .scriptureReference:
            return originalText.contains(":") ? nil : "\(originalText)\n\nScripture context:"
        default:
            return nil
        }
    }

    func effectPolicy(
        for triggers: [AmenTriggerResult],
        reaction: AmenReactionType? = nil
    ) -> AmenReactionEffectPolicy? {
        let primary = triggers.first(where: \.shouldApplyVisualEffect)

        if let primary, primary.type == .scriptureReference {
            return AmenReactionEffectPolicy(
                effectType: .livingWordShimmer,
                triggerType: primary.type,
                lane: primary.lane,
                durationMs: 900,
                intensity: 0.65,
                microcopy: "Scripture context",
                shouldRespectReducedMotion: true
            )
        }

        if let primary, primary.type == .prayerRequest || primary.type == .grief {
            return AmenReactionEffectPolicy(
                effectType: .prayerThreadGlow,
                triggerType: primary.type,
                lane: primary.lane,
                durationMs: 1000,
                intensity: 0.7,
                microcopy: reaction == .praying ? "Prayer joined" : "Prayer moment",
                shouldRespectReducedMotion: true
            )
        }

        if let primary, primary.type == .testimony || primary.type == .gratitude {
            return AmenReactionEffectPolicy(
                effectType: reaction == .amen || reaction == .praiseGod ? .amenPulse : .gratitudeBloom,
                triggerType: primary.type,
                lane: primary.lane,
                durationMs: 900,
                intensity: 0.75,
                microcopy: "Testimony moment",
                shouldRespectReducedMotion: true
            )
        }

        if let primary, primary.type == .shameTone || primary.type == .conflictTone {
            return AmenReactionEffectPolicy(
                effectType: .peaceSlowdown,
                triggerType: primary.type,
                lane: primary.lane,
                durationMs: 1200,
                intensity: 0.8,
                microcopy: primary.type == .conflictTone ? "Peace check" : "Discernment moment",
                shouldRespectReducedMotion: true
            )
        }

        if let reaction {
            return AmenReactionEffectPolicy(
                effectType: .amenPulse,
                triggerType: nil,
                lane: .green,
                durationMs: 900,
                intensity: 0.55,
                microcopy: reaction.title,
                shouldRespectReducedMotion: true
            )
        }

        return nil
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

    private func containsScripture(in text: String) -> Bool {
        let books = [
            "psalm ", "psalms ", "john ", "romans ", "proverbs ", "matthew ",
            "genesis ", "revelation ", "scripture says", "bible says"
        ]
        if containsAny(text, patterns: books) {
            return true
        }

        let regex = #"(?i)\b(?:1|2|3)?\s?[A-Za-z]+\s\d{1,3}(?::\d{1,3}(?:-\d{1,3})?)?\b"#
        return text.range(of: regex, options: .regularExpression) != nil
    }
}

struct AmenSafetyReactionLayer: View {
    let triggers: [AmenTriggerResult]
    let maxVisible: Int
    let onTapTrigger: (AmenTriggerResult) -> Void

    init(
        triggers: [AmenTriggerResult],
        maxVisible: Int = 2,
        onTapTrigger: @escaping (AmenTriggerResult) -> Void
    ) {
        self.triggers = triggers
        self.maxVisible = maxVisible
        self.onTapTrigger = onTapTrigger
    }

    var body: some View {
        let visibleTriggers = Array(triggers.prefix(maxVisible))

        if !visibleTriggers.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(visibleTriggers) { trigger in
                        triggerCapsule(for: trigger)
                    }
                }
                .padding(.vertical, 2)
            }
            .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder
    private func triggerCapsule(for trigger: AmenTriggerResult) -> some View {
        switch trigger.type {
        case .scriptureReference:
            AmenScriptureContextCapsule(trigger: trigger) { onTapTrigger(trigger) }
        case .prayerRequest, .grief:
            AmenPrayerRequestCapsule(trigger: trigger) { onTapTrigger(trigger) }
        case .testimony, .gratitude:
            AmenTestimonyMomentCapsule(trigger: trigger) { onTapTrigger(trigger) }
        case .wisdomPrompt:
            AmenWisdomPromptCapsule(trigger: trigger) { onTapTrigger(trigger) }
        default:
            AmenSpiritualTriggerChip(trigger: trigger) { onTapTrigger(trigger) }
        }
    }
}

struct AmenSpiritualTriggerChip: View {
    let trigger: AmenTriggerResult
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                AmenSafetyLaneBadge(lane: trigger.lane)
                VStack(alignment: .leading, spacing: 1) {
                    Text(trigger.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(trigger.message)
                        .font(.system(size: 11))
                        .foregroundStyle(.black.opacity(0.58))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule(style: .continuous).fill(Color.white.opacity(0.88)))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(trigger.title). \(trigger.message)")
    }
}

struct AmenPrayerRequestCapsule: View {
    let trigger: AmenTriggerResult
    let action: () -> Void

    var body: some View {
        AmenSpiritualTriggerChip(trigger: trigger, action: action)
    }
}

struct AmenScriptureContextCapsule: View {
    let trigger: AmenTriggerResult
    let action: () -> Void

    var body: some View {
        AmenSpiritualTriggerChip(trigger: trigger, action: action)
    }
}

struct AmenTestimonyMomentCapsule: View {
    let trigger: AmenTriggerResult
    let action: () -> Void

    var body: some View {
        AmenSpiritualTriggerChip(trigger: trigger, action: action)
    }
}

struct AmenWisdomPromptCapsule: View {
    let trigger: AmenTriggerResult
    let action: () -> Void

    var body: some View {
        AmenSpiritualTriggerChip(trigger: trigger, action: action)
    }
}

struct AmenReactionBar: View {
    let reactions: [AmenReactionType]
    let onSelect: (AmenReactionType) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(reactions, id: \.self) { reaction in
                    AmenReactionButton(reaction: reaction) {
                        onSelect(reaction)
                    }
                }
            }
        }
    }
}

struct AmenReactionButton: View {
    let reaction: AmenReactionType
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: reaction.symbolName)
                    .font(.system(size: 12, weight: .semibold))
                Text(reaction.title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.black.opacity(0.82))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule(style: .continuous).fill(Color.white.opacity(0.82)))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(reaction.title)
    }
}

struct AmenDiscernmentSheet: View {
    let trigger: AmenTriggerResult
    let originalText: String
    let suggestedRewrite: String?
    let onAction: (AmenDiscernmentAction) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(sheetTitle)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.black)

                Text(trigger.message)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.74))

                Text("Your words are still yours. Amen is offering a pause before they reach someone else.")
                    .font(.system(size: 14))
                    .foregroundStyle(.black.opacity(0.7))

                if let suggestedRewrite, !suggestedRewrite.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Rewrite preview")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.black.opacity(0.5))

                        Text("Original")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.black.opacity(0.45))
                        Text("“\(originalText)”")
                            .font(.system(size: 14))
                            .foregroundStyle(.black.opacity(0.84))

                        Text("Suggested")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.black.opacity(0.45))
                        Text("“\(suggestedRewrite)”")
                            .font(.system(size: 14))
                            .foregroundStyle(.black.opacity(0.84))
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.white.opacity(0.8))
                    )
                }

                VStack(spacing: 10) {
                    ForEach(trigger.recommendedActions, id: \.self) { action in
                        Button {
                            onAction(action)
                        } label: {
                            Text(action.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(primaryAction == action ? Color.white : Color.black.opacity(0.82))
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 48)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(primaryAction == action ? Color.black : Color.white.opacity(0.84))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(24)
        }
        .background(Color.white.ignoresSafeArea())
    }

    private var sheetTitle: String {
        switch trigger.type {
        case .prayerRequest: "Prayer Moment"
        case .scriptureReference: "Scripture Detected"
        case .testimony, .gratitude: "Testimony Moment"
        case .conflictTone: "Peace Check"
        default: "Discernment Moment"
        }
    }

    private var primaryAction: AmenDiscernmentAction? {
        trigger.recommendedActions.first(where: { $0 == .editWithGrace || $0 == .rewriteGently || $0 == .joinPrayer || $0 == .openScripture })
            ?? trigger.recommendedActions.first
    }
}

struct AmenComposerDiscernmentOverlay: View {
    let triggers: [AmenTriggerResult]

    var body: some View {
        if !triggers.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                AmenSafetyReactionLayer(triggers: triggers, maxVisible: 3) { _ in }
                    .allowsHitTesting(false)

                if triggers.contains(where: { $0.type == .conflictTone || $0.type == .shameTone }) {
                    Text("Pause stays available, but Amen is slowing the moment down.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.black.opacity(0.58))
                        .accessibilityLabel("Discernment moment detected")
                }
            }
        }
    }
}

struct AmenReactionEffectHost: View {
    let policy: AmenReactionEffectPolicy?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let policy {
            effectView(for: policy)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func effectView(for policy: AmenReactionEffectPolicy) -> some View {
        switch policy.effectType {
        case .amenPulse:
            AmenPulseEffect(reduceMotion: reduceMotion && policy.shouldRespectReducedMotion)
        case .prayerThreadGlow:
            PrayerThreadGlowEffect(reduceMotion: reduceMotion && policy.shouldRespectReducedMotion)
        case .livingWordShimmer, .scriptureCapsule:
            LivingWordShimmerEffect(reduceMotion: reduceMotion && policy.shouldRespectReducedMotion)
        case .peaceSlowdown, .discernmentPause:
            PeaceSlowdownEffect()
        case .gratitudeBloom:
            GratitudeBloomEffect(reduceMotion: reduceMotion && policy.shouldRespectReducedMotion)
        case .none:
            EmptyView()
        }
    }
}

struct AmenCommentReactionEffectHost: View {
    let policy: AmenReactionEffectPolicy?

    var body: some View {
        AmenReactionEffectHost(policy: policy)
    }
}

struct AmenMicrocopyToast: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.black.opacity(0.82))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule(style: .continuous).fill(Color.white.opacity(0.92)))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 8, y: 2)
    }
}

struct AmenSafetyLaneBadge: View {
    let lane: AmenSafetyLane

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(fillColor)
                .frame(width: 8, height: 8)
            Text(lane.accessibilityLabel)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(.black.opacity(0.66))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(lane.accessibilityLabel)
    }

    private var fillColor: Color {
        switch lane {
        case .green: Color.black.opacity(0.55)
        case .blue: Color.black.opacity(0.42)
        case .amber: Color.black.opacity(0.28)
        case .red: Color.black.opacity(0.2)
        }
    }
}

private struct AmenPulseEffect: View {
    let reduceMotion: Bool
    @State private var animate = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.black.opacity(0.08), lineWidth: 18)
                .frame(width: 120, height: 120)
                .scaleEffect(animate && !reduceMotion ? 1.2 : 0.7)
                .opacity(animate ? 0 : 0.85)

            Text("Amen")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.black.opacity(0.7))
                .offset(y: animate && !reduceMotion ? -24 : 0)
                .opacity(animate ? 0 : 1)
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.9)) {
                animate = true
            }
        }
    }
}

private struct PrayerThreadGlowEffect: View {
    let reduceMotion: Bool
    @State private var glow = false

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.04))
                .frame(width: 180, height: 72)
                .shadow(color: Color.black.opacity(glow ? 0.12 : 0.03), radius: glow ? 20 : 8, y: 0)

            if reduceMotion {
                Text("Prayer")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.54))
            } else {
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(Color.black.opacity(0.16))
                            .frame(width: 8, height: 8)
                            .offset(y: glow ? -18 : 10)
                            .opacity(glow ? 0 : 1)
                            .animation(.easeOut(duration: 0.9).delay(Double(index) * 0.08), value: glow)
                    }
                }
            }
        }
        .onAppear {
            glow = true
        }
    }
}

private struct LivingWordShimmerEffect: View {
    let reduceMotion: Bool
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.clear)
                .overlay(
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.9), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: reduceMotion ? 32 : 80)
                    .offset(x: phase * width)
                )
                .mask(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .onAppear {
            withAnimation(.easeInOut(duration: reduceMotion ? 0.35 : 0.9)) {
                phase = 1
            }
        }
    }
}

private struct PeaceSlowdownEffect: View {
    @State private var visible = false

    var body: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Color.black.opacity(visible ? 0.035 : 0.015))
            .overlay(
                Text("Peace check")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.black.opacity(0.35))
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2)) {
                    visible = true
                }
            }
    }
}

private struct GratitudeBloomEffect: View {
    let reduceMotion: Bool
    @State private var bloom = false

    var body: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(
                RadialGradient(
                    colors: [Color.black.opacity(bloom ? 0.05 : 0.01), .clear],
                    center: .center,
                    startRadius: 8,
                    endRadius: bloom ? (reduceMotion ? 80 : 160) : 40
                )
            )
            .onAppear {
                withAnimation(.easeOut(duration: reduceMotion ? 0.25 : 0.8)) {
                    bloom = true
                }
            }
    }
}
