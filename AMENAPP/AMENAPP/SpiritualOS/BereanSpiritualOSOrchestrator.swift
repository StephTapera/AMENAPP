import Foundation
import FirebaseAuth
import FirebaseFunctions

// MARK: - User Action Event

struct SpiritualOSUserEvent {
    let surface: SpiritualOSSurface
    let text: String
    let actionId: String
    let typingBehavior: TypingBehavior?
    let associatedPersonId: String?
    let associatedContentId: String?
}

enum SpiritualOSSurface: String, CaseIterable {
    case postComposer = "post_composer"
    case commentComposer = "comment_composer"
    case bereanChat = "berean_chat"
    case churchNotes = "church_notes"
    case prayerJournal = "prayer_journal"
    case walkWithChrist = "walk_with_christ"
    case amenMedia = "amen_media"
    case directMessage = "direct_message"
}

// MARK: - Orchestrator

/// Routes user action events through the Spiritual OS pipeline.
/// Runs lightweight client classifiers first; escalates to Berean AI only when needed.
/// Never hard-blocks the user. Throttles prompts to at most 1 per 5 minutes per surface.
@MainActor
final class BereanSpiritualOSOrchestrator: ObservableObject {
    static let shared = BereanSpiritualOSOrchestrator()

    // MARK: - Dependencies

    private let unsentService = UnsentThoughtsService.shared
    private let momentService = MomentInterceptionService.shared
    private let wordWeightService = WeightOfWordsService.shared
    private let reflectionService = PostActionReflectionService.shared
    private let eternalWeightService = EternalWeightService.shared

    // MARK: - Throttle State

    // Per-surface timestamp of the last surfaced prompt
    private var lastPromptBySurface: [SpiritualOSSurface: Date] = [:]
    private let minimumPromptIntervalSeconds: TimeInterval = 300 // 5 minutes

    private init() {}

    // MARK: - Main Entry Point

    /// Evaluate a user action event and return a SpiritualOSPrompt if warranted.
    /// Returns nil if throttled or if no meaningful signal is present.
    func evaluate(event: SpiritualOSUserEvent) async -> SpiritualOSPrompt? {
        guard Auth.auth().currentUser != nil else { return nil }
        guard canSurfacePrompt(for: event.surface) else { return nil }
        guard !event.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        // Step 1: Run lightweight classifiers
        let clientFlags = unsentService.detectRisk(text: event.text, surface: event.surface.rawValue)
        let momentTriggers = detectMomentTriggers(event: event)

        // Step 2: Early return if no client-side signals
        let clientSignalCount = clientFlags.count + momentTriggers.count
        guard clientSignalCount > 0 else { return nil }

        // Step 3: Word weight check (fast, client-side heuristic first)
        let wordWeightSignal = assessWordWeight(text: event.text)

        // Step 4: Determine if deeper Berean analysis is needed
        let needsBereanAnalysis = clientSignalCount >= 2 || wordWeightSignal >= 0.7

        // Step 5: Compose the prompt from gathered signals
        if momentTriggers.count > 0 && !momentService.shouldShowOverlay {
            // Moment interception takes priority
            let riskScore = Double(momentTriggers.count) / 5.0
            if riskScore > 0.4 {
                let prompt = buildMomentInterceptPrompt(
                    triggers: momentTriggers,
                    riskScore: riskScore,
                    surface: event.surface
                )
                if prompt.shouldSurfacePrompt {
                    recordPromptSurfaced(for: event.surface)
                    return prompt
                }
            }
        }

        if wordWeightSignal >= 0.6 && event.surface == .postComposer || event.surface == .commentComposer {
            let prompt = buildWeightOfWordsPrompt(score: wordWeightSignal, surface: event.surface)
            if prompt.shouldSurfacePrompt {
                recordPromptSurfaced(for: event.surface)
                return prompt
            }
        }

        if !clientFlags.isEmpty {
            let intensity = Double(clientFlags.count) / 5.0
            if intensity > 0.3 {
                let prompt = buildUnsentThoughtPrompt(
                    flags: clientFlags,
                    intensity: intensity,
                    surface: event.surface,
                    needsBereanAnalysis: needsBereanAnalysis
                )
                if prompt.shouldSurfacePrompt {
                    recordPromptSurfaced(for: event.surface)

                    // Fire deeper analysis in background if warranted — does not block the return
                    if needsBereanAnalysis {
                        Task { [weak self] in
                            guard let self else { return }
                            _ = await self.unsentService.analyzeText(
                                text: event.text,
                                surface: event.surface.rawValue
                            )
                        }
                    }

                    return prompt
                }
            }
        }

        return nil
    }

    // MARK: - Post-Action Reflection Trigger

    /// Call after a user completes a significant spiritual action.
    func triggerPostActionReflection(actionId: String, actionType: ReflectionActionType) {
        guard Auth.auth().currentUser != nil else { return }
        reflectionService.triggerReflection(for: actionId, actionType: actionType)
    }

    // MARK: - Eternal Weight Hook

    /// Call when a user has produced content that should be tracked over time.
    func evaluateEternalWeight(contentId: String) async {
        guard Auth.auth().currentUser != nil else { return }
        await eternalWeightService.calculateWeight(for: contentId)
    }

    // MARK: - Prompt Builders

    private func buildMomentInterceptPrompt(
        triggers: [MomentTriggerType],
        riskScore: Double,
        surface: SpiritualOSSurface
    ) -> SpiritualOSPrompt {
        let message: String
        if triggers.contains(.lateNightPosting) {
            message = "It's late. Would you like to save this and revisit it in the morning?"
        } else if triggers.contains(.spiritualManipulationRisk) {
            message = "Something in your message may carry more weight than intended. Take a moment before sending?"
        } else if triggers.contains(.highAngerScore) {
            message = "Your words carry strong emotion right now. That's okay — just take a breath first?"
        } else {
            message = "Before you send this, take a moment. You can always come back to it."
        }

        return SpiritualOSPrompt(
            promptType: .momentIntercept,
            confidence: riskScore,
            userFacingMessage: message,
            suggestedActions: [.breathe, .prayFirst, .saveAsDraft, .continueWriting],
            privateSignalIds: [],
            safetyFlags: triggers.map { $0.rawValue },
            shouldSurfacePrompt: riskScore > 0.4
        )
    }

    private func buildWeightOfWordsPrompt(score: Double, surface: SpiritualOSSurface) -> SpiritualOSPrompt {
        let label: WordWeightLabel
        switch score {
        case 0.0..<0.3: label = .light
        case 0.3..<0.5: label = .encouraging
        case 0.5..<0.7: label = .heavy
        case 0.7..<0.85: label = .sharp
        default: label = .harmful
        }

        return SpiritualOSPrompt(
            promptType: .weightOfWordsAlert,
            confidence: score,
            userFacingMessage: label.mirrorMessage,
            suggestedActions: score >= 0.7
                ? [.rewriteWithGrace, .runPeaceCheck, .saveAsDraft, .shareAnyway]
                : [.continueWriting, .runPeaceCheck],
            privateSignalIds: [],
            safetyFlags: score >= 0.85 ? ["harmful_language_risk"] : [],
            shouldSurfacePrompt: score >= 0.6
        )
    }

    private func buildUnsentThoughtPrompt(
        flags: [String],
        intensity: Double,
        surface: SpiritualOSSurface,
        needsBereanAnalysis: Bool
    ) -> SpiritualOSPrompt {
        let message: String
        if flags.contains("shame_language") {
            message = "Some of these words may carry more sting than intended. Worth a second look?"
        } else if flags.contains("conflict_language") {
            message = "There's some tension in this message. Would you like to run a peace check first?"
        } else if flags.contains("late_night") {
            message = "Writing late at night can sometimes feel different in the morning. Would you like to save this?"
        } else {
            message = "You've been writing a while. Take a moment before you decide to send?"
        }

        var actions: [SpiritualOSAction] = [.continueWriting, .saveAsDraft, .turnToPrayer, .runPeaceCheck]
        if flags.contains("conflict_language") {
            actions = [.runPeaceCheck, .saveAsDraft, .turnToPrayer, .continueWriting]
        }

        return SpiritualOSPrompt(
            promptType: .unsentThoughtWarning,
            confidence: intensity,
            userFacingMessage: message,
            suggestedActions: actions,
            privateSignalIds: [],
            safetyFlags: flags,
            shouldSurfacePrompt: intensity > 0.3
        )
    }

    // MARK: - Client-Side Helpers

    private func detectMomentTriggers(event: SpiritualOSUserEvent) -> [MomentTriggerType] {
        guard let behavior = event.typingBehavior else { return [] }
        return momentService.evaluate(
            text: event.text,
            surface: event.surface.rawValue,
            typingBehavior: behavior
        )
    }

    private func assessWordWeight(text: String) -> Double {
        let lowered = text.lowercased()
        var score = 0.0

        let sharpWords = ["should be ashamed", "pathetic", "disgraceful", "how dare", "unbelievable",
                          "typical", "always do this", "never listen", "you people", "disgusting"]
        let matchCount = sharpWords.filter { lowered.contains($0) }.count
        score += Double(matchCount) * 0.2

        let manipulationWords = ["god told me", "if you were really christian", "you have to obey",
                                 "the bible says you must", "you're going to hell"]
        let manipCount = manipulationWords.filter { lowered.contains($0) }.count
        score += Double(manipCount) * 0.35

        return min(score, 1.0)
    }

    // MARK: - Throttle

    private func canSurfacePrompt(for surface: SpiritualOSSurface) -> Bool {
        guard let last = lastPromptBySurface[surface] else { return true }
        return Date().timeIntervalSince(last) > minimumPromptIntervalSeconds
    }

    private func recordPromptSurfaced(for surface: SpiritualOSSurface) {
        lastPromptBySurface[surface] = Date()
    }
}

// MARK: - MomentInterceptionService Helper Extension

private extension MomentInterceptionService {
    /// Synchronous trigger detection for use by the orchestrator (no overlay side effects)
    func evaluate(text: String, surface: String, typingBehavior: TypingBehavior) -> [MomentTriggerType] {
        var triggers: [MomentTriggerType] = []
        let hour = Calendar.current.component(.hour, from: Date())

        if hour >= 22 || hour <= 4 { triggers.append(.lateNightPosting) }
        if typingBehavior.wordsPerMinute > 120 { triggers.append(.rapidTyping) }
        if typingBehavior.deleteRewriteCount > 3 { triggers.append(.repeatedDeleteRewrite) }

        let lowered = text.lowercased()
        let angerWords = ["furious", "outraged", "how dare", "unbelievable", "disgusting", "shameful"]
        if angerWords.contains(where: { lowered.contains($0) }) { triggers.append(.highAngerScore) }

        let manipulationWords = ["god told me", "if you were really christian", "you have to", "the bible says you must"]
        if manipulationWords.contains(where: { lowered.contains($0) }) { triggers.append(.spiritualManipulationRisk) }

        return triggers
    }
}
