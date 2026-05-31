// A11yCoPilotService.swift
// AMENAPP — Accessibility Intelligence Layer

import Foundation

@MainActor
final class A11yCoPilotService: ObservableObject {

    static let shared = A11yCoPilotService()

    @Published private(set) var pendingSuggestion: AccessibilitySuggestion? = nil
    @Published private(set) var isShowingBanner: Bool = false

    private var suppressedTypes: Set<AccessibilitySuggestionType> = []

    private init() {}

    func record(signal: AccessibilitySignal) {
        AccessibilitySignalCollector.shared.recordSignal(signal)
        evaluateSuggestion()
    }

    func suppress(type: AccessibilitySuggestionType) {
        suppressedTypes.insert(type)
        isShowingBanner = false
        pendingSuggestion = nil
    }

    func dismissBanner() {
        isShowingBanner = false
        pendingSuggestion = nil
    }

    func acceptSuggestion(_ suggestion: AccessibilitySuggestion) {
        dlog("[A11yCoPilot] applying \(suggestion.type.rawValue)")
        dismissBanner()
    }

    private func evaluateSuggestion() {
        guard AMENFeatureFlags.shared.adaptiveAccessibilityEnabled else { return }
        guard !isShowingBanner else { return }

        let agg = AccessibilitySignalCollector.shared.signals

        if agg.translateCount >= 5 && !suppressedTypes.contains(.enableAutoTranslate) {
            surface(AccessibilitySuggestion(
                type: .enableAutoTranslate,
                title: "Enable Auto-Translate",
                message: "You've translated several posts. Turn on auto-translate to see them in your language automatically.",
                actionLabel: "Enable"
            ))
            return
        }

        if agg.simplifyCount >= 5 && !suppressedTypes.contains(.enableDefaultSimplify) {
            surface(AccessibilitySuggestion(
                type: .enableDefaultSimplify,
                title: "Simplify by Default",
                message: "You frequently simplify content. Enable simplified reading as your default view.",
                actionLabel: "Enable"
            ))
        }
    }

    private func surface(_ suggestion: AccessibilitySuggestion) {
        pendingSuggestion = suggestion
        isShowingBanner = true
    }
}
