//
//  AppConstants.swift
//  AMENAPP
//
//  Created by Claude Code on 4/7/26.
//
//  Centralized constants for UserDefaults keys, URLs, and configuration values.
//  Prevents typos and makes migration/deprecation easier.
//

import Foundation
import UIKit

// MARK: - Scene-Aware Screen Metrics
//
// Replacement for `UIScreen.main`, which is deprecated and returns the wrong
// values under multi-window contexts (iPad Split View, Stage Manager, external
// displays). These accessors resolve the *active foreground* window scene and
// read its key window's bounds — the app's actual on-screen size — rather than
// the full physical screen.
//
// Prefer SwiftUI's `GeometryReader` or `@Environment(\.displayScale)` inside
// views where layout precision matters; use these as drop-in replacements for
// legacy `UIScreen.main` call sites where a structural refactor isn't warranted.
enum ScreenMetrics {
    /// The active foreground window scene, falling back to any connected scene.
    private static var activeScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    /// Bounds of the app's key window in the active scene — the correct size to
    /// lay out against under Split View / Stage Manager. Falls back to the
    /// scene's screen bounds, then to a sensible default at very early launch.
    static var bounds: CGRect {
        if let scene = activeScene {
            if let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first {
                return window.bounds
            }
            return scene.screen.bounds
        }
        return CGRect(x: 0, y: 0, width: 390, height: 844)
    }

    /// Display scale of the active scene's screen (e.g. for `ImageRenderer`).
    static var scale: CGFloat {
        activeScene?.screen.scale ?? 2.0
    }
}

// MARK: - UserDefaults Keys

/// Centralized UserDefaults keys to prevent typos and ensure consistency across the app.
/// Use these static accessors instead of string literals.
enum UserDefaultsKeys {
    // MARK: - Onboarding & First-Run

    /// Per-user onboarding completion flag: "hasCompletedOnboarding_{userId}"
    static func hasCompletedOnboarding(userId: String) -> String {
        "hasCompletedOnboarding_\(userId)"
    }

    /// Global age verification completion (COPPA gate)
    static let hasCompletedAgeVerification = "hasCompletedAgeVerification"

    /// Notification onboarding shown flag
    static let notifOnboardingShown = "notifOnboardingShown"

    /// Account type onboarding completed
    static let amenAccountTypeOnboardingComplete = "amenAccountTypeOnboardingComplete"

    // MARK: - Migrations

    /// User search keywords migration completed
    static let hasRunUserKeywordsMigration = "hasRunUserKeywordsMigration"

    // MARK: - Authentication

    /// Remember me preference (session persistence)
    static let rememberMe = "rememberMe"

    /// Cached username for auto-login splash
    static let cachedUsername = "cachedUsername"

    /// Cached photo URL for auto-login splash
    static let cachedPhotoURL = "cachedPhotoURL"

    /// Last auth token validity check timestamp
    static let lastAuthTokenCheckDate = "lastAuthTokenCheckDate"

    // MARK: - 2FA

    /// 2FA enabled flag (non-PII, safe for UserDefaults)
    static let twoFactorAuthEnabled = "twoFactorAuthEnabled"

    // NOTE: Phone number is stored in Keychain, not UserDefaults (PII protection)

    // MARK: - Onboarding Prompts

    /// First post welcome prompt pending flag
    static let showFirstPostPromptPending = "showFirstPostPromptPending"

    // MARK: - Current User Profile

    /// Current user's profile image URL (for tab bar avatar)
    static let currentUserProfileImageURL = "currentUserProfileImageURL"

    // MARK: - App Version Tracking

    /// Last launched app version (for detecting updates)
    static let lastLaunchedVersion = "lastLaunchedVersion"

    // MARK: - Daily Verse Cache

    /// Cached serialized PersonalizedDailyVerse (Data)
    static let cachedDailyVerse = "cachedDailyVerse"

    /// Date the cached daily verse was fetched
    static let cachedVerseDate = "cachedVerseDate"

    // MARK: - Notifications

    /// Notification focus-mode enabled flag
    static let notificationFocusMode = "notificationFocusMode"
}

// MARK: - App Configuration

/// Centralized app configuration values (URLs, IDs, limits)
enum AppConfig {
    // MARK: - URLs

    /// App Store URL for force update prompts
    static let appStoreURL = "https://apps.apple.com/app/id6740238684"

    // MARK: - Background Tasks

    /// Background feed refresh task identifier
    static let backgroundFeedRefreshTaskId = "com.amenapp.feed.refresh"

    // MARK: - Cache Configuration

    /// URL cache memory capacity (64 MB)
    static let urlCacheMemoryCapacity = 64 * 1024 * 1024

    /// URL cache disk capacity (256 MB)
    static let urlCacheDiskCapacity = 256 * 1024 * 1024

    /// URL cache disk path
    static let urlCacheDiskPath = "amen_url_cache"

    // MARK: - Performance Budgets

    /// Maximum loading screen timeout (5 seconds)
    static let maxLoadingScreenTimeout: UInt64 = 5_000_000_000

    /// User data cache duration (5 seconds)
    static let userDataCacheDuration: TimeInterval = 5.0

    // MARK: - Rate Limits

    /// Maximum reports per user per day
    static let maxReportsPerDay = 10

    /// Password reset cooldown (60 seconds)
    static let passwordResetCooldown: TimeInterval = 60

    /// Email verification cooldown (60 seconds)
    static let emailVerificationCooldown: TimeInterval = 60

    /// 2FA session TTL (30 minutes)
    static let twoFactorSessionTTL: TimeInterval = 30 * 60

    // MARK: - Content Limits

    /// Maximum additional report details length (1000 chars)
    static let maxReportDetailsLength = 1000

    // MARK: - AI Detection

    /// AI content detection confidence threshold (40%)
    static let aiDetectionThreshold = 0.4

    /// AI content auto-delete confidence threshold (70%)
    static let aiAutoDeleteThreshold = 0.7

    // MARK: - Legal & Compliance

    /// Nested enum for legal/compliance constants
    enum Legal {
        /// Minimum age requirement (COPPA compliance)
        static let minimumAge = 13
    }
}

// MARK: - Firebase Collection Paths
// (Consider moving FirebaseManager.CollectionPath here for consistency)
