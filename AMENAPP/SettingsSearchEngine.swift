// SettingsSearchEngine.swift
// AMEN App — Contextual search engine for Settings
//
// Keyword + synonym + intent-phrase matching index.
// Indexes every setting row with primary keywords, synonyms, and
// natural-language intent phrases so users can type things like
// "change my name" and land on Edit Profile.

import SwiftUI

// MARK: - Search Entry Model

struct SettingsSearchEntry: Identifiable {
    let id = UUID()
    let icon: String
    let iconBg: Color?
    let label: String
    let subtitle: String
    let group: String

    /// Primary keywords (exact-match favored)
    let keywords: [String]
    /// Synonyms and alternate terms (fuzzy)
    let synonyms: [String]
    /// Natural-language intent phrases
    let intents: [String]

    /// Navigation destination tag — matched in SettingsView's navigation handler
    let destination: SettingsDestination
}

// MARK: - Destination enum

enum SettingsDestination: String, Hashable {
    case editProfile
    case account
    case notifications
    case messaging
    case integrations
    case privacy
    case security
    case bereanAI
    case feedContent
    case dailyVerse
    case wellbeing
    case language
    case creatorInsights
    case importContent
    case helpSupport
    case reportProblem
    case aboutAmen
    case signOut
    case deleteAccount
    case changePassword
    case twoFactor
    case loginActivity
    case downloadData
    case accountStatus
    case appPermissions
    case mutedWords
    case feedPreferences
    case defaultPostSettings
    case motionAnimations
    case textSize
    case captionsAltText
    case screenTime
    case sundayFocus
    case takeABreak
    case prayerReminders
    case quietMode
    case drafts
    case scheduleReply
    case editMessages
    case appearance
    case accessibility
    case storageData
    case familySafety
}

// MARK: - Settings Search Engine

@MainActor
final class SettingsSearchEngine: ObservableObject {
    static let shared = SettingsSearchEngine()

    @Published var results: [SettingsSearchEntry] = []
    @Published var query: String = ""

    private let index: [SettingsSearchEntry]

    private init() {
        self.index = Self.buildIndex()
    }

    // MARK: - Search

    func search(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.query = trimmed

        guard !trimmed.isEmpty else {
            results = []
            return
        }

        let terms = trimmed.split(separator: " ").map(String.init)

        // Score each entry
        var scored: [(entry: SettingsSearchEntry, score: Int)] = []

        for entry in index {
            var score = 0

            for term in terms {
                // Exact keyword match: +10
                if entry.keywords.contains(where: { $0.contains(term) }) {
                    score += 10
                }
                // Label contains term: +8
                if entry.label.lowercased().contains(term) {
                    score += 8
                }
                // Subtitle contains term: +4
                if entry.subtitle.lowercased().contains(term) {
                    score += 4
                }
                // Synonym match: +6
                if entry.synonyms.contains(where: { $0.contains(term) }) {
                    score += 6
                }
                // Intent phrase match: +7
                if entry.intents.contains(where: { $0.contains(term) }) {
                    score += 7
                }
                // Group match: +2
                if entry.group.lowercased().contains(term) {
                    score += 2
                }
            }

            if score > 0 {
                scored.append((entry, score))
            }
        }

        // Sort by score descending, then alphabetically
        results = scored
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.entry.label < $1.entry.label }
            .map(\.entry)
    }

    // MARK: - Build Index

    private static func buildIndex() -> [SettingsSearchEntry] {
        [
            // ── Account Group ──────────────────────────────────────────
            SettingsSearchEntry(
                icon: "person", iconBg: .blue,
                label: "Edit Profile", subtitle: "Name, bio, links",
                group: "Account",
                keywords: ["profile", "name", "bio", "links", "photo", "picture", "avatar"],
                synonyms: ["display name", "about me", "profile picture", "social links"],
                intents: ["change my name", "update my bio", "edit my profile", "change profile picture"],
                destination: .editProfile
            ),
            SettingsSearchEntry(
                icon: "at", iconBg: .gray,
                label: "Account", subtitle: "Email, username, password",
                group: "Account",
                keywords: ["account", "email", "username", "password"],
                synonyms: ["login", "credentials", "sign in", "authentication"],
                intents: ["change my email", "update username", "reset password", "change my password"],
                destination: .account
            ),
            SettingsSearchEntry(
                icon: "bell", iconBg: .red,
                label: "Notifications", subtitle: "Push, email, in-app",
                group: "Account",
                keywords: ["notifications", "push", "alerts", "email"],
                synonyms: ["reminders", "sounds", "badges", "banners"],
                intents: ["turn off notifications", "stop push alerts", "manage notifications", "notification sounds"],
                destination: .notifications
            ),
            SettingsSearchEntry(
                icon: "message", iconBg: Color(red: 0.2, green: 0.6, blue: 0.9),
                label: "Messaging", subtitle: "Schedule Reply, Edit Message",
                group: "Account",
                keywords: ["messaging", "messages", "chat", "reply"],
                synonyms: ["dm", "direct message", "conversations"],
                intents: ["schedule a reply", "edit sent messages", "message settings"],
                destination: .messaging
            ),
            SettingsSearchEntry(
                icon: "square.grid.2x2", iconBg: .indigo,
                label: "Integrations", subtitle: "Widgets, Live Activities, Siri",
                group: "Account",
                keywords: ["integrations", "widgets", "siri", "live activities"],
                synonyms: ["shortcuts", "home screen", "lock screen"],
                intents: ["add a widget", "set up siri", "enable live activities"],
                destination: .integrations
            ),
            SettingsSearchEntry(
                icon: "lock", iconBg: .green,
                label: "Privacy & Safety", subtitle: "Who can see your content",
                group: "Account",
                keywords: ["privacy", "safety", "block", "restrict"],
                synonyms: ["who can see", "visibility", "hidden", "private account"],
                intents: ["make my account private", "block someone", "who can message me"],
                destination: .privacy
            ),
            SettingsSearchEntry(
                icon: "shield", iconBg: .yellow,
                label: "Security", subtitle: "2FA, active sessions",
                group: "Account",
                keywords: ["security", "2fa", "sessions", "devices"],
                synonyms: ["two factor", "authentication", "login history"],
                intents: ["enable 2fa", "see my devices", "check active sessions"],
                destination: .security
            ),

            // ── Preferences Group ──────────────────────────────────────
            SettingsSearchEntry(
                icon: "sparkles", iconBg: .purple,
                label: "Berean AI", subtitle: "AI settings, Scripture sources",
                group: "Preferences",
                keywords: ["berean", "ai", "artificial intelligence", "scripture"],
                synonyms: ["chatbot", "assistant", "bible ai", "smart"],
                intents: ["change ai settings", "berean preferences", "scripture sources"],
                destination: .bereanAI
            ),
            SettingsSearchEntry(
                icon: "slider.horizontal.3", iconBg: .orange,
                label: "Feed & Content", subtitle: "What you see and when",
                group: "Preferences",
                keywords: ["feed", "content", "algorithm", "timeline"],
                synonyms: ["home feed", "for you", "recommended"],
                intents: ["change what i see", "feed preferences", "customize my feed"],
                destination: .feedContent
            ),
            SettingsSearchEntry(
                icon: "heart.text.square", iconBg: .teal,
                label: "Wellbeing", subtitle: "Screen time, daily limits",
                group: "Preferences",
                keywords: ["wellbeing", "screen time", "limits", "break"],
                synonyms: ["digital wellness", "usage", "health"],
                intents: ["set screen time limits", "take a break", "wellness settings"],
                destination: .wellbeing
            ),
            SettingsSearchEntry(
                icon: "character.bubble", iconBg: .indigo,
                label: "Language", subtitle: "Language & Translation",
                group: "Preferences",
                keywords: ["language", "translation", "translate"],
                synonyms: ["locale", "region", "multilingual"],
                intents: ["change language", "translation settings", "translate posts"],
                destination: .language
            ),

            // ── Tools & Data Group ─────────────────────────────────────
            SettingsSearchEntry(
                icon: "chart.line.uptrend.xyaxis", iconBg: Color(.darkGray),
                label: "Creator & Insights", subtitle: "Analytics, reach, growth",
                group: "Tools & Data",
                keywords: ["creator", "insights", "analytics", "reach"],
                synonyms: ["dashboard", "stats", "metrics", "growth"],
                intents: ["see my analytics", "creator dashboard", "how many views"],
                destination: .creatorInsights
            ),
            SettingsSearchEntry(
                icon: "square.and.arrow.down.on.square", iconBg: Color(.darkGray),
                label: "Import Content", subtitle: "Bring in from other platforms",
                group: "Tools & Data",
                keywords: ["import", "content", "data", "migrate"],
                synonyms: ["transfer", "bring over", "other platforms"],
                intents: ["import from instagram", "bring my data", "migrate content"],
                destination: .importContent
            ),

            // ── Help & Legal Group ─────────────────────────────────────
            SettingsSearchEntry(
                icon: "questionmark.circle", iconBg: nil,
                label: "Help & Support", subtitle: "FAQs, contact us",
                group: "Help & Legal",
                keywords: ["help", "support", "faq", "contact"],
                synonyms: ["questions", "customer service", "how to"],
                intents: ["i need help", "contact support", "how do i"],
                destination: .helpSupport
            ),
            SettingsSearchEntry(
                icon: "flag", iconBg: nil,
                label: "Report a Problem", subtitle: "Bugs, feedback",
                group: "Help & Legal",
                keywords: ["report", "bug", "problem", "feedback"],
                synonyms: ["issue", "error", "crash", "broken"],
                intents: ["report a bug", "something is broken", "send feedback"],
                destination: .reportProblem
            ),
            SettingsSearchEntry(
                icon: "info.circle", iconBg: nil,
                label: "About AMEN", subtitle: "App version",
                group: "Help & Legal",
                keywords: ["about", "version", "amen", "info"],
                synonyms: ["app version", "build", "credits"],
                intents: ["what version am i on", "about this app"],
                destination: .aboutAmen
            ),

            // ── Nested settings ────────────────────────────────────────
            SettingsSearchEntry(
                icon: "key", iconBg: nil,
                label: "Change Password", subtitle: "Security > Password",
                group: "Security",
                keywords: ["password", "change password"],
                synonyms: ["reset password", "new password"],
                intents: ["change my password", "reset my password", "update password"],
                destination: .changePassword
            ),
            SettingsSearchEntry(
                icon: "lock.app.dashed", iconBg: nil,
                label: "Two-Factor Authentication", subtitle: "Security > 2FA",
                group: "Security",
                keywords: ["2fa", "two factor", "authentication"],
                synonyms: ["mfa", "verification code", "authenticator"],
                intents: ["enable two factor", "set up 2fa", "add verification"],
                destination: .twoFactor
            ),
            SettingsSearchEntry(
                icon: "iphone.gen3", iconBg: nil,
                label: "Login Activity & Devices", subtitle: "Security > Sessions",
                group: "Security",
                keywords: ["login", "activity", "devices", "sessions"],
                synonyms: ["active devices", "where am i logged in"],
                intents: ["see my devices", "where am i logged in", "check login activity"],
                destination: .loginActivity
            ),
            SettingsSearchEntry(
                icon: "arrow.down.circle", iconBg: nil,
                label: "Download Your Data", subtitle: "Security > Data export",
                group: "Security",
                keywords: ["download", "data", "export"],
                synonyms: ["backup", "archive", "data request"],
                intents: ["download my data", "export my data", "get a backup"],
                destination: .downloadData
            ),
            SettingsSearchEntry(
                icon: "text.word.spacing", iconBg: nil,
                label: "Muted Words & Topics", subtitle: "Feed & Content > Muted",
                group: "Feed & Content",
                keywords: ["muted", "words", "topics", "hidden"],
                synonyms: ["blocked words", "filter", "hide"],
                intents: ["mute a word", "hide topics", "filter content"],
                destination: .mutedWords
            ),
            SettingsSearchEntry(
                icon: "figure.walk.motion", iconBg: nil,
                label: "Motion & Animations", subtitle: "Feed & Content > Motion",
                group: "Feed & Content",
                keywords: ["motion", "animations", "reduce motion"],
                synonyms: ["accessibility", "movement", "transitions"],
                intents: ["turn off animations", "reduce motion", "stop animations"],
                destination: .motionAnimations
            ),
            SettingsSearchEntry(
                icon: "textformat.size", iconBg: nil,
                label: "Text Size & Display", subtitle: "Feed & Content > Text",
                group: "Feed & Content",
                keywords: ["text", "size", "font", "display"],
                synonyms: ["bigger text", "smaller text", "dynamic type"],
                intents: ["make text bigger", "change font size", "increase text size"],
                destination: .textSize
            ),
            SettingsSearchEntry(
                icon: "clock.arrow.2.circlepath", iconBg: nil,
                label: "Schedule Reply", subtitle: "Messaging > Schedule",
                group: "Messaging",
                keywords: ["schedule", "reply", "delayed"],
                synonyms: ["send later", "timed reply"],
                intents: ["schedule a reply", "send a message later"],
                destination: .scheduleReply
            ),
            SettingsSearchEntry(
                icon: "pencil", iconBg: nil,
                label: "Edit Messages", subtitle: "Messaging > Edit",
                group: "Messaging",
                keywords: ["edit", "messages", "sent"],
                synonyms: ["modify", "correct", "fix message"],
                intents: ["edit a sent message", "can i edit messages"],
                destination: .editMessages
            ),
            SettingsSearchEntry(
                icon: "chart.bar", iconBg: nil,
                label: "Screen Time & Usage", subtitle: "Wellbeing > Screen Time",
                group: "Wellbeing",
                keywords: ["screen time", "usage", "daily limit"],
                synonyms: ["how much time", "app usage"],
                intents: ["see my screen time", "set a daily limit"],
                destination: .screenTime
            ),
            SettingsSearchEntry(
                icon: "moon", iconBg: nil,
                label: "Quiet Mode", subtitle: "Wellbeing > Quiet",
                group: "Wellbeing",
                keywords: ["quiet", "mode", "do not disturb"],
                synonyms: ["dnd", "silent", "focus mode"],
                intents: ["turn on quiet mode", "enable do not disturb"],
                destination: .quietMode
            ),
            SettingsSearchEntry(
                icon: "alarm", iconBg: nil,
                label: "Prayer Reminders", subtitle: "Wellbeing > Prayer",
                group: "Wellbeing",
                keywords: ["prayer", "reminders", "alarm"],
                synonyms: ["prayer time", "daily prayer"],
                intents: ["set prayer reminders", "remind me to pray"],
                destination: .prayerReminders
            ),
            SettingsSearchEntry(
                icon: "paintpalette", iconBg: nil,
                label: "Appearance", subtitle: "Dark mode, display",
                group: "Preferences",
                keywords: ["appearance", "dark mode", "light mode", "theme"],
                synonyms: ["color scheme", "display", "dark", "light"],
                intents: ["switch to dark mode", "change theme", "enable dark mode", "change appearance"],
                destination: .appearance
            ),
            SettingsSearchEntry(
                icon: "accessibility", iconBg: nil,
                label: "Accessibility", subtitle: "Motion, contrast, text size",
                group: "Preferences",
                keywords: ["accessibility", "motion", "contrast", "haptic"],
                synonyms: ["reduce motion", "high contrast", "voiceover", "a11y"],
                intents: ["turn off animations", "increase contrast", "accessibility settings"],
                destination: .accessibility
            ),
            SettingsSearchEntry(
                icon: "internaldrive", iconBg: nil,
                label: "Storage & Data", subtitle: "Cache, media quality",
                group: "Tools & Data",
                keywords: ["storage", "data", "cache", "media"],
                synonyms: ["clear cache", "free space", "data usage", "video quality"],
                intents: ["clear my cache", "free up storage", "reduce data usage"],
                destination: .storageData
            ),
            SettingsSearchEntry(
                icon: "person.2", iconBg: nil,
                label: "Family Safety", subtitle: "Parental controls, content filters",
                group: "Account",
                keywords: ["family", "safety", "parental", "controls", "kids"],
                synonyms: ["child", "guardian", "parent", "restrict"],
                intents: ["set parental controls", "family settings", "restrict content for kids"],
                destination: .familySafety
            ),
        ]
    }
}
