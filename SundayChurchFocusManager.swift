//
//  SundayChurchFocusManager.swift
//  AMENAPP
//
//  Thin bridge over ShabbatModeService.
//  Keeps existing @Published properties so all existing views compile unchanged.
//  All real logic lives in ShabbatModeService.
//
//  SCHEDULE: Active all day Sunday (00:00–23:59) in the user's LOCAL timezone.
//  (The previous 6 AM–4 PM window is removed per the hard requirements.)
//

import Foundation
import SwiftUI
import Combine

@MainActor
class SundayChurchFocusManager: ObservableObject {
    static let shared = SundayChurchFocusManager()

    // MARK: - Published State (kept for backwards-compat with existing views)

    /// True when it is Sunday in the user's local timezone.
    @Published private(set) var isInChurchFocusWindow: Bool = false
    /// Kept for SundayShabbatPromptView; not used for gating — use ShabbatModeService.
    @Published private(set) var hasOptedOut: Bool = false
    /// Show the one-per-Sunday soft prompt sheet.
    @Published var showSundayPrompt: Bool = false
    /// Master enable toggle — proxied to ShabbatModeService.
    @Published var isEnabled: Bool = true {
        didSet {
            guard oldValue != isEnabled else { return }
            ShabbatModeService.shared.setEnabled(isEnabled)
        }
    }

    // MARK: - Private

    private let optOutKey         = "shabbatMode_optedOut"
    private let optOutDateKey     = "shabbatMode_optOutDate"
    private let lastPromptDateKey = "shabbatMode_lastPromptDate"
    private var cancellables      = Set<AnyCancellable>()

    // MARK: - Init

    private init() {
        // Mirror ShabbatModeService state so existing views stay reactive
        ShabbatModeService.shared.$isSunday
            .receive(on: RunLoop.main)
            .sink { [weak self] sunday in
                self?.isInChurchFocusWindow = sunday
            }
            .store(in: &cancellables)

        ShabbatModeService.shared.$isEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                if self.isEnabled != enabled { self.isEnabled = enabled }
            }
            .store(in: &cancellables)

        isEnabled = ShabbatModeService.shared.isEnabled
        isInChurchFocusWindow = ShabbatModeService.shared.isSunday
        loadOptOutPreference()
        checkShouldShowSundayPrompt()
    }

    // MARK: - Public API

    /// True when restrictions should be enforced right now.
    func shouldGateFeature() -> Bool {
        ShabbatModeService.shared.isShabbatActiveNow() && !hasOptedOut
    }

    /// Toggle Shabbat Mode. Delegates to ShabbatModeService and persists to Firestore.
    func setEnabled(_ enabled: Bool) {
        ShabbatModeService.shared.setEnabled(enabled)
        // isEnabled @Published will be updated via the Combine sink above
    }

    // MARK: - Opt-out (today only)

    func setOptOut(_ optOut: Bool) {
        hasOptedOut = optOut
        UserDefaults.standard.set(optOut, forKey: optOutKey)
        if optOut {
            UserDefaults.standard.set(Date(), forKey: optOutDateKey)
        } else {
            UserDefaults.standard.removeObject(forKey: optOutDateKey)
        }
        print("🕊️ Shabbat Mode opt-out (today): \(optOut)")
    }

    // MARK: - AllowedFeature (kept for backwards-compat)

    enum AllowedFeature {
        case churchNotes, findChurch, settings
    }

    func isFeatureAllowed(_ feature: AllowedFeature) -> Bool { true }

    // MARK: - Sunday prompt

    func dismissSundayPrompt(enableMode: Bool) {
        showSundayPrompt = false
        UserDefaults.standard.set(Date(), forKey: lastPromptDateKey)
        setOptOut(!enableMode)
    }

    // MARK: - UI helpers

    var windowDescription: String { "Every Sunday" }

    func timeRemainingInWindow() -> String? {
        guard isInChurchFocusWindow else { return nil }
        // Until midnight
        let calendar = Calendar.current
        let now = Date()
        let endOfDay = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now) ?? Date(timeIntervalSinceNow: 86400))
        let hours = Int(endOfDay.timeIntervalSince(now) / 3600)
        return hours <= 1 ? "less than 1 hour" : "\(hours) hours"
    }

    // MARK: - Private helpers

    private func loadOptOutPreference() {
        let calendar = Calendar.current
        if let date = UserDefaults.standard.object(forKey: optOutDateKey) as? Date,
           !calendar.isDateInToday(date) {
            UserDefaults.standard.removeObject(forKey: optOutKey)
            UserDefaults.standard.removeObject(forKey: optOutDateKey)
            hasOptedOut = false
            return
        }
        hasOptedOut = UserDefaults.standard.bool(forKey: optOutKey)
    }

    private func checkShouldShowSundayPrompt() {
        guard isEnabled else { return }
        let calendar = Calendar.current
        guard calendar.component(.weekday, from: Date()) == 1 else {
            showSundayPrompt = false; return
        }
        if let last = UserDefaults.standard.object(forKey: lastPromptDateKey) as? Date,
           calendar.isDateInToday(last) {
            showSundayPrompt = false; return
        }
        showSundayPrompt = true
    }
}
