// AmenSmartPromptEngine.swift
// AMEN App — Smart Contextual Prompt Engine
//
// Central eligibility arbiter for the prompt system.
// Owns the prompt catalog, suppression rules, cooldown enforcement,
// and recording of all prompt lifecycle events.
//
// Design principles:
//   - Never show stacked prompts
//   - Never prompt during worship, live prayer, Berean generation, or sensitive reflection
//   - Suppress after repeated dismissals (per cooldown policy)
//   - Defer native permission dialogs until after user taps a clear CTA
//   - No guilt / urgency / manipulative copy
//   - All analytics properties are safe (no spiritual content)

import Foundation
import UserNotifications

@MainActor
final class AmenSmartPromptEngine {

    static let shared = AmenSmartPromptEngine()

    private let store = AmenSmartPromptStateStore.shared
    private let flags = AMENFeatureFlags.shared

    private init() {}

    // MARK: - Public API

    /// Returns the highest-priority eligible prompt for the given surface and context,
    /// or nil if the engine decides suppression is warranted.
    func eligiblePrompt(
        surface: AmenSmartPromptSurface,
        context: AmenSmartPromptContext
    ) async -> AmenSmartPrompt? {
        guard flags.smartContextualPromptsEnabled else {
            await recordSuppression(.globalKillSwitch, surface: surface)
            return nil
        }

        if let reason = globalSuppressionReason(context: context) {
            await recordSuppression(reason, surface: surface)
            return nil
        }

        let candidates = catalog(for: surface)
            .filter { isFlagEnabled(for: $0.type) }
            .filter { isEligible($0, context: context) }
            .sorted { $0.priority > $1.priority }

        return candidates.first
    }

    /// Call immediately after the engine returns a non-nil prompt.
    func recordImpression(_ prompt: AmenSmartPrompt) {
        store.recordImpression(for: prompt.persistenceKey)
        store.recordSurfacePrompt(for: prompt.surface)
        store.recordGlobalPrompt()
        AMENAnalyticsService.shared.track(.smartPromptImpression(
            promptType: prompt.type.rawValue,
            surface: prompt.surface.rawValue
        ))
    }

    /// Call when the user taps the primary or secondary CTA.
    func recordAction(_ action: AmenSmartPromptAction, for prompt: AmenSmartPrompt) {
        store.recordAction(for: prompt.persistenceKey)
        if action.isPrimary {
            AMENAnalyticsService.shared.track(.smartPromptPrimaryAction(
                promptType: prompt.type.rawValue,
                surface: prompt.surface.rawValue
            ))
            if prompt.permissionRequirement != .none {
                AMENAnalyticsService.shared.track(.smartPromptPermissionRequested(
                    promptType: prompt.type.rawValue,
                    permissionType: prompt.permissionRequirement.rawValue
                ))
            }
        } else {
            AMENAnalyticsService.shared.track(.smartPromptSecondaryAction(
                promptType: prompt.type.rawValue,
                surface: prompt.surface.rawValue
            ))
        }
    }

    /// Call when the prompt is dismissed by the user (swipe, secondary tap, or timeout).
    func recordDismissal(_ reason: AmenSmartPromptDismissalReason, for prompt: AmenSmartPrompt) {
        store.recordDismissal(for: prompt.persistenceKey)
        if store.dismissalCount(for: prompt.persistenceKey) >= prompt.cooldownPolicy.maxDismissals {
            store.markPermanentlySuppressed(prompt.persistenceKey)
        }
        AMENAnalyticsService.shared.track(.smartPromptDismissed(
            promptType: prompt.type.rawValue,
            surface: prompt.surface.rawValue,
            reason: reason.rawValue
        ))
    }

    /// Call when permission result comes back after primary CTA tap.
    func recordPermissionResult(granted: Bool, for prompt: AmenSmartPrompt) {
        if granted {
            AMENAnalyticsService.shared.track(.smartPromptPermissionGranted(
                promptType: prompt.type.rawValue,
                permissionType: prompt.permissionRequirement.rawValue
            ))
        } else {
            AMENAnalyticsService.shared.track(.smartPromptPermissionDenied(
                promptType: prompt.type.rawValue,
                permissionType: prompt.permissionRequirement.rawValue
            ))
        }
    }

    // MARK: - Suppression

    private func globalSuppressionReason(context: AmenSmartPromptContext) -> AmenSmartPromptSuppressionReason? {
        if context.isInWorshipSession             { return .activeWorshipSession }
        if context.isInLivePrayer                { return .activeLivePrayerSession }
        if context.isBereanGenerating             { return .activeBereanGeneration }
        if context.isInSensitiveReflection        { return .activeSensitiveReflection }
        if context.isInActiveTextEntry            { return .activeTextEntry }
        if context.isNativePermissionDialogActive { return .nativePermissionDialogActive }

        if let last = store.globalLastPromptDate,
           Date().timeIntervalSince(last) < 1800 {
            return .globalCooldown
        }
        return nil
    }

    private func isEligible(_ prompt: AmenSmartPrompt, context: AmenSmartPromptContext) -> Bool {
        if store.isPermanentlySuppressed(prompt.persistenceKey) { return false }
        if store.dismissalCount(for: prompt.persistenceKey) >= prompt.cooldownPolicy.maxDismissals { return false }

        if let last = store.lastImpressionDate(for: prompt.persistenceKey),
           Date().timeIntervalSince(last) < prompt.cooldownPolicy.perPromptType {
            return false
        }

        if let surfaceLast = store.lastPromptDate(for: prompt.surface),
           Date().timeIntervalSince(surfaceLast) < prompt.cooldownPolicy.perSurface {
            return false
        }

        if prompt.permissionRequirement == .notifications,
           context.notificationPermissionStatus == .authorized {
            return false
        }

        return true
    }

    private func isFlagEnabled(for type: AmenSmartPromptType) -> Bool {
        switch type {
        case .prayerReplyNotification:  return flags.smartPromptPrayerNotificationsEnabled
        case .churchEventReminder:      return flags.smartPromptChurchUpdatesEnabled
        case .bereanStudyContinuation:  return flags.smartPromptBereanContinuationEnabled
        case .resumeReflection:         return flags.smartPromptBereanContinuationEnabled
        case .quietMode:                return flags.smartPromptQuietModeEnabled
        case .selahPause:               return flags.smartPromptSelahPauseEnabled
        case .joinConversation:         return flags.smartPromptSpacesJoinEnabled
        case .creatorActivity:          return flags.smartPromptCreatorInsightsEnabled
        case .seasonalObservance:       return flags.smartPromptObservancesEnabled
        case .worshipContinuity:        return flags.smartPromptAmbientHeroEnabled
        case .communityReply:           return flags.smartContextualPromptsEnabled
        case .needPrayerSupport:        return flags.smartContextualPromptsEnabled
        case .locationForChurch:        return flags.smartContextualPromptsEnabled
        case .calendarForEvents:        return flags.smartContextualPromptsEnabled
        case .cameraPointOfUse:         return flags.smartContextualPromptsEnabled
        }
    }

    private func recordSuppression(_ reason: AmenSmartPromptSuppressionReason, surface: AmenSmartPromptSurface) async {
        AMENAnalyticsService.shared.track(.smartPromptSuppressed(
            surface: surface.rawValue,
            reason: reason.rawValue
        ))
    }

    // MARK: - Prompt Catalog

    private func catalog(for surface: AmenSmartPromptSurface) -> [AmenSmartPrompt] {
        switch surface {
        case .prayerRequests:
            return [prayerReplyPrompt]
        case .churchDetail, .findAChurch:
            return [churchUpdatesPrompt]
        case .bereanAI, .studyContinuation:
            return [bereanContinuationPrompt]
        case .churchNotes:
            return [resumeReflectionPrompt]
        case .selah, .worshipMedia:
            return [selahPausePrompt, quietModePrompt]
        case .amenSpaces:
            return [joinConversationPrompt]
        case .mediaDetail:
            return [worshipContinuityPrompt]
        case .creatorTools:
            return [creatorActivityPrompt]
        case .eventReminder:
            return [churchUpdatesPrompt]
        case .homeFeed, .messages, .createPost,
             .notificationsOnboarding, .ambientHero:
            return []
        }
    }

    // MARK: - Prompt Definitions

    private var prayerReplyPrompt: AmenSmartPrompt {
        AmenSmartPrompt(
            type: .prayerReplyNotification,
            surface: .prayerRequests,
            priority: .high,
            title: "Stay close to this prayer?",
            body: "We can let you know when people pray or reply.",
            systemImage: "bell.badge.fill",
            primaryAction: .primary("Enable Prayer Updates", route: .requestNotificationPermission),
            secondaryActionTitle: "Not Now",
            permissionRequirement: .notifications,
            cooldownPolicy: AmenSmartPromptCooldownPolicy(
                perPromptType: 72 * 3600,
                perSurface:    8 * 3600,
                global:        1800,
                maxDismissals: 2
            )
        )
    }

    private var churchUpdatesPrompt: AmenSmartPrompt {
        AmenSmartPrompt(
            type: .churchEventReminder,
            surface: .churchDetail,
            priority: .medium,
            title: "Keep up with this church?",
            body: "Get service reminders, live updates, and important announcements.",
            systemImage: "building.columns.fill",
            primaryAction: .primary("Keep Me Updated", route: .requestNotificationPermission),
            secondaryActionTitle: "Maybe Later",
            permissionRequirement: .notifications,
            cooldownPolicy: .gentle
        )
    }

    private var bereanContinuationPrompt: AmenSmartPrompt {
        AmenSmartPrompt(
            type: .bereanStudyContinuation,
            surface: .bereanAI,
            priority: .medium,
            title: "Continue this study?",
            body: "Receive gentle reminders to return to this passage.",
            systemImage: "book.pages.fill",
            primaryAction: .primary("Remind Me", route: .requestNotificationPermission),
            secondaryActionTitle: "Not Now",
            permissionRequirement: .notifications,
            cooldownPolicy: .default
        )
    }

    private var resumeReflectionPrompt: AmenSmartPrompt {
        AmenSmartPrompt(
            type: .resumeReflection,
            surface: .churchNotes,
            priority: .medium,
            title: "Continue your reflection later?",
            body: "We can remind you to return to this note when you're ready.",
            systemImage: "note.text",
            primaryAction: .primary("Remind Me", route: .requestNotificationPermission),
            secondaryActionTitle: "Not Now",
            permissionRequirement: .notifications,
            cooldownPolicy: .default
        )
    }

    private var selahPausePrompt: AmenSmartPrompt {
        AmenSmartPrompt(
            type: .selahPause,
            surface: .selah,
            priority: .low,
            title: "Pause and reflect?",
            body: "You can take a Selah moment before continuing.",
            systemImage: "leaf.fill",
            primaryAction: .primary("Start Selah", route: .openSelah),
            secondaryActionTitle: "Continue",
            cooldownPolicy: .gentle
        )
    }

    private var quietModePrompt: AmenSmartPrompt {
        AmenSmartPrompt(
            type: .quietMode,
            surface: .selah,
            priority: .low,
            title: "Calmer tonight?",
            body: "Reduce motion, lower notification intensity, and focus on Scripture.",
            systemImage: "moon.stars.fill",
            primaryAction: .primary("Enable Quiet Mode", route: .openQuietMode),
            secondaryActionTitle: "Not Now",
            cooldownPolicy: .gentle
        )
    }

    private var joinConversationPrompt: AmenSmartPrompt {
        AmenSmartPrompt(
            type: .joinConversation,
            surface: .amenSpaces,
            priority: .low,
            title: "Join this conversation?",
            body: "This discussion is active. Add your perspective when you're ready.",
            systemImage: "bubble.left.and.bubble.right.fill",
            primaryAction: .primary("Join", route: .dismiss),
            secondaryActionTitle: "Not Now",
            cooldownPolicy: .gentle
        )
    }

    private var worshipContinuityPrompt: AmenSmartPrompt {
        AmenSmartPrompt(
            type: .worshipContinuity,
            surface: .mediaDetail,
            priority: .low,
            title: "Continue this series?",
            body: "Follow this creator to stay connected with their teaching.",
            systemImage: "play.circle.fill",
            primaryAction: .primary("Follow Creator", route: .dismiss),
            secondaryActionTitle: "Maybe Later",
            cooldownPolicy: .gentle
        )
    }

    private var creatorActivityPrompt: AmenSmartPrompt {
        AmenSmartPrompt(
            type: .creatorActivity,
            surface: .creatorTools,
            priority: .medium,
            title: "Your community is active",
            body: "Several people engaged with your recent post. Respond when you're ready.",
            systemImage: "person.3.fill",
            primaryAction: .primary("See Activity", route: .dismiss),
            secondaryActionTitle: "Later",
            cooldownPolicy: .default
        )
    }
}
