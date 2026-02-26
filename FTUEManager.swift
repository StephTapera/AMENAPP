//
//  FTUEManager.swift
//  AMENAPP
//
//  First-Time User Experience (FTUE) Manager
//  Handles onboarding coach marks state, persistence, and versioning
//

import Foundation
import SwiftUI
import Combine
import FirebaseAnalytics

/// Manages first-time user experience state and persistence
@MainActor
class FTUEManager: ObservableObject {
    static let shared = FTUEManager()
    
    // MARK: - Published State
    
    @Published var shouldShowCoachMarks: Bool = false
    @Published var currentStep: CoachMarkStep = .swipeLeft
    @Published var hasCompletedFTUE: Bool = false
    
    // MARK: - Persistence Keys
    
    private let ftueCompletedKey = "ftue_completed_v1"
    private let ftueVersionKey = "ftue_version"
    private let currentVersion = "1.0"
    
    // MARK: - Initialization
    
    private init() {
        loadFTUEState()
    }
    
    // MARK: - Public Methods
    
    /// Check if FTUE should be shown (call after user signs in/up)
    func checkAndShowFTUE() {
        if !hasCompletedFTUE {
            trackFTUEStart()
            // Small delay to ensure main feed is loaded
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.shouldShowCoachMarks = true
                self.trackStepView(self.currentStep)
            }
        }
    }
    
    /// Mark FTUE as completed and persist
    func completeFTUE() {
        trackFTUEComplete(skipped: false)
        hasCompletedFTUE = true
        shouldShowCoachMarks = false
        saveFTUEState()
    }
    
    /// Skip FTUE (treated same as completion)
    func skipFTUE() {
        trackStepCompletion(currentStep, skipped: true)
        trackFTUEComplete(skipped: true)
        completeFTUE()
    }
    
    /// Move to next step in tutorial
    func nextStep() {
        // Track completion of current step
        trackStepCompletion(currentStep, skipped: false)
        
        switch currentStep {
        case .swipeLeft:
            currentStep = .swipeRight
        case .swipeRight:
            currentStep = .bereanIntro
        case .bereanIntro:
            completeFTUE()
        }
        
        // Track viewing of next step
        if currentStep != .bereanIntro || currentStep != .swipeLeft {
            trackStepView(currentStep)
        }
    }
    
    /// Go back to previous step
    func previousStep() {
        switch currentStep {
        case .swipeLeft:
            break // Already at first step
        case .swipeRight:
            currentStep = .swipeLeft
        case .bereanIntro:
            currentStep = .swipeRight
        }
    }
    
    /// Reset FTUE (for testing or "Replay Tutorial" feature)
    func resetFTUE() {
        hasCompletedFTUE = false
        currentStep = .swipeLeft
        UserDefaults.standard.removeObject(forKey: ftueCompletedKey)
        UserDefaults.standard.removeObject(forKey: ftueVersionKey)
    }
    
    // MARK: - Private Methods
    
    private func loadFTUEState() {
        hasCompletedFTUE = UserDefaults.standard.bool(forKey: ftueCompletedKey)
        
        // Check version - if version changed, show FTUE again
        let savedVersion = UserDefaults.standard.string(forKey: ftueVersionKey)
        if savedVersion != currentVersion && savedVersion != nil {
            hasCompletedFTUE = false
        }
    }
    
    private func saveFTUEState() {
        UserDefaults.standard.set(true, forKey: ftueCompletedKey)
        UserDefaults.standard.set(currentVersion, forKey: ftueVersionKey)
    }
}

// MARK: - Coach Mark Step

enum CoachMarkStep: Int, CaseIterable {
    case swipeLeft = 0
    case swipeRight = 1
    case bereanIntro = 2
    
    var title: String {
        switch self {
        case .swipeLeft:
            return "Acknowledge Posts"
        case .swipeRight:
            return "Join the Conversation"
        case .bereanIntro:
            return "Meet Berean"
        }
    }
    
    var description: String {
        switch self {
        case .swipeLeft:
            return "Swipe left to acknowledge"
        case .swipeRight:
            return "Swipe right to comment"
        case .bereanIntro:
            return "Your AI assistant for biblical insight, scripture help, and thoughtful guidance."
        }
    }
    
    var icon: String {
        switch self {
        case .swipeLeft:
            return "hand.thumbsup.fill"
        case .swipeRight:
            return "message.fill"
        case .bereanIntro:
            return "sparkles"
        }
    }
    
    var primaryButtonText: String {
        switch self {
        case .swipeLeft, .swipeRight:
            return "Next"
        case .bereanIntro:
            return "Got it"
        }
    }
}

// MARK: - Coach Mark Model

struct CoachMark: Identifiable {
    let id = UUID()
    let step: CoachMarkStep
    let targetFrame: CGRect?
    let anchorPoint: AnchorPoint
    
    enum AnchorPoint {
        case postCard
        case bereanButton
        case custom(CGRect)
    }
}

// MARK: - Analytics Extension

extension FTUEManager {
    
    /// Track FTUE start
    private func trackFTUEStart() {
        Analytics.logEvent("ftue_started", parameters: [
            "version": currentVersion
        ])
    }
    
    /// Track step view
    private func trackStepView(_ step: CoachMarkStep) {
        Analytics.logEvent("ftue_step_viewed", parameters: [
            "step": step.rawValue,
            "step_name": stepName(step)
        ])
    }
    
    /// Track step completion
    private func trackStepCompletion(_ step: CoachMarkStep, skipped: Bool) {
        Analytics.logEvent("ftue_step_completed", parameters: [
            "step": step.rawValue,
            "step_name": stepName(step),
            "skipped": skipped
        ])
    }
    
    /// Track FTUE completion
    private func trackFTUEComplete(skipped: Bool) {
        Analytics.logEvent("ftue_completed", parameters: [
            "version": currentVersion,
            "skipped": skipped
        ])
    }
    
    private func stepName(_ step: CoachMarkStep) -> String {
        switch step {
        case .swipeLeft: return "swipe_left"
        case .swipeRight: return "swipe_right"
        case .bereanIntro: return "berean_intro"
        }
    }
}
