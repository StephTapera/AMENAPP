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
    @Published var currentStep: CoachMarkStep = .openTable
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
    
    /// Check if FTUE should be shown (call after user signs in/up).
    /// Waits until the feed has at least one post before presenting so the
    /// overlay never appears over an empty screen.
    func checkAndShowFTUE() {
        guard !hasCompletedFTUE else { return }
        trackFTUEStart()

        Task { @MainActor in
            // Poll until PostsManager has posts, up to 6 seconds.
            let deadline = Date().addingTimeInterval(6)
            while Date() < deadline {
                if PostsManager.shared.openTablePosts.isEmpty == false {
                    break
                }
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
            }
            // Small visual buffer after posts appear so the feed isn't still animating in.
            try? await Task.sleep(nanoseconds: 600_000_000) // 600ms
            shouldShowCoachMarks = true
            trackStepView(currentStep)
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
        trackStepCompletion(currentStep, skipped: false)

        let allSteps = CoachMarkStep.allCases
        if let idx = allSteps.firstIndex(of: currentStep), idx + 1 < allSteps.count {
            currentStep = allSteps[idx + 1]
            trackStepView(currentStep)
        } else {
            completeFTUE()
        }
    }

    /// Go back to previous step
    func previousStep() {
        let allSteps = CoachMarkStep.allCases
        if let idx = allSteps.firstIndex(of: currentStep), idx > 0 {
            currentStep = allSteps[idx - 1]
        }
    }
    
    /// Reset FTUE (for testing or "Replay Tutorial" feature)
    func resetFTUE() {
        hasCompletedFTUE = false
        currentStep = .openTable
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
    case openTable   = 0
    case prayer      = 1
    case bereanIntro = 2
    case messages    = 3

    var title: String {
        switch self {
        case .openTable:   return "The Open Table"
        case .prayer:      return "Pray Together"
        case .bereanIntro: return "Meet Berean"
        case .messages:    return "Faith-First Messaging"
        }
    }

    var description: String {
        switch self {
        case .openTable:
            return "Share what's on your heart. Amen posts, leave comments, and encourage your community."
        case .prayer:
            return "Post prayer requests, pray for others, and mark prayers as answered."
        case .bereanIntro:
            return "Your AI guide for scripture, biblical insight, and thoughtful answers — grounded in the Word."
        case .messages:
            return "Connect with mutual followers. Every conversation starts with mutual trust."
        }
    }

    var icon: String {
        switch self {
        case .openTable:   return "newspaper.fill"
        case .prayer:      return "hands.sparkles.fill"
        case .bereanIntro: return "sparkles"
        case .messages:    return "bubble.left.and.bubble.right.fill"
        }
    }

    var isLastStep: Bool {
        self == CoachMarkStep.allCases.last
    }

    var primaryButtonText: String {
        isLastStep ? "Get Started" : "Next"
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
        case .openTable:   return "open_table"
        case .prayer:      return "prayer"
        case .bereanIntro: return "berean_intro"
        case .messages:    return "messages"
        }
    }
}
