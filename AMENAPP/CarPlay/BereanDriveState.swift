// BereanDriveState.swift
// AMEN — Berean Drive CarPlay
//
// All models, enums, and state types for the Berean Drive CarPlay experience.
// CarPlay entitlement required: com.apple.developer.carplay-audio
// (and optionally com.apple.developer.carplay-communication for message features)
// Gate all CarPlay surfaces behind AMENFeatureFlags.shared.carPlayBereanEnabled.

import Foundation

// MARK: - Drive Mode

enum BereanDriveMode: String, CaseIterable, Codable {
    case home              = "home"
    case prayerRide        = "prayer_ride"
    case bereanVoice       = "berean_voice"
    case scriptureReflect  = "scripture_reflect"
    case sermonAudio       = "sermon_audio"
    case churchNoteRecap   = "church_note_recap"
    case findChurch        = "find_church"
    case messageGroup      = "message_group"

    var displayTitle: String {
        switch self {
        case .home:             return "Berean Drive"
        case .prayerRide:       return "Prayer Ride"
        case .bereanVoice:      return "Ask Berean"
        case .scriptureReflect: return "Scripture Reflection"
        case .sermonAudio:      return "Sermon Audio"
        case .churchNoteRecap:  return "Church Notes Recap"
        case .findChurch:       return "Find a Church"
        case .messageGroup:     return "Small Group Messages"
        }
    }

    var systemImageName: String {
        switch self {
        case .home:             return "house.fill"
        case .prayerRide:       return "hands.sparkles.fill"
        case .bereanVoice:      return "waveform.circle.fill"
        case .scriptureReflect: return "book.closed.fill"
        case .sermonAudio:      return "headphones.circle.fill"
        case .churchNoteRecap:  return "note.text"
        case .findChurch:       return "mappin.circle.fill"
        case .messageGroup:     return "bubble.left.and.bubble.right.fill"
        }
    }
}

// MARK: - Prayer Mode

enum BereanPrayerMode: String, CaseIterable, Codable {
    case calm           = "calm"
    case gratitude      = "gratitude"
    case anxietyStress  = "anxiety_stress"
    case morningCommute = "morning_commute"
    case nightDrive     = "night_drive"
    case beforeChurch   = "before_church"

    var displayTitle: String {
        switch self {
        case .calm:           return "Calm & Peace"
        case .gratitude:      return "Gratitude"
        case .anxietyStress:  return "Anxiety & Stress"
        case .morningCommute: return "Morning Commute"
        case .nightDrive:     return "Night Drive"
        case .beforeChurch:   return "Before Church"
        }
    }

    var prayerPrompt: String {
        switch self {
        case .calm:
            return "A prayer for peace and stillness during your drive."
        case .gratitude:
            return "A prayer of thankfulness for today's blessings."
        case .anxietyStress:
            return "A prayer of comfort and strength for what you're carrying."
        case .morningCommute:
            return "A prayer to start the day with purpose and grace."
        case .nightDrive:
            return "A prayer of reflection and rest as the day ends."
        case .beforeChurch:
            return "A prayer of preparation to receive and give with open hands."
        }
    }
}

// MARK: - Drive Safety State

enum BereanDriveSafetyState: String, Codable {
    case safe        = "safe"
    case blocked     = "blocked"
    case summarized  = "summarized"
    case handoffRequired = "handoff_required"

    var isBlocked: Bool { self == .blocked }
}

// MARK: - Drive Response (from backend)

struct BereanDriveResponse: Codable {
    let spokenText: String
    let displayTitle: String
    let displaySubtitle: String?
    let safetyState: BereanDriveSafetyState
    let handoffRequired: Bool
    let handoffReason: String?
    let sourceRefs: [String]
    let actionButtons: [BereanDriveAction]
    let audioDurationEstimateSeconds: Double?

    // Validates the response is safe for driving output
    var isReadAloudSafe: Bool {
        safetyState != .blocked && !spokenText.isEmpty
    }
}

// MARK: - Drive Action

struct BereanDriveAction: Codable, Identifiable {
    let id: String
    let label: String
    let actionType: BereanDriveActionType
    let payload: String?
}

enum BereanDriveActionType: String, Codable {
    case navigateToChurch  = "navigate_to_church"
    case callChurch        = "call_church"
    case hearServiceTime   = "hear_service_time"
    case saveChurch        = "save_church"
    case shareETA          = "share_eta"
    case continueOnPhone   = "continue_on_phone"
    case replyMessage      = "reply_message"
    case startPrayer       = "start_prayer"
    case continueSession   = "continue_session"
}

// MARK: - Church Result (for Find a Church in CarPlay)

struct BereanDriveChurchResult: Codable, Identifiable {
    let id: String
    let name: String
    let distanceMiles: Double?
    let address: String?
    let phoneNumber: String?
    let nextServiceTime: String?
    let denomination: String?
    let latitude: Double?
    let longitude: Double?
    let amenSpaceId: String?

    var distanceLabel: String {
        guard let d = distanceMiles else { return "" }
        return String(format: "%.1f mi", d)
    }

    var hasNavigation: Bool { latitude != nil && longitude != nil }
}

// MARK: - Message Preview (for Safe Messaging in CarPlay)

struct BereanDriveMessagePreview: Identifiable {
    let id: String
    let senderName: String
    let previewText: String       // already safety-screened display text
    let originalText: String      // raw text, never displayed in CarPlay
    let timestamp: Date
    let conversationId: String
    let isGroupMessage: Bool
    let safetyState: BereanDriveSafetyState
}

// MARK: - Session State

enum BereanDriveSessionPhase: String, Codable {
    case idle       = "idle"
    case active     = "active"
    case paused     = "paused"
    case handingOff = "handing_off"
    case ended      = "ended"
}

struct BereanDriveSession: Codable {
    let sessionId: String
    let userId: String
    let startedAt: Date
    var phase: BereanDriveSessionPhase
    var activeMode: BereanDriveMode
    var activePrayerMode: BereanPrayerMode?
    var continuationContext: BereanDriveContinuationContext?

    static func new(userId: String, mode: BereanDriveMode = .home) -> BereanDriveSession {
        BereanDriveSession(
            sessionId: UUID().uuidString,
            userId: userId,
            startedAt: Date(),
            phase: .active,
            activeMode: mode,
            activePrayerMode: nil,
            continuationContext: nil
        )
    }
}

// MARK: - Continuity / Handoff

struct BereanDriveContinuationContext: Codable {
    let sourceSessionId: String?
    let sourceSurface: BereanDriveContinuationSurface
    let resumePayload: String?
    let createdAt: Date
}

enum BereanDriveContinuationSurface: String, Codable {
    case bereanConversation = "berean_conversation"
    case churchNotes        = "church_notes"
    case sermonAudio        = "sermon_audio"
    case savedChurch        = "saved_church"
    case prayerSession      = "prayer_session"
}

// MARK: - User Preferences (persisted to UserDefaults)

struct BereanDrivePreferences: Codable {
    var defaultMode: BereanDriveMode = .home
    var preferredScriptureTranslation: String = "NIV"
    var prayerStyle: BereanDrivePrayerStyle = .guided
    var churchSearchRadiusMiles: Double = 25
    var allowedSmallGroupContactIds: [String] = []
    var youthSafetyEnabled: Bool = true
    var proactiveSuggestionsEnabled: Bool = false
    var drivingContextEnabled: Bool = true
    var locationPersonalizationEnabled: Bool = true
    var messageReadAloudEnabled: Bool = true
    var churchDiscoveryPersonalizationEnabled: Bool = true

    static let defaultsKey = "BereanDrivePreferences"

    static func load() -> BereanDrivePreferences {
        guard
            let data = UserDefaults.standard.data(forKey: defaultsKey),
            let prefs = try? JSONDecoder().decode(BereanDrivePreferences.self, from: data)
        else { return BereanDrivePreferences() }
        return prefs
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}

enum BereanDrivePrayerStyle: String, Codable, CaseIterable {
    case guided         = "guided"
    case scriptural     = "scriptural"
    case contemplative  = "contemplative"
    case spontaneous    = "spontaneous"

    var displayTitle: String {
        switch self {
        case .guided:         return "Guided"
        case .scriptural:     return "Scriptural"
        case .contemplative:  return "Contemplative"
        case .spontaneous:    return "Spontaneous"
        }
    }
}

// MARK: - CarPlay Availability

enum BereanCarPlayAvailability {
    case available
    case featureFlagDisabled
    case entitlementMissing
    case unavailable(reason: String)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

// MARK: - Driving-Safe Response Limits

enum BereanDriveResponsePolicy {
    static let maxSpokenCharacters = 400        // ~45 seconds at normal TTS rate
    static let minSpokenCharacters = 60         // ~8 seconds minimum
    static let maxDisplayTitleLength = 40
    static let maxDisplaySubtitleLength = 80
    static let maxActionButtons = 3
    static let maxChurchResults = 8
    static let maxMessagePreviews = 5

    static func isSafeForDriving(spokenText: String) -> Bool {
        spokenText.count <= maxSpokenCharacters
    }

    static func truncateForDriving(_ text: String) -> String {
        guard text.count > maxSpokenCharacters else { return text }
        let truncated = String(text.prefix(maxSpokenCharacters))
        guard let lastSentence = truncated.range(of: ".", options: .backwards) else {
            return truncated + "…"
        }
        return String(truncated[...lastSentence.lowerBound])
    }
}

// MARK: - Cloud Function Callable Name Constants
// Canonical callable names for all Berean Drive Cloud Functions.
// Used by BereanDriveSessionService and BereanCarPlayTests.
enum BereanDriveCallableNames {
    static let respond              = "bereanDriveRespond"
    static let summarize            = "bereanDriveSummarize"
    static let prayerSession        = "bereanDrivePrayerSession"
    static let churchSearch         = "bereanDriveChurchSearch"
    static let messageSafetyReview  = "bereanDriveMessageSafetyReview"
}
