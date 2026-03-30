//
//  SeasonalPromptService.swift
//  AMENAPP
//
//  Seasonal Prompt Service — all prompt templates for Berean AI, Church Notes,
//  daily training prompts, and notification copy, organized by Christian season.
//
//  This service provides:
//    - Berean system prompt fragments per season/holiday
//    - Church Notes guided templates per season
//    - Daily verse/prompt suggestions per season
//    - Notification copy per season (intentional, non-spammy)
//    - Seasonal follow-up action suggestions
//    - Community/human connection reminders
//    - Safety guardrail reminders per season
//
//  Design principles:
//    - Never louder than Scripture
//    - Never feels like marketing or engagement bait
//    - Always preserves path to real church and community
//    - Respects denominational differences
//    - Seasonally aware but not overbearing
//

import Foundation

// MARK: - Seasonal Prompt Type

enum SeasonalPromptType: String, Codable {
    case bereanReflection      // In-chat reflection question
    case bereanGreeting        // Seasonal opening prompt
    case dailyTraining         // Daily action/reflection prompt
    case churchNotesGuide      // Church Notes template prompts
    case notification          // Push/local notification copy
    case communityReminder     // "Don't walk this alone" nudge
    case safetyGuardrail       // Theological safety reminder
}

// MARK: - Seasonal Prompt

struct SeasonalPrompt: Identifiable, Codable {
    let id: String
    let season: LiturgicalSeasonType
    let holiday: HolidayType?           // nil = applies to whole season
    let promptType: SeasonalPromptType
    let title: String
    let body: String
    let scriptureReferences: [String]
    let actionLabel: String?
    let actionDeepLink: String?
    let toneMode: SeasonalToneMode
    let safetyNote: String?             // Optional guardrail note
}

// MARK: - Seasonal Prompt Service

final class SeasonalPromptService {

    static let shared = SeasonalPromptService()

    private let allPrompts: [SeasonalPrompt]

    private init() {
        allPrompts = SeasonalPromptService.buildAllPrompts()
    }

    // MARK: - Query API

    /// Returns all prompts for a given season.
    func prompts(for season: LiturgicalSeasonType) -> [SeasonalPrompt] {
        allPrompts.filter { $0.season == season }
    }

    /// Returns all prompts for a specific holiday.
    func prompts(for holiday: HolidayType) -> [SeasonalPrompt] {
        allPrompts.filter { $0.holiday == holiday }
    }

    /// Returns prompts of a specific type for a season.
    func prompts(for season: LiturgicalSeasonType, type: SeasonalPromptType) -> [SeasonalPrompt] {
        allPrompts.filter { $0.season == season && $0.promptType == type }
    }

    /// Returns a random Berean greeting for the current season.
    func bereanGreeting(for season: LiturgicalSeasonType) -> SeasonalPrompt? {
        prompts(for: season, type: .bereanGreeting).randomElement()
    }

    /// Returns Berean reflection prompts for the current season.
    func bereanReflections(for season: LiturgicalSeasonType) -> [SeasonalPrompt] {
        prompts(for: season, type: .bereanReflection)
    }

    /// Returns daily training prompts for the current season.
    func dailyPrompts(for season: LiturgicalSeasonType) -> [SeasonalPrompt] {
        prompts(for: season, type: .dailyTraining)
    }

    /// Returns notification copy for the current season.
    func notificationPrompts(for season: LiturgicalSeasonType) -> [SeasonalPrompt] {
        prompts(for: season, type: .notification)
    }

    /// Returns the Church Notes template for a given season.
    func churchNotesTemplate(for season: LiturgicalSeasonType) -> ChurchNotesTemplateData? {
        let guides = prompts(for: season, type: .churchNotesGuide)
        guard !guides.isEmpty else { return nil }

        return ChurchNotesTemplateData(
            seasonName: season.displayName,
            templateTitle: "\(season.displayName) Reflection",
            prompts: guides.map(\.body)
        )
    }

    /// Returns community/human connection reminders for a season.
    func communityReminders(for season: LiturgicalSeasonType) -> [SeasonalPrompt] {
        prompts(for: season, type: .communityReminder)
    }

    /// Returns safety guardrail reminders.
    func safetyGuardrails(for season: LiturgicalSeasonType) -> [SeasonalPrompt] {
        prompts(for: season, type: .safetyGuardrail)
    }

    /// Builds the Berean system prompt fragment for a specific season.
    func bereanSeasonalSystemPrompt(for season: LiturgicalSeasonType) -> String {
        var lines: [String] = []

        lines.append("--- Seasonal Berean Behavior ---")
        lines.append("Current season: \(season.displayName)")
        lines.append("Tone: \(season.toneMode.bereanToneHint)")
        lines.append("")

        // Add seasonal reflection prompts as suggested questions
        let reflections = bereanReflections(for: season)
        if !reflections.isEmpty {
            lines.append("Seasonal reflection questions you may weave in naturally:")
            for prompt in reflections.prefix(3) {
                lines.append("- \"\(prompt.body)\"")
            }
            lines.append("")
        }

        // Add community reminder
        if let reminder = communityReminders(for: season).first {
            lines.append("Community reminder: \(reminder.body)")
            lines.append("")
        }

        // Add safety guardrail
        if let guardrail = safetyGuardrails(for: season).first {
            lines.append("Safety note: \(guardrail.body)")
        }

        lines.append("--- End Seasonal Behavior ---")
        return lines.joined(separator: "\n")
    }

    // MARK: - Prompt Definitions

    private static func buildAllPrompts() -> [SeasonalPrompt] {
        var prompts: [SeasonalPrompt] = []

        // ─── ADVENT ──────────────────────────────────────────
        prompts.append(contentsOf: [
            SeasonalPrompt(
                id: "advent_greeting_1", season: .advent, holiday: nil,
                promptType: .bereanGreeting,
                title: "Advent Greeting",
                body: "We're in the season of Advent — a time of waiting and holy anticipation. How are you preparing your heart?",
                scriptureReferences: ["Isaiah 9:6", "Luke 1:46-55"],
                actionLabel: nil, actionDeepLink: nil,
                toneMode: .contemplative, safetyNote: nil
            ),
            SeasonalPrompt(
                id: "advent_reflect_1", season: .advent, holiday: nil,
                promptType: .bereanReflection,
                title: "Advent Reflection",
                body: "What are you waiting on God for this season?",
                scriptureReferences: ["Psalm 27:14", "Isaiah 40:31"],
                actionLabel: "Reflect", actionDeepLink: "amen://berean",
                toneMode: .contemplative, safetyNote: nil
            ),
            SeasonalPrompt(
                id: "advent_reflect_2", season: .advent, holiday: nil,
                promptType: .bereanReflection,
                title: "Advent Preparation",
                body: "What distractions are crowding out preparation for what God wants to do?",
                scriptureReferences: ["Luke 1:26-38"],
                actionLabel: nil, actionDeepLink: nil,
                toneMode: .contemplative, safetyNote: nil
            ),
            SeasonalPrompt(
                id: "advent_reflect_3", season: .advent, holiday: nil,
                promptType: .bereanReflection,
                title: "Advent Hope",
                body: "Where do you most need hope right now?",
                scriptureReferences: ["Romans 15:13", "Isaiah 9:6"],
                actionLabel: nil, actionDeepLink: nil,
                toneMode: .contemplative, safetyNote: nil
            ),
            SeasonalPrompt(
                id: "advent_daily_1", season: .advent, holiday: nil,
                promptType: .dailyTraining,
                title: "Advent Daily",
                body: "Slow down today. Before the rush, pause and ask God what He wants you to notice.",
                scriptureReferences: ["Psalm 46:10"],
                actionLabel: nil, actionDeepLink: nil,
                toneMode: .contemplative, safetyNote: nil
            ),
            SeasonalPrompt(
                id: "advent_notes_1", season: .advent, holiday: nil,
                promptType: .churchNotesGuide,
                title: "Advent Notes",
                body: "What am I waiting on God for?",
                scriptureReferences: [], actionLabel: nil, actionDeepLink: nil,
                toneMode: .contemplative, safetyNote: nil
            ),
            SeasonalPrompt(
                id: "advent_notes_2", season: .advent, holiday: nil,
                promptType: .churchNotesGuide,
                title: "Advent Notes",
                body: "Where do I need hope?",
                scriptureReferences: [], actionLabel: nil, actionDeepLink: nil,
                toneMode: .contemplative, safetyNote: nil
            ),
            SeasonalPrompt(
                id: "advent_notes_3", season: .advent, holiday: nil,
                promptType: .churchNotesGuide,
                title: "Advent Notes",
                body: "What distractions are crowding out preparation?",
                scriptureReferences: [], actionLabel: nil, actionDeepLink: nil,
                toneMode: .contemplative, safetyNote: nil
            ),
            SeasonalPrompt(
                id: "advent_notif_1", season: .advent, holiday: nil,
                promptType: .notification,
                title: "Advent Notification",
                body: "Today's Advent reflection is ready.",
                scriptureReferences: [],
                actionLabel: "Reflect", actionDeepLink: "amen://berean?season=advent",
                toneMode: .contemplative, safetyNote: nil
            ),
        ])

        // ─── CHRISTMAS ──────────────────────────────────────
        prompts.append(contentsOf: [
            SeasonalPrompt(
                id: "christmas_greeting_1", season: .christmas, holiday: .christmas,
                promptType: .bereanGreeting,
                title: "Christmas Greeting",
                body: "Merry Christmas. God became one of us. How does the incarnation speak to where you are right now?",
                scriptureReferences: ["John 1:14", "Luke 2:10-11"],
                actionLabel: nil, actionDeepLink: nil,
                toneMode: .celebratory, safetyNote: nil
            ),
            SeasonalPrompt(
                id: "christmas_reflect_1", season: .christmas, holiday: .christmas,
                promptType: .bereanReflection,
                title: "Christmas Reflection",
                body: "What does it mean to you that God chose to come near?",
                scriptureReferences: ["Matthew 1:23", "John 1:14"],
                actionLabel: nil, actionDeepLink: nil,
                toneMode: .celebratory, safetyNote: nil
            ),
            SeasonalPrompt(
                id: "christmas_notif_1", season: .christmas, holiday: .christmas,
                promptType: .notification,
                title: "Christmas Notification",
                body: "Emmanuel — God is with us. Take a moment to reflect.",
                scriptureReferences: ["Matthew 1:23"],
                actionLabel: "Reflect", actionDeepLink: "amen://berean?season=christmas",
                toneMode: .celebratory, safetyNote: nil
            ),
            SeasonalPrompt(
                id: "christmas_community_1", season: .christmas, holiday: nil,
                promptType: .communityReminder,
                title: "Christmas Community",
                body: "Christmas can be joyful and also lonely. If you're alone this season, consider reaching out to a church or someone you trust.",
                scriptureReferences: ["Hebrews 10:24-25"],
                actionLabel: "Find a Church", actionDeepLink: "amen://find-church",
                toneMode: .celebratory, safetyNote: nil
            ),
        ])

        // ─── LENT ────────────────────────────────────────────
        prompts.append(contentsOf: [
            SeasonalPrompt(
                id: "lent_greeting_1", season: .lent, holiday: nil,
                promptType: .bereanGreeting,
                title: "Lent Greeting",
                body: "We're in the season of Lent — a time for examination, repentance, and returning to God. How is your heart?",
                scriptureReferences: ["Joel 2:12-13", "Psalm 51:10"],
                actionLabel: nil, actionDeepLink: nil,
                toneMode: .reflective, safetyNote: nil
            ),
            SeasonalPrompt(
                id: "lent_reflect_1", season: .lent, holiday: nil,
                promptType: .bereanReflection,
                title: "Lent Examination",
                body: "Is there something you need to surrender during this Lenten season?",
                scriptureReferences: ["Joel 2:12-13", "Psalm 139:23-24"],
                actionLabel: nil, actionDeepLink: nil,
                toneMode: .reflective, safetyNote: nil
            ),
            SeasonalPrompt(
                id: "lent_reflect_2", season: .lent, holiday: nil,
                promptType: .bereanReflection,
                title: "Lent Fasting",
                body: "What are you fasting from, and what are you making room for?",
                scriptureReferences: ["Matthew 6:16-18", "Isaiah 58:6-7"],
                actionLabel: nil, actionDeepLink: nil,
                toneMode: .reflective, safetyNote: nil
            ),
            SeasonalPrompt(
                id: "lent_reflect_3", season: .lent, holiday: nil,
                promptType: .bereanReflection,
                title: "Lent Repentance",
                body: "What is God exposing in your life that needs to change?",
                scriptureReferences: ["Psalm 51:10", "2 Corinthians 7:10"],
                actionLabel: nil, actionDeepLink: nil,
                toneMode: .reflective, safetyNote: nil
            ),
            SeasonalPrompt(
                id: "lent_daily_1", season: .lent, holiday: nil,
                promptType: .dailyTraining,
                title: "Lent Daily",
                body: "Choose one area of your life to examine honestly before God today.",
                scriptureReferences: ["Lamentations 3:40"],
                actionLabel: nil, actionDeepLink: nil,
                toneMode: .reflective, safetyNote: nil
            ),
            SeasonalPrompt(
                id: "lent_notes_1", season: .lent, holiday: nil,
                promptType: .churchNotesGuide,
                title: "Lent Notes", body: "What needs repentance?",
                scriptureReferences: [], actionLabel: nil, actionDeepLink: nil,
                toneMode: .reflective, safetyNote: nil
            ),
            SeasonalPrompt(
                id: "lent_notes_2", season: .lent, holiday: nil,
                promptType: .churchNotesGuide,
                title: "Lent Notes", body: "What am I fasting from and why?",
                scriptureReferences: [], actionLabel: nil, actionDeepLink: nil,
                toneMode: .reflective, safetyNote: nil
            ),
            SeasonalPrompt(
                id: "lent_notes_3", season: .lent, holiday: nil,
                promptType: .churchNotesGuide,
                title: "Lent Notes", body: "What is God exposing in me?",
                scriptureReferences: [], actionLabel: nil, actionDeepLink: nil,
                toneMode: .reflective, safetyNote: nil
            ),
            SeasonalPrompt(
                id: "lent_notif_1", season: .lent, holiday: nil,
                promptType: .notification,
                title: "Lent Notification",
                body: "Would you like to reflect on what God exposed today?",
                scriptureReferences: [],
                actionLabel: "Reflect", actionDeepLink: "amen://berean?season=lent",
                toneMode: .reflective, safetyNote: nil
            ),
        ])

        // ─── HOLY WEEK ──────────────────────────────────────
        prompts.append(contentsOf: [
            SeasonalPrompt(
                id: "hw_palm_reflect", season: .holyWeek, holiday: .palmSunday,
                promptType: .bereanReflection,
                title: "Palm Sunday",
                body: "The crowds shouted Hosanna — but some would turn away. Where does your heart stand with Jesus today?",
                scriptureReferences: ["Matthew 21:1-11"],
                actionLabel: nil, actionDeepLink: nil,
                toneMode: .solemn, safetyNote: nil
            ),
            SeasonalPrompt(
                id: "hw_thursday_reflect", season: .holyWeek, holiday: .maundyThursday,
                promptType: .bereanReflection,
                title: "Maundy Thursday",
                body: "Jesus washed His disciples' feet and broke bread. What does humble service look like in your life?",
                scriptureReferences: ["John 13:1-17"],
                actionLabel: nil, actionDeepLink: nil,
                toneMode: .solemn, safetyNote: nil
            ),
            SeasonalPrompt(
                id: "hw_goodfriday_reflect", season: .holyWeek, holiday: .goodFriday,
                promptType: .bereanReflection,
                title: "Good Friday",
                body: "Would you like to reflect on the cross today? What does it confront in you?",
                scriptureReferences: ["Isaiah 53:4-6", "John 19:30"],
                actionLabel: nil, actionDeepLink: nil,
                toneMode: .solemn, safetyNote: nil
            ),
            SeasonalPrompt(
                id: "hw_goodfriday_notes_1", season: .holyWeek, holiday: .goodFriday,
                promptType: .churchNotesGuide,
                title: "Good Friday Notes", body: "What does the cross confront in me?",
                scriptureReferences: [], actionLabel: nil, actionDeepLink: nil,
                toneMode: .solemn, safetyNote: nil
            ),
            SeasonalPrompt(
                id: "hw_goodfriday_notes_2", season: .holyWeek, holiday: .goodFriday,
                promptType: .churchNotesGuide,
                title: "Good Friday Notes", body: "What sin, shame, or pride needs to be laid down?",
                scriptureReferences: [], actionLabel: nil, actionDeepLink: nil,
                toneMode: .solemn, safetyNote: nil
            ),
            SeasonalPrompt(
                id: "hw_saturday_reflect", season: .holyWeek, holiday: .holySaturday,
                promptType: .bereanReflection,
                title: "Holy Saturday",
                body: "Today is a day of silence and waiting. What are you waiting on God for, even when it feels like nothing is happening?",
                scriptureReferences: ["Psalm 27:14"],
                actionLabel: nil, actionDeepLink: nil,
                toneMode: .solemn, safetyNote: nil
            ),
            SeasonalPrompt(
                id: "hw_goodfriday_notif", season: .holyWeek, holiday: .goodFriday,
                promptType: .notification,
                title: "Good Friday Notification",
                body: "Take a quiet moment to reflect on the cross.",
                scriptureReferences: [],
                actionLabel: "Reflect", actionDeepLink: "amen://berean?holiday=good_friday",
                toneMode: .solemn, safetyNote: nil
            ),
        ])

        // ─── EASTER ──────────────────────────────────────────
        prompts.append(contentsOf: [
            SeasonalPrompt(
                id: "easter_greeting_1", season: .easter, holiday: .easter,
                promptType: .bereanGreeting,
                title: "Easter Greeting",
                body: "He is risen! The tomb is empty and hope is alive. How is the resurrection shaping your week?",
                scriptureReferences: ["Matthew 28:6", "1 Corinthians 15:55-57"],
                actionLabel: nil, actionDeepLink: nil,
                toneMode: .joyful, safetyNote: nil
            ),
            SeasonalPrompt(
                id: "easter_reflect_1", season: .easter, holiday: .easter,
                promptType: .bereanReflection,
                title: "Easter Reflection",
                body: "What areas of your life need resurrection hope?",
                scriptureReferences: ["Romans 6:4", "2 Corinthians 5:17"],
                actionLabel: nil, actionDeepLink: nil,
                toneMode: .joyful, safetyNote: nil
            ),
            SeasonalPrompt(
                id: "easter_reflect_2", season: .easter, holiday: nil,
                promptType: .bereanReflection,
                title: "Easter Season",
                body: "Where is God calling you into renewed faith?",
                scriptureReferences: ["Ephesians 2:4-5"],
                actionLabel: nil, actionDeepLink: nil,
                toneMode: .joyful, safetyNote: nil
            ),
            SeasonalPrompt(
                id: "easter_notes_1", season: .easter, holiday: .easter,
                promptType: .churchNotesGuide,
                title: "Easter Notes", body: "What areas of my life need resurrection hope?",
                scriptureReferences: [], actionLabel: nil, actionDeepLink: nil,
                toneMode: .joyful, safetyNote: nil
            ),
            SeasonalPrompt(
                id: "easter_notes_2", season: .easter, holiday: .easter,
                promptType: .churchNotesGuide,
                title: "Easter Notes", body: "Where is God calling me into renewed faith?",
                scriptureReferences: [], actionLabel: nil, actionDeepLink: nil,
                toneMode: .joyful, safetyNote: nil
            ),
            SeasonalPrompt(
                id: "easter_notif_1", season: .easter, holiday: .easter,
                promptType: .notification,
                title: "Easter Notification",
                body: "Looking for an Easter service near you?",
                scriptureReferences: [],
                actionLabel: "Find Services", actionDeepLink: "amen://find-church?holiday=easter",
                toneMode: .joyful, safetyNote: nil
            ),
            SeasonalPrompt(
                id: "easter_community_1", season: .easter, holiday: nil,
                promptType: .communityReminder,
                title: "Easter Community",
                body: "Easter is best celebrated in community. Consider visiting a church this week — even if it's been a while.",
                scriptureReferences: ["Hebrews 10:24-25"],
                actionLabel: "Find a Church", actionDeepLink: "amen://find-church",
                toneMode: .joyful, safetyNote: nil
            ),
        ])

        // ─── PENTECOST ──────────────────────────────────────
        prompts.append(contentsOf: [
            SeasonalPrompt(
                id: "pentecost_greeting_1", season: .pentecost, holiday: .pentecost,
                promptType: .bereanGreeting,
                title: "Pentecost Greeting",
                body: "This is the season of Pentecost — the Spirit empowering the Church. What would bold faith look like for you this week?",
                scriptureReferences: ["Acts 2:1-4", "Acts 1:8"],
                actionLabel: nil, actionDeepLink: nil,
                toneMode: .activating, safetyNote: nil
            ),
            SeasonalPrompt(
                id: "pentecost_reflect_1", season: .pentecost, holiday: nil,
                promptType: .bereanReflection,
                title: "Pentecost Boldness",
                body: "Where do you need boldness from the Holy Spirit?",
                scriptureReferences: ["Acts 4:31", "2 Timothy 1:7"],
                actionLabel: nil, actionDeepLink: nil,
                toneMode: .activating, safetyNote: nil
            ),
            SeasonalPrompt(
                id: "pentecost_reflect_2", season: .pentecost, holiday: nil,
                promptType: .bereanReflection,
                title: "Pentecost Mission",
                body: "How is the Spirit leading you to act, serve, or speak?",
                scriptureReferences: ["John 16:13", "Romans 8:14"],
                actionLabel: nil, actionDeepLink: nil,
                toneMode: .activating, safetyNote: nil
            ),
            SeasonalPrompt(
                id: "pentecost_notes_1", season: .pentecost, holiday: nil,
                promptType: .churchNotesGuide,
                title: "Pentecost Notes", body: "Where do I need boldness?",
                scriptureReferences: [], actionLabel: nil, actionDeepLink: nil,
                toneMode: .activating, safetyNote: nil
            ),
            SeasonalPrompt(
                id: "pentecost_notes_2", season: .pentecost, holiday: nil,
                promptType: .churchNotesGuide,
                title: "Pentecost Notes", body: "How is the Spirit leading me to act?",
                scriptureReferences: [], actionLabel: nil, actionDeepLink: nil,
                toneMode: .activating, safetyNote: nil
            ),
            SeasonalPrompt(
                id: "pentecost_notif_1", season: .pentecost, holiday: nil,
                promptType: .notification,
                title: "Pentecost Notification",
                body: "Pause and pray: where do you need boldness this week?",
                scriptureReferences: [],
                actionLabel: "Pray", actionDeepLink: "amen://berean?season=pentecost",
                toneMode: .activating, safetyNote: nil
            ),
        ])

        // ─── NEW YEAR CONSECRATION ──────────────────────────
        prompts.append(contentsOf: [
            SeasonalPrompt(
                id: "newyear_greeting_1", season: .christmas, holiday: .newYearConsecration,
                promptType: .bereanGreeting,
                title: "New Year Consecration",
                body: "A new year begins. This is a season to dedicate your path to God. What is He calling you to this year?",
                scriptureReferences: ["Jeremiah 29:11", "Proverbs 16:3"],
                actionLabel: nil, actionDeepLink: nil,
                toneMode: .contemplative, safetyNote: nil
            ),
            SeasonalPrompt(
                id: "newyear_reflect_1", season: .christmas, holiday: .newYearConsecration,
                promptType: .bereanReflection,
                title: "New Year Dedication",
                body: "What would it look like to commit this year fully to God?",
                scriptureReferences: ["Joshua 24:15", "Psalm 37:5"],
                actionLabel: nil, actionDeepLink: nil,
                toneMode: .contemplative, safetyNote: nil
            ),
        ])

        // ─── ORDINARY TIME ──────────────────────────────────
        prompts.append(contentsOf: [
            SeasonalPrompt(
                id: "ordinary_greeting_1", season: .ordinaryTimeLate, holiday: nil,
                promptType: .bereanGreeting,
                title: "Ordinary Time Greeting",
                body: "Faithfulness grows in the ordinary. What is God teaching you in the everyday?",
                scriptureReferences: ["Luke 16:10", "Colossians 3:23"],
                actionLabel: nil, actionDeepLink: nil,
                toneMode: .balanced, safetyNote: nil
            ),
        ])

        // ─── UNIVERSAL SAFETY GUARDRAILS ────────────────────
        let allSeasons: [LiturgicalSeasonType] = [.advent, .christmas, .lent, .holyWeek, .easter, .pentecost]
        for season in allSeasons {
            prompts.append(SeasonalPrompt(
                id: "safety_\(season.rawValue)", season: season, holiday: nil,
                promptType: .safetyGuardrail,
                title: "Safety Guardrail",
                body: "This app is a guide, not a replacement for church, pastors, or real-life community. Consider attending a local service or reaching out to a trusted believer.",
                scriptureReferences: ["Hebrews 10:24-25"],
                actionLabel: "Find a Church", actionDeepLink: "amen://find-church",
                toneMode: season.toneMode, safetyNote: "Always preserve path to real community."
            ))
        }

        return prompts
    }
}
