// AmenAppIntents.swift
// AMENAPP
//
// Siri Shortcuts / App Intents integration for AMEN.
// Each intent opens the app and routes to the appropriate faith feature.
//
// WIRING REQUIRED in AMENAPPApp.swift:
// 1. Call AmenIntentDonationService.donateIntents() in app init
// 2. Handle openURL/onContinueUserActivity to route Spotlight results via AmenSpotlightService.handleSpotlightResult

import Foundation

#if canImport(AppIntents)
import AppIntents

// MARK: - Shortcuts Provider

@available(iOS 16.0, *)
struct AmenAppShortcutsProvider: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartPrayerModeIntent(),
            phrases: [
                "Start prayer mode in \(.applicationName)",
                "Open prayer in \(.applicationName)",
                "Start praying in \(.applicationName)"
            ],
            shortTitle: "Start Prayer Mode",
            systemImageName: "hands.sparkles"
        )
        AppShortcut(
            intent: AskBereanIntent(),
            phrases: [
                "Ask Berean in \(.applicationName)",
                "Ask \(.applicationName) a Bible question",
                "Ask scripture question in \(.applicationName)"
            ],
            shortTitle: "Ask Berean",
            systemImageName: "book.fill"
        )
        AppShortcut(
            intent: FindChurchIntent(),
            phrases: [
                "Find a church in \(.applicationName)",
                "Find churches near me in \(.applicationName)"
            ],
            shortTitle: "Find a Church",
            systemImageName: "building.columns"
        )
        AppShortcut(
            intent: OpenChurchNotesIntent(),
            phrases: [
                "Open my church notes in \(.applicationName)",
                "Open church notes in \(.applicationName)",
                "Show my notes in \(.applicationName)"
            ],
            shortTitle: "Open Church Notes",
            systemImageName: "note.text"
        )
        AppShortcut(
            intent: StartReflectionIntent(),
            phrases: [
                "Start quiet reflection in \(.applicationName)",
                "Start reflection in \(.applicationName)",
                "Open reflection mode in \(.applicationName)"
            ],
            shortTitle: "Start Quiet Reflection",
            systemImageName: "moon.stars"
        )
        AppShortcut(
            intent: SendPrayerRequestIntent(),
            phrases: [
                "Send a prayer request in \(.applicationName)",
                "Create prayer request in \(.applicationName)",
                "Post prayer request in \(.applicationName)"
            ],
            shortTitle: "Send Prayer Request",
            systemImageName: "paperplane"
        )
    }
}

// MARK: - 1. StartPrayerModeIntent

@available(iOS 16.0, *)
struct StartPrayerModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Start prayer mode"
    static var description = IntentDescription("Open AMEN prayer and reflection mode")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        dlog("[AmenIntents] StartPrayerModeIntent fired")
        await MainActor.run {
            NotificationCenter.default.post(name: Notification.Name("openPrayerMode"), object: nil)
        }
        return .result()
    }
}

// MARK: - 2. AskBereanIntent

@available(iOS 16.0, *)
struct AskBereanIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask Berean"
    static var description = IntentDescription("Ask the Berean AI assistant a scripture question")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Question", description: "What do you want to ask?", requestValueDialog: "What do you want to ask?")
    var question: String?

    func perform() async throws -> some IntentResult {
        dlog("[AmenIntents] AskBereanIntent fired — question: \(question ?? "none")")
        if let q = question, !q.isEmpty {
            UserDefaults.standard.set(q, forKey: "pendingBereanQuestion")
        }
        await MainActor.run {
            NotificationCenter.default.post(name: Notification.Name("openBerean"), object: nil)
        }
        return .result()
    }
}

// MARK: - 3. FindChurchIntent

@available(iOS 16.0, *)
struct FindChurchIntent: AppIntent {
    static var title: LocalizedStringResource = "Find a church"
    static var description = IntentDescription("Search for churches near you")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        dlog("[AmenIntents] FindChurchIntent fired")
        await MainActor.run {
            NotificationCenter.default.post(name: Notification.Name("openFindChurch"), object: nil)
        }
        return .result()
    }
}

// MARK: - 4. OpenChurchNotesIntent

@available(iOS 16.0, *)
struct OpenChurchNotesIntent: AppIntent {
    static var title: LocalizedStringResource = "Open my church notes"
    static var description = IntentDescription("View and edit your church notes in AMEN")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        dlog("[AmenIntents] OpenChurchNotesIntent fired")
        await MainActor.run {
            NotificationCenter.default.post(name: Notification.Name("openChurchNotes"), object: nil)
        }
        return .result()
    }
}

// MARK: - 5. StartReflectionIntent

@available(iOS 16.0, *)
struct StartReflectionIntent: AppIntent {
    static var title: LocalizedStringResource = "Start quiet reflection"
    static var description = IntentDescription("Enter AMEN calm reflection mode")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        dlog("[AmenIntents] StartReflectionIntent fired")
        await MainActor.run {
            NotificationCenter.default.post(name: Notification.Name("openReflection"), object: nil)
        }
        return .result()
    }
}

// MARK: - 6. SendPrayerRequestIntent

@available(iOS 16.0, *)
struct SendPrayerRequestIntent: AppIntent {
    static var title: LocalizedStringResource = "Send a prayer request"
    static var description = IntentDescription("Open the prayer request composer")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Message", description: "Your prayer request", requestValueDialog: "What is your prayer request?")
    var message: String?

    func perform() async throws -> some IntentResult {
        dlog("[AmenIntents] SendPrayerRequestIntent fired — message: \(message ?? "none")")
        if let msg = message, !msg.isEmpty {
            UserDefaults.standard.set(msg, forKey: "pendingPrayerMessage")
        }
        await MainActor.run {
            NotificationCenter.default.post(name: Notification.Name("openPrayerComposer"), object: nil)
        }
        return .result()
    }
}

// MARK: - Intent Donation Service

/// Call `AmenIntentDonationService.donateIntents()` once at first app launch
/// (or after sign-in) so iOS learns the user's Siri shortcuts.
@available(iOS 16.0, *)
@MainActor
final class AmenIntentDonationService {

    private init() {}

    /// Updates the AppShortcuts parameter signatures with the system.
    /// Call this on first launch (and after any login state change) so
    /// iOS surfaces the correct phrases in Siri Suggestions and Shortcuts.
    static func donateIntents() {
        dlog("[AmenIntents] Donating app shortcuts to system")
        AmenAppShortcutsProvider.updateAppShortcutParameters()
    }
}

#else

// MARK: - Stub for pre-iOS 16 / pre-AppIntents environments

/// No-op stub so the codebase compiles on simulators/targets without AppIntents.
@MainActor
final class AmenIntentDonationService {
    private init() {}
    static func donateIntents() {
        dlog("[AmenIntents] AppIntents not available on this platform — skipping donation")
    }
}

#endif
