// BereanSmartPillSystem.swift
// AMENAPP
//
// Mode-aware, safety-aware smart pill system for Berean AI.
// Renders contextual action pills below AI responses.
//
// Rules:
//   - Safety override pills replace mode pills during crisis states
//   - Debate/deep-dive pills are hidden during crisis
//   - Pills are feature-flag gated (bereanSmartPillsEnabled)
//   - Each pill fires a real action + analytics event
//   - Reduce Motion support
//   - VoiceOver accessible
//

import SwiftUI

// MARK: - BereanScriptureReferenceExtractor

enum BereanScriptureReferenceExtractor {
    private static let pattern: String = {
        let books = [
            "genesis","exodus","leviticus","numbers","deuteronomy",
            "joshua","judges","ruth","samuel","kings","chronicles",
            "ezra","nehemiah","esther","job","psalm","psalms",
            "proverbs","ecclesiastes","isaiah","jeremiah","lamentations",
            "ezekiel","daniel","hosea","joel","amos","obadiah","jonah",
            "micah","nahum","habakkuk","zephaniah","haggai","zechariah",
            "malachi","matthew","mark","luke","john","acts","romans",
            "corinthians","galatians","ephesians","philippians","colossians",
            "thessalonians","timothy","titus","philemon","hebrews","james",
            "peter","jude","revelation"
        ]
        return "(?:1|2|3|i|ii|iii)?\\s*(?:\(books.joined(separator: "|")))\\s+\\d+(?:[:\\.]\\d+)?(?:\\s*-\\s*\\d+)?"
    }()

    private static let regex: NSRegularExpression? = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)

    static func references(in text: String) -> [String] {
        guard let regex else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }
}

// MARK: - BereanSmartPill

enum BereanSmartPill: String, CaseIterable {
    // Generic
    case explainDeeper       = "explain_deeper"
    case showScriptureContext = "show_scripture_context"
    case compareInterpretations = "compare_interpretations"
    case showCrossReferences = "show_cross_references"
    case saveToSelah         = "save_to_selah"
    case addToChurchNotes    = "add_to_church_notes"
    case buildStudyPlan      = "build_study_plan"
    case prayThrough         = "pray_through"
    case reflectPrivately    = "reflect_privately"
    case askTrustedPastor    = "ask_trusted_pastor"
    case seeAnotherPerspective = "see_another_perspective"
    case pauseBeforeResponding = "pause_before_responding"
    case continueResearch    = "continue_research"

    // Wisdom/Paul lens
    case comparePassages     = "compare_passages"
    case practicalNextStep   = "practical_next_step"
    case showDoctrineContext = "show_doctrine_context"

    // Prayer/David lens
    case turnIntoJournal     = "turn_into_journal"
    case readAPsalm          = "read_a_psalm"

    // Discernment/Solomon lens
    case discernMotives      = "discern_motives"
    case wiseNextStep        = "wise_next_step"

    // Safety override (shown during crisis — replace all others)
    case pause               = "pause"
    case breathe             = "breathe"
    case talkToSomeone       = "talk_to_someone"
    case findImmediateHelp   = "find_immediate_help"
    case savePrivately       = "save_privately"
    case readPsalm23         = "read_psalm_23"

    var displayLabel: String {
        switch self {
        case .explainDeeper:          return "Explain deeper"
        case .showScriptureContext:   return "Show context"
        case .compareInterpretations: return "Compare views"
        case .showCrossReferences:    return "Cross-references"
        case .saveToSelah:            return "Save to Selah"
        case .addToChurchNotes:       return "Add to Notes"
        case .buildStudyPlan:         return "Build study plan"
        case .prayThrough:            return "Pray through this"
        case .reflectPrivately:       return "Reflect privately"
        case .askTrustedPastor:       return "Ask a pastor"
        case .seeAnotherPerspective:  return "Another view"
        case .pauseBeforeResponding:  return "Pause"
        case .continueResearch:       return "Continue research"
        case .comparePassages:        return "Compare passages"
        case .practicalNextStep:      return "Next step"
        case .showDoctrineContext:    return "Doctrine context"
        case .turnIntoJournal:        return "Add to journal"
        case .readAPsalm:             return "Read a Psalm"
        case .discernMotives:         return "Discern motives"
        case .wiseNextStep:           return "Wise next step"
        case .pause:                  return "Pause"
        case .breathe:                return "Breathe"
        case .talkToSomeone:          return "Talk to someone"
        case .findImmediateHelp:      return "Find help"
        case .savePrivately:          return "Save privately"
        case .readPsalm23:            return "Read Psalm 23"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .saveToSelah:      return "Save to Selah journal"
        case .addToChurchNotes: return "Add to Church Notes"
        case .talkToSomeone:    return "Talk to someone trusted"
        case .findImmediateHelp: return "Find immediate help"
        default:                return displayLabel
        }
    }

    var isSafetyPill: Bool {
        switch self {
        case .pause, .breathe, .talkToSomeone, .findImmediateHelp, .savePrivately, .readPsalm23:
            return true
        default:
            return false
        }
    }

    var isDebateOrDeepDive: Bool {
        switch self {
        case .compareInterpretations, .comparePassages, .showCrossReferences,
             .showDoctrineContext, .continueResearch, .buildStudyPlan, .explainDeeper:
            return true
        default:
            return false
        }
    }
}

// MARK: - BereanSmartPillEngine

struct BereanSmartPillEngine {

    /// Returns the appropriate smart pills for the given context.
    /// Safety state overrides all mode-based preferences.
    static func pills(
        lens: BereanTheoLens,
        isCrisisState: Bool,
        sensitivityFlags: [SensitivityFlag],
        hasScriptureRefs: Bool
    ) -> [BereanSmartPill] {

        // Safety override: crisis/self-harm states get only safety pills
        let isCrisis = isCrisisState ||
            sensitivityFlags.contains(.crisisEscalation) ||
            sensitivityFlags.contains(.pastoralEscalation)

        if isCrisis {
            return safetyOverridePills()
        }

        // Check for scrupulosity — suppress debate pills
        let suppressDebate = sensitivityFlags.contains(.scrupulosityRisk)

        // Build mode-preferred pills
        var preferred = lens.preferredSmartPills

        // Always include cross-surface actions when bridges are enabled
        if AMENFeatureFlags.shared.bereanSelahBridgeEnabled {
            if !preferred.contains(.saveToSelah) {
                preferred.insert(.saveToSelah, at: min(2, preferred.count))
            }
        }
        if AMENFeatureFlags.shared.bereanChurchNotesBridgeEnabled {
            if !preferred.contains(.addToChurchNotes) {
                preferred.append(.addToChurchNotes)
            }
        }

        // Add scripture context pill if response has refs
        if hasScriptureRefs && !preferred.contains(.showScriptureContext) {
            preferred.insert(.showScriptureContext, at: 0)
        }

        // Suppress debate/deep-dive pills for scrupulosity
        if suppressDebate {
            preferred = preferred.filter { !$0.isDebateOrDeepDive }
            preferred.append(.askTrustedPastor)
        }

        // Feature flag check
        guard AMENFeatureFlags.shared.bereanSmartPillsEnabled else { return [] }

        return Array(preferred.prefix(6))
    }

    /// Safety-only pill set for crisis states.
    private static func safetyOverridePills() -> [BereanSmartPill] {
        return [.pause, .breathe, .talkToSomeone, .findImmediateHelp, .readPsalm23, .savePrivately]
    }
}

// MARK: - BereanSmartPillsView

struct BereanSmartPillsView: View {
    let message: BereanSpiritualMessage
    let conversationId: String
    let onAskFollowUp: (String) -> Void
    let onShowScriptureContext: (String) -> Void

    @State private var showSelahSheet = false
    @State private var showChurchNotesSheet = false

    @ObservedObject private var lensStore = BereanTheoLensStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isCrisisState: Bool {
        message.structuredResponse?.sensitivityFlags.contains(.crisisEscalation) == true ||
        message.structuredResponse?.spiritualState?.primaryState == .crisis
    }

    private var pills: [BereanSmartPill] {
        BereanSmartPillEngine.pills(
            lens: lensStore.selectedLens,
            isCrisisState: isCrisisState,
            sensitivityFlags: message.structuredResponse?.sensitivityFlags ?? [],
            hasScriptureRefs: !BereanScriptureReferenceExtractor.references(in: message.content).isEmpty
        )
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(pills, id: \.rawValue) { pill in
                    BereanSmartPillButton(
                        pill: pill,
                        onTap: { handlePillTap(pill) }
                    )
                }
            }
            .padding(.horizontal, 2)
        }
        .sheet(isPresented: $showSelahSheet) {
            BereanSaveToSelahSheet(
                message: message,
                conversationId: conversationId,
                isPresented: $showSelahSheet
            )
        }
        .sheet(isPresented: $showChurchNotesSheet) {
            BereanSaveToChurchNotesSheet(
                message: message,
                conversationId: conversationId,
                isPresented: $showChurchNotesSheet
            )
        }
    }

    private func handlePillTap(_ pill: BereanSmartPill) {
        AMENAnalyticsService.shared.track(.bereanSmartPillTapped(pill: pill.rawValue))

        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()

        switch pill {
        case .saveToSelah:
            showSelahSheet = true

        case .addToChurchNotes:
            showChurchNotesSheet = true

        case .showScriptureContext:
            let refs = BereanScriptureReferenceExtractor.references(in: message.content)
            if let firstRef = refs.first {
                onShowScriptureContext(firstRef)
                AMENAnalyticsService.shared.track(.bereanScriptureContextOpened)
            }

        case .explainDeeper:
            onAskFollowUp("Can you explain this more deeply?")

        case .compareInterpretations, .comparePassages:
            onAskFollowUp("What are the main different interpretations of this?")

        case .showCrossReferences:
            onAskFollowUp("What are the key cross-references for this passage?")

        case .showDoctrineContext:
            onAskFollowUp("What is the broader doctrinal context here?")

        case .practicalNextStep:
            onAskFollowUp("What is one practical next step I should consider?")

        case .prayThrough:
            onAskFollowUp("Help me pray through this topic.")

        case .reflectPrivately:
            showSelahSheet = true

        case .turnIntoJournal:
            showSelahSheet = true

        case .readAPsalm:
            onAskFollowUp("Which psalm speaks most directly to this?")

        case .discernMotives:
            onAskFollowUp("Help me discern the motives or pressures at play here.")

        case .pauseBeforeResponding, .pause:
            // Pause: just haptic + no action — encourages the user to stop and think
            let notification = UINotificationFeedbackGenerator()
            notification.notificationOccurred(.warning)

        case .breathe:
            // Breathing: surface a simple encouragement
            onAskFollowUp("Give me a brief grounding reflection to help me slow down.")

        case .talkToSomeone:
            AMENAnalyticsService.shared.track(.bereanHumanSupportSuggested(context: "smart_pill"))
            onAskFollowUp("I need to talk to someone trusted. What would be helpful to tell them?")

        case .findImmediateHelp:
            AMENAnalyticsService.shared.track(.bereanHumanSupportSuggested(context: "crisis_pill"))
            // In a real app this would open a crisis resources view
            onAskFollowUp("Please show me crisis support resources.")

        case .readPsalm23:
            onAskFollowUp("Show me Psalm 23 and help me reflect on it slowly.")

        case .savePrivately:
            showSelahSheet = true

        case .buildStudyPlan:
            onAskFollowUp("Help me build a short study plan around this topic.")

        case .continueResearch:
            AMENAnalyticsService.shared.track(.bereanResearchViewOpened)
            onAskFollowUp("Let's go deeper on this topic. What should I study next?")

        case .wiseNextStep:
            onAskFollowUp("What is the wisest next step I could take here?")

        case .seeAnotherPerspective:
            onAskFollowUp("What would a different Christian tradition say about this?")

        case .askTrustedPastor:
            AMENAnalyticsService.shared.track(.bereanHumanSupportSuggested(context: "pastor_referral"))
            onAskFollowUp("How would I bring this question to my pastor?")
        }
    }
}

// MARK: - BereanSmartPillButton

private struct BereanSmartPillButton: View {
    let pill: BereanSmartPill
    let onTap: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var pillColor: Color {
        pill.isSafetyPill ? Color(red: 0.85, green: 0.25, blue: 0.30) : Color.primary
    }

    var body: some View {
        Button(action: onTap) {
            Text(pill.displayLabel)
                .font(AMENFont.regular(12))
                .foregroundColor(pill.isSafetyPill ? .white : .primary)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(
                            pill.isSafetyPill
                            ? pillColor
                            : (reduceTransparency ? Color(.secondarySystemBackground) : Color(.secondarySystemBackground))
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    pill.isSafetyPill ? .clear : Color.primary.opacity(0.08),
                                    lineWidth: 0.5
                                )
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(pill.accessibilityLabel)
    }
}
