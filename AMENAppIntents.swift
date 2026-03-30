//
//  AMENAppIntents.swift
//  AMENAPP
//
//  App Intents for Siri Shortcuts, Focus Filters, and Spotlight donations.
//

import AppIntents
import SwiftUI

// MARK: - Open Prayer Intent

struct OpenPrayerIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Prayer"
    static var description = IntentDescription("Open the Prayer section in AMEN")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(name: .navigateToTab, object: nil, userInfo: ["tab": 2])
        }
        return .result()
    }
}

// MARK: - Open Berean AI Intent

struct OpenBereanIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask Berean AI"
    static var description = IntentDescription("Open the Berean AI assistant in AMEN")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Question")
    var question: String?

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            var info: [String: Any] = [:]
            if let q = question { info["prompt"] = q }
            NotificationCenter.default.post(name: .openBereanFromLiveActivity, object: nil, userInfo: info)
        }
        return .result()
    }
}

// MARK: - Daily Verse Intent

struct DailyVerseIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Daily Verse"
    static var description = IntentDescription("Get today's daily verse from AMEN")

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let verse = await DailyVerseGenkitService.shared.todayVerse?.text
        return .result(value: verse ?? "The Lord is my shepherd, I shall not want. — Psalm 23:1")
    }
}

// MARK: - Create Post Intent

struct CreatePostIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Post"
    static var description = IntentDescription("Create a new post in AMEN")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Post Category")
    var category: PostCategoryEntity?

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(name: .openCreatePost, object: nil)
        }
        return .result()
    }
}

// MARK: - Prayer Focus Filter

struct PrayerFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "AMEN Prayer Focus"
    static var description: IntentDescription? = IntentDescription("Configure AMEN behavior during Prayer focus")

    @Parameter(title: "Silence Social Features")
    var silenceSocial: Bool?

    @Parameter(title: "Show Only Prayer Content")
    var prayerOnly: Bool?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "Prayer Focus",
            subtitle: "Quiet social features for focused prayer time"
        )
    }

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            if silenceSocial == true {
                ShabbatModeService.shared.setEnabled(true)
            }
            UserDefaults.standard.set(prayerOnly == true, forKey: "focusFilterPrayerOnly")
        }
        return .result()
    }
}

// MARK: - Shortcuts Provider

struct AMENShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenPrayerIntent(),
            phrases: [
                "Open prayer in \(.applicationName)",
                "Let me pray with \(.applicationName)"
            ],
            shortTitle: "Open Prayer",
            systemImageName: "hands.sparkles.fill"
        )
        AppShortcut(
            intent: OpenBereanIntent(),
            phrases: [
                "Ask \(.applicationName) a question",
                "Open Berean in \(.applicationName)"
            ],
            shortTitle: "Ask Berean AI",
            systemImageName: "sparkle"
        )
        AppShortcut(
            intent: DailyVerseIntent(),
            phrases: [
                "Get today's verse from \(.applicationName)",
                "Daily verse from \(.applicationName)"
            ],
            shortTitle: "Daily Verse",
            systemImageName: "book.fill"
        )
        AppShortcut(
            intent: PostPrayerRequestIntent(),
            phrases: [
                "Post a prayer request on \(.applicationName)",
                "Ask for prayer on \(.applicationName)"
            ],
            shortTitle: "Post Prayer Request",
            systemImageName: "hands.and.sparkles"
        )
        AppShortcut(
            intent: ShareTestimonyIntent(),
            phrases: [
                "Share a testimony on \(.applicationName)",
                "Post my testimony on \(.applicationName)"
            ],
            shortTitle: "Share Testimony",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: RSVPEventIntent(),
            phrases: [
                "RSVP to an event on \(.applicationName)",
                "I'll be there on \(.applicationName)"
            ],
            shortTitle: "RSVP to Event",
            systemImageName: "calendar.badge.plus"
        )
        AppShortcut(
            intent: DiscoverPrayerNeedsIntent(),
            phrases: [
                "Discover prayer needs on \(.applicationName)",
                "Who needs prayer on \(.applicationName)"
            ],
            shortTitle: "Discover Prayer Needs",
            systemImageName: "person.2.wave.2"
        )
    }
}

// MARK: - Entity

struct PostCategoryEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Post Category")
    static var defaultQuery = PostCategoryQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct PostCategoryQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [PostCategoryEntity] {
        let all = allCategories()
        return all.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [PostCategoryEntity] {
        allCategories()
    }

    private func allCategories() -> [PostCategoryEntity] {
        [
            PostCategoryEntity(id: "testimony", name: "Testimony"),
            PostCategoryEntity(id: "prayer", name: "Prayer"),
            PostCategoryEntity(id: "reflection", name: "Reflection"),
            PostCategoryEntity(id: "question", name: "Question"),
            PostCategoryEntity(id: "gratitude", name: "Gratitude"),
            PostCategoryEntity(id: "encouragement", name: "Encouragement"),
        ]
    }
}

// navigateToTab and openCreatePost are defined in NotificationExtensions.swift

// MARK: - Preference-gated Intents (v2 — full feature spec)

private func siriEnabled() async -> Bool {
    await MainActor.run { AMENUserPreferencesService.shared.preferences.siriIntegrationEnabled }
}

private let siriDisabledDialog = IntentDialog("Siri integration is turned off. Enable it in AMEN Settings → Siri & Shortcuts.")

// MARK: Post a Prayer Request

struct PostPrayerRequestIntent: AppIntent {
    static var title: LocalizedStringResource = "Post a Prayer Request"
    static var description = IntentDescription("Share a prayer request with your AMEN community.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Prayer Request", description: "What would you like prayer for?")
    var prayerText: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard await siriEnabled() else { return .result(dialog: siriDisabledDialog) }
        if let text = prayerText {
            await MainActor.run { UserDefaults.standard.set(text, forKey: "siri_pending_prayer") }
        }
        NotificationCenter.default.post(name: .amenOpenPrayerComposer, object: prayerText)
        return .result(dialog: "Opening your prayer request in AMEN 🙏")
    }
}

// MARK: Share a Testimony

struct ShareTestimonyIntent: AppIntent {
    static var title: LocalizedStringResource = "Share a Testimony"
    static var description = IntentDescription("Share what God has done in your life.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Testimony", description: "Briefly describe what you want to share")
    var testimonyText: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard await siriEnabled() else { return .result(dialog: siriDisabledDialog) }
        if let text = testimonyText {
            await MainActor.run { UserDefaults.standard.set(text, forKey: "siri_pending_testimony") }
        }
        NotificationCenter.default.post(name: .amenOpenTestimonyComposer, object: testimonyText)
        return .result(dialog: "Opening your testimony in AMEN ✨")
    }
}

// MARK: RSVP to an Event

struct RSVPEventIntent: AppIntent {
    static var title: LocalizedStringResource = "RSVP to an Event"
    static var description = IntentDescription("Let your church community know you'll be there.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Event Name", description: "The name of the event")
    var eventName: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard await siriEnabled() else { return .result(dialog: siriDisabledDialog) }
        if let name = eventName {
            await MainActor.run { UserDefaults.standard.set(name, forKey: "siri_pending_rsvp_event") }
        }
        NotificationCenter.default.post(name: .amenOpenEvents, object: eventName)
        let msg = eventName.map { "Opening RSVP for \"\($0)\" 📅" } ?? "Opening Events in AMEN 📅"
        return .result(dialog: IntentDialog(stringLiteral: msg))
    }
}

// MARK: Discover Prayer Needs

struct DiscoverPrayerNeedsIntent: AppIntent {
    static var title: LocalizedStringResource = "Discover Prayer Needs"
    static var description = IntentDescription("See who in your community needs prayer right now.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard await siriEnabled() else { return .result(dialog: siriDisabledDialog) }
        NotificationCenter.default.post(name: .amenOpenPrayerFeed, object: nil)
        return .result(dialog: "Opening the Prayer feed in AMEN 🙏")
    }
}

// MARK: - Deep-link Notification Names (Siri intent routing)

extension Notification.Name {
    static let amenOpenPrayerComposer    = Notification.Name("amen.openPrayerComposer")
    static let amenOpenTestimonyComposer = Notification.Name("amen.openTestimonyComposer")
    static let amenOpenEvents            = Notification.Name("amen.openEvents")
    static let amenOpenPrayerFeed        = Notification.Name("amen.openPrayerFeed")
}
