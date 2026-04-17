// AccessibilitySuggestionEngine.swift
// AMEN App — Accessibility Intelligence Layer (Phase 5)
//
// Rule-based suggestion engine using aggregated accessibility signals.
// Suggests feature auto-enablement with cooldown (max 1/session, max 3/week).
// Never auto-switches — always presents suggestion for user acceptance.

import Foundation

@MainActor
final class AccessibilitySuggestionEngine: ObservableObject {

    static let shared = AccessibilitySuggestionEngine()

    // MARK: - Published State

    @Published private(set) var pendingSuggestion: AccessibilitySuggestion?

    // MARK: - Cooldown

    private let cooldownKey = "amen.accessibility.suggestions"
    private var sessionSuggestionShown = false
    private let maxWeeklySuggestions = 3

    private init() {}

    // MARK: - Public API

    /// Evaluate signals and generate a suggestion if appropriate.
    /// Call this periodically (e.g., after each translation or simplification action).
    func evaluate() {
        guard AMENFeatureFlags.shared.adaptiveAccessibilityEnabled else { return }
        guard !sessionSuggestionShown else { return }
        guard canShowSuggestion() else { return }

        let collector = AccessibilitySignalCollector.shared
        let suggestion = generateSuggestion(collector: collector)

        if let suggestion {
            pendingSuggestion = suggestion
            sessionSuggestionShown = true
            recordSuggestionShown()
        }
    }

    /// User accepted the suggestion
    func acceptSuggestion() {
        guard let suggestion = pendingSuggestion else { return }
        applySuggestion(suggestion)
        pendingSuggestion = nil
    }

    /// User dismissed the suggestion
    func dismissSuggestion() {
        pendingSuggestion = nil
    }

    // MARK: - Suggestion Rules

    private func generateSuggestion(collector: AccessibilitySignalCollector) -> AccessibilitySuggestion? {
        // Rule 1: High translate frequency + no auto-translate → suggest auto-translate
        if collector.frequency(for: .translated) == .high {
            let prefs = TranslationSettingsManager.shared.preferences
            if prefs.contentTranslationMode != .auto {
                return AccessibilitySuggestion(
                    type: .enableAutoTranslate,
                    title: "Auto-translate posts?",
                    message: "You translate posts frequently. Would you like to turn on auto-translation?",
                    actionLabel: "Turn On"
                )
            }
        }

        // Rule 2: High simplify frequency → suggest default simplify
        if collector.frequency(for: .simplified) == .high {
            return AccessibilitySuggestion(
                type: .enableDefaultSimplify,
                title: "Simplify by default?",
                message: "You often use the Understand feature. Would you like posts simplified automatically?",
                actionLabel: "Enable"
            )
        }

        // Rule 3: Moderate listen frequency → suggest audio preferences
        if collector.frequency(for: .listenedToPost) == .moderate {
            return AccessibilitySuggestion(
                type: .configureAudio,
                title: "Customize audio settings",
                message: "You use Listen frequently. Would you like to adjust playback speed and voice?",
                actionLabel: "Set Up"
            )
        }

        // Rule 4: High translate frequency for a specific language + no per-language auto-translate → suggest it
        if collector.frequency(for: .translated) == .high,
           AMENFeatureFlags.shared.perLanguageAutoTranslateEnabled {
            let prefs = TranslationSettingsManager.shared.preferences
            if prefs.perLanguageAutoTranslate.isEmpty {
                return AccessibilitySuggestion(
                    type: .enablePerLanguageAutoTranslate,
                    title: "Auto-translate by language?",
                    message: "You translate often. Would you like to auto-translate posts from specific languages?",
                    actionLabel: "Set Up"
                )
            }
        }

        // Rule 5: Frequent toggling between original and translated → suggest side-by-side
        if collector.frequency(for: .modeChanged) == .high,
           AMENFeatureFlags.shared.sideBySideTranslationEnabled {
            let prefs = TranslationSettingsManager.shared.preferences
            if !prefs.sideBySideEnabled {
                return AccessibilitySuggestion(
                    type: .enableSideBySide,
                    title: "Side-by-side view?",
                    message: "You switch between original and translated text often. Would you like to see both at once?",
                    actionLabel: "Enable"
                )
            }
        }

        // Rule 6: Natural/Contextual mode used frequently → suggest setting as default
        if collector.frequency(for: .modeChanged) == .moderate {
            let currentDefault = TranslationSettingsManager.shared.preferences.defaultTranslationMode
            if currentDefault == .literal {
                return AccessibilitySuggestion(
                    type: .setDefaultTranslationMode,
                    title: "Change default translation?",
                    message: "You often switch translation modes. Would you like to set Natural as your default?",
                    actionLabel: "Set Natural"
                )
            }
        }

        return nil
    }

    private func applySuggestion(_ suggestion: AccessibilitySuggestion) {
        switch suggestion.type {
        case .enableAutoTranslate:
            Task {
                await TranslationSettingsManager.shared.update(mode: .auto)
            }
        case .enableDefaultSimplify:
            // Set default readability mode preference
            UserDefaults.standard.set(true, forKey: "amen.readability.autoSimplify")
        case .configureAudio:
            // This opens settings — handled by the banner's action
            break
        case .enableContextCards:
            break
        case .enablePerLanguageAutoTranslate:
            // Opens per-language settings — handled by the banner's navigation action
            break
        case .enableSideBySide:
            Task {
                await TranslationSettingsManager.shared.update(sideBySideEnabled: true)
            }
        case .setDefaultTranslationMode:
            Task {
                await TranslationSettingsManager.shared.update(translationMode: .natural)
            }
        }
    }

    // MARK: - Cooldown Management

    private func canShowSuggestion() -> Bool {
        let timestamps = UserDefaults.standard.array(forKey: cooldownKey) as? [TimeInterval] ?? []
        let oneWeekAgo = Date().timeIntervalSince1970 - (7 * 86400)
        let recentCount = timestamps.filter { $0 > oneWeekAgo }.count
        return recentCount < maxWeeklySuggestions
    }

    private func recordSuggestionShown() {
        var timestamps = UserDefaults.standard.array(forKey: cooldownKey) as? [TimeInterval] ?? []
        timestamps.append(Date().timeIntervalSince1970)
        // Keep only last 30 days of records
        let thirtyDaysAgo = Date().timeIntervalSince1970 - (30 * 86400)
        timestamps = timestamps.filter { $0 > thirtyDaysAgo }
        UserDefaults.standard.set(timestamps, forKey: cooldownKey)
    }
}
