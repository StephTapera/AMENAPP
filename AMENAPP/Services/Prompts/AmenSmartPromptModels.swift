// AmenSmartPromptModels.swift
// AMEN App — Smart Contextual Prompt System Models
//
// Defines all types, enums, and value objects for the prompt system.
// No logic here — pure data shapes.

import Foundation
import UserNotifications

// MARK: - Prompt Type

/// Every distinct prompt scenario in the AMEN product. Raw values are used
/// as UserDefaults keys and analytics properties — never change them.
enum AmenSmartPromptType: String, Codable, CaseIterable {
    case prayerReplyNotification    = "prayer_reply_notification"
    case churchEventReminder        = "church_event_reminder"
    case bereanStudyContinuation    = "berean_study_continuation"
    case communityReply             = "community_reply"
    case creatorActivity            = "creator_activity"
    case resumeReflection           = "resume_reflection"
    case quietMode                  = "quiet_mode"
    case needPrayerSupport          = "need_prayer_support"
    case selahPause                 = "selah_pause"
    case joinConversation           = "join_conversation"
    case seasonalObservance         = "seasonal_observance"
    case worshipContinuity          = "worship_continuity"
    case locationForChurch          = "location_for_church"
    case calendarForEvents          = "calendar_for_events"
    case cameraPointOfUse           = "camera_point_of_use"
}

// MARK: - Prompt Surface

/// The AMEN screen or flow where a prompt may appear.
enum AmenSmartPromptSurface: String, Codable, CaseIterable {
    case homeFeed                = "home_feed"
    case amenSpaces              = "amen_spaces"
    case bereanAI                = "berean_ai"
    case messages                = "messages"
    case churchNotes             = "church_notes"
    case selah                   = "selah"
    case findAChurch             = "find_a_church"
    case churchDetail            = "church_detail"
    case mediaDetail             = "media_detail"
    case createPost              = "create_post"
    case prayerRequests          = "prayer_requests"
    case creatorTools            = "creator_tools"
    case notificationsOnboarding = "notifications_onboarding"
    case eventReminder           = "event_reminder"
    case studyContinuation       = "study_continuation"
    case worshipMedia            = "worship_media"
    case ambientHero             = "ambient_hero"
}

// MARK: - Prompt Priority

enum AmenSmartPromptPriority: Int, Comparable, Codable {
    case low    = 0
    case medium = 1
    case high   = 2

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

// MARK: - Presentation Style

enum AmenSmartPromptPresentation: String, Codable {
    case card    // Bottom-anchored overlay card, swipe-to-dismiss
    case banner  // Top-anchored transient bar, auto-dismiss after 6 s
    case sheet   // Half-sheet modal (.medium detent)
    case hero    // Inline full-width card in a feed/scroll view
}

// MARK: - Permission Requirement

enum AmenSmartPromptPermissionRequirement: String, Codable {
    case notifications
    case location
    case calendar
    case camera
    case microphone
    case none
}

// MARK: - Route

/// Where the primary CTA navigates or what it triggers.
enum AmenSmartPromptRoute: Codable, Equatable {
    case requestNotificationPermission
    case requestLocationPermission
    case requestCalendarPermission
    case openAppSettings
    case openSelah
    case openQuietMode
    case openBereanStudy
    case openChurchDetail(churchId: String)
    case dismiss
}

// MARK: - Action

struct AmenSmartPromptAction: Codable, Equatable {
    let title: String
    let isPrimary: Bool
    let route: AmenSmartPromptRoute

    static func primary(_ title: String, route: AmenSmartPromptRoute) -> Self {
        Self(title: title, isPrimary: true, route: route)
    }

    static func secondary(_ title: String) -> Self {
        Self(title: title, isPrimary: false, route: .dismiss)
    }
}

// MARK: - Cooldown Policy

struct AmenSmartPromptCooldownPolicy: Codable {
    /// Minimum time before the same prompt type can show again.
    let perPromptType: TimeInterval
    /// Minimum time before any prompt shows on the same surface.
    let perSurface: TimeInterval
    /// Minimum time before any prompt shows anywhere in the app.
    let global: TimeInterval
    /// After this many dismissals the prompt is permanently suppressed.
    let maxDismissals: Int

    static let `default` = AmenSmartPromptCooldownPolicy(
        perPromptType: 48 * 3600,
        perSurface:    8 * 3600,
        global:        1800,
        maxDismissals: 3
    )

    static let gentle = AmenSmartPromptCooldownPolicy(
        perPromptType: 7 * 24 * 3600,
        perSurface:    24 * 3600,
        global:        3600,
        maxDismissals: 2
    )
}

// MARK: - Dismissal Reason

enum AmenSmartPromptDismissalReason: String, Codable {
    case userTappedSecondaryAction   = "secondary_action"
    case userSwipedAway              = "swiped_away"
    case timedOut                    = "timed_out"
    case suppressedByCooldown        = "cooldown"
    case suppressedByFeatureFlag     = "feature_flag"
    case suppressedByKillSwitch      = "kill_switch"
    case suppressedByQuietMode       = "quiet_mode"
    case suppressedBySensitiveFlow   = "sensitive_flow"
    case suppressedByRepeatDismissal = "repeat_dismissals"
}

// MARK: - Suppression Reason

enum AmenSmartPromptSuppressionReason: String {
    case featureFlagDisabled                   = "feature_flag_disabled"
    case globalKillSwitch                      = "global_kill_switch"
    case nativePermissionDialogActive          = "native_permission_dialog_active"
    case activeWorshipSession                  = "active_worship_session"
    case activeLivePrayerSession               = "active_live_prayer_session"
    case activeBereanGeneration                = "active_berean_generation"
    case activeSensitiveReflection             = "active_sensitive_reflection"
    case activeTextEntry                       = "active_text_entry"
    case globalCooldown                        = "global_cooldown"
    case surfaceCooldown                       = "surface_cooldown"
    case promptTypeCooldown                    = "prompt_type_cooldown"
    case maxDismissalsReached                  = "max_dismissals_reached"
    case permanentlySuppressed                 = "permanently_suppressed"
    case notificationPermissionAlreadyGranted  = "notification_permission_already_granted"
    case stackedPromptActive                   = "stacked_prompt_active"
}

// MARK: - Context

/// Caller-provided snapshot of the current app state at trigger time.
/// The engine reads this to apply suppression rules.
struct AmenSmartPromptContext {
    var isInWorshipSession:             Bool = false
    var isInLivePrayer:                 Bool = false
    var isBereanGenerating:             Bool = false
    var isInSensitiveReflection:        Bool = false
    var isInActiveTextEntry:            Bool = false
    var isNativePermissionDialogActive: Bool = false
    var notificationPermissionStatus: UNAuthorizationStatus = .notDetermined
    var currentUserId:    String? = nil
    var associatedEntityId: String? = nil
}

// MARK: - Prompt

/// An immutable value representing a single contextual prompt.
struct AmenSmartPrompt: Identifiable {
    let id: UUID = UUID()
    /// Used as the UserDefaults persistence key. Stable across sessions.
    let persistenceKey: String
    let type: AmenSmartPromptType
    let surface: AmenSmartPromptSurface
    let priority: AmenSmartPromptPriority
    let title: String
    let body: String
    let systemImage: String
    let primaryAction: AmenSmartPromptAction
    let secondaryAction: AmenSmartPromptAction
    let permissionRequirement: AmenSmartPromptPermissionRequirement
    let cooldownPolicy: AmenSmartPromptCooldownPolicy
    let presentation: AmenSmartPromptPresentation

    init(
        type: AmenSmartPromptType,
        surface: AmenSmartPromptSurface,
        priority: AmenSmartPromptPriority                  = .medium,
        title: String,
        body: String,
        systemImage: String,
        primaryAction: AmenSmartPromptAction,
        secondaryActionTitle: String                       = "Not Now",
        permissionRequirement: AmenSmartPromptPermissionRequirement = .none,
        cooldownPolicy: AmenSmartPromptCooldownPolicy      = .default,
        presentation: AmenSmartPromptPresentation          = .card
    ) {
        self.persistenceKey       = type.rawValue
        self.type                 = type
        self.surface              = surface
        self.priority             = priority
        self.title                = title
        self.body                 = body
        self.systemImage          = systemImage
        self.primaryAction        = primaryAction
        self.secondaryAction      = .secondary(secondaryActionTitle)
        self.permissionRequirement = permissionRequirement
        self.cooldownPolicy       = cooldownPolicy
        self.presentation         = presentation
    }
}
