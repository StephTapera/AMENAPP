//
//  SundayChurchFocusManager.swift
//  AMENAPP
//
//  Shabbat Mode - Time-based feature gating (6am-4pm local time on Sundays)
//  Restricts social features to encourage church focus
//  Allows opt-out via Settings
//

import Foundation
import SwiftUI
import Combine

@MainActor
class SundayChurchFocusManager: ObservableObject {
    static let shared = SundayChurchFocusManager()
    
    // MARK: - Published State
    
    @Published private(set) var isInChurchFocusWindow: Bool = false
    @Published private(set) var hasOptedOut: Bool = false
    @Published var showSundayPrompt: Bool = false
    @Published var isEnabled: Bool = true  // Can be toggled in Settings
    
    // MARK: - Constants
    
    private let optOutKey = "shabbatMode_optedOut"
    private let enabledKey = "shabbatMode_enabled"
    private let lastPromptDateKey = "shabbatMode_lastPromptDate"
    private let windowStartHour = 6  // 6:00 AM
    private let windowEndHour = 16   // 4:00 PM
    
    // MARK: - Timer
    
    private var timer: Timer?
    
    // MARK: - Initialization
    
    private init() {
        loadOptOutPreference()
        loadEnabledPreference()
        updateChurchFocusState()
        startMonitoring()
        checkShouldShowSundayPrompt()
    }
    
    deinit {
        timer?.invalidate()
    }
    
    // MARK: - Public API
    
    /// Check if a feature should be gated right now
    func shouldGateFeature() -> Bool {
        return isEnabled && isInChurchFocusWindow && !hasOptedOut
    }
    
    /// Toggle Shabbat Mode on/off in Settings
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: enabledKey)
        print("🕊️ Shabbat Mode enabled: \(enabled)")
    }
    
    /// Features that remain accessible during church focus window
    enum AllowedFeature {
        case churchNotes
        case findChurch
        case settings
    }
    
    /// Check if feature is allowed during church focus
    func isFeatureAllowed(_ feature: AllowedFeature) -> Bool {
        return true // Church Notes, Find Church, Settings always allowed
    }
    
    /// Update opt-out preference
    func setOptOut(_ optOut: Bool) {
        hasOptedOut = optOut
        UserDefaults.standard.set(optOut, forKey: optOutKey)
        print("🕊️ Shabbat Mode opt-out: \(optOut)")
    }
    
    // MARK: - Time Checking
    
    private func updateChurchFocusState() {
        let calendar = Calendar.current
        let now = Date()
        
        // Check if today is Sunday (1 = Sunday in Gregorian calendar)
        let weekday = calendar.component(.weekday, from: now)
        let isSunday = (weekday == 1)
        
        guard isSunday else {
            isInChurchFocusWindow = false
            return
        }
        
        // Check if current time is within window (6am-4pm local time)
        let hour = calendar.component(.hour, from: now)
        let isWithinWindow = (hour >= windowStartHour && hour < windowEndHour)
        
        isInChurchFocusWindow = isWithinWindow
        
        #if DEBUG
        print("🕊️ Shabbat Mode: Sunday=\(isSunday), Hour=\(hour), Window=\(isWithinWindow), Active=\(shouldGateFeature())")
        #endif
    }
    
    // MARK: - Monitoring
    
    private func startMonitoring() {
        // Check every minute for transitions
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateChurchFocusState()
            }
        }
    }
    
    // MARK: - Persistence
    
    private func loadOptOutPreference() {
        hasOptedOut = UserDefaults.standard.bool(forKey: optOutKey)
    }
    
    private func loadEnabledPreference() {
        // Default to true if not set
        if UserDefaults.standard.object(forKey: enabledKey) == nil {
            isEnabled = true
            UserDefaults.standard.set(true, forKey: enabledKey)
        } else {
            isEnabled = UserDefaults.standard.bool(forKey: enabledKey)
        }
    }
    
    /// Check if we should show Sunday prompt (once per Sunday)
    private func checkShouldShowSundayPrompt() {
        guard isEnabled else { return }
        
        let calendar = Calendar.current
        let now = Date()
        let weekday = calendar.component(.weekday, from: now)
        
        guard weekday == 1 else { // Only on Sundays
            showSundayPrompt = false
            return
        }
        
        // Check if we've already shown prompt today
        if let lastPromptDate = UserDefaults.standard.object(forKey: lastPromptDateKey) as? Date {
            if calendar.isDateInToday(lastPromptDate) {
                showSundayPrompt = false
                return
            }
        }
        
        // Show prompt
        showSundayPrompt = true
    }
    
    /// Dismiss Sunday prompt and record it
    func dismissSundayPrompt(enableMode: Bool) {
        showSundayPrompt = false
        UserDefaults.standard.set(Date(), forKey: lastPromptDateKey)
        
        if enableMode {
            hasOptedOut = false
            UserDefaults.standard.set(false, forKey: optOutKey)
        } else {
            hasOptedOut = true
            UserDefaults.standard.set(true, forKey: optOutKey)
        }
    }
    
    // MARK: - Helper Functions
    
    /// Get user-friendly time window string
    var windowDescription: String {
        "Sunday, 6:00 AM – 4:00 PM"
    }
    
    /// Get time remaining in window (for UI display)
    func timeRemainingInWindow() -> String? {
        guard isInChurchFocusWindow else { return nil }
        
        let calendar = Calendar.current
        let now = Date()
        let currentHour = calendar.component(.hour, from: now)
        let hoursRemaining = windowEndHour - currentHour
        
        if hoursRemaining == 1 {
            return "1 hour"
        } else {
            return "\(hoursRemaining) hours"
        }
    }
}
