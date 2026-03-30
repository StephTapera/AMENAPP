//
//  WelcomeScreenManager.swift
//  AMENAPP
//
//  Created by Steph on 1/15/26.
//

import Foundation
import Combine

/// Manages when the AMEN logo welcome screen should be displayed.
///
/// Shows only on three meaningful moments — NOT on every cold launch:
///   1. Fresh install  (onboarding not yet completed)
///   2. App update     (CFBundleShortVersionString changed since last launch)
///   3. Sign-in after being logged out  (call markSignIn() from the auth flow)
@MainActor
final class WelcomeScreenManager: ObservableObject {

    // MARK: - Stored state (UserDefaults)

    private var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") }
        set { UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    private var lastSeenAppVersion: String {
        get { UserDefaults.standard.string(forKey: "lastSeenAppVersion") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "lastSeenAppVersion") }
    }

    // Set to true by the auth flow when a nil → user sign-in transition occurs.
    private var didSignInThisSession = false

    // MARK: - Public API

    /// Call this when the user actively signs in (auth state transitions nil → user).
    func markSignIn() {
        didSignInThisSession = true
    }

    /// Determines if the welcome screen should be shown this launch.
    func shouldShowWelcome() -> Bool {
        // 1. Fresh install / onboarding not yet completed
        if !hasCompletedOnboarding {
            return true
        }

        // 2. App was updated since last launch
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        if !currentVersion.isEmpty && currentVersion != lastSeenAppVersion {
            return true
        }

        // 3. User signed back in after being logged out this session
        if didSignInThisSession {
            return true
        }

        return false
    }

    /// Records that the launch was handled; stamps the current app version.
    func recordLaunch() {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        if !currentVersion.isEmpty {
            lastSeenAppVersion = currentVersion
        }
        didSignInThisSession = false
    }

    /// Marks onboarding as complete.
    func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    /// Reset for testing purposes.
    func resetForTesting() {
        hasCompletedOnboarding = false
        lastSeenAppVersion = ""
        didSignInThisSession = false
    }
}
