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
//
// P2 FIX: AmenAppShortcutsProvider has been REMOVED to eliminate the duplicate
// AppShortcutsProvider registration. iOS only supports one AppShortcutsProvider per
// app target; having two caused conflicting / duplicate shortcuts in Siri Suggestions.
//
// The canonical provider is AMENShortcutsProvider in AMENAPP/AMENAppIntents.swift.
// The intents defined in this file (StartPrayerModeIntent, AskBereanIntent, etc.)
// are still registered as shortcuts inside AMENShortcutsProvider via the
// openPrayerMode / openBerean / etc. NotificationCenter chain → AmenIntentRouter.

// MARK: - 1. StartPrayerModeIntent

@available(iOS 16.0, *)
struct StartPrayerModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Start prayer mode"
    static var description = IntentDescription("Open AMEN prayer and reflection mode")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        dlog("[AmenIntents] StartPrayerModeIntent fired")
        await MainActor.run {
            AppNavigationRouter.shared.navigate(to: .resources)
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
            AppNavigationRouter.shared.navigate(to: .askBerean(question: nil))
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
            AppNavigationRouter.shared.navigate(to: .findChurch)
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
            AppNavigationRouter.shared.navigate(to: .churchNotes)
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
            AppNavigationRouter.shared.navigate(to: .reflection)
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
            AppNavigationRouter.shared.navigate(to: .prayerNew)
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
        #if targetEnvironment(simulator)
        // On simulator, updateAppShortcutParameters() triggers the lskd metadata daemon
        // to try to validate the provider, which always fails with
        // LNMetadataProviderErrorDomain Code=9004. App Shortcuts don't function on
        // simulator anyway — skip the call entirely to keep the log clean.
        dlog("[AmenIntents] Skipping App Shortcuts registration on simulator (lskd unsupported)")
        #else
        dlog("[AmenIntents] Donating app shortcuts to system")
        // AmenAppShortcutsProvider was removed (P2 FIX — duplicate provider).
        // The canonical provider is AMENShortcutsProvider in AMENAppIntents.swift.
        AMENShortcutsProvider.updateAppShortcutParameters()
        #endif
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
