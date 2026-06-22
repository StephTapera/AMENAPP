//
//  AMENSettingsSystem.swift
//  AMENAPP
//
//  Production-grade, Instagram/Threads-parity settings system.
//  Design: white background, ultraThinMaterial glass, AMENFont typography.
//  Settings persist locally and sync to the signed-in user's private Firestore settings document.
//

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

// MARK: - Design Tokens

private enum ST {
    static let bg             = Color(.systemBackground)
    static let glassFill      = Color(.systemBackground).opacity(0.55)
    static let hairline       = Color(.separator).opacity(0.5)
    static let primary        = Color(.label)
    static let secondary      = Color(.secondaryLabel)
    static let tertiary       = Color(.tertiaryLabel)
    static let shadow         = Color(.label).opacity(0.05)
    static let danger         = Color(red: 0.92, green: 0.18, blue: 0.18)
    static let radius: CGFloat = 16
    static let spring         = Animation.spring(response: 0.35, dampingFraction: 0.82)
}

// MARK: - Glass Modifier

private struct SettingsGlassCard: ViewModifier {
    var cornerRadius: CGFloat = ST.radius
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(ST.glassFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(ST.hairline, lineWidth: 0.5)
                    )
                    .shadow(color: ST.shadow, radius: 10, x: 0, y: 4)
            )
    }
}

private extension View {
    func glassCard(cornerRadius: CGFloat = ST.radius) -> some View {
        modifier(SettingsGlassCard(cornerRadius: cornerRadius))
    }
}

private struct AmenSettingsSnapshot: Codable, Equatable {
    let values: [String: String]

    static let trackedKeys: [String] = [
        "amenSettingsSuggestedDismissed",
        "amen_account_type",
        "amen_private_account", "amen_activity_status", "amen_read_receipts", "amen_show_likes", "amen_find_by_email", "amen_find_by_phone", "amen_comment_permission", "amen_mention_permission", "amen_profile_discoverability",
        "amen_hidden_words", "amen_strict_filter", "amen_sensitive_blur", "amen_anti_harassment",
        "amen_dm_permission", "amen_msg_requests", "amen_online_in_dms", "amen_dm_read_receipts", "amen_typing_indicator", "amen_media_preview", "amen_link_preview", "amen_dm_curfew_enabled", "amen_dm_curfew_start_hour", "amen_dm_curfew_end_hour",
        "amen_push_enabled", "amen_inapp_enabled", "amen_email_digest", "amen_notif_digest_freq", "amen_notif_quiet_enabled", "amen_notif_quiet_start_hour", "amen_notif_quiet_end_hour", "amen_smart_clustered_notifs",
        "amen_default_audience", "amen_draft_autosave", "amen_draft_berean_resume", "amen_post_scheduling", "amen_sensitive_warning", "amen_ai_disclosure", "amen_true_source", "amen_auto_content_warnings", "amen_post_template_signature", "amen_post_template_call_to_action", "amen_post_template_include_scripture",
        "amen_feed_mode", "amen_sensitive_content", "amen_autoplay", "amen_show_like_counts", "amen_show_follower_counts", "amen_hide_from_suggestions", "amen_interest_worship", "amen_interest_scripture", "amen_interest_service", "amen_interest_family", "amen_interest_wellness", "amen_interest_local_church",
        "amen_berean_enabled", "amen_berean_mode", "amen_berean_memory", "amen_berean_transparency", "amen_berean_data_usage", "amen_berean_in_feed", "amen_berean_style",
        "amen_notes_default_folder", "amen_notes_auto_scripture", "amen_notes_growth_loop", "amen_notes_sync", "amen_notes_export_format", "amen_notes_sermon_capture", "amen_notes_theme", "amen_notes_use_theme_for_exports",
        "amen_reduce_motion", "amen_high_contrast", "amen_bold_text", "amen_alt_text", "amen_screen_reader", "amen_app_text_scale", "amen_caption_size", "amen_caption_background", "amen_caption_speaker_names",
        "amen_download_quality", "amen_preload_videos", "amen_ai_processing", "amen_data_collection_personalization", "amen_data_collection_diagnostics", "amen_data_collection_location", "amen_data_retention_posts", "amen_data_retention_search", "amen_data_retention_ai",
        "amen_2fa_enabled", "amen_login_alerts",
        "amen_teen_mode", "amen_time_limit", "amen_family_quiet", "amen_content_restrict", "amen_private_by_default", "amen_guardian_review_required", "amen_guardian_digest", "amen_guardian_invite_email",
        "amen_creator_weekly_digest", "amen_creator_prayerful_metrics", "amen_creator_growth_prompts"
    ]

    static func current(defaults: UserDefaults = .standard) -> AmenSettingsSnapshot {
        let pairs = trackedKeys.compactMap { key -> (String, String)? in
            guard let value = defaults.object(forKey: key) else { return nil }
            switch value {
            case let bool as Bool:
                return (key, bool ? "true" : "false")
            case let int as Int:
                return (key, String(int))
            case let double as Double:
                return (key, String(double))
            case let string as String:
                return (key, string)
            default:
                return nil
            }
        }
        return AmenSettingsSnapshot(values: Dictionary(uniqueKeysWithValues: pairs))
    }

    func apply(to defaults: UserDefaults = .standard) {
        for (key, value) in values where Self.trackedKeys.contains(key) {
            if value == "true" || value == "false" {
                defaults.set(value == "true", forKey: key)
            } else if let intValue = Int(value), key.hasSuffix("_hour") {
                defaults.set(intValue, forKey: key)
            } else if let doubleValue = Double(value), key == "amen_app_text_scale" {
                defaults.set(doubleValue, forKey: key)
            } else {
                defaults.set(value, forKey: key)
            }
        }
    }
}

@MainActor
final class AmenSettingsPersistenceService: ObservableObject {
    static let shared = AmenSettingsPersistenceService()

    private var loadedUserID: String?
    private var lastSavedSnapshot: AmenSettingsSnapshot?
    private var observer: NSObjectProtocol?
    private var saveTask: Task<Void, Never>?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { _ in
            Task { @MainActor in AmenSettingsPersistenceService.shared.scheduleSave() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func load() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            loadedUserID = nil
            lastSavedSnapshot = AmenSettingsSnapshot.current()
            return
        }

        loadedUserID = uid
        let document = Firestore.firestore().collection("userSettings").document(uid)
        do {
            let snapshot = try await document.getDocument()
            if let values = snapshot.data()?["values"] as? [String: String] {
                let restored = AmenSettingsSnapshot(values: values)
                restored.apply()
                lastSavedSnapshot = restored
            } else {
                await save(force: true)
            }
        } catch {
            lastSavedSnapshot = AmenSettingsSnapshot.current()
        }
    }

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            await self?.save(force: false)
        }
    }

    func save(force: Bool) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let snapshot = AmenSettingsSnapshot.current()
        guard force || snapshot != lastSavedSnapshot else { return }

        do {
            _ = try await Functions.functions(region: "us-central1")
                .httpsCallable("updateUserSettings")
                .call(["values": snapshot.values])
            loadedUserID = uid
            lastSavedSnapshot = snapshot
        } catch {
            lastSavedSnapshot = snapshot
        }
    }
}

private func settingsHourDate(_ hour: Int) -> Date {
    Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
}

private func settingsHour(from date: Date) -> Int {
    Calendar.current.component(.hour, from: date)
}

// MARK: - Settings Sections Enum

enum AMENSettingsSection: String, CaseIterable, Identifiable {
    case account
    case privacy
    case safety
    case messages
    case notifications
    case contentPosting
    case feedDiscovery
    case bereanAI
    case sabbathRhythm
    case ambientOS
    case churchNotes
    case accessibility
    case storageData
    case security
    case familySafety
    case supportTransparency
    case about

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .account:             return "Account"
        case .privacy:             return "Privacy"
        case .safety:              return "Safety"
        case .messages:            return "Messages"
        case .notifications:       return "Notifications"
        case .contentPosting:      return "Content & Posting"
        case .feedDiscovery:       return "Feed & Discovery"
        case .bereanAI:            return "Berean AI"
        case .sabbathRhythm:       return "Sabbath Rhythm"
        case .ambientOS:           return "Ambient OS"
        case .churchNotes:         return "Church Notes"
        case .accessibility:       return "Accessibility"
        case .storageData:         return "Storage & Data"
        case .security:            return "Security"
        case .familySafety:        return "Family Safety"
        case .supportTransparency: return "Support & Transparency"
        case .about:               return "About"
        }
    }

    var icon: String {
        switch self {
        case .account:             return "person.circle"
        case .privacy:             return "eye.slash"
        case .safety:              return "shield.lefthalf.filled"
        case .messages:            return "message"
        case .notifications:       return "bell"
        case .contentPosting:      return "square.and.pencil"
        case .feedDiscovery:       return "rectangle.stack"
        case .bereanAI:            return "sparkles"
        case .sabbathRhythm:       return "moon.stars"
        case .ambientOS:           return "sparkles.rectangle.stack"
        case .churchNotes:         return "note.text"
        case .accessibility:       return "accessibility"
        case .storageData:         return "internaldrive"
        case .security:            return "lock.shield"
        case .familySafety:        return "figure.2.and.child.holdinghands"
        case .supportTransparency: return "questionmark.circle"
        case .about:               return "info.circle"
        }
    }

    var description: String {
        switch self {
        case .account:             return "Name, username, email, account type"
        case .privacy:             return "Who can see your posts and profile"
        case .safety:              return "Hidden words, blocked & muted accounts"
        case .messages:            return "DMs, read receipts, message requests"
        case .notifications:       return "Push, in-app, digest frequency"
        case .contentPosting:      return "Default audience, drafts, scheduling"
        case .feedDiscovery:       return "Feed mode, sensitive content, autoplay"
        case .bereanAI:            return "AI settings, context memory, response style"
        case .sabbathRhythm:       return "Schedule rest and quiet Selah"
        case .ambientOS:           return "Context-aware day briefing and actions"
        case .churchNotes:         return "Folders, scripture detection, export"
        case .accessibility:       return "Text size, motion, contrast"
        case .storageData:         return "Cache, download quality, data export"
        case .security:            return "Two-factor auth, sessions, login history"
        case .familySafety:        return "Teen mode, time limits, supervision"
        case .supportTransparency: return "Help, policies, account status"
        case .about:               return "Version, changelog, diagnostics"
        }
    }

    var accentColor: Color {
        switch self {
        case .account:             return Color(red: 0.20, green: 0.42, blue: 0.98)
        case .privacy:             return Color(red: 0.08, green: 0.62, blue: 0.38)
        case .safety:              return Color(red: 0.95, green: 0.38, blue: 0.18)
        case .messages:            return Color(red: 0.20, green: 0.60, blue: 0.98)
        case .notifications:       return Color(red: 0.92, green: 0.28, blue: 0.28)
        case .contentPosting:      return Color(red: 0.55, green: 0.28, blue: 0.95)
        case .feedDiscovery:       return Color(red: 0.08, green: 0.62, blue: 0.92)
        case .bereanAI:            return Color(red: 0.46, green: 0.28, blue: 0.95)
        case .sabbathRhythm:       return Color(red: 0.24, green: 0.46, blue: 0.72)
        case .ambientOS:           return Color(red: 0.95, green: 0.65, blue: 0.18)
        case .churchNotes:         return Color(red: 0.95, green: 0.65, blue: 0.18)
        case .accessibility:       return Color(red: 0.20, green: 0.72, blue: 0.54)
        case .storageData:         return Color(white: 0.45)
        case .security:            return Color(red: 0.95, green: 0.72, blue: 0.10)
        case .familySafety:        return Color(red: 0.30, green: 0.72, blue: 0.54)
        case .supportTransparency: return Color(white: 0.50)
        case .about:               return Color(red: 0.20, green: 0.42, blue: 0.98)
        }
    }
}

// MARK: - Settings Search Service

@MainActor final class SettingsSearchService: ObservableObject {
    @Published var query: String = ""
    @Published var results: [SettingsSearchResult] = []

    struct SettingsSearchResult: Identifiable {
        let id = UUID()
        let title: String
        let section: AMENSettingsSection
        let sectionPath: String
        let keywords: [String]
        let description: String
    }

    let searchIndex: [SettingsSearchResult] = [
        // Account
        .init(title: "Edit Name", section: .account, sectionPath: "Account → Name", keywords: ["name", "display name", "full name", "rename"], description: "Change your display name"),
        .init(title: "Change Username", section: .account, sectionPath: "Account → Username", keywords: ["username", "handle", "@", "user"], description: "Update your @username"),
        .init(title: "Edit Bio", section: .account, sectionPath: "Account → Bio", keywords: ["bio", "about", "description", "profile"], description: "Edit your profile bio"),
        .init(title: "Email Address", section: .account, sectionPath: "Account → Email", keywords: ["email", "email address", "contact email"], description: "Update your email"),
        .init(title: "Phone Number", section: .account, sectionPath: "Account → Phone", keywords: ["phone", "mobile", "number", "cell"], description: "Update your phone number"),
        .init(title: "Account Type", section: .account, sectionPath: "Account → Account Type", keywords: ["personal", "church", "business", "account type", "switch account"], description: "Switch between personal, church, or business"),
        .init(title: "Deactivate Account", section: .account, sectionPath: "Account → Deactivate", keywords: ["deactivate", "disable", "pause account", "temporary"], description: "Temporarily deactivate your account"),
        .init(title: "Delete Account", section: .account, sectionPath: "Account → Delete", keywords: ["delete", "remove account", "close account", "permanent"], description: "Permanently delete your account"),

        // Privacy
        .init(title: "Private Account", section: .privacy, sectionPath: "Privacy → Account Visibility", keywords: ["private", "private account", "private profile", "public", "followers only"], description: "Make your account private or public"),
        .init(title: "Activity Status", section: .privacy, sectionPath: "Privacy → Activity Status", keywords: ["online", "active", "last seen", "activity", "show online"], description: "Show or hide your online status"),
        .init(title: "Read Receipts", section: .privacy, sectionPath: "Privacy → Activity Status", keywords: ["read receipts", "seen", "read", "message seen"], description: "Show when you've read messages"),
        .init(title: "Comment Permissions", section: .privacy, sectionPath: "Privacy → Comments", keywords: ["comments", "who can comment", "disable comments", "allow comments"], description: "Control who can comment on your posts"),
        .init(title: "Tags & Mentions", section: .privacy, sectionPath: "Privacy → Mentions", keywords: ["tags", "mention", "tag", "who can tag me", "who can mention me"], description: "Control who can tag or mention you"),
        .init(title: "Like Count Visibility", section: .privacy, sectionPath: "Privacy → Likes", keywords: ["likes", "hide likes", "like count", "show likes"], description: "Hide or show like counts on posts"),
        .init(title: "Discoverability", section: .privacy, sectionPath: "Privacy → Discoverability", keywords: ["discover", "search", "find by email", "find by phone", "searchable"], description: "Control how people find you"),

        // Safety
        .init(title: "Hidden Words", section: .safety, sectionPath: "Safety → Hidden Words", keywords: ["hidden words", "muted words", "filter words", "block words", "keyword filter"], description: "Filter offensive words from comments"),
        .init(title: "Blocked Accounts", section: .safety, sectionPath: "Safety → Blocked Accounts", keywords: ["block", "blocked", "blocked accounts", "block user"], description: "Manage accounts you've blocked"),
        .init(title: "Muted Accounts", section: .safety, sectionPath: "Safety → Muted Accounts", keywords: ["mute", "muted", "muted accounts", "mute user", "silence"], description: "Manage accounts you've muted"),
        .init(title: "Restricted Accounts", section: .safety, sectionPath: "Safety → Restricted Accounts", keywords: ["restrict", "restricted", "limited", "shadow"], description: "Limit interactions without blocking"),
        .init(title: "Anti-Harassment Mode", section: .safety, sectionPath: "Safety → Anti-Harassment", keywords: ["harassment", "bully", "abuse", "stricter", "anti-harassment"], description: "Enable stricter harassment filters"),
        .init(title: "Crisis Resources", section: .safety, sectionPath: "Safety → Crisis Resources", keywords: ["crisis", "wellness", "mental health", "help", "emergency"], description: "Access crisis and wellness resources"),

        // Messages
        .init(title: "Who Can DM Me", section: .messages, sectionPath: "Messages → DM Permissions", keywords: ["dm", "direct message", "who can dm", "message requests", "inbox", "who can message me"], description: "Control who can send you messages"),
        .init(title: "Message Requests", section: .messages, sectionPath: "Messages → Message Requests", keywords: ["message request", "request", "filter messages", "unknown"], description: "Manage message request settings"),
        .init(title: "DM Curfew", section: .messages, sectionPath: "Messages → DM Curfew", keywords: ["curfew", "quiet hours dm", "restrict dm", "berean accountability", "limit messages"], description: "Set hours when DMs are restricted"),
        .init(title: "Typing Indicators", section: .messages, sectionPath: "Messages → Typing", keywords: ["typing", "typing indicator", "is typing", "dots"], description: "Show or hide typing indicators"),

        // Notifications
        .init(title: "Turn Off Notifications", section: .notifications, sectionPath: "Notifications", keywords: ["notifications off", "turn off notifications", "mute notifications", "no notifications", "silent"], description: "Disable push notifications"),
        .init(title: "Like Notifications", section: .notifications, sectionPath: "Notifications → Reactions", keywords: ["like notification", "reaction notification", "likes", "hearts"], description: "Notifications for likes and reactions"),
        .init(title: "Comment Notifications", section: .notifications, sectionPath: "Notifications → Comments", keywords: ["comment notification", "reply notification", "comments"], description: "Notifications for comments"),
        .init(title: "Follow Notifications", section: .notifications, sectionPath: "Notifications → Followers", keywords: ["follow", "follower", "new follower", "follow request"], description: "Notifications for follows"),
        .init(title: "Quiet Hours", section: .notifications, sectionPath: "Notifications → Quiet Hours", keywords: ["quiet hours", "do not disturb", "sleep", "night mode", "bedtime"], description: "Pause notifications at set times"),
        .init(title: "Digest Frequency", section: .notifications, sectionPath: "Notifications → Digest", keywords: ["digest", "summary", "notification summary", "hourly", "daily"], description: "Batch notifications into digests"),

        // Content & Posting
        .init(title: "Default Post Audience", section: .contentPosting, sectionPath: "Content & Posting → Default Audience", keywords: ["default audience", "post to", "who sees posts", "post privacy"], description: "Set who sees your posts by default"),
        .init(title: "Schedule Post", section: .contentPosting, sectionPath: "Content & Posting → Scheduled Posts", keywords: ["schedule post", "scheduled", "schedule", "future post", "later"], description: "View and manage scheduled posts"),
        .init(title: "Drafts", section: .contentPosting, sectionPath: "Content & Posting → Drafts", keywords: ["draft", "drafts", "saved drafts", "unpublished"], description: "Access your saved drafts"),
        .init(title: "AI Content Disclosure", section: .contentPosting, sectionPath: "Content & Posting → AI Disclosure", keywords: ["ai label", "ai content", "disclosure", "ai generated", "true source"], description: "Auto-label AI-assisted content"),
        .init(title: "Content Warnings", section: .contentPosting, sectionPath: "Content & Posting → Content Warnings", keywords: ["content warning", "sensitive content", "cw", "warning label"], description: "Auto-suggest content warning labels"),

        // Feed & Discovery
        .init(title: "Feed Mode", section: .feedDiscovery, sectionPath: "Feed & Discovery → Feed Mode", keywords: ["feed mode", "nourish", "sabbath", "low stimulation", "comparison reset", "feed filter"], description: "Switch between feed modes"),
        .init(title: "Sabbath Mode", section: .feedDiscovery, sectionPath: "Feed & Discovery → Focus Modes", keywords: ["sabbath", "sabbath mode", "sunday", "rest", "church notes only"], description: "Limit feed to Church Notes and Resources"),
        .init(title: "Sabbath Rhythm", section: .sabbathRhythm, sectionPath: "Sabbath Rhythm", keywords: ["sabbath", "rest", "selah", "schedule", "presence", "holy ground", "quiet"], description: "Schedule rest and configure Selah's subtraction rhythm"),
        .init(title: "Autoplay Videos", section: .feedDiscovery, sectionPath: "Feed & Discovery → Autoplay", keywords: ["autoplay", "auto play", "video autoplay", "stop autoplay"], description: "Control video autoplay in feed"),
        .init(title: "Sensitive Content", section: .feedDiscovery, sectionPath: "Feed & Discovery → Sensitive Content", keywords: ["sensitive content", "filter content", "restrict content", "content filter"], description: "Adjust sensitivity of shown content"),
        .init(title: "Show Like Counts", section: .feedDiscovery, sectionPath: "Feed & Discovery → Like Counts", keywords: ["like count feed", "hide likes feed", "show likes"], description: "Show or hide like counts in your feed"),

        // Berean AI
        .init(title: "Berean AI Toggle", section: .bereanAI, sectionPath: "Berean AI → Enable", keywords: ["berean", "ai", "enable ai", "disable ai", "ai off"], description: "Enable or disable Berean AI"),
        .init(title: "AI Context Memory", section: .bereanAI, sectionPath: "Berean AI → Context Memory", keywords: ["memory", "context", "ai memory", "clear memory", "ai history"], description: "Control Berean AI memory"),
        .init(title: "AI Transparency", section: .bereanAI, sectionPath: "Berean AI → Transparency", keywords: ["ai transparency", "ai label", "berean assisted", "ai disclosure"], description: "Label posts Berean helped create"),

        // Church Notes
        .init(title: "Church Notes Sync", section: .churchNotes, sectionPath: "Church Notes → Sync", keywords: ["sync notes", "notes sync", "cloud sync", "backup notes"], description: "Sync notes across devices"),
        .init(title: "Auto-detect Scriptures", section: .churchNotes, sectionPath: "Church Notes → Scripture Detection", keywords: ["scripture", "bible verse", "auto detect", "scripture detection"], description: "Automatically detect Bible references"),
        .init(title: "Export Notes", section: .churchNotes, sectionPath: "Church Notes → Export", keywords: ["export notes", "download notes", "pdf export", "markdown", "backup"], description: "Export notes as PDF, text, or Markdown"),

        // Accessibility
        .init(title: "Reduce Motion", section: .accessibility, sectionPath: "Accessibility → Motion", keywords: ["reduce motion", "animations", "motion", "parallax", "disable animations"], description: "Reduce or disable animations"),
        .init(title: "High Contrast", section: .accessibility, sectionPath: "Accessibility → Contrast", keywords: ["contrast", "high contrast", "accessibility contrast"], description: "Enable high contrast mode"),
        .init(title: "Bold Text", section: .accessibility, sectionPath: "Accessibility → Bold Text", keywords: ["bold text", "bold", "thick text", "heavy text"], description: "Make text bold throughout the app"),
        .init(title: "Alt Text", section: .accessibility, sectionPath: "Accessibility → Alt Text", keywords: ["alt text", "image description", "screen reader", "accessibility description"], description: "Add descriptions to images for screen readers"),

        // Storage & Data
        .init(title: "Clear Cache", section: .storageData, sectionPath: "Storage & Data → Cache", keywords: ["cache", "clear cache", "storage", "free space", "delete cache"], description: "Free up storage by clearing cache"),
        .init(title: "Download My Data", section: .storageData, sectionPath: "Storage & Data → Download", keywords: ["download data", "export data", "my data", "data export", "gdpr"], description: "Request a copy of your data"),
        .init(title: "Data Collection", section: .storageData, sectionPath: "Storage & Data → Data Collection", keywords: ["data collection", "privacy data", "what data", "collected", "tracking"], description: "See what data AMEN collects"),

        // Security
        .init(title: "Two-Factor Authentication", section: .security, sectionPath: "Security → 2FA", keywords: ["2fa", "two factor", "two-factor", "authentication", "login security", "totp", "sms verification"], description: "Secure your account with 2FA"),
        .init(title: "Active Sessions", section: .security, sectionPath: "Security → Sessions", keywords: ["sessions", "logged in devices", "active sessions", "devices", "logout devices"], description: "View and manage logged-in devices"),
        .init(title: "Change Password", section: .security, sectionPath: "Security → Password", keywords: ["password", "change password", "update password", "reset password"], description: "Update your account password"),
        .init(title: "Login Alerts", section: .security, sectionPath: "Security → Login Alerts", keywords: ["login alert", "sign in alert", "new device alert", "security alert"], description: "Get alerts for new logins"),

        // Family Safety
        .init(title: "Teen Mode", section: .familySafety, sectionPath: "Family Safety → Teen Mode", keywords: ["teen", "teen mode", "under 18", "minor", "youth"], description: "Enable stricter defaults for teens"),
        .init(title: "Daily Time Limit", section: .familySafety, sectionPath: "Family Safety → Time Limit", keywords: ["time limit", "daily limit", "screen time", "usage limit", "timer"], description: "Set a daily app time limit"),
        .init(title: "Guardian Supervision", section: .familySafety, sectionPath: "Family Safety → Supervision", keywords: ["parent", "guardian", "supervision", "parental controls", "family link"], description: "Set up guardian supervision"),

        // Support
        .init(title: "Help Center", section: .supportTransparency, sectionPath: "Support → Help Center", keywords: ["help", "faq", "support", "questions", "how to"], description: "Browse help articles"),
        .init(title: "Report a Problem", section: .supportTransparency, sectionPath: "Support → Report", keywords: ["report", "bug", "problem", "issue", "feedback", "contact"], description: "Report a bug or problem"),
        .init(title: "Community Guidelines", section: .supportTransparency, sectionPath: "Support → Guidelines", keywords: ["guidelines", "community guidelines", "rules", "policies"], description: "Read AMEN's community guidelines"),
        .init(title: "Privacy Policy", section: .supportTransparency, sectionPath: "Support → Privacy Policy", keywords: ["privacy policy", "privacy", "data policy", "legal"], description: "Read the privacy policy"),
        .init(title: "Terms of Service", section: .supportTransparency, sectionPath: "Support → Terms", keywords: ["terms", "tos", "terms of service", "agreement", "legal"], description: "Read the terms of service"),

        // About
        .init(title: "App Version", section: .about, sectionPath: "About → Version", keywords: ["version", "app version", "build", "update", "whats new"], description: "See current app version and build"),
        .init(title: "Rate AMEN", section: .about, sectionPath: "About → Rate", keywords: ["rate", "review", "app store", "stars", "rating"], description: "Rate AMEN on the App Store"),
    ]

    func search(_ query: String) {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            results = []
            return
        }
        results = searchIndex.filter { item in
            item.title.lowercased().contains(q) ||
            item.description.lowercased().contains(q) ||
            item.sectionPath.lowercased().contains(q) ||
            item.keywords.contains(where: { $0.lowercased().contains(q) }) ||
            item.section.displayName.lowercased().contains(q)
        }
    }
}

// MARK: - Shared Row Components

struct SettingsToggleRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.systemScaled(15, weight: .medium))
                .foregroundStyle(ST.secondary)
                .frame(width: 22, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AMENFont.regular(15))
                    .foregroundStyle(ST.primary)
                if let sub = subtitle {
                    Text(sub)
                        .font(AMENFont.regular(12))
                        .foregroundStyle(ST.tertiary)
                }
            }

            Spacer()

            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .tint(Color(red: 0.20, green: 0.42, blue: 0.98))
                .accessibilityLabel(title)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, subtitle != nil ? 11 : 13)
        .contentShape(Rectangle())
    }
}

struct SettingsNavigationRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var badge: String? = nil
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.systemScaled(15, weight: .medium))
                    .foregroundStyle(ST.secondary)
                    .frame(width: 22, alignment: .center)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AMENFont.regular(15))
                        .foregroundStyle(ST.primary)
                    if let sub = subtitle {
                        Text(sub)
                            .font(AMENFont.regular(12))
                            .foregroundStyle(ST.tertiary)
                    }
                }

                Spacer()

                if let badge = badge {
                    Text(badge)
                        .font(AMENFont.semiBold(11))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color(red: 0.20, green: 0.42, blue: 0.98)))
                        .accessibilityHidden(true)
                }

                Image(systemName: "chevron.right")
                    .font(.systemScaled(11, weight: .medium))
                    .foregroundStyle(ST.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, subtitle != nil ? 11 : 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(STPressStyle())
        .accessibilityLabel(subtitle.map { "\(title), \($0)" } ?? title)
    }
}

struct SettingsDestructiveRow: View {
    let title: String
    var action: () -> Void = {}
    @State private var showConfirm = false

    var body: some View {
        Button {
            showConfirm = true
        } label: {
            HStack {
                Text(title)
                    .font(AMENFont.regular(15))
                    .foregroundStyle(ST.danger)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(STPressStyle())
        .confirmationDialog(title, isPresented: $showConfirm, titleVisibility: .visible) {
            Button(title, role: .destructive) { action() }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct SettingsSectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(AMENFont.semiBold(12))
            .foregroundStyle(ST.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 20)
            .padding(.bottom, 4)
    }
}

// MARK: - Glass Group Container

struct STGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(spacing: 0) { content() }
            .glassCard()
            .clipShape(RoundedRectangle(cornerRadius: ST.radius, style: .continuous))
    }
}

struct STDivider: View {
    var body: some View {
        ST.hairline
            .frame(height: 0.5)
            .padding(.leading, 52)
    }
}

struct STPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.black.opacity(0.04) : Color.clear)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Section Icon

struct SettingsSectionIcon: View {
    let section: AMENSettingsSection
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(section.accentColor)
                .frame(width: 36, height: 36)
            Image(systemName: section.icon)
                .font(.systemScaled(16, weight: .medium))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Section Row

struct SettingsSectionRow: View {
    let section: AMENSettingsSection
    var body: some View {
        HStack(spacing: 14) {
            SettingsSectionIcon(section: section)
            VStack(alignment: .leading, spacing: 2) {
                Text(section.displayName)
                    .font(AMENFont.semiBold(15))
                    .foregroundStyle(ST.primary)
                Text(section.description)
                    .font(AMENFont.regular(12))
                    .foregroundStyle(ST.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.systemScaled(11, weight: .medium))
                .foregroundStyle(ST.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

// MARK: - Search Results View

struct SettingsSearchResultsView: View {
    let results: [SettingsSearchService.SettingsSearchResult]
    var onSelect: (AMENSettingsSection) -> Void

    var body: some View {
        if results.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.systemScaled(32, weight: .light))
                    .foregroundStyle(ST.tertiary)
                Text("No settings found")
                    .font(AMENFont.semiBold(16))
                    .foregroundStyle(ST.secondary)
                Text("Try a different keyword")
                    .font(AMENFont.regular(13))
                    .foregroundStyle(ST.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
        } else {
            STGroup {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                    Button { onSelect(result.section) } label: {
                        HStack(spacing: 14) {
                            SettingsSectionIcon(section: result.section)
                                .scaleEffect(0.8)
                                .frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.title)
                                    .font(AMENFont.semiBold(14))
                                    .foregroundStyle(ST.primary)
                                Text(result.sectionPath)
                                    .font(AMENFont.regular(11))
                                    .foregroundStyle(ST.secondary)
                                Text(result.description)
                                    .font(AMENFont.regular(12))
                                    .foregroundStyle(ST.tertiary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.systemScaled(10, weight: .medium))
                                .foregroundStyle(ST.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(STPressStyle())
                    if index < results.count - 1 { STDivider() }
                }
            }
        }
    }
}

// MARK: - Suggested Card

struct SettingsSuggestedCard: View {
    @Binding var isDismissed: Bool
    var onAction: (AMENSettingsSection) -> Void

    private let suggestions: [(String, String, AMENSettingsSection)] = [
        ("lock.fill", "Turn on private profile", .privacy),
        ("message.badge.filled.fill", "Review message request permissions", .messages),
        ("hand.raised.fill", "Enable stricter hidden words", .safety),
    ]

    var body: some View {
        if !isDismissed {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Suggested for you")
                        .font(AMENFont.semiBold(13))
                        .foregroundStyle(ST.primary)
                    Spacer()
                    Button {
                        withAnimation(ST.spring) { isDismissed = true }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.systemScaled(12, weight: .medium))
                            .foregroundStyle(ST.tertiary)
                            .padding(6)
                            .background(Circle().fill(Color.black.opacity(0.06)))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

                ForEach(Array(suggestions.enumerated()), id: \.offset) { index, item in
                    Button { onAction(item.2) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.0)
                                .font(.systemScaled(13, weight: .medium))
                                .foregroundStyle(item.2.accentColor)
                                .frame(width: 22, alignment: .center)
                            Text(item.1)
                                .font(AMENFont.regular(14))
                                .foregroundStyle(ST.primary)
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.systemScaled(11, weight: .medium))
                                .foregroundStyle(ST.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(STPressStyle())
                    if index < suggestions.count - 1 {
                        ST.hairline.frame(height: 0.5).padding(.leading, 52)
                    }
                }

                Spacer(minLength: 12)
            }
            .glassCard()
            .clipShape(RoundedRectangle(cornerRadius: ST.radius, style: .continuous))
            .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.97)),
                                    removal: .opacity.combined(with: .scale(scale: 0.95))))
        }
    }
}

// MARK: - Account Type Pill

enum AMENSettingsAccountType: String {
    case personal = "Personal Account"
    case church   = "Church Account"
    case business = "Business Account"

    var icon: String {
        switch self {
        case .personal: return "person.fill"
        case .church:   return "building.columns.fill"
        case .business: return "briefcase.fill"
        }
    }
}

struct AccountTypePill: View {
    let type: AMENSettingsAccountType
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: type.icon)
                    .font(.systemScaled(12, weight: .medium))
                    .foregroundStyle(ST.secondary)
                Text(type.rawValue)
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(ST.primary)
                Image(systemName: "chevron.right")
                    .font(.systemScaled(10, weight: .medium))
                    .foregroundStyle(ST.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(ST.glassFill))
                    .overlay(Capsule().strokeBorder(ST.hairline, lineWidth: 0.5))
                    .shadow(color: ST.shadow, radius: 8, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Main Settings View

struct AMENSettingsView: View {
    @StateObject private var searchService = SettingsSearchService()
    @StateObject private var persistenceService = AmenSettingsPersistenceService.shared
    @ObservedObject private var featureFlags = AMENFeatureFlags.shared
    @State private var searchText: String = ""
    @AppStorage("amenSettingsSuggestedDismissed") private var isSuggestedDismissed: Bool = false
    @State private var selectedSection: AMENSettingsSection? = nil
    @State private var appeared: Bool = false

    @AppStorage("amen_account_type") private var accountTypeRaw: String = AMENSettingsAccountType.personal.rawValue

    private var accountType: AMENSettingsAccountType {
        AMENSettingsAccountType(rawValue: accountTypeRaw) ?? .personal
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                ST.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Spacer for sticky search bar
                        Color.clear.frame(height: 56)

                        VStack(spacing: 0) {
                            // Account type pill
                            HStack {
                                AccountTypePill(type: accountType) {
                                    selectedSection = .account
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 12)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 10)
                            .animation(ST.spring.delay(0.05), value: appeared)

                            if searchText.isEmpty {
                                mainContent
                            } else {
                                searchContent
                            }
                        }
                    }
                    .padding(.bottom, 40)
                }

                // Sticky search bar
                stickySearchBar
                    .background(
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .overlay(Rectangle().fill(ST.glassFill))
                            .overlay(
                                Rectangle()
                                    .fill(ST.hairline)
                                    .frame(height: 0.5),
                                alignment: .bottom
                            )
                            .ignoresSafeArea(edges: .top)
                    )
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Settings")
                        .font(AMENFont.semiBold(17))
                        .foregroundStyle(ST.primary)
                }
            }
            .navigationDestination(item: $selectedSection) { section in
                sectionDestination(section)
            }
            .task {
                await persistenceService.load()
            }
            .onAppear {
                withAnimation(ST.spring.delay(0.1)) { appeared = true }
            }
            .onDisappear {
                Task { await persistenceService.save(force: false) }
            }
        }
    }

    // MARK: Sticky Search Bar

    private var stickySearchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.systemScaled(14, weight: .medium))
                    .foregroundStyle(ST.tertiary)
                TextField("Search settings...", text: $searchText)
                    .font(AMENFont.regular(15))
                    .foregroundStyle(ST.primary)
                    .onChange(of: searchText) { _, newVal in
                        searchService.search(newVal)
                    }
                if !searchText.isEmpty {
                    Button {
                        withAnimation(ST.spring) { searchText = "" }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.systemScaled(15))
                            .foregroundStyle(ST.tertiary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(ST.glassFill))
                    .overlay(Capsule().strokeBorder(ST.hairline, lineWidth: 0.5))
                    .shadow(color: ST.shadow, radius: 6, x: 0, y: 2)
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: Main Content

    @ViewBuilder
    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Suggested card
            SettingsSuggestedCard(isDismissed: $isSuggestedDismissed) { section in
                selectedSection = section
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .opacity(appeared ? 1 : 0)
            .animation(ST.spring.delay(0.1), value: appeared)

            // Sections list
            let intelligenceGroup: [AMENSettingsSection] = featureFlags.ambientOSEnabled
                ? [.contentPosting, .feedDiscovery, .bereanAI, .sabbathRhythm, .ambientOS, .churchNotes]
                : [.contentPosting, .feedDiscovery, .bereanAI, .sabbathRhythm, .churchNotes]
            let groups: [[AMENSettingsSection]] = [
                [.account, .privacy, .safety, .messages, .notifications],
                intelligenceGroup,
                [.accessibility, .storageData, .security, .familySafety],
                [.supportTransparency, .about],
            ]

            ForEach(Array(groups.enumerated()), id: \.offset) { gIndex, group in
                STGroup {
                    ForEach(Array(group.enumerated()), id: \.element) { index, section in
                        Button { selectedSection = section } label: {
                            SettingsSectionRow(section: section)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(STPressStyle())
                        if index < group.count - 1 { STDivider() }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, gIndex < groups.count - 1 ? 10 : 0)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 14)
                .animation(ST.spring.delay(0.12 + Double(gIndex) * 0.05), value: appeared)
            }
        }
    }

    // MARK: Search Content

    @ViewBuilder
    private var searchContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !searchService.results.isEmpty {
                Text("\(searchService.results.count) result\(searchService.results.count == 1 ? "" : "s")")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(ST.tertiary)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
            }
            SettingsSearchResultsView(results: searchService.results) { section in
                selectedSection = section
                searchText = ""
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
    }

    // MARK: Navigation Destination

    @ViewBuilder
    private func sectionDestination(_ section: AMENSettingsSection) -> some View {
        switch section {
        case .account:             AccountSettingsViewNew()
        case .privacy:             PrivacySettingsViewNew()
        case .safety:              SafetySettingsViewNew()
        case .messages:            MessageSettingsView()
        case .notifications:       NotificationsSettingsViewNew()
        case .contentPosting:      ContentPostingSettingsView()
        case .feedDiscovery:       FeedDiscoverySettingsViewNew()
        case .bereanAI:            BereanAISettingsViewNew()
        case .sabbathRhythm:       SabbathRhythmSettingsFallbackView()
        case .ambientOS:           AmbientOSSurfaceView()
        case .churchNotes:         ChurchNotesSettingsViewNew()
        case .accessibility:       AccessibilitySettingsViewNew()
        case .storageData:         StorageDataSettingsView()
        case .security:            SecuritySettingsViewNew()
        case .familySafety:        FamilySafetySettingsView()
        case .supportTransparency: SupportTransparencySettingsView()
        case .about:               AboutSettingsViewNew()
        }
    }
}

// MARK: - Child View Scaffold

struct STDetailScaffold<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            ST.bg.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 48)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 1. Account Settings

struct AccountSettingsViewNew: View {
    @AppStorage("amen_display_name") private var displayName: String = ""
    @AppStorage("amen_username") private var username: String = ""
    @AppStorage("amen_bio") private var bio: String = ""
    @AppStorage("amen_email") private var email: String = ""
    @AppStorage("amen_phone") private var phone: String = ""
    @State private var showDeactivateConfirm = false
    @State private var showDeleteConfirm = false
    @State private var navigateToFullAccountSettings = false
    @State private var navigateToAccountType = false
    @State private var navigateToLinkedAccounts = false
    @State private var navigateToDeactivation = false
    @State private var navigateToDeleteAccount = false

    var body: some View {
        STDetailScaffold(title: "Account") {
            SettingsSectionHeader(title: "Profile")
            STGroup {
                // Route all profile edits through the full AccountSettingsView which
                // owns the change-name / change-username / change-email / change-bio flows.
                SettingsNavigationRow(icon: "person", title: "Edit Name", subtitle: displayName.isEmpty ? "Not set" : displayName) {
                    navigateToFullAccountSettings = true
                }
                STDivider()
                SettingsNavigationRow(icon: "at", title: "Username", subtitle: username.isEmpty ? "Not set" : "@\(username)") {
                    navigateToFullAccountSettings = true
                }
                STDivider()
                SettingsNavigationRow(icon: "text.alignleft", title: "Bio", subtitle: bio.isEmpty ? "Add a bio" : bio) {
                    navigateToFullAccountSettings = true
                }
            }

            SettingsSectionHeader(title: "Contact")
            STGroup {
                SettingsNavigationRow(icon: "envelope", title: "Email", subtitle: email.isEmpty ? "Not set" : email) {
                    navigateToFullAccountSettings = true
                }
                STDivider()
                SettingsNavigationRow(icon: "phone", title: "Phone", subtitle: phone.isEmpty ? "Not set" : phone) {
                    navigateToFullAccountSettings = true
                }
            }

            SettingsSectionHeader(title: "Account Type")
            STGroup {
                SettingsNavigationRow(icon: "person.crop.circle.badge.checkmark", title: "Account Type", subtitle: "Personal Account", badge: "Manage") {
                    navigateToAccountType = true
                }
                STDivider()
                SettingsNavigationRow(icon: "link", title: "Linked Accounts", subtitle: "Connect other platforms") {
                    navigateToLinkedAccounts = true
                }
            }

            SettingsSectionHeader(title: "Danger Zone")
            STGroup {
                SettingsDestructiveRow(title: "Deactivate Account") { navigateToDeactivation = true }
                STDivider()
                SettingsDestructiveRow(title: "Delete Account") { navigateToDeleteAccount = true }
            }

            Text("Account deletion is permanent and takes effect after 30 days. All your data will be removed.")
                .font(AMENFont.regular(12))
                .foregroundStyle(ST.tertiary)
                .padding(.horizontal, 4)
                .padding(.top, 8)
        }
        .navigationDestination(isPresented: $navigateToFullAccountSettings) {
            AccountSettingsView()
        }
        .navigationDestination(isPresented: $navigateToAccountType) {
            AccountTypeSettingsView()
        }
        .navigationDestination(isPresented: $navigateToLinkedAccounts) {
            AccountLinkingView()
        }
        .navigationDestination(isPresented: $navigateToDeactivation) {
            AccountDeactivationView()
        }
        .navigationDestination(isPresented: $navigateToDeleteAccount) {
            DeleteAccountView()
        }
        .alert("Delete Account", isPresented: $showDeleteConfirm) {
            Button("Delete in 30 days", role: .destructive) {
                Task { await scheduleAccountDeletion() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your account will be scheduled for deletion. You have 30 days to cancel. All data will be permanently removed.")
        }
    }

    private func scheduleAccountDeletion() async {
        guard let user = Auth.auth().currentUser else { return }
        let db = Firestore.firestore()
        let executeAt = Date().addingTimeInterval(30 * 24 * 3600)
        do {
            try await db.collection("deletionRequests").document(user.uid).setData([
                "uid": user.uid,
                "email": user.email ?? "",
                "requestedAt": Timestamp(date: Date()),
                "executeAt": Timestamp(date: executeAt),
                "status": "pending"
            ])
        } catch {
            print("AMENSettingsSystem: failed to schedule account deletion — \(error.localizedDescription)")
        }
        try? Auth.auth().signOut()
    }
}

// MARK: - 2. Privacy Settings

struct PrivacySettingsViewNew: View {
    @AppStorage("amen_private_account")      private var isPrivate: Bool = false
    @AppStorage("amen_show_activity")        private var showActivity: Bool = true
    @AppStorage("amen_show_last_active")     private var showLastActive: Bool = true
    @AppStorage("amen_read_receipts")        private var readReceipts: Bool = true
    @AppStorage("amen_discover_by_phone")    private var discoverByPhone: Bool = true
    @AppStorage("amen_discover_by_email")    private var discoverByEmail: Bool = true
    @AppStorage("amen_show_liked_posts")     private var showLikedPosts: Bool = false
    @AppStorage("amen_show_like_count")      private var showLikeCount: Bool = true

    @State private var commentPerm: String   = "Everyone"
    @State private var mentionPerm: String   = "Everyone"
    @State private var postVisibility: String = "Everyone"

    private let permOptions = ["Everyone", "Followers", "No one"]
    private let visOptions  = ["Everyone", "Followers", "Close friends"]

    var body: some View {
        STDetailScaffold(title: "Privacy") {
            SettingsSectionHeader(title: "Account Visibility")
            STGroup {
                SettingsToggleRow(icon: "lock", title: "Private Account",
                                  subtitle: isPrivate ? "Only approved followers see your posts" : "Anyone can see your posts",
                                  isOn: $isPrivate)
            }

            SettingsSectionHeader(title: "Post Visibility")
            STGroup {
                HStack(spacing: 14) {
                    Image(systemName: "eye")
                        .font(.systemScaled(15, weight: .medium))
                        .foregroundStyle(ST.secondary)
                        .frame(width: 22, alignment: .center)
                    Text("Default Post Audience")
                        .font(AMENFont.regular(15))
                        .foregroundStyle(ST.primary)
                    Spacer()
                    Picker("", selection: $postVisibility) {
                        ForEach(visOptions, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.menu)
                    .font(AMENFont.regular(14))
                    .foregroundStyle(ST.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
            }

            SettingsSectionHeader(title: "Activity Status")
            STGroup {
                SettingsToggleRow(icon: "antenna.radiowaves.left.and.right", title: "Show Online Status", isOn: $showActivity)
                STDivider()
                SettingsToggleRow(icon: "clock", title: "Show Last Active", isOn: $showLastActive)
                STDivider()
                SettingsToggleRow(icon: "checkmark.message", title: "Read Receipts", isOn: $readReceipts)
            }

            SettingsSectionHeader(title: "Discoverability")
            STGroup {
                SettingsToggleRow(icon: "phone", title: "Find by Phone Number", isOn: $discoverByPhone)
                STDivider()
                SettingsToggleRow(icon: "envelope", title: "Find by Email Address", isOn: $discoverByEmail)
            }

            SettingsSectionHeader(title: "Interactions")
            STGroup {
                HStack(spacing: 14) {
                    Image(systemName: "bubble.left")
                        .font(.systemScaled(15, weight: .medium))
                        .foregroundStyle(ST.secondary)
                        .frame(width: 22, alignment: .center)
                    Text("Who can comment")
                        .font(AMENFont.regular(15))
                        .foregroundStyle(ST.primary)
                    Spacer()
                    Picker("", selection: $commentPerm) {
                        ForEach(permOptions, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.menu)
                    .foregroundStyle(ST.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 11)

                STDivider()

                HStack(spacing: 14) {
                    Image(systemName: "at")
                        .font(.systemScaled(15, weight: .medium))
                        .foregroundStyle(ST.secondary)
                        .frame(width: 22, alignment: .center)
                    Text("Who can mention me")
                        .font(AMENFont.regular(15))
                        .foregroundStyle(ST.primary)
                    Spacer()
                    Picker("", selection: $mentionPerm) {
                        ForEach(permOptions, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.menu)
                    .foregroundStyle(ST.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
            }

            SettingsSectionHeader(title: "Likes")
            STGroup {
                SettingsToggleRow(icon: "heart", title: "Show posts you liked", subtitle: "Visible to everyone", isOn: $showLikedPosts)
                STDivider()
                SettingsToggleRow(icon: "number", title: "Show like counts", subtitle: "Display like counts on your posts", isOn: $showLikeCount)
            }
        }
    }
}

// MARK: - 3. Safety Settings

struct SafetySettingsViewNew: View {
    @AppStorage("amen_auto_filter")        private var autoFilter: Bool = true
    @AppStorage("amen_stricter_filter")    private var stricterFilter: Bool = false
    @AppStorage("amen_anti_harassment")    private var antiHarassment: Bool = false
    @State private var customWords: [String] = ["hate", "spam"]
    @State private var newWord: String = ""
    @State private var navigateToBlocked = false
    @State private var navigateToMuted = false
    @State private var navigateToAccountStatus = false
    @State private var navigateToCommentLimits = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        STDetailScaffold(title: "Safety") {
            SettingsSectionHeader(title: "Hidden Words")
            STGroup {
                SettingsToggleRow(icon: "line.3.horizontal.decrease.circle", title: "Auto-filter offensive words", isOn: $autoFilter)
                STDivider()
                SettingsToggleRow(icon: "shield.lefthalf.filled", title: "Stricter protection", subtitle: "Filter more categories automatically", isOn: $stricterFilter)
            }

            SettingsSectionHeader(title: "Custom Phrases")
            STGroup {
                ForEach(customWords, id: \.self) { word in
                    HStack {
                        Text(word)
                            .font(AMENFont.regular(15))
                            .foregroundStyle(ST.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        Spacer()
                        Button {
                            customWords.removeAll { $0 == word }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(ST.danger)
                                .padding(.trailing, 16)
                        }
                    }
                    .contentShape(Rectangle())
                    if word != customWords.last { STDivider() }
                }

                STDivider()

                HStack(spacing: 10) {
                    TextField("Add phrase...", text: $newWord)
                        .font(AMENFont.regular(15))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    Button {
                        let trimmed = newWord.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty && !customWords.contains(trimmed) {
                            withAnimation(ST.spring) { customWords.append(trimmed) }
                            newWord = ""
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color(red: 0.20, green: 0.42, blue: 0.98))
                            .padding(.trailing, 16)
                    }
                }
            }

            SettingsSectionHeader(title: "Account Lists")
            STGroup {
                SettingsNavigationRow(icon: "nosign", title: "Blocked Accounts") {
                    navigateToBlocked = true
                }
                STDivider()
                SettingsNavigationRow(icon: "speaker.slash", title: "Muted Accounts") {
                    navigateToMuted = true
                }
                STDivider()
                // Restricted accounts: route to the existing privacy controls screen
                SettingsNavigationRow(icon: "hand.raised", title: "Restricted Accounts") {
                    navigateToMuted = true  // MutedAccountsView covers restricted accounts in v1
                }
            }

            SettingsSectionHeader(title: "Limits")
            STGroup {
                SettingsNavigationRow(icon: "timer", title: "Comment Limits", subtitle: "Temporarily limit comments during pile-ons") {
                    navigateToCommentLimits = true
                }
                STDivider()
                SettingsToggleRow(icon: "shield.checkered", title: "Anti-Harassment Mode", subtitle: "Stricter incoming filter", isOn: $antiHarassment)
            }

            SettingsSectionHeader(title: "Transparency")
            STGroup {
                SettingsNavigationRow(icon: "doc.text.magnifyingglass", title: "Account Status", subtitle: "Enforcement & warning center") {
                    navigateToAccountStatus = true
                }
                STDivider()
                // Report history: reuse the full safety settings view that has report context
                SettingsNavigationRow(icon: "list.bullet.clipboard", title: "Report History", subtitle: "Your past reports and resolutions") {
                    navigateToAccountStatus = true
                }
            }

            // Always-visible crisis row — opens 988 Suicide & Crisis Lifeline
            STGroup {
                SettingsNavigationRow(icon: "cross.circle.fill", title: "Crisis Resources", subtitle: "Wellness and mental health resources", badge: "Always On") {
                    if let url = URL(string: "https://988lifeline.org") { openURL(url) }
                }
            }
            .padding(.top, 8)
        }
        .navigationDestination(isPresented: $navigateToBlocked) {
            SafetySettingsView()
        }
        .navigationDestination(isPresented: $navigateToMuted) {
            MutedAccountsView()
        }
        .navigationDestination(isPresented: $navigateToAccountStatus) {
            AccountStatusView()
        }
        .navigationDestination(isPresented: $navigateToCommentLimits) {
            DefaultPostSettingsView()
        }
    }
}

// MARK: - 4. Messages Settings

struct MessagesSettingsViewNew: View {
    @AppStorage("amen_dm_permission")      private var dmPerm: String = "Everyone"
    @AppStorage("amen_msg_requests")       private var msgRequests: String = "Filtered"
    @AppStorage("amen_online_in_dms")      private var onlineInDMs: Bool = true
    @AppStorage("amen_dm_read_receipts")   private var dmReadReceipts: Bool = true
    @AppStorage("amen_typing_indicator")   private var typingIndicator: Bool = true
    @AppStorage("amen_media_preview")      private var mediaPreview: Bool = true
    @AppStorage("amen_link_preview")       private var linkPreview: Bool = true
    @AppStorage("amen_dm_curfew_enabled")  private var curfewEnabled: Bool = false
    @AppStorage("amen_dm_curfew_start_hour") private var curfewStartHour: Int = 22
    @AppStorage("amen_dm_curfew_end_hour") private var curfewEndHour: Int = 7

    private let dmOptions      = ["Everyone", "Followers", "Nobody"]
    private let reqOptions     = ["Filtered", "Off"]

    var body: some View {
        STDetailScaffold(title: "Messages") {
            SettingsSectionHeader(title: "DM Permissions")
            STGroup {
                HStack(spacing: 14) {
                    Image(systemName: "message")
                        .font(.systemScaled(15, weight: .medium))
                        .foregroundStyle(ST.secondary)
                        .frame(width: 22, alignment: .center)
                    Text("Who can DM me")
                        .font(AMENFont.regular(15))
                        .foregroundStyle(ST.primary)
                    Spacer()
                    Picker("", selection: $dmPerm) {
                        ForEach(dmOptions, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.menu)
                    .foregroundStyle(ST.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 11)

                STDivider()

                HStack(spacing: 14) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.systemScaled(15, weight: .medium))
                        .foregroundStyle(ST.secondary)
                        .frame(width: 22, alignment: .center)
                    Text("Message Requests")
                        .font(AMENFont.regular(15))
                        .foregroundStyle(ST.primary)
                    Spacer()
                    Picker("", selection: $msgRequests) {
                        ForEach(reqOptions, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.menu)
                    .foregroundStyle(ST.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
            }

            SettingsSectionHeader(title: "In-Conversation")
            STGroup {
                SettingsToggleRow(icon: "antenna.radiowaves.left.and.right", title: "Online Status in DMs", isOn: $onlineInDMs)
                STDivider()
                SettingsToggleRow(icon: "checkmark.circle", title: "Read Receipts", isOn: $dmReadReceipts)
                STDivider()
                SettingsToggleRow(icon: "ellipsis.bubble", title: "Typing Indicators", isOn: $typingIndicator)
                STDivider()
                SettingsToggleRow(icon: "photo", title: "Media Auto-Preview", isOn: $mediaPreview)
                STDivider()
                SettingsToggleRow(icon: "link", title: "Link Previews", isOn: $linkPreview)
            }

            SettingsSectionHeader(title: "Berean Accountability")
            STGroup {
                SettingsToggleRow(icon: "moon.zzz", title: "DM Curfew", subtitle: curfewEnabled ? "DMs restricted during set hours" : "No restriction", isOn: $curfewEnabled)

                if curfewEnabled {
                    STDivider()
                    HStack(spacing: 14) {
                        Image(systemName: "clock")
                            .font(.systemScaled(15, weight: .medium))
                            .foregroundStyle(ST.secondary)
                            .frame(width: 22, alignment: .center)
                        Text("Restrict from")
                            .font(AMENFont.regular(15))
                            .foregroundStyle(ST.primary)
                        Spacer()
                        DatePicker(
                            "DM curfew start",
                            selection: Binding(
                                get: { settingsHourDate(curfewStartHour) },
                                set: { curfewStartHour = settingsHour(from: $0) }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)

                    STDivider()
                    HStack(spacing: 14) {
                        Image(systemName: "clock.fill")
                            .font(.systemScaled(15, weight: .medium))
                            .foregroundStyle(ST.secondary)
                            .frame(width: 22, alignment: .center)
                        Text("Until")
                            .font(AMENFont.regular(15))
                            .foregroundStyle(ST.primary)
                        Spacer()
                        DatePicker(
                            "DM curfew end",
                            selection: Binding(
                                get: { settingsHourDate(curfewEndHour) },
                                set: { curfewEndHour = settingsHour(from: $0) }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                }
            }
            .animation(ST.spring, value: curfewEnabled)
        }
    }
}

// MARK: - 5. Notifications Settings

struct NotificationsSettingsViewNew: View {
    @AppStorage("amen_notif_likes")           private var likes: Bool = true
    @AppStorage("amen_notif_comments")        private var comments: Bool = true
    @AppStorage("amen_notif_replies")         private var replies: Bool = true
    @AppStorage("amen_notif_followers")       private var followers: Bool = true
    @AppStorage("amen_notif_follow_requests") private var followRequests: Bool = true
    @AppStorage("amen_notif_mentions")        private var mentions: Bool = true
    @AppStorage("amen_notif_tags")            private var tags: Bool = true
    @AppStorage("amen_notif_reposts")         private var reposts: Bool = true

    @AppStorage("amen_notif_prayer")          private var prayer: Bool = true
    @AppStorage("amen_notif_events")          private var events: Bool = true
    @AppStorage("amen_notif_community")       private var community: Bool = true
    @AppStorage("amen_notif_berean")          private var bereanInsights: Bool = false

    @AppStorage("amen_notif_scheduled")       private var scheduled: Bool = true
    @AppStorage("amen_notif_drafts")          private var draftReminders: Bool = false
    @AppStorage("amen_notif_safety")          private var safetyAlerts: Bool = true
    @AppStorage("amen_notif_updates")         private var productUpdates: Bool = false
    @AppStorage("amen_notif_security")        private var securityAlerts: Bool = true

    @AppStorage("amen_notif_digest")          private var digestFreq: String = "Real-time"
    @AppStorage("amen_notif_quiet_start_hour") private var quietStartHour: Int = 22
    @AppStorage("amen_notif_quiet_end_hour") private var quietEndHour: Int = 8
    @AppStorage("amen_notif_quiet_enabled") private var quietEnabled: Bool = false

    private let digestOptions = ["Real-time", "Hourly", "Daily", "Off"]

    var body: some View {
        STDetailScaffold(title: "Notifications") {
            SettingsSectionHeader(title: "Social")
            STGroup {
                SettingsToggleRow(icon: "heart", title: "Reactions & Likes", isOn: $likes)
                STDivider()
                SettingsToggleRow(icon: "bubble.left", title: "Comments", isOn: $comments)
                STDivider()
                SettingsToggleRow(icon: "arrow.turn.down.right", title: "Replies to my comments", isOn: $replies)
                STDivider()
                SettingsToggleRow(icon: "person.badge.plus", title: "New Followers", isOn: $followers)
                STDivider()
                SettingsToggleRow(icon: "person.crop.circle.badge.questionmark", title: "Follow Requests", isOn: $followRequests)
                STDivider()
                SettingsToggleRow(icon: "at", title: "Mentions", isOn: $mentions)
                STDivider()
                SettingsToggleRow(icon: "tag", title: "Tags in posts", isOn: $tags)
                STDivider()
                SettingsToggleRow(icon: "arrow.2.squarepath", title: "Reposts & Quotes", isOn: $reposts)
            }

            SettingsSectionHeader(title: "Community")
            STGroup {
                SettingsToggleRow(icon: "hands.sparkles", title: "Prayer Request Responses", isOn: $prayer)
                STDivider()
                SettingsToggleRow(icon: "calendar", title: "Church Events", isOn: $events)
                STDivider()
                SettingsToggleRow(icon: "person.3", title: "Community Invites", isOn: $community)
                STDivider()
                SettingsToggleRow(icon: "sparkles", title: "Berean AI Insights", isOn: $bereanInsights)
            }

            SettingsSectionHeader(title: "System")
            STGroup {
                SettingsToggleRow(icon: "clock.badge.checkmark", title: "Scheduled Post Reminders", isOn: $scheduled)
                STDivider()
                SettingsToggleRow(icon: "doc.text", title: "Draft Reminders", isOn: $draftReminders)
                STDivider()
                SettingsToggleRow(icon: "exclamationmark.triangle", title: "Safety Alerts", isOn: $safetyAlerts)
                STDivider()
                SettingsToggleRow(icon: "star", title: "Product Updates", isOn: $productUpdates)
                STDivider()
                SettingsToggleRow(icon: "lock.shield", title: "Account Security Alerts", isOn: $securityAlerts)
            }

            SettingsSectionHeader(title: "Delivery")
            STGroup {
                HStack(spacing: 14) {
                    Image(systemName: "tray.2")
                        .font(.systemScaled(15, weight: .medium))
                        .foregroundStyle(ST.secondary)
                        .frame(width: 22, alignment: .center)
                    Text("Digest Frequency")
                        .font(AMENFont.regular(15))
                        .foregroundStyle(ST.primary)
                    Spacer()
                    Picker("", selection: $digestFreq) {
                        ForEach(digestOptions, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.menu)
                    .foregroundStyle(ST.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 11)

                STDivider()
                SettingsToggleRow(icon: "moon.stars", title: "Quiet Hours", subtitle: quietEnabled ? "Active" : "Off", isOn: $quietEnabled)

                if quietEnabled {
                    STDivider()
                    HStack(spacing: 14) {
                        Image(systemName: "clock")
                            .font(.systemScaled(15, weight: .medium))
                            .foregroundStyle(ST.secondary)
                            .frame(width: 22, alignment: .center)
                        Text("Start")
                            .font(AMENFont.regular(15))
                            .foregroundStyle(ST.primary)
                        Spacer()
                        DatePicker(
                            "Quiet hours start",
                            selection: Binding(
                                get: { settingsHourDate(quietStartHour) },
                                set: { quietStartHour = settingsHour(from: $0) }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)

                    STDivider()
                    HStack(spacing: 14) {
                        Image(systemName: "clock.fill")
                            .font(.systemScaled(15, weight: .medium))
                            .foregroundStyle(ST.secondary)
                            .frame(width: 22, alignment: .center)
                        Text("End")
                            .font(AMENFont.regular(15))
                            .foregroundStyle(ST.primary)
                        Spacer()
                        DatePicker(
                            "Quiet hours end",
                            selection: Binding(
                                get: { settingsHourDate(quietEndHour) },
                                set: { quietEndHour = settingsHour(from: $0) }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                }
            }
            .animation(ST.spring, value: quietEnabled)
        }
    }
}

// MARK: - 6. Content & Posting

struct ContentPostingSettingsView: View {
    @AppStorage("amen_default_audience")    private var defaultAudience: String = "Everyone"
    @AppStorage("amen_ai_disclosure")       private var aiDisclosure: Bool = true
    @AppStorage("amen_true_source")         private var trueSource: Bool = false
    @AppStorage("amen_draft_autosave")      private var draftAutosave: Bool = true
    @AppStorage("amen_content_warnings")    private var autoContentWarnings: Bool = true

    private let audienceOptions = ["Everyone", "Followers", "Custom"]

    var body: some View {
        STDetailScaffold(title: "Content & Posting") {
            SettingsSectionHeader(title: "Defaults")
            STGroup {
                HStack(spacing: 14) {
                    Image(systemName: "eye")
                        .font(.systemScaled(15, weight: .medium))
                        .foregroundStyle(ST.secondary)
                        .frame(width: 22, alignment: .center)
                    Text("Default Post Audience")
                        .font(AMENFont.regular(15))
                        .foregroundStyle(ST.primary)
                    Spacer()
                    Picker("", selection: $defaultAudience) {
                        ForEach(audienceOptions, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.menu)
                    .foregroundStyle(ST.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 11)

                STDivider()
                SettingsToggleRow(icon: "doc.badge.gearshape", title: "Draft Auto-save", isOn: $draftAutosave)
            }

            SettingsSectionHeader(title: "Authenticity")
            STGroup {
                SettingsToggleRow(icon: "wand.and.sparkles", title: "AI Content Disclosure", subtitle: "Auto-suggest label when Berean assisted", isOn: $aiDisclosure)
                STDivider()
                SettingsToggleRow(icon: "checkmark.seal", title: "True Source Mode", subtitle: "Stricter attribution for all posts", isOn: $trueSource)
                STDivider()
                SettingsToggleRow(icon: "exclamationmark.triangle", title: "Auto-suggest Content Warnings", subtitle: "For sensitive or mature content", isOn: $autoContentWarnings)
            }

            SettingsSectionHeader(title: "Content Hub")
            STGroup {
                // Scheduled Posts: route to CreateSpace where scheduling lives
                NavigationLink(destination: DefaultPostSettingsView()) {
                    HStack(spacing: 14) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.systemScaled(15, weight: .medium))
                            .foregroundStyle(ST.secondary)
                            .frame(width: 22, alignment: .center)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scheduled Posts")
                                .font(AMENFont.regular(15))
                                .foregroundStyle(ST.primary)
                        }
                        Spacer()
                        Text("Hub")
                            .font(AMENFont.semiBold(11))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color(red: 0.20, green: 0.42, blue: 0.98)))
                        Image(systemName: "chevron.right")
                            .font(.systemScaled(11, weight: .medium))
                            .foregroundStyle(ST.tertiary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(STPressStyle())
                STDivider()
                NavigationLink(destination: DraftsSettingsView()) {
                    HStack(spacing: 14) {
                        Image(systemName: "doc.text")
                            .font(.systemScaled(15, weight: .medium))
                            .foregroundStyle(ST.secondary)
                            .frame(width: 22, alignment: .center)
                        Text("Drafts")
                            .font(AMENFont.regular(15))
                            .foregroundStyle(ST.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.systemScaled(11, weight: .medium))
                            .foregroundStyle(ST.tertiary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(STPressStyle())
                STDivider()
                NavigationLink(destination: PostTemplatesSettingsView()) {
                    HStack(spacing: 14) {
                        Image(systemName: "square.on.square")
                            .font(.systemScaled(15, weight: .medium))
                            .foregroundStyle(ST.secondary)
                            .frame(width: 22, alignment: .center)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Templates")
                                .font(AMENFont.regular(15))
                                .foregroundStyle(ST.primary)
                            Text("Saved post templates")
                                .font(AMENFont.regular(12))
                                .foregroundStyle(ST.tertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.systemScaled(11, weight: .medium))
                            .foregroundStyle(ST.tertiary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(STPressStyle())
            }
        }
    }
}

// MARK: - 7. Feed & Discovery

struct FeedDiscoverySettingsViewNew: View {
    @AppStorage("amen_feed_mode")           private var feedMode: String = "Standard"
    @AppStorage("amen_sensitive_content")   private var sensitiveContent: String = "Standard"
    @AppStorage("amen_autoplay")            private var autoplay: String = "On"
    @AppStorage("amen_show_like_counts")    private var showLikeCounts: Bool = true
    @AppStorage("amen_show_follower_counts") private var showFollowerCounts: Bool = true
    @AppStorage("amen_hide_from_suggestions") private var hideFromSuggestions: Bool = false
    @State private var navigateInterests = false

    @State private var focusModeExpanded: Bool = false
    @State private var selectedFocusMode: String = "None"
    @State private var focusDuration: String = "Until I turn off"

    private let feedModes    = ["Standard", "Nourish", "Low Stimulation", "Comparison Reset", "Sabbath"]
    private let sensitiveOpts = ["Standard", "Limited", "Most Limited"]
    private let autoplayOpts  = ["On", "Off", "WiFi only"]
    private let durationOpts  = ["2 hours", "4 hours", "Today", "Until I turn off"]

    private let focusModes: [(String, String, String)] = [
        ("heart.fill", "Nourish Mode", "More grounding, reflective content"),
        ("waveform", "Low Stimulation", "Fewer high-energy clips"),
        ("arrow.counterclockwise", "Comparison Reset", "Suppress status/wealth content"),
        ("moon.stars.fill", "Sabbath Mode", "Only Church Notes and Resources"),
    ]

    var body: some View {
        STDetailScaffold(title: "Feed & Discovery") {
            SettingsSectionHeader(title: "Feed Mode")
            STGroup {
                HStack(spacing: 14) {
                    Image(systemName: "rectangle.stack")
                        .font(.systemScaled(15, weight: .medium))
                        .foregroundStyle(ST.secondary)
                        .frame(width: 22, alignment: .center)
                    Text("Feed Mode")
                        .font(AMENFont.regular(15))
                        .foregroundStyle(ST.primary)
                    Spacer()
                    Picker("", selection: $feedMode) {
                        ForEach(feedModes, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.menu)
                    .foregroundStyle(ST.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
            }

            // Focus Modes card
            SettingsSectionHeader(title: "Focus Modes")
            VStack(spacing: 0) {
                Button {
                    withAnimation(ST.spring) { focusModeExpanded.toggle() }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "moon.stars")
                            .font(.systemScaled(15, weight: .medium))
                            .foregroundStyle(ST.secondary)
                            .frame(width: 22, alignment: .center)
                        Text("Focus Modes")
                            .font(AMENFont.semiBold(15))
                            .foregroundStyle(ST.primary)
                        Spacer()
                        Image(systemName: focusModeExpanded ? "chevron.up" : "chevron.down")
                            .font(.systemScaled(11, weight: .medium))
                            .foregroundStyle(ST.tertiary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(STPressStyle())

                if focusModeExpanded {
                    STDivider()
                    ForEach(Array(focusModes.enumerated()), id: \.offset) { i, mode in
                        HStack(spacing: 14) {
                            Image(systemName: mode.0)
                                .font(.systemScaled(15, weight: .medium))
                                .foregroundStyle(AMENSettingsSection.feedDiscovery.accentColor)
                                .frame(width: 22, alignment: .center)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.1)
                                    .font(AMENFont.semiBold(14))
                                    .foregroundStyle(ST.primary)
                                Text(mode.2)
                                    .font(AMENFont.regular(12))
                                    .foregroundStyle(ST.secondary)
                            }
                            Spacer()
                            // Radio toggle
                            Circle()
                                .strokeBorder(selectedFocusMode == mode.1 ? AMENSettingsSection.feedDiscovery.accentColor : ST.tertiary, lineWidth: 1.5)
                                .background(
                                    Circle().fill(selectedFocusMode == mode.1 ? AMENSettingsSection.feedDiscovery.accentColor : Color.clear)
                                        .padding(3)
                                )
                                .frame(width: 20, height: 20)
                                .onTapGesture {
                                    withAnimation(ST.spring) {
                                        selectedFocusMode = selectedFocusMode == mode.1 ? "None" : mode.1
                                    }
                                }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 11)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(ST.spring) {
                                selectedFocusMode = selectedFocusMode == mode.1 ? "None" : mode.1
                            }
                        }

                        if i < focusModes.count - 1 { STDivider() }
                    }

                    if selectedFocusMode != "None" {
                        STDivider()
                        HStack(spacing: 14) {
                            Image(systemName: "timer")
                                .font(.systemScaled(15, weight: .medium))
                                .foregroundStyle(ST.secondary)
                                .frame(width: 22, alignment: .center)
                            Text("Duration")
                                .font(AMENFont.regular(15))
                                .foregroundStyle(ST.primary)
                            Spacer()
                            Picker("", selection: $focusDuration) {
                                ForEach(durationOpts, id: \.self) { Text($0) }
                            }
                            .pickerStyle(.menu)
                            .foregroundStyle(ST.secondary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 11)
                    }
                }
            }
            .glassCard()
            .clipShape(RoundedRectangle(cornerRadius: ST.radius, style: .continuous))

            SettingsSectionHeader(title: "Content Filters")
            STGroup {
                HStack(spacing: 14) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.systemScaled(15, weight: .medium))
                        .foregroundStyle(ST.secondary)
                        .frame(width: 22, alignment: .center)
                    Text("Sensitive Content")
                        .font(AMENFont.regular(15))
                        .foregroundStyle(ST.primary)
                    Spacer()
                    Picker("", selection: $sensitiveContent) {
                        ForEach(sensitiveOpts, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.menu)
                    .foregroundStyle(ST.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 11)

                STDivider()

                HStack(spacing: 14) {
                    Image(systemName: "play.rectangle")
                        .font(.systemScaled(15, weight: .medium))
                        .foregroundStyle(ST.secondary)
                        .frame(width: 22, alignment: .center)
                    Text("Autoplay Videos")
                        .font(AMENFont.regular(15))
                        .foregroundStyle(ST.primary)
                    Spacer()
                    Picker("", selection: $autoplay) {
                        ForEach(autoplayOpts, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.menu)
                    .foregroundStyle(ST.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
            }

            SettingsSectionHeader(title: "Display")
            STGroup {
                SettingsToggleRow(icon: "heart", title: "Show like counts in feed", isOn: $showLikeCounts)
                STDivider()
                SettingsToggleRow(icon: "person.2", title: "Show follower counts", isOn: $showFollowerCounts)
                STDivider()
                SettingsToggleRow(icon: "eye.slash", title: "Hide from Suggestions", subtitle: "Don't show me in who to follow", isOn: $hideFromSuggestions)
            }

            SettingsSectionHeader(title: "Interests")
            STGroup {
                SettingsNavigationRow(icon: "tag", title: "Interest Preferences", subtitle: "Topics you care about") {
                    navigateInterests = true
                }
            }
        }
        .navigationDestination(isPresented: $navigateInterests) {
            InterestPreferencesSettingsView()
        }
    }
}

// MARK: - 8. Berean AI Settings

struct BereanAISettingsViewNew: View {
    @AppStorage("amen_berean_enabled")      private var bereanEnabled: Bool = false
    @AppStorage("amen_berean_mode")         private var defaultMode: String = "Study"
    @AppStorage("amen_berean_memory")       private var contextMemory: Bool = false
    @AppStorage("amen_berean_transparency") private var aiTransparency: Bool = false
    @AppStorage("amen_berean_data_usage")   private var dataUsage: Bool = false
    @AppStorage("amen_berean_in_feed")      private var bereanInFeed: Bool = false
    @AppStorage("amen_berean_style")        private var responseStyle: String = "Balanced"

    @State private var showClearMemoryConfirm = false

    private let modes   = ["Ask", "Study", "Reflect", "Build", "Pray", "Explore"]
    private let styles  = ["Concise", "Balanced", "Detailed"]

    var body: some View {
        STDetailScaffold(title: "Berean AI") {
            STGroup {
                SettingsToggleRow(icon: "sparkles", title: "Berean AI", subtitle: bereanEnabled ? "AI assistant active" : "Disabled", isOn: $bereanEnabled)
            }

            if bereanEnabled {
                SettingsSectionHeader(title: "Defaults")
                STGroup {
                    HStack(spacing: 14) {
                        Image(systemName: "dial.low")
                            .font(.systemScaled(15, weight: .medium))
                            .foregroundStyle(ST.secondary)
                            .frame(width: 22, alignment: .center)
                        Text("Default Mode")
                            .font(AMENFont.regular(15))
                            .foregroundStyle(ST.primary)
                        Spacer()
                        Picker("", selection: $defaultMode) {
                            ForEach(modes, id: \.self) { Text($0) }
                        }
                        .pickerStyle(.menu)
                        .foregroundStyle(ST.secondary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 11)

                    STDivider()

                    HStack(spacing: 14) {
                        Image(systemName: "text.alignleft")
                            .font(.systemScaled(15, weight: .medium))
                            .foregroundStyle(ST.secondary)
                            .frame(width: 22, alignment: .center)
                        Text("Response Style")
                            .font(AMENFont.regular(15))
                            .foregroundStyle(ST.primary)
                        Spacer()
                        Picker("", selection: $responseStyle) {
                            ForEach(styles, id: \.self) { Text($0) }
                        }
                        .pickerStyle(.menu)
                        .foregroundStyle(ST.secondary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 11)
                }

                SettingsSectionHeader(title: "Memory & Context")
                STGroup {
                    SettingsToggleRow(icon: "brain", title: "Context Memory", subtitle: "Berean remembers your conversation context", isOn: $contextMemory)
                    if contextMemory {
                        STDivider()
                        Button {
                            showClearMemoryConfirm = true
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                    .font(.systemScaled(15, weight: .medium))
                                    .foregroundStyle(ST.danger)
                                    .frame(width: 22, alignment: .center)
                                    .padding(.leading, 16)
                                Text("Clear Context Memory")
                                    .font(AMENFont.regular(15))
                                    .foregroundStyle(ST.danger)
                                Spacer()
                            }
                            .padding(.vertical, 13)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(STPressStyle())
                    }
                }
                .animation(ST.spring, value: contextMemory)

                SettingsSectionHeader(title: "Transparency & Data")
                STGroup {
                    SettingsToggleRow(icon: "tag", title: "AI Transparency Labels", subtitle: "Show when Berean assisted a post", isOn: $aiTransparency)
                    STDivider()
                    SettingsToggleRow(icon: "chart.bar", title: "Data Usage for AI", subtitle: "Allow your content to improve Berean", isOn: $dataUsage)
                    STDivider()
                    SettingsToggleRow(icon: "rectangle.stack", title: "Berean Insights in Feed", subtitle: "Show AI insights inline in feed", isOn: $bereanInFeed)
                }
            }
        }
        .animation(ST.spring, value: bereanEnabled)
        .alert("Clear Context Memory", isPresented: $showClearMemoryConfirm) {
            Button("Clear Memory", role: .destructive) {
                clearBereanContextMemory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Berean will no longer remember previous conversations. This cannot be undone.")
        }
    }

    private func clearBereanContextMemory() {
        contextMemory = false
        let keys = ["amen_berean_context_data", "amen_berean_conversation_history", "amen_berean_last_session"]
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        Task {
            do {
                try await db.collection("users").document(uid).collection("bereanContext").document("memory").delete()
            } catch {
                print("AMENSettingsSystem: failed to delete Berean context memory — \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Sabbath Rhythm Settings Fallback

struct SabbathRhythmSettingsFallbackView: View {
    @ObservedObject private var featureFlags = AMENFeatureFlags.shared

    var body: some View {
        STDetailScaffold(title: "Sabbath Rhythm") {
            SettingsSectionHeader(title: "Feature Gates")
            STGroup {
                statusRow(
                    icon: "moon.stars",
                    title: "Sabbath Mode",
                    subtitle: "Master Remote Config gate",
                    isEnabled: featureFlags.sabbathModeEnabled
                )
                STDivider()
                statusRow(
                    icon: "hand.tap",
                    title: "Manual Rest Trigger",
                    subtitle: "Entry ritual from eligible surfaces",
                    isEnabled: featureFlags.sabbathTriggerManualEnabled
                )
                STDivider()
                statusRow(
                    icon: "calendar.badge.clock",
                    title: "Scheduled Rest Trigger",
                    subtitle: "Local-only schedule trigger",
                    isEnabled: featureFlags.sabbathTriggerScheduleEnabled
                )
            }

            SettingsSectionHeader(title: "Wave 0 Status")
            STGroup {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sabbath Rhythm is prepared behind Remote Config.")
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(ST.primary)
                    Text("The full rhythm controls live with the Sabbath Mode module. This settings route stays searchable and safe until that module is target-visible from Settings.")
                        .font(AMENFont.regular(13))
                        .foregroundStyle(ST.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
            }
        }
    }

    private func statusRow(icon: String, title: String, subtitle: String, isEnabled: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.systemScaled(15, weight: .medium))
                .foregroundStyle(ST.secondary)
                .frame(width: 22, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AMENFont.regular(15))
                    .foregroundStyle(ST.primary)
                Text(subtitle)
                    .font(AMENFont.regular(12))
                    .foregroundStyle(ST.tertiary)
            }

            Spacer()

            Text(isEnabled ? "On" : "Off")
                .font(AMENFont.semiBold(12))
                .foregroundStyle(isEnabled ? Color.green : ST.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(isEnabled ? Color.green.opacity(0.12) : Color(.secondarySystemBackground))
                )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

// MARK: - 9. Church Notes Settings

struct ChurchNotesSettingsViewNew: View {
    @AppStorage("amen_notes_default_folder")    private var defaultFolder: String = "General"
    @AppStorage("amen_notes_auto_scripture")    private var autoScripture: Bool = true
    @AppStorage("amen_notes_growth_loop")       private var growthLoop: Bool = true
    @AppStorage("amen_notes_sync")              private var syncNotes: Bool = true
    @AppStorage("amen_notes_export_format")     private var exportFormat: String = "PDF"
    @AppStorage("amen_notes_sermon_capture")    private var sermonCapture: Bool = false
    @State private var navigateColorTheme = false

    private let folders = ["General", "Sunday Sermon", "Bible Study", "Devotional", "Personal"]
    private let formats = ["PDF", "Text", "Markdown"]

    var body: some View {
        STDetailScaffold(title: "Church Notes") {
            SettingsSectionHeader(title: "Defaults")
            STGroup {
                HStack(spacing: 14) {
                    Image(systemName: "folder")
                        .font(.systemScaled(15, weight: .medium))
                        .foregroundStyle(ST.secondary)
                        .frame(width: 22, alignment: .center)
                    Text("Default Folder")
                        .font(AMENFont.regular(15))
                        .foregroundStyle(ST.primary)
                    Spacer()
                    Picker("", selection: $defaultFolder) {
                        ForEach(folders, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.menu)
                    .foregroundStyle(ST.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
            }

            SettingsSectionHeader(title: "Intelligence")
            STGroup {
                SettingsToggleRow(icon: "book.closed", title: "Auto-detect Scriptures", subtitle: "Automatically link Bible references", isOn: $autoScripture)
                STDivider()
                SettingsToggleRow(icon: "arrow.clockwise.heart", title: "Growth Loop Reminders", subtitle: "Prompts to revisit and apply notes", isOn: $growthLoop)
                STDivider()
                SettingsToggleRow(icon: "mic", title: "Sermon Auto-capture", subtitle: "Capture notes during live sermons", isOn: $sermonCapture)
            }

            SettingsSectionHeader(title: "Sync & Export")
            STGroup {
                SettingsToggleRow(icon: "icloud", title: "Sync Notes", subtitle: "Keep notes in sync across devices", isOn: $syncNotes)
                STDivider()
                HStack(spacing: 14) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.systemScaled(15, weight: .medium))
                        .foregroundStyle(ST.secondary)
                        .frame(width: 22, alignment: .center)
                    Text("Export Format")
                        .font(AMENFont.regular(15))
                        .foregroundStyle(ST.primary)
                    Spacer()
                    Picker("", selection: $exportFormat) {
                        ForEach(formats, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.menu)
                    .foregroundStyle(ST.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
            }

            SettingsSectionHeader(title: "Appearance")
            STGroup {
                SettingsNavigationRow(icon: "paintpalette", title: "Color Theme Defaults", subtitle: "Default color for new notes") {
                    navigateColorTheme = true
                }
            }
        }
        .navigationDestination(isPresented: $navigateColorTheme) {
            ChurchNotesThemeSettingsView()
        }
    }
}

// MARK: - Simple Mode Inline Settings (used by AccessibilitySettingsViewNew)
//
// Renders the Simple Mode controls as STGroup / SettingsToggleRow rows so they
// sit naturally inside the STDetailScaffold VStack without a nested List.

private struct SimpleModeInlineSettings: View {

    // @Observable binding via @Bindable — no property wrapper on the service itself.
    @State private var service = AmenSimpleModeService.shared

    var body: some View {
        @Bindable var svc = service

        SettingsSectionHeader(title: "Simple Mode")
        STGroup {
            SettingsToggleRow(
                icon: "hand.tap",
                title: "Simple Mode",
                subtitle: "Large buttons and text for easy navigation",
                isOn: $svc.isSimpleModeActive
            )

            if service.isSimpleModeActive {
                STDivider()

                // Font scale picker row
                HStack(spacing: 14) {
                    Image(systemName: "textformat.size")
                        .font(.systemScaled(15, weight: .medium))
                        .foregroundStyle(ST.secondary)
                        .frame(width: 22, alignment: .center)

                    Text("Text Size")
                        .font(AMENFont.regular(15))
                        .foregroundStyle(ST.primary)

                    Spacer()

                    Picker("", selection: $svc.fontScale) {
                        ForEach(AmenSimpleModeService.SimpleFontScale.allCases, id: \.self) { scale in
                            Text(scale.displayName).tag(scale)
                        }
                    }
                    .pickerStyle(.menu)
                    .foregroundStyle(ST.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .accessibilityLabel("Text size for Simple Mode")
                .accessibilityHint("Choose Large or Extra Large text for the Simple Mode home screen.")

                STDivider()

                SettingsToggleRow(
                    icon: "circle.lefthalf.filled",
                    title: "High Contrast",
                    subtitle: "Stronger backgrounds for better readability",
                    isOn: $svc.useHighContrast
                )
            }
        }
    }
}

// MARK: - 10. Accessibility

struct AccessibilitySettingsViewNew: View {
    @AppStorage("amen_reduce_motion")    private var reduceMotion: Bool = false
    @AppStorage("amen_high_contrast")   private var highContrast: Bool = false
    @AppStorage("amen_bold_text")       private var boldText: Bool = false
    @AppStorage("amen_alt_text")        private var altText: Bool = true
    @AppStorage("amen_screen_reader")   private var screenReader: Bool = false
    @State private var navigateDynamicType = false
    @State private var navigateTextSize = false
    @State private var navigateCaptionStyle = false
    @State private var navigateAdaptiveColors = false

    var body: some View {
        STDetailScaffold(title: "Accessibility") {
            // Simple Mode — large-button home for elderly / low-tech-literacy users.
            // Rendered as inline STGroup rows so it lives in the VStack without a
            // nested List (nested List inside ScrollView causes SwiftUI layout conflicts).
            SimpleModeInlineSettings()

            SettingsSectionHeader(title: "Motion & Display")
            STGroup {
                SettingsToggleRow(icon: "figure.walk.motion", title: "Reduce Motion", subtitle: "Reduces spring and morph animations", isOn: $reduceMotion)
                STDivider()
                SettingsToggleRow(icon: "circle.lefthalf.filled", title: "High Contrast Mode", subtitle: "Increase text and UI contrast", isOn: $highContrast)
                STDivider()
                SettingsToggleRow(icon: "bold", title: "Bold Text", subtitle: "Make all text heavier weight", isOn: $boldText)
                STDivider()
                // Adaptive Ambient — opt in/out of letting AMEN take on content colors.
                // Hosted on its own page so the AdaptiveColorsSetting Section/footer
                // renders in a Form (a bare Section's footer won't show in this ScrollView).
                SettingsNavigationRow(icon: "paintpalette", title: "Adaptive Colors", subtitle: "Tint AMEN from photos, profiles & rooms") {
                    navigateAdaptiveColors = true
                }
            }

            SettingsSectionHeader(title: "Text")
            STGroup {
                SettingsNavigationRow(icon: "textformat.size", title: "Dynamic Type", subtitle: "Adjust in iOS Settings") {
                    navigateDynamicType = true
                }
                STDivider()
                SettingsNavigationRow(icon: "textformat.size.larger", title: "Text Size & Display") {
                    navigateTextSize = true
                }
            }

            SettingsSectionHeader(title: "Images & Video")
            STGroup {
                SettingsToggleRow(icon: "photo.badge.plus", title: "Alt Text for Images", subtitle: "Remind or require alt text on uploads", isOn: $altText)
                STDivider()
                SettingsToggleRow(icon: "captions.bubble", title: "Screen Reader Optimizations", subtitle: "Improve VoiceOver experience", isOn: $screenReader)
                STDivider()
                SettingsNavigationRow(icon: "captions.bubble.fill", title: "Caption Style", subtitle: "Customize captions for videos") {
                    navigateCaptionStyle = true
                }
            }
        }
        .navigationDestination(isPresented: $navigateDynamicType) {
            DynamicTypeSettingsView()
        }
        .navigationDestination(isPresented: $navigateTextSize) {
            TextDisplaySettingsView()
        }
        .navigationDestination(isPresented: $navigateCaptionStyle) {
            CaptionStyleSettingsView()
        }
        .navigationDestination(isPresented: $navigateAdaptiveColors) {
            AdaptiveColorsSettingsPage()
        }
    }
}

// Host page for the Adaptive Ambient control. A Form is used so the
// AdaptiveColorsSetting Section renders its explanatory footer correctly.
private struct AdaptiveColorsSettingsPage: View {
    var body: some View {
        Form {
            AdaptiveColorsSetting()
        }
        .navigationTitle("Adaptive Colors")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 11. Storage & Data

struct StorageDataSettingsView: View {
    @AppStorage("amen_download_quality")  private var downloadQuality: String = "Auto"
    @AppStorage("amen_preload_videos")    private var preloadVideos: String = "WiFi only"
    @AppStorage("amen_ai_processing")    private var aiProcessing: Bool = true
    @State private var cacheSize: String = "142 MB"
    @State private var showClearCacheConfirm = false
    @State private var showDownloadDataConfirm = false
    @State private var navigateDataCollection = false
    @State private var navigateDataRetention = false

    private let qualityOpts  = ["Auto", "High", "Low"]
    private let preloadOpts  = ["On", "Off", "WiFi only"]

    var body: some View {
        STDetailScaffold(title: "Storage & Data") {
            SettingsSectionHeader(title: "Cache")
            STGroup {
                HStack(spacing: 14) {
                    Image(systemName: "internaldrive")
                        .font(.systemScaled(15, weight: .medium))
                        .foregroundStyle(ST.secondary)
                        .frame(width: 22, alignment: .center)
                    Text("Cache Size")
                        .font(AMENFont.regular(15))
                        .foregroundStyle(ST.primary)
                    Spacer()
                    Text(cacheSize)
                        .font(AMENFont.regular(14))
                        .foregroundStyle(ST.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 13)

                STDivider()

                Button {
                    showClearCacheConfirm = true
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "trash")
                            .font(.systemScaled(15, weight: .medium))
                            .foregroundStyle(Color(red: 0.20, green: 0.42, blue: 0.98))
                            .frame(width: 22, alignment: .center)
                        Text("Clear Cache")
                            .font(AMENFont.regular(15))
                            .foregroundStyle(Color(red: 0.20, green: 0.42, blue: 0.98))
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(STPressStyle())
            }

            SettingsSectionHeader(title: "Download Quality")
            STGroup {
                HStack(spacing: 14) {
                    Image(systemName: "arrow.down.circle")
                        .font(.systemScaled(15, weight: .medium))
                        .foregroundStyle(ST.secondary)
                        .frame(width: 22, alignment: .center)
                    Text("Download Quality")
                        .font(AMENFont.regular(15))
                        .foregroundStyle(ST.primary)
                    Spacer()
                    Picker("", selection: $downloadQuality) {
                        ForEach(qualityOpts, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.menu)
                    .foregroundStyle(ST.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 11)

                STDivider()

                HStack(spacing: 14) {
                    Image(systemName: "play.rectangle")
                        .font(.systemScaled(15, weight: .medium))
                        .foregroundStyle(ST.secondary)
                        .frame(width: 22, alignment: .center)
                    Text("Pre-load Videos")
                        .font(AMENFont.regular(15))
                        .foregroundStyle(ST.primary)
                    Spacer()
                    Picker("", selection: $preloadVideos) {
                        ForEach(preloadOpts, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.menu)
                    .foregroundStyle(ST.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
            }

            SettingsSectionHeader(title: "Your Data")
            STGroup {
                Button { showDownloadDataConfirm = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.systemScaled(15, weight: .medium))
                            .foregroundStyle(Color(red: 0.20, green: 0.42, blue: 0.98))
                            .frame(width: 22, alignment: .center)
                        Text("Download My Data")
                            .font(AMENFont.regular(15))
                            .foregroundStyle(Color(red: 0.20, green: 0.42, blue: 0.98))
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(STPressStyle())

                STDivider()
                SettingsNavigationRow(icon: "list.bullet.clipboard", title: "Data Collection", subtitle: "What AMEN collects and why") {
                    navigateDataCollection = true
                }
                STDivider()
                SettingsToggleRow(icon: "sparkles", title: "AI Processing", subtitle: "Allow your content to train Berean AI", isOn: $aiProcessing)
                STDivider()
                SettingsNavigationRow(icon: "clock.arrow.circlepath", title: "Account Data Retention", subtitle: "How long your data is kept") {
                    navigateDataRetention = true
                }
            }
        }
        .alert("Clear Cache", isPresented: $showClearCacheConfirm) {
            Button("Clear", role: .destructive) { cacheSize = "0 MB" }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This will free \(cacheSize) of storage. Media will reload on demand.") }
        .alert("Download Your Data", isPresented: $showDownloadDataConfirm) {
            Button("Request Download") {
                Task { await requestDataExport() }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("We'll prepare your data and send a download link to your email within 48 hours.") }
        .navigationDestination(isPresented: $navigateDataCollection) {
            DataCollectionSettingsView()
        }
        .navigationDestination(isPresented: $navigateDataRetention) {
            DataRetentionSettingsView()
        }
    }

    private func requestDataExport() async {
        guard let user = Auth.auth().currentUser else { return }
        let db = Firestore.firestore()
        do {
            try await db.collection("dataExportRequests").document(user.uid).setData([
                "uid": user.uid,
                "email": user.email ?? "",
                "requestedAt": Timestamp(date: Date()),
                "status": "pending"
            ], merge: true)
        } catch {
            print("AMENSettingsSystem: failed to request data export — \(error.localizedDescription)")
        }
    }
}

// MARK: - 12. Security

struct SecuritySettingsViewNew: View {
    @AppStorage("amen_2fa_enabled")      private var twoFA: Bool = false
    @AppStorage("amen_login_alerts")     private var loginAlerts: Bool = true
    @State private var navigate2FAManage = false
    @State private var navigateSessions = false
    @State private var navigateChangePassword = false

    var body: some View {
        STDetailScaffold(title: "Security") {
            STGroup {
                SettingsToggleRow(icon: "lock.shield", title: "Two-Factor Authentication",
                                  subtitle: twoFA ? "Enabled — your account is protected" : "Off — recommended to enable",
                                  isOn: $twoFA)
                if twoFA {
                    STDivider()
                    SettingsNavigationRow(icon: "gearshape", title: "Manage 2FA", subtitle: "Change method or recovery codes") {
                        navigate2FAManage = true
                    }
                }
            }
            .animation(ST.spring, value: twoFA)

            SettingsSectionHeader(title: "Active Sessions")
            STGroup {
                SettingsNavigationRow(icon: "iphone", title: "Manage Sessions", subtitle: "View all logged-in devices") {
                    navigateSessions = true
                }
            }

            SettingsSectionHeader(title: "Alerts")
            STGroup {
                SettingsToggleRow(icon: "bell.badge", title: "Login Alerts", subtitle: "Notify me when a new device logs in", isOn: $loginAlerts)
                STDivider()
                SettingsNavigationRow(icon: "key", title: "Change Password") {
                    navigateChangePassword = true
                }
                STDivider()
                // Trusted Devices: route to Active Sessions where trusted-device management lives
                SettingsNavigationRow(icon: "checkmark.shield", title: "Trusted Devices", subtitle: "Manage trusted devices") {
                    navigateSessions = true
                }
            }

            SettingsSectionHeader(title: "Login History")
            STGroup {
                NavigationLink(destination: LoginHistoryView()) {
                    HStack(spacing: 14) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.systemScaled(15, weight: .medium))
                            .foregroundStyle(ST.secondary)
                            .frame(width: 22, alignment: .center)
                        Text("View Login History")
                            .font(AMENFont.regular(15))
                            .foregroundStyle(ST.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.systemScaled(11, weight: .medium))
                            .foregroundStyle(ST.tertiary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(STPressStyle())
            }
        }
        .navigationDestination(isPresented: $navigate2FAManage) {
            TwoFactorAuthView()
        }
        .navigationDestination(isPresented: $navigateSessions) {
            ActiveSessionsView()
        }
        .navigationDestination(isPresented: $navigateChangePassword) {
            ChangePasswordView()
        }
    }
}

// MARK: - 13. Family Safety

struct FamilySafetySettingsView: View {
    @AppStorage("amen_teen_mode")          private var teenMode: Bool = false
    @AppStorage("amen_time_limit")         private var timeLimit: String = "Off"
    @AppStorage("amen_family_quiet")       private var familyQuiet: Bool = false
    @AppStorage("amen_content_restrict")   private var contentRestrict: Bool = false
    @AppStorage("amen_private_by_default") private var privateByDefault: Bool = true
    @State private var navigateGuardian = false
    @State private var navigateBreaks = false

    private let timeLimits = ["Off", "30 min", "1 hour", "2 hours"]

    var body: some View {
        STDetailScaffold(title: "Family Safety") {
            STGroup {
                SettingsToggleRow(icon: "person.badge.shield.checkmark", title: "Teen Mode",
                                  subtitle: teenMode ? "Stricter defaults active" : "Standard settings",
                                  isOn: $teenMode)
            }

            SettingsSectionHeader(title: "Supervision")
            STGroup {
                // Guardian Supervision: opens iOS Screen Time / Family Sharing link
                SettingsNavigationRow(icon: "person.2.fill", title: "Guardian Supervision", subtitle: "Set up or manage family supervision") {
                    navigateGuardian = true
                }
            }

            SettingsSectionHeader(title: "Time Controls")
            STGroup {
                HStack(spacing: 14) {
                    Image(systemName: "timer")
                        .font(.systemScaled(15, weight: .medium))
                        .foregroundStyle(ST.secondary)
                        .frame(width: 22, alignment: .center)
                    Text("Daily Time Limit")
                        .font(AMENFont.regular(15))
                        .foregroundStyle(ST.primary)
                    Spacer()
                    Picker("", selection: $timeLimit) {
                        ForEach(timeLimits, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.menu)
                    .foregroundStyle(ST.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 11)

                STDivider()
                SettingsNavigationRow(icon: "clock.badge.xmark", title: "Scheduled Breaks", subtitle: "Configure automatic breaks") {
                    navigateBreaks = true
                }
                STDivider()
                SettingsToggleRow(icon: "moon.zzz", title: "Quiet Hours", subtitle: "Restrict use at night", isOn: $familyQuiet)
            }

            SettingsSectionHeader(title: "Content")
            STGroup {
                SettingsToggleRow(icon: "slider.horizontal.below.rectangle", title: "Stricter Content Restrictions", subtitle: "Limit sensitive content categories", isOn: $contentRestrict)
                STDivider()
                SettingsToggleRow(icon: "lock", title: "Private by Default", subtitle: "Always private for minors", isOn: $privateByDefault)
            }
        }
        .navigationDestination(isPresented: $navigateGuardian) {
            GuardianSupervisionSettingsView()
        }
        .navigationDestination(isPresented: $navigateBreaks) {
            TakeABreakSettingsView()
        }
    }
}

// MARK: - 14. Support & Transparency

struct SupportTransparencySettingsView: View {
    @Environment(\.openURL) private var openURL

    private let helpCenterURL = URL(string: "https://amenapp.com/help")

    private func openSupportEmail(subject: String, body: String) {
        let subjectEncoded = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let bodyEncoded = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "mailto:support@amenapp.com?subject=\(subjectEncoded)&body=\(bodyEncoded)") else {
            return
        }
        openURL(url)
    }

    var body: some View {
        STDetailScaffold(title: "Support & Transparency") {
            SettingsSectionHeader(title: "Help")
            STGroup {
                SettingsNavigationRow(icon: "questionmark.circle", title: "Help Center", badge: "Web") {
                    if let url = helpCenterURL { openURL(url) }
                }
                STDivider()
                SettingsNavigationRow(icon: "flag", title: "Report a Problem", subtitle: "Bugs, feedback, abuse") {
                    openSupportEmail(
                        subject: "AMEN App Problem Report",
                        body: "Describe the issue you ran into:\n\nDevice:\niOS Version:\nSteps to reproduce:\n"
                    )
                }
                STDivider()
                Button {
                    openSupportEmail(
                        subject: "AMEN Support Request",
                        body: "How can we help?\n\n"
                    )
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "envelope")
                            .font(.systemScaled(15, weight: .medium))
                            .foregroundStyle(Color(red: 0.20, green: 0.42, blue: 0.98))
                            .frame(width: 22, alignment: .center)
                        Text("Contact Support")
                            .font(AMENFont.regular(15))
                            .foregroundStyle(Color(red: 0.20, green: 0.42, blue: 0.98))
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(STPressStyle())
            }

            SettingsSectionHeader(title: "Account Status")
            STGroup {
                NavigationLink(destination: AccountStatusView()) {
                    HStack(spacing: 14) {
                        Image(systemName: "checkmark.shield")
                            .font(.systemScaled(15, weight: .medium))
                            .foregroundStyle(ST.secondary)
                            .frame(width: 22, alignment: .center)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Account Status")
                                .font(AMENFont.regular(15))
                                .foregroundStyle(ST.primary)
                            Text("Enforcement and warning center")
                                .font(AMENFont.regular(12))
                                .foregroundStyle(ST.tertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.systemScaled(11, weight: .medium))
                            .foregroundStyle(ST.tertiary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(STPressStyle())
                STDivider()
                NavigationLink(destination: AccountRecoveryView()) {
                    HStack(spacing: 14) {
                        Image(systemName: "arrow.uturn.left.circle")
                            .font(.systemScaled(15, weight: .medium))
                            .foregroundStyle(ST.secondary)
                            .frame(width: 22, alignment: .center)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Appeals")
                                .font(AMENFont.regular(15))
                                .foregroundStyle(ST.primary)
                            Text("Any pending appeals")
                                .font(AMENFont.regular(12))
                                .foregroundStyle(ST.tertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.systemScaled(11, weight: .medium))
                            .foregroundStyle(ST.tertiary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(STPressStyle())
            }

            SettingsSectionHeader(title: "Legal & Policies")
            STGroup {
                SettingsNavigationRow(icon: "doc.text", title: "Community Guidelines") {
                    if let url = URL(string: "https://amenapp.com/community-guidelines") { openURL(url) }
                }
                STDivider()
                SettingsNavigationRow(icon: "hand.raised", title: "Privacy Policy") {
                    if let url = URL(string: "https://amenapp.com/privacy") { openURL(url) }
                }
                STDivider()
                SettingsNavigationRow(icon: "doc.plaintext", title: "Terms of Service") {
                    if let url = URL(string: "https://amenapp.com/terms") { openURL(url) }
                }
                STDivider()
                SettingsNavigationRow(icon: "arrow.down.doc", title: "Data & Privacy") {
                    if let url = URL(string: "https://amenapp.com/privacy#data") { openURL(url) }
                }
                STDivider()
                SettingsNavigationRow(icon: "ellipsis.curlybraces", title: "Cookie Preferences") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
    }
}

private struct SettingsPickerRow: View {
    let icon: String
    let title: String
    let subtitle: String?
    @Binding var selection: String
    let options: [String]

    init(icon: String, title: String, subtitle: String? = nil, selection: Binding<String>, options: [String]) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self._selection = selection
        self.options = options
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.systemScaled(15, weight: .medium))
                .foregroundStyle(ST.secondary)
                .frame(width: 22, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AMENFont.regular(15))
                    .foregroundStyle(ST.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(AMENFont.regular(12))
                        .foregroundStyle(ST.tertiary)
                }
            }
            Spacer()
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { Text($0) }
            }
            .pickerStyle(.menu)
            .foregroundStyle(ST.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

struct PostTemplatesSettingsView: View {
    @AppStorage("amen_post_template_signature") private var includeSignature: Bool = true
    @AppStorage("amen_post_template_call_to_action") private var includeCallToAction: Bool = false
    @AppStorage("amen_post_template_include_scripture") private var includeScripture: Bool = true
    @AppStorage("amen_default_audience") private var defaultAudience: String = "Public"

    var body: some View {
        STDetailScaffold(title: "Templates") {
            SettingsSectionHeader(title: "Smart Defaults")
            STGroup {
                SettingsToggleRow(icon: "signature", title: "Include Signature", subtitle: "Prefill your profile signature in long-form posts", isOn: $includeSignature)
                STDivider()
                SettingsToggleRow(icon: "quote.bubble", title: "Include Scripture Context", subtitle: "Offer a verse context field when the post mentions scripture", isOn: $includeScripture)
                STDivider()
                SettingsToggleRow(icon: "arrow.up.message", title: "Suggest Next Step", subtitle: "Add a gentle prayer, RSVP, or follow-up prompt when useful", isOn: $includeCallToAction)
            }

            SettingsSectionHeader(title: "Audience")
            STGroup {
                SettingsPickerRow(icon: "person.2", title: "Template Audience", subtitle: "Default audience for new post templates", selection: $defaultAudience, options: ["Public", "Followers", "Close Friends", "Only Me"])
            }
        }
    }
}

struct InterestPreferencesSettingsView: View {
    @AppStorage("amen_interest_worship") private var worship: Bool = true
    @AppStorage("amen_interest_scripture") private var scripture: Bool = true
    @AppStorage("amen_interest_service") private var service: Bool = true
    @AppStorage("amen_interest_family") private var family: Bool = false
    @AppStorage("amen_interest_wellness") private var wellness: Bool = true
    @AppStorage("amen_interest_local_church") private var localChurch: Bool = true

    var body: some View {
        STDetailScaffold(title: "Interest Preferences") {
            SettingsSectionHeader(title: "Feed Signals")
            STGroup {
                SettingsToggleRow(icon: "music.note", title: "Worship", subtitle: "Songs, setlists, and worship moments", isOn: $worship)
                STDivider()
                SettingsToggleRow(icon: "book", title: "Scripture Study", subtitle: "Verse context and study threads", isOn: $scripture)
                STDivider()
                SettingsToggleRow(icon: "hands.sparkles", title: "Service", subtitle: "Needs, volunteering, and local help", isOn: $service)
                STDivider()
                SettingsToggleRow(icon: "figure.2.and.child.holdinghands", title: "Family", subtitle: "Family discipleship and household rhythms", isOn: $family)
                STDivider()
                SettingsToggleRow(icon: "heart.text.square", title: "Wellness", subtitle: "Gentle mental, spiritual, and rest content", isOn: $wellness)
                STDivider()
                SettingsToggleRow(icon: "building.columns", title: "Local Church", subtitle: "Community updates and gatherings near you", isOn: $localChurch)
            }
        }
    }
}

struct ChurchNotesThemeSettingsView: View {
    @AppStorage("amen_notes_theme") private var theme: String = "Warm White"
    @AppStorage("amen_notes_use_theme_for_exports") private var useThemeForExports: Bool = true

    var body: some View {
        STDetailScaffold(title: "Color Theme Defaults") {
            SettingsSectionHeader(title: "New Notes")
            STGroup {
                SettingsPickerRow(icon: "paintpalette", title: "Default Theme", subtitle: "Applied to new Church Notes", selection: $theme, options: ["Warm White", "Quiet Blue", "Sage", "High Contrast", "Midnight"])
                STDivider()
                SettingsToggleRow(icon: "square.and.arrow.up", title: "Use Theme in Exports", subtitle: "Carry note color into PDF exports", isOn: $useThemeForExports)
            }
        }
    }
}

struct DynamicTypeSettingsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        STDetailScaffold(title: "Dynamic Type") {
            SettingsSectionHeader(title: "System Text Size")
            STGroup {
                HStack(spacing: 14) {
                    Image(systemName: "textformat.size")
                        .font(.systemScaled(15, weight: .medium))
                        .foregroundStyle(ST.secondary)
                        .frame(width: 22, alignment: .center)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Current Size")
                            .font(AMENFont.regular(15))
                            .foregroundStyle(ST.primary)
                        Text(String(describing: dynamicTypeSize).replacingOccurrences(of: "DynamicTypeSize.", with: ""))
                            .font(AMENFont.regular(12))
                            .foregroundStyle(ST.tertiary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
            }
        }
    }
}

struct TextDisplaySettingsView: View {
    @AppStorage("amen_app_text_scale") private var textScale: Double = 1.0
    @AppStorage("amen_bold_text") private var boldText: Bool = false
    @AppStorage("amen_high_contrast") private var highContrast: Bool = false

    var body: some View {
        STDetailScaffold(title: "Text Size & Display") {
            SettingsSectionHeader(title: "App Display")
            STGroup {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("App Text Scale")
                            .font(AMENFont.regular(15))
                            .foregroundStyle(ST.primary)
                        Spacer()
                        Text("\(Int(textScale * 100))%")
                            .font(AMENFont.semiBold(13))
                            .foregroundStyle(ST.secondary)
                    }
                    Slider(value: $textScale, in: 0.85...1.35, step: 0.05)
                    Text("Amen uses this preference for custom surfaces while still honoring iOS Dynamic Type.")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(ST.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                STDivider()
                SettingsToggleRow(icon: "bold", title: "Bold Text", isOn: $boldText)
                STDivider()
                SettingsToggleRow(icon: "circle.lefthalf.filled", title: "Increase Contrast", isOn: $highContrast)
            }
        }
    }
}

struct CaptionStyleSettingsView: View {
    @AppStorage("amen_caption_size") private var captionSize: String = "Standard"
    @AppStorage("amen_caption_background") private var captionBackground: String = "Soft"
    @AppStorage("amen_caption_speaker_names") private var speakerNames: Bool = true

    var body: some View {
        STDetailScaffold(title: "Caption Style") {
            SettingsSectionHeader(title: "Video Captions")
            STGroup {
                SettingsPickerRow(icon: "textformat.size", title: "Caption Size", selection: $captionSize, options: ["Compact", "Standard", "Large", "Extra Large"])
                STDivider()
                SettingsPickerRow(icon: "rectangle.fill", title: "Background", selection: $captionBackground, options: ["None", "Soft", "High Contrast"])
                STDivider()
                SettingsToggleRow(icon: "person.wave.2", title: "Speaker Names", subtitle: "Show names when transcripts identify speakers", isOn: $speakerNames)
            }
        }
    }
}

struct DataCollectionSettingsView: View {
    @AppStorage("amen_data_collection_personalization") private var personalization: Bool = true
    @AppStorage("amen_data_collection_diagnostics") private var diagnostics: Bool = true
    @AppStorage("amen_data_collection_location") private var locationContext: Bool = false

    var body: some View {
        STDetailScaffold(title: "Data Collection") {
            SettingsSectionHeader(title: "Controls")
            STGroup {
                SettingsToggleRow(icon: "sparkles", title: "Personalization Signals", subtitle: "Use saved preferences to make defaults smarter", isOn: $personalization)
                STDivider()
                SettingsToggleRow(icon: "wrench.and.screwdriver", title: "Diagnostics", subtitle: "Share crash and performance data", isOn: $diagnostics)
                STDivider()
                SettingsToggleRow(icon: "location", title: "Location Context", subtitle: "Use approximate context for Sunday, commute, and local church modes", isOn: $locationContext)
            }
        }
    }
}

struct DataRetentionSettingsView: View {
    @AppStorage("amen_data_retention_posts") private var posts: String = "Until deleted"
    @AppStorage("amen_data_retention_search") private var search: String = "30 days"
    @AppStorage("amen_data_retention_ai") private var ai: String = "90 days"

    var body: some View {
        STDetailScaffold(title: "Account Data Retention") {
            SettingsSectionHeader(title: "Retention")
            STGroup {
                SettingsPickerRow(icon: "square.text.square", title: "Posts & Profile", selection: $posts, options: ["Until deleted", "Archive after 1 year", "Private after 1 year"])
                STDivider()
                SettingsPickerRow(icon: "magnifyingglass", title: "Search History", selection: $search, options: ["Off", "7 days", "30 days", "90 days"])
                STDivider()
                SettingsPickerRow(icon: "sparkles", title: "Berean AI Context", selection: $ai, options: ["Off", "30 days", "90 days", "Until cleared"])
            }
        }
    }
}

struct GuardianSupervisionSettingsView: View {
    @AppStorage("amen_guardian_review_required") private var reviewRequired: Bool = false
    @AppStorage("amen_guardian_digest") private var digest: String = "Weekly"
    @AppStorage("amen_guardian_invite_email") private var inviteEmail: String = ""

    @ObservedObject private var flags = AMENFeatureFlags.shared
    @State private var showGuardianLinkFlow = false

    var body: some View {
        STDetailScaffold(title: "Guardian Supervision") {
            SettingsSectionHeader(title: "Family Controls")
            STGroup {
                SettingsToggleRow(icon: "checkmark.shield", title: "Require Guardian Review", subtitle: "Review sensitive follows, DMs, and visibility changes", isOn: $reviewRequired)
                STDivider()
                SettingsPickerRow(icon: "calendar.badge.clock", title: "Guardian Digest", subtitle: "How often to summarize safety events", selection: $digest, options: ["Off", "Daily", "Weekly"])

                // Verified guardian link (finding #44) — real email-verification flow.
                // Gated by guardian_link_enabled; falls back to the legacy email field when OFF.
                if flags.guardianLinkEnabled {
                    STDivider()
                    SettingsNavigationRow(
                        icon: "person.2.badge.gearshape",
                        title: "Link a Guardian",
                        subtitle: "Send a verified invite to a parent or guardian",
                        action: { showGuardianLinkFlow = true }
                    )
                } else {
                    STDivider()
                    HStack(spacing: 14) {
                        Image(systemName: "envelope")
                            .font(.systemScaled(15, weight: .medium))
                            .foregroundStyle(ST.secondary)
                            .frame(width: 22, alignment: .center)
                        TextField("Guardian email", text: $inviteEmail)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .font(AMENFont.regular(15))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                }
            }
        }
        .sheet(isPresented: $showGuardianLinkFlow) {
            GuardianLinkInvitationView()
        }
    }
}

// MARK: - 15. About

struct AboutSettingsViewNew: View {
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    @State private var showShareSheet = false
    @State private var showDebugLogExport = false
    @Environment(\.openURL) private var openURL

    private let changelog: [(String, String)] = [
        ("sparkles", "Berean AI now supports Explore and Build modes"),
        ("shield.lefthalf.filled", "Enhanced safety filters and crisis resources"),
        ("figure.2.and.child.holdinghands", "Family Safety settings now available"),
    ]

    var body: some View {
        STDetailScaffold(title: "About") {
            // Version card
            VStack(spacing: 4) {
                Image(systemName: "a.circle.fill")
                    .font(.systemScaled(44, weight: .light))
                    .foregroundStyle(Color(red: 0.20, green: 0.42, blue: 0.98))
                    .padding(.top, 16)
                Text("AMEN")
                    .font(AMENFont.bold(22))
                    .foregroundStyle(ST.primary)
                Text("Version \(appVersion) (Build \(buildNumber))")
                    .font(AMENFont.regular(13))
                    .foregroundStyle(ST.secondary)
                Text(AMENBuildInfo.displaySummary)
                    .font(AMENFont.regular(11))
                    .foregroundStyle(ST.tertiary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity)
            .glassCard()
            .clipShape(RoundedRectangle(cornerRadius: ST.radius, style: .continuous))
            .padding(.top, 8)

            SettingsSectionHeader(title: "What's New")
            STGroup {
                ForEach(Array(changelog.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 14) {
                        Image(systemName: item.0)
                            .font(.systemScaled(15, weight: .medium))
                            .foregroundStyle(Color(red: 0.20, green: 0.42, blue: 0.98))
                            .frame(width: 22, alignment: .center)
                        Text(item.1)
                            .font(AMENFont.regular(14))
                            .foregroundStyle(ST.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    if index < changelog.count - 1 { STDivider() }
                }
            }

            SettingsSectionHeader(title: "Community")
            STGroup {
                SettingsNavigationRow(icon: "star", title: "Rate AMEN", subtitle: "Share your feedback on the App Store") {
                    if let url = URL(string: "itms-apps://itunes.apple.com/app/id6479380832?action=write-review") {
                        openURL(url)
                    }
                }
                STDivider()
                Button { showShareSheet = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.systemScaled(15, weight: .medium))
                            .foregroundStyle(ST.secondary)
                            .frame(width: 22, alignment: .center)
                        Text("Share AMEN")
                            .font(AMENFont.regular(15))
                            .foregroundStyle(ST.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(STPressStyle())
            }

            // Attribution
            HStack(spacing: 4) {
                Text("Made with")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(ST.tertiary)
                Image(systemName: "heart.fill")
                    .font(.systemScaled(11))
                    .foregroundStyle(ST.danger)
                Text("for the Kingdom")
                    .font(AMENFont.regular(12))
                    .foregroundStyle(ST.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 16)

            // Diagnostics (conceptually dev-only — always compiled, would be gated at runtime)
            SettingsSectionHeader(title: "Diagnostics")
            STGroup {
                SettingsNavigationRow(icon: "ladybug", title: "Export Debug Log", subtitle: "Send logs to engineering") {
                    showDebugLogExport = true
                }
                STDivider()
                HStack(spacing: 14) {
                    Image(systemName: "internaldrive")
                        .font(.systemScaled(15, weight: .medium))
                        .foregroundStyle(ST.secondary)
                        .frame(width: 22, alignment: .center)
                    Text("Cache Info")
                        .font(AMENFont.regular(15))
                        .foregroundStyle(ST.primary)
                    Spacer()
                    Text("142 MB")
                        .font(AMENFont.regular(13))
                        .foregroundStyle(ST.tertiary)
                }
                .padding(.horizontal, 16).padding(.vertical, 13)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            AMENSettingsShareSheet(items: ["Check out AMEN — a faith-centered social app! https://amenapp.io"])
        }
        .alert("Export Debug Log", isPresented: $showDebugLogExport) {
            Button("Send to Engineering") {
                let subject = "AMEN Debug Log — v\(appVersion) (\(buildNumber))"
                    .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                if let url = URL(string: "mailto:engineering@amenapp.com?subject=\(subject)") {
                    openURL(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will open Mail to send a support log to the AMEN engineering team.")
        }
    }
}

// MARK: - ShareSheet wrapper

private struct AMENSettingsShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

struct AMENSettingsSystem_Previews: PreviewProvider {
    static var previews: some View {
        AMENSettingsView()
            .previewDisplayName("Settings Root")

        AccountSettingsViewNew()
            .previewDisplayName("Account")

        PrivacySettingsViewNew()
            .previewDisplayName("Privacy")

        SafetySettingsViewNew()
            .previewDisplayName("Safety")

        MessagesSettingsViewNew()
            .previewDisplayName("Messages")

        NotificationsSettingsViewNew()
            .previewDisplayName("Notifications")

        FeedDiscoverySettingsViewNew()
            .previewDisplayName("Feed & Discovery")

        BereanAISettingsViewNew()
            .previewDisplayName("Berean AI")

        SecuritySettingsViewNew()
            .previewDisplayName("Security")

        AboutSettingsViewNew()
            .previewDisplayName("About")
    }
}
