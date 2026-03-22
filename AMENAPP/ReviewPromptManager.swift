//
//  ReviewPromptManager.swift
//  AMENAPP
//
//  Smart in-app review prompt presentation manager
//  Controls when and how often the rating prompt appears
//

import Foundation
import StoreKit
import Combine

/// Manages when to show the in-app review prompt
/// Implements intelligent conditions to avoid over-prompting
@MainActor
final class ReviewPromptManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = ReviewPromptManager()
    
    // MARK: - Published State
    
    /// Whether the prompt should be shown
    @Published var shouldShowPrompt = false
    
    // MARK: - UserDefaults Keys
    
    private enum Keys {
        static let appLaunchCount = "reviewPrompt_appLaunchCount"
        static let lastPromptDate = "reviewPrompt_lastPromptDate"
        static let hasRatedApp = "reviewPrompt_hasRatedApp"
        static let hasDismissedPrompt = "reviewPrompt_hasDismissedPrompt"
        static let lastDismissalDate = "reviewPrompt_lastDismissalDate"
        static let successfulSessionCount = "reviewPrompt_successfulSessionCount"
    }
    
    // MARK: - Configuration
    
    /// Minimum app launches before showing prompt
    private let minimumLaunchCount = 5
    
    /// Minimum successful sessions before showing prompt
    private let minimumSessionCount = 3
    
    /// Days to wait after dismissal before showing again
    private let daysBetweenPrompts = 90
    
    /// Days to wait after rating before showing again (if needed)
    private let daysBetweenRatings = 365
    
    // MARK: - Initialization
    
    private init() {
        // Increment launch count on init
        incrementLaunchCount()
    }
    
    // MARK: - Public Methods
    
    /// Check if prompt should be shown and update state
    func checkShouldShowPrompt() {
        if hasRatedApp {
            // User has already rated, don't show again for a long time
            if let lastRatingDate = lastPromptDate,
               daysSince(lastRatingDate) < daysBetweenRatings {
                shouldShowPrompt = false
                return
            }
        }
        
        guard !hasDismissedPrompt || canShowAfterDismissal else {
            // User dismissed and cooldown period not passed
            shouldShowPrompt = false
            return
        }
        
        guard appLaunchCount >= minimumLaunchCount else {
            // Not enough launches
            shouldShowPrompt = false
            return
        }
        
        guard successfulSessionCount >= minimumSessionCount else {
            // Not enough successful sessions
            shouldShowPrompt = false
            return
        }
        
        // All conditions met
        shouldShowPrompt = true
        dlog("✅ Review prompt conditions met - ready to show")
    }
    
    /// Increment successful session count
    /// Call this when user completes a meaningful action (post, prayer, etc.)
    func incrementSuccessfulSession() {
        successfulSessionCount += 1
        dlog("📊 Successful session count: \(successfulSessionCount)")
        
        // Check if we should show prompt
        checkShouldShowPrompt()
    }
    
    /// Mark that user rated the app
    func userDidRate() {
        hasRatedApp = true
        lastPromptDate = Date()
        shouldShowPrompt = false
        dlog("⭐️ User rated app - thank you!")
    }
    
    /// Mark that user dismissed the prompt
    func userDidDismiss() {
        hasDismissedPrompt = true
        lastDismissalDate = Date()
        shouldShowPrompt = false
        dlog("👋 User dismissed review prompt")
    }
    
    /// Request native StoreKit review (iOS 14+)
    /// This shows the system review dialog
    func requestNativeReview() {
        if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            SKStoreReviewController.requestReview(in: scene)
            userDidRate()
        }
    }
    
    /// Open App Store page for manual review
    /// Fallback for older iOS or if user wants to write a review
    func openAppStoreForReview() {
        // TODO: Replace with your actual App Store ID
        let appStoreID = "YOUR_APP_STORE_ID"
        
        if let url = URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review") {
            UIApplication.shared.open(url)
            userDidRate()
        }
    }
    
    /// Reset all prompt data (useful for testing)
    func resetPromptData() {
        UserDefaults.standard.removeObject(forKey: Keys.appLaunchCount)
        UserDefaults.standard.removeObject(forKey: Keys.lastPromptDate)
        UserDefaults.standard.removeObject(forKey: Keys.hasRatedApp)
        UserDefaults.standard.removeObject(forKey: Keys.hasDismissedPrompt)
        UserDefaults.standard.removeObject(forKey: Keys.lastDismissalDate)
        UserDefaults.standard.removeObject(forKey: Keys.successfulSessionCount)
        shouldShowPrompt = false
        dlog("🔄 Review prompt data reset")
    }
    
    // MARK: - Private Helpers
    
    private func incrementLaunchCount() {
        appLaunchCount += 1
        dlog("🚀 App launch count: \(appLaunchCount)")
    }
    
    private var canShowAfterDismissal: Bool {
        guard let lastDismissal = lastDismissalDate else {
            return true
        }
        return daysSince(lastDismissal) >= daysBetweenPrompts
    }
    
    private func daysSince(_ date: Date) -> Int {
        Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
    }
    
    // MARK: - UserDefaults Properties
    
    private var appLaunchCount: Int {
        get { UserDefaults.standard.integer(forKey: Keys.appLaunchCount) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.appLaunchCount) }
    }
    
    private var successfulSessionCount: Int {
        get { UserDefaults.standard.integer(forKey: Keys.successfulSessionCount) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.successfulSessionCount) }
    }
    
    private var hasRatedApp: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.hasRatedApp) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.hasRatedApp) }
    }
    
    private var hasDismissedPrompt: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.hasDismissedPrompt) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.hasDismissedPrompt) }
    }
    
    private var lastPromptDate: Date? {
        get { UserDefaults.standard.object(forKey: Keys.lastPromptDate) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Keys.lastPromptDate) }
    }
    
    private var lastDismissalDate: Date? {
        get { UserDefaults.standard.object(forKey: Keys.lastDismissalDate) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Keys.lastDismissalDate) }
    }
}
