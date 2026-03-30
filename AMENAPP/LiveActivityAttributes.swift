
//
//  LiveActivityAttributes.swift
//  AMENAPP
//
//  Data types for Dynamic Island / Live Activities.
//  Three use cases: Church Service, Prayer Reminder, Worship Music.
//
//  ═══════════════════════════════════════════════════════════════════════
//  These are stub types that compile without ActivityKit linked.
//  When ActivityKit.framework IS linked to the AMENAPP target, these
//  structs gain `ActivityAttributes` conformance in the Widget Extension
//  target (via LiveActivityViews.swift, which must be in the extension).
//  ═══════════════════════════════════════════════════════════════════════

import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

// MARK: - 1. Church Service

struct ChurchServiceActivityAttributes: Codable, Hashable {
    let churchId: String
    let churchName: String
    let serviceType: String
    let deepLinkURL: URL

    struct ContentState: Codable, Hashable {
        var phase: ServicePhase
        var minutesUntilStart: Int
        var displayTime: String

        enum ServicePhase: String, Codable {
            case upcoming
            case active
            case ending
        }
    }
}

// MARK: - 2. Prayer Reminder

struct PrayerReminderActivityAttributes: Codable, Hashable {
    let prayerId: String
    let authorName: String
    let prayerTitle: String
    let deepLinkURL: URL

    struct ContentState: Codable, Hashable {
        var status: PrayerStatus
        var minutesRemaining: Int
        var amenCount: Int

        enum PrayerStatus: String, Codable {
            case active
            case prayed
            case snoozed
        }
    }
}

// MARK: - 3. Worship Music

struct WorshipMusicActivityAttributes: Codable, Hashable {
    let songTitle: String
    let artist: String
    let albumArtURL: String?
    let appleMusicURL: URL?
    let churchNoteId: String?
    let deepLinkURL: URL

    struct ContentState: Codable, Hashable {
        var isPlaying: Bool
        var elapsedSeconds: Int
        var totalSeconds: Int
    }
}

// MARK: - 4. Reply Assist (Comment / DM / Tone Assist)

/// Privacy-safe attributes for the "Reply Assist" Dynamic Island experience.
///
/// Design principles:
/// - displayName is optional — omitted for privacy if the sender is unknown/blocked.
/// - suggestion strings are pre-moderated server-side before being placed here.
///   They MUST be ≤60 characters each (enforced by SmartReplySuggestionService).
/// - privacyLevel controls whether content may appear on the Lock Screen.
/// - The activity expires after 15 minutes (enforced by LiveActivityManager).
struct ReplyActivityAttributes: Codable, Hashable {

    // MARK: - Reply Type

    enum ReplyType: String, Codable, Hashable {
        case comment    // new comment on user's post or mention
        case dm         // new direct message from allowed sender
        case toneAssist // tone warning triggered on user's outgoing reply
    }

    // MARK: - Privacy Level

    enum PrivacyLevel: String, Codable, Hashable {
        /// Default: show no message content on Lock Screen (only "New message").
        case noPreview
        /// User opted-in via Settings → Show Message Previews.
        case previewAllowed
    }

    // MARK: - Static Attributes (set once at activity creation)

    /// What triggered this activity.
    let replyType: ReplyType
    /// postId for .comment / .toneAssist; conversationId for .dm.
    let entityId: String
    /// commentId (optional) for .comment type.
    let subEntityId: String?
    /// Display name of the actor (commenter, DM sender). Nil if privacy restricted.
    let displayName: String?
    /// ISO-8601 creation timestamp string (Date not Codable-safe across processes).
    let createdAtISO: String
    /// ISO-8601 expiry timestamp (15 minutes after creation).
    let expiresAtISO: String

    // MARK: - Dynamic Content State (updated as suggestions arrive or timeout)

    struct ContentState: Codable, Hashable {
        /// Up to 3 pre-moderated reply suggestions (≤60 chars each).
        /// If empty, fallback chips are shown by the UI.
        var suggestion1: String
        var suggestion2: String
        var suggestion3: String
        /// Whether suggestions have been loaded (false = show loading indicator).
        var suggestionsReady: Bool
        /// Privacy level for this update (mirrors the attribute but allows runtime override).
        var privacyLevel: PrivacyLevel
        /// Short context snippet (only populated when privacyLevel == .previewAllowed, ≤80 chars).
        var contextSnippet: String?

        // MARK: Fallback state (suggestions not available / moderation blocked)

        static let fallback = ContentState(
            suggestion1: "I hear you.",
            suggestion2: "Thanks for sharing.",
            suggestion3: "I'm praying for you.",
            suggestionsReady: true,
            privacyLevel: .noPreview,
            contextSnippet: nil
        )

        static let loading = ContentState(
            suggestion1: "",
            suggestion2: "",
            suggestion3: "",
            suggestionsReady: false,
            privacyLevel: .noPreview,
            contextSnippet: nil
        )
    }

    // MARK: - Helpers

    var createdAt: Date? {
        ISO8601DateFormatter().date(from: createdAtISO)
    }

    var expiresAt: Date? {
        ISO8601DateFormatter().date(from: expiresAtISO)
    }

    var isExpired: Bool {
        guard let exp = expiresAt else { return true }
        return Date() >= exp
    }
}

// MARK: - 5. Berean AI Assistant

enum BereanLiveMode: String, Codable, Hashable {
    case listening
    case thinking
    case speaking
    case verse
    case idle
}

struct BereanDynamicIslandAttributes: Codable, Hashable {
    let sessionID: String
    let sessionName: String

    struct ContentState: Codable, Hashable {
        var mode: BereanLiveMode
        var title: String
        var subtitle: String
        var progress: Double
        var scriptureReference: String?
        var isSpeaking: Bool
        var lastUpdatedLabel: String?
    }
}

extension BereanDynamicIslandAttributes.ContentState {
    static func listening() -> Self {
        .init(mode: .listening, title: "Berean is listening",
              subtitle: "Ask about scripture, prayer, or guidance",
              progress: 0.12, scriptureReference: nil, isSpeaking: false, lastUpdatedLabel: "Live")
    }
    static func thinking(progress: Double = 0.45) -> Self {
        .init(mode: .thinking, title: "Preparing a response",
              subtitle: "Grounding answer with context and scripture",
              progress: progress, scriptureReference: nil, isSpeaking: false, lastUpdatedLabel: "Analyzing")
    }
    static func speaking(reference: String? = nil) -> Self {
        .init(mode: .speaking, title: "Berean is speaking",
              subtitle: "Voice response in progress",
              progress: 0.92, scriptureReference: reference, isSpeaking: true, lastUpdatedLabel: "Now speaking")
    }
    static func verse(_ reference: String) -> Self {
        .init(mode: .verse, title: "Scripture surfaced",
              subtitle: "Reference ready to open in assistant",
              progress: 1.0, scriptureReference: reference, isSpeaking: false, lastUpdatedLabel: "Reference ready")
    }
    static func idle() -> Self {
        .init(mode: .idle, title: "Berean ready", subtitle: "Assistant available",
              progress: 0.0, scriptureReference: nil, isSpeaking: false, lastUpdatedLabel: nil)
    }
}

// MARK: - ActivityAttributes conformances

#if canImport(ActivityKit)
extension ChurchServiceActivityAttributes: ActivityAttributes {}
extension PrayerReminderActivityAttributes: ActivityAttributes {}
extension WorshipMusicActivityAttributes: ActivityAttributes {}
extension ReplyActivityAttributes: ActivityAttributes {}
extension BereanDynamicIslandAttributes: ActivityAttributes {}
#endif

extension ReplyActivityAttributes {
    /// Compact title shown in Dynamic Island pill and Lock Screen.
    var compactTitle: String {
        switch replyType {
        case .comment:    return "New comment"
        case .dm:         return "New message"
        case .toneAssist: return "Tone Assist"
        }
    }

    /// SF Symbol name for the compact Dynamic Island dot.
    var symbolName: String {
        switch replyType {
        case .comment:    return "bubble.left.fill"
        case .dm:         return "paperplane.fill"
        case .toneAssist: return "wand.and.stars"
        }
    }
}
