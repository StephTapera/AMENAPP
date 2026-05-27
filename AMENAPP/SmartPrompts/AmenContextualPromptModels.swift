import SwiftUI

// MARK: - Prompt Types

enum AmenPromptType: String, Codable, CaseIterable {
    // Contextual notification permission prompts — shown only when UNAuthorizationStatus == .notDetermined
    case prayerReplyNotifications   // trigger: prayer post receives first engagement
    case churchEventReminders       // trigger: user follows a church
    case bereanStudyFollowUp        // trigger: Berean study session completes
    case communityInteraction       // trigger: post receives ≥ 3 replies
    case creatorTeacherUpdate       // trigger: first sermon/study upload

    // In-app contextual nudge cards — no system permission needed
    case continueReflection         // trigger: unfinished Church Note found on open
    case quietMode                  // trigger: late-night scrolling (after 10 PM)
    case needPrayer                 // trigger: inactivity after emotionally heavy content
    case takeAPause                 // trigger: feed session exceeds configured limit
}

extension AmenPromptType {
    var isNotificationPermissionPrompt: Bool {
        switch self {
        case .prayerReplyNotifications, .churchEventReminders,
             .bereanStudyFollowUp, .communityInteraction, .creatorTeacherUpdate:
            return true
        case .continueReflection, .quietMode, .needPrayer, .takeAPause:
            return false
        }
    }

    /// Hours to wait before re-showing this prompt after a dismiss.
    var cooldownHours: Int {
        switch self {
        case .prayerReplyNotifications:  return 72
        case .churchEventReminders:      return 48
        case .bereanStudyFollowUp:       return 24
        case .communityInteraction:      return 48
        case .creatorTeacherUpdate:      return 72
        case .continueReflection:        return 4
        case .quietMode:                 return 12
        case .needPrayer:                return 24
        case .takeAPause:                return 2
        }
    }

    /// Auto-permanently-dismiss after this many shows (never repeats).
    var maxShows: Int {
        switch self {
        case .prayerReplyNotifications, .churchEventReminders,
             .bereanStudyFollowUp, .communityInteraction, .creatorTeacherUpdate:
            return 3
        case .quietMode, .needPrayer:
            return 5
        case .continueReflection, .takeAPause:
            return 20
        }
    }
}

// MARK: - Prompt Model

struct AmenContextualPrompt: Identifiable {
    let id: AmenPromptType
    let icon: String
    let iconTint: Color
    let title: String
    let body: String
    let primaryLabel: String
    let secondaryLabel: String
    let principles: [AmenPromptPrinciple]
    let primaryAction: AmenPromptPrimaryAction
    let metadata: [String: Any]
}

struct AmenPromptPrinciple: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
}

enum AmenPromptPrimaryAction {
    case requestSystemNotifications
    case enableQuietMode
    case openPrayer
    case openSelah
    case resumeNote
    case continueScrolling
}

// MARK: - Notification Names

extension Notification.Name {
    static let amenPromptEnableQuietMode  = Notification.Name("amen.prompt.enableQuietMode")
    static let amenPromptOpenSelah        = Notification.Name("amen.prompt.openSelah")
    static let amenPromptResumeChurchNote = Notification.Name("amen.prompt.resumeChurchNote")
}

// MARK: - Factory

extension AmenContextualPrompt {
    static func make(_ type: AmenPromptType, metadata: [String: Any] = [:]) -> AmenContextualPrompt {
        switch type {

        case .prayerReplyNotifications:
            return AmenContextualPrompt(
                id: type,
                icon: "hands.and.sparkles",
                iconTint: .purple,
                title: "People are praying for you",
                body: "Would you like to know when someone prays for you or replies to your prayer?",
                primaryLabel: "Enable Prayer Updates",
                secondaryLabel: "Not now",
                principles: [
                    .init(icon: "checkmark.shield",    label: "Only sent for meaningful interactions"),
                    .init(icon: "eye.slash",            label: "No engagement bait or counters"),
                    .init(icon: "slider.horizontal.3",  label: "Change anytime in Settings"),
                ],
                primaryAction: .requestSystemNotifications,
                metadata: metadata
            )

        case .churchEventReminders:
            let name = metadata["churchName"] as? String ?? "this church"
            return AmenContextualPrompt(
                id: type,
                icon: "building.columns",
                iconTint: .blue,
                title: "Stay connected with \(name)",
                body: "Get notified about service times, live streams, and announcements.",
                primaryLabel: "Keep Me Updated",
                secondaryLabel: "Maybe later",
                principles: [
                    .init(icon: "bell.badge",          label: "Events and live services only"),
                    .init(icon: "hand.raised",          label: "You control which churches notify you"),
                    .init(icon: "slider.horizontal.3",  label: "Manage in Church Settings"),
                ],
                primaryAction: .requestSystemNotifications,
                metadata: metadata
            )

        case .bereanStudyFollowUp:
            return AmenContextualPrompt(
                id: type,
                icon: "book.and.wrench",
                iconTint: .orange,
                title: "Continue your study journey",
                body: "Receive gentle reminders to return to your studies — no pressure, just continuity.",
                primaryLabel: "Enable Study Reminders",
                secondaryLabel: "Not now",
                principles: [
                    .init(icon: "calendar.badge.clock", label: "Sent at times you choose"),
                    .init(icon: "hand.raised",           label: "Never daily streaks or pressure"),
                    .init(icon: "slider.horizontal.3",   label: "Pause or stop anytime"),
                ],
                primaryAction: .requestSystemNotifications,
                metadata: metadata
            )

        case .communityInteraction:
            return AmenContextualPrompt(
                id: type,
                icon: "bubble.left.and.bubble.right",
                iconTint: .green,
                title: "People are joining your conversation",
                body: "Want updates on discussions you care about?",
                primaryLabel: "Enable Conversation Updates",
                secondaryLabel: "Not now",
                principles: [
                    .init(icon: "checkmark.shield",    label: "Only conversations you started or joined"),
                    .init(icon: "eye.slash",            label: "No like counts or vanity metrics"),
                    .init(icon: "slider.horizontal.3",  label: "Thread-level control in Settings"),
                ],
                primaryAction: .requestSystemNotifications,
                metadata: metadata
            )

        case .creatorTeacherUpdate:
            return AmenContextualPrompt(
                id: type,
                icon: "waveform.badge.person.crop",
                iconTint: .indigo,
                title: "Your community is responding",
                body: "Stay connected when members save, share, or engage with your content.",
                primaryLabel: "Enable Creator Updates",
                secondaryLabel: "Not now",
                principles: [
                    .init(icon: "chart.bar.xaxis",     label: "Qualitative signals, not vanity counts"),
                    .init(icon: "lock.shield",          label: "Private to you — never shared publicly"),
                    .init(icon: "slider.horizontal.3",  label: "Frequency controls in Creator Settings"),
                ],
                primaryAction: .requestSystemNotifications,
                metadata: metadata
            )

        case .continueReflection:
            let noteTitle = metadata["noteTitle"] as? String ?? "your reflection"
            return AmenContextualPrompt(
                id: type,
                icon: "note.text",
                iconTint: .yellow,
                title: "You left something open",
                body: "Your reflection \"\(noteTitle)\" is waiting whenever you're ready.",
                primaryLabel: "Resume",
                secondaryLabel: "Dismiss",
                principles: [
                    .init(icon: "clock", label: "Saved exactly where you left off"),
                ],
                primaryAction: .resumeNote,
                metadata: metadata
            )

        case .quietMode:
            return AmenContextualPrompt(
                id: type,
                icon: "moon.stars",
                iconTint: .indigo,
                title: "Would you like a calmer experience tonight?",
                body: "Reduce motion, quiet notifications, and shift to a gentler feed.",
                primaryLabel: "Enter Quiet Mode",
                secondaryLabel: "Keep browsing",
                principles: [
                    .init(icon: "moon",        label: "Automatically ends at morning"),
                    .init(icon: "hand.raised",  label: "Your feed rhythm stays intact"),
                ],
                primaryAction: .enableQuietMode,
                metadata: metadata
            )

        case .needPrayer:
            return AmenContextualPrompt(
                id: type,
                icon: "heart.text.square",
                iconTint: .pink,
                title: "You're not alone",
                body: "Would you like prayer, a Scripture, or a quiet moment?",
                primaryLabel: "Open Prayer",
                secondaryLabel: "I'm okay",
                principles: [
                    .init(icon: "lock.shield", label: "Completely private — never shared"),
                    .init(icon: "hand.raised",  label: "No tracking or behavioral inference"),
                ],
                primaryAction: .openPrayer,
                metadata: metadata
            )

        case .takeAPause:
            return AmenContextualPrompt(
                id: type,
                icon: "leaf",
                iconTint: .green,
                title: "Pause and reflect?",
                body: "You've been in the feed for a while. Take a Selah moment or continue.",
                primaryLabel: "Take a Selah Moment",
                secondaryLabel: "Continue browsing",
                principles: [
                    .init(icon: "clock",       label: "Takes less than 60 seconds"),
                    .init(icon: "hand.raised",  label: "No guilt — just an invitation"),
                ],
                primaryAction: .openSelah,
                metadata: metadata
            )
        }
    }
}
