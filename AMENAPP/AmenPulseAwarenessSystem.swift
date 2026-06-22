import SwiftUI
import Combine

// MARK: - AmenPulseAwarenessSystem
//
// Detects interaction signals (confusion, fatigue, hesitation, etc.) and
// surfaces quiet contextual suggestions — never manipulative, only helpful.
//
// Design contract:
//  - Pulse ADAPTS the UI (reduces density, calms motion, offers help)
//  - Pulse does NOT push urgency, create FOMO, or exploit emotional state
//  - Max 1 Pulse suggestion shown at a time
//  - Suggestions auto-dismiss after suggestionsAutoDismissInterval
//  - All signals are logged via logPresenceSignal (best-effort, privacy-safe)

@MainActor
final class AmenPulseAwarenessEngine: ObservableObject {
    static let shared = AmenPulseAwarenessEngine()

    // MARK: - Published State

    @Published private(set) var currentSuggestion: PulseSuggestion? = nil
    @Published private(set) var focusModeActive: Bool = false
    @Published private(set) var densityLevel: DensityLevel = .normal

    // MARK: - Signal Counters (session-scoped, privacy-safe)

    private var confusionCount = 0
    private var repeatedTapCount = 0
    private var failedActionCount = 0
    private var scrollFatigueCount = 0
    private var lastScrollActivity = Date()
    private var dismissTimer: AnyCancellable?

    private let suggestionsAutoDismissInterval: TimeInterval = 8

    private init() {}

    // MARK: - Signal Recording

    func recordSignal(_ type: AmenPulseSignalType, screen: String = "", sourceId: String? = nil) {
        switch type {
        case .confusion:
            confusionCount += 1
            evaluateConfusion(screen: screen)
        case .repeatedTap:
            repeatedTapCount += 1
            evaluateRepeatedTap(screen: screen)
        case .failedAction:
            failedActionCount += 1
            evaluateFailedAction(screen: screen)
        case .scrollFatigue:
            scrollFatigueCount += 1
            evaluateScrollFatigue(screen: screen)
        case .hesitation:
            evaluateHesitation(screen: screen)
        case .reflectionMoment:
            surfaceSuggestion(.reflectAndSave, screen: screen)
        case .urgency:
            densityLevel = .reduced
        case .overload:
            activateFocusMode()
        }

        // Privacy-safe background log
        Task {
            await AmenSemanticIntelligenceService.shared.logPresenceSignal(
                screen: screen,
                signalType: type,
                sourceId: sourceId
            )
        }
    }

    // MARK: - Suggestion Surface

    func surfaceSuggestion(_ suggestion: PulseSuggestion, screen: String = "") {
        guard currentSuggestion == nil || currentSuggestion!.priority <= suggestion.priority else { return }
        currentSuggestion = suggestion
        scheduleDismiss()

        // Analytics
        Task {
            await AmenSemanticIntelligenceService.shared.logPresenceSignal(
                screen: screen,
                signalType: .hesitation,
                metadata: ["suggestionType": suggestion.analyticsName]
            )
        }
    }

    func dismissSuggestion() {
        dismissTimer?.cancel()
        currentSuggestion = nil
    }

    // MARK: - Focus Mode

    func activateFocusMode() {
        focusModeActive = true
        densityLevel = .minimal
    }

    func deactivateFocusMode() {
        focusModeActive = false
        densityLevel = .normal
        confusionCount = 0
    }

    // MARK: - Evaluation Logic

    private func evaluateConfusion(screen: String) {
        switch confusionCount {
        case 2: surfaceSuggestion(.simplify, screen: screen)
        case 4: surfaceSuggestion(.askBerean, screen: screen)
        case 6: activateFocusMode()
        default: break
        }
    }

    private func evaluateRepeatedTap(screen: String) {
        if repeatedTapCount >= 3 {
            surfaceSuggestion(.simplify, screen: screen)
            repeatedTapCount = 0
        }
    }

    private func evaluateFailedAction(screen: String) {
        if failedActionCount >= 2 {
            surfaceSuggestion(.needHelp, screen: screen)
            failedActionCount = 0
        }
    }

    private func evaluateScrollFatigue(screen: String) {
        if scrollFatigueCount >= 5 {
            surfaceSuggestion(.pauseAndReflect, screen: screen)
            densityLevel = .reduced
            scrollFatigueCount = 0
        }
    }

    private func evaluateHesitation(screen: String) {
        surfaceSuggestion(.saveToSelah, screen: screen)
    }

    // MARK: - Auto-dismiss

    private func scheduleDismiss() {
        dismissTimer?.cancel()
        dismissTimer = Just(())
            .delay(for: .seconds(suggestionsAutoDismissInterval), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.currentSuggestion = nil
            }
    }

    // MARK: - Session Reset

    func resetSession() {
        confusionCount = 0
        repeatedTapCount = 0
        failedActionCount = 0
        scrollFatigueCount = 0
        currentSuggestion = nil
        focusModeActive = false
        densityLevel = .normal
        dismissTimer?.cancel()
    }
}

// MARK: - PulseSuggestion

struct PulseSuggestion: Identifiable, Equatable {
    let id = UUID()
    let icon: String
    let message: String
    let priority: AmenPresencePriority
    let analyticsName: String
    let action: (() -> Void)?

    static func == (lhs: PulseSuggestion, rhs: PulseSuggestion) -> Bool {
        lhs.id == rhs.id
    }

    // Standard suggestions
    static let simplify = PulseSuggestion(
        icon: "text.redaction",
        message: "Need a simpler explanation?",
        priority: .semanticDefinition,
        analyticsName: "simplify",
        action: nil
    )

    static let askBerean = PulseSuggestion(
        icon: "sparkles",
        message: "Ask Berean to explain this?",
        priority: .semanticDefinition,
        analyticsName: "ask_berean",
        action: nil
    )

    static let pauseAndReflect = PulseSuggestion(
        icon: "pause.circle",
        message: "Want to pause and reflect?",
        priority: .reflection,
        analyticsName: "pause_and_reflect",
        action: nil
    )

    static let saveToSelah = PulseSuggestion(
        icon: "bookmark",
        message: "Save this to Selah?",
        priority: .reflection,
        analyticsName: "save_to_selah",
        action: nil
    )

    static let reflectAndSave = PulseSuggestion(
        icon: "heart.text.square",
        message: "Open Church Notes?",
        priority: .reflection,
        analyticsName: "open_church_notes",
        action: nil
    )

    static let needHelp = PulseSuggestion(
        icon: "questionmark.circle",
        message: "Having trouble? Let Berean help.",
        priority: .activeTask,
        analyticsName: "need_help",
        action: nil
    )
}

// MARK: - DensityLevel

enum DensityLevel {
    case normal
    case reduced
    case minimal
}

// MARK: - AmenPulseBannerView
// A compact Liquid Glass banner that surfaces the current Pulse suggestion.

struct AmenPulseBannerView: View {
    let suggestion: PulseSuggestion
    var onAction: (() -> Void)? = nil
    var onDismiss: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPressed = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: suggestion.icon)
                .font(.systemScaled(14, weight: .medium))
                .foregroundStyle(.primary.opacity(0.72))

            Text(suggestion.message)
                .font(.systemScaled(13, weight: .medium))
                .foregroundStyle(.primary)

            Spacer()

            if onAction != nil {
                Button("Yes") {
                    onAction?()
                    onDismiss()
                }
                .font(.systemScaled(13, weight: .semibold))
                .foregroundStyle(.blue)
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.systemScaled(11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss suggestion")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(bannerBackground)
        .clipShape(Capsule(style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(suggestion.message)
        .accessibilityHint(onAction != nil ? "Double-tap to act, or swipe to dismiss" : "")
        .transition(
            reduceMotion
                ? .opacity
                : .opacity.combined(with: .move(edge: .bottom))
        )
    }

    @ViewBuilder
    private var bannerBackground: some View {
        if reduceTransparency {
            Capsule(style: .continuous)
                .fill(Color(.systemBackground))
                .overlay(Capsule(style: .continuous).strokeBorder(Color.primary.opacity(0.14)))
        } else {
            Capsule(style: .continuous)
                .fill(.thinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color.white.opacity(0.16), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        ))
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.48), Color.white.opacity(0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.6
                        )
                }
        }
    }
}

// MARK: - View Modifier: Pulse Awareness Overlay

extension View {
    /// Attaches a Pulse suggestion banner to the bottom of any view.
    /// Banner appears above the keyboard / bottom bar.
    @MainActor
    func amenPulseOverlay(
        engine: AmenPulseAwarenessEngine? = nil,
        onAction: ((PulseSuggestion) -> Void)? = nil
    ) -> some View {
        modifier(AmenPulseOverlayModifier(engine: engine ?? AmenPulseAwarenessEngine.shared, onAction: onAction))
    }
}

struct AmenPulseOverlayModifier: ViewModifier {
    @ObservedObject var engine: AmenPulseAwarenessEngine
    var onAction: ((PulseSuggestion) -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let suggestion = engine.currentSuggestion {
                    AmenPulseBannerView(
                        suggestion: suggestion,
                        onAction: onAction.map { fn in { fn(suggestion) } },
                        onDismiss: { engine.dismissSuggestion() }
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }
            }
            .animation(
                reduceMotion ? .none : .spring(response: 0.32, dampingFraction: 0.84),
                value: engine.currentSuggestion?.id
            )
    }
}
