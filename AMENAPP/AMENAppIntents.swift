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
