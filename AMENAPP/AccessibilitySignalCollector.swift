// AccessibilitySignalCollector.swift
// AMEN App — Accessibility Intelligence Layer (Phase 5)
//
// Records on-device accessibility signals (translated, simplified, listened, etc.)
// Aggregates into frequency buckets (low/moderate/high) for suggestion engine.
// Privacy-safe: stores only counts in UserDefaults, never raw content.

import Foundation

@MainActor
final class AccessibilitySignalCollector: ObservableObject {

    static let shared = AccessibilitySignalCollector()

    // MARK: - Published State

    @Published private(set) var signals: AggregatedAccessibilitySignals

    // MARK: - Private

    private let storageKey = "amen.accessibility.signals"

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(AggregatedAccessibilitySignals.self, from: data) {
            signals = decoded
        } else {
            signals = .default
        }
    }

    // MARK: - Public API

    /// Record a signal when the user uses an accessibility feature
    func recordSignal(_ signal: AccessibilitySignal) {
        guard AMENFeatureFlags.shared.adaptiveAccessibilityEnabled else { return }

        switch signal {
        case .translated:
            signals.translateCount += 1
        case .simplified:
            signals.simplifyCount += 1
        case .listenedToPost:
            signals.listenCount += 1
        case .contextCardOpened:
            signals.contextCardCount += 1
        case .textSizeChanged:
            signals.textSizeChangedCount += 1
        case .modeChanged:
            signals.modeChangedCount += 1
        case .sideBySideToggled:
            signals.sideBySideToggledCount += 1
        case .perLanguageAutoTranslateSet:
            signals.perLanguageAutoTranslateSetCount += 1
        }

        signals.lastRecordedAt = Date()
        persist()
    }

    /// Get frequency bucket for a signal type
    func frequency(for signal: AccessibilitySignal) -> FrequencyBucket {
        let count: Int
        switch signal {
        case .translated: count = signals.translateCount
        case .simplified: count = signals.simplifyCount
        case .listenedToPost: count = signals.listenCount
        case .contextCardOpened: count = signals.contextCardCount
        case .textSizeChanged: count = signals.textSizeChangedCount
        case .modeChanged: count = signals.modeChangedCount
        case .sideBySideToggled: count = signals.sideBySideToggledCount
        case .perLanguageAutoTranslateSet: count = signals.perLanguageAutoTranslateSetCount
        }
        return AggregatedAccessibilitySignals.bucket(for: count)
    }

    /// Reset all signal counts (for testing or user request)
    func reset() {
        signals = .default
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        if let data = try? JSONEncoder().encode(signals) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
