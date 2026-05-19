import Foundation

enum BereanPulseMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case all
    case spiritual
    case founder
    case business
    case work
    case creative
    case wellness
    case church
    case prayer
    case learning
    case relationships
    case openLoops

    var id: String { rawValue }

    var titleKey: String.LocalizationValue {
        switch self {
        case .all: return "All"
        case .spiritual: return "Spiritual"
        case .founder: return "Founder"
        case .business: return "Business"
        case .work: return "Work"
        case .creative: return "Creative"
        case .wellness: return "Wellness"
        case .church: return "Church"
        case .prayer: return "Prayer"
        case .learning: return "Learning"
        case .relationships: return "Relationships"
        case .openLoops: return "Open Loops"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .spiritual: return "book.pages"
        case .founder: return "sparkles.rectangle.stack"
        case .business: return "chart.line.uptrend.xyaxis"
        case .work: return "briefcase"
        case .creative: return "lightbulb"
        case .wellness: return "heart.text.square"
        case .church: return "building.columns"
        case .prayer: return "hands.sparkles"
        case .learning: return "graduationcap"
        case .relationships: return "person.2"
        case .openLoops: return "arrow.triangle.branch"
        }
    }
}

enum BereanPulsePermissionSource: String, Codable, CaseIterable, Identifiable, Hashable {
    case amenActivity
    case bereanChatHistory
    case savedPosts
    case prayerJournal
    case churchActivity
    case location
    case calendar
    case contacts
    case notifications
    case wellnessHealth
    case workProjectContext
    case appUsageBehavior

    var id: String { rawValue }

    var titleKey: String.LocalizationValue {
        switch self {
        case .amenActivity: return "AMEN Activity"
        case .bereanChatHistory: return "Berean Chat History"
        case .savedPosts: return "Saved Posts"
        case .prayerJournal: return "Prayer Journal"
        case .churchActivity: return "Church Activity"
        case .location: return "Location"
        case .calendar: return "Calendar"
        case .contacts: return "Contacts"
        case .notifications: return "Notifications"
        case .wellnessHealth: return "Wellness"
        case .workProjectContext: return "Work Context"
        case .appUsageBehavior: return "App Usage"
        }
    }

    var explanationKey: String.LocalizationValue {
        switch self {
        case .amenActivity:
            return "Used to continue activity you already started in AMEN."
        case .bereanChatHistory:
            return "Used to carry context from prior Berean conversations into helpful follow-up cards."
        case .savedPosts:
            return "Used to continue ideas you intentionally saved."
        case .prayerJournal:
            return "Used only to help continue private prayer reflections you choose to share with Berean Pulse."
        case .churchActivity:
            return "Used to prepare church and community follow-ups based on activity you already took in the app."
        case .location:
            return "Used only to suggest nearby churches, gatherings, and church-related next steps."
        case .calendar:
            return "Used only to help prepare meeting follow-ups and time-aware work prompts."
        case .contacts:
            return "Used only when you ask Berean to draft relationship or outreach follow-ups."
        case .notifications:
            return "Used only if you want proactive morning or follow-up reminders."
        case .wellnessHealth:
            return "Used to surface lightweight wellness check-ins when you allow it."
        case .workProjectContext:
            return "Used to continue work and project threads you want Berean to help manage."
        case .appUsageBehavior:
            return "Used to rank cards based on what has actually been useful to you."
        }
    }

    var requiresSystemPrompt: Bool {
        switch self {
        case .location, .calendar, .contacts, .notifications:
            return true
        case .amenActivity, .bereanChatHistory, .savedPosts, .prayerJournal, .churchActivity, .wellnessHealth, .workProjectContext, .appUsageBehavior:
            return false
        }
    }
}

enum BereanPulsePermissionStatus: String, Codable, CaseIterable {
    case notRequested
    case granted
    case denied
    case limited
    case unavailable
}

enum BereanPulseFeedbackState: String, Codable, CaseIterable {
    case neutral
    case liked
    case disliked
}

enum BereanPulsePrivacyLevel: String, Codable, CaseIterable {
    case low
    case personal
    case sensitive
}

enum BereanPulseSignalSensitivity: String, Codable, CaseIterable {
    case low
    case personal
    case sensitive
}

enum BereanPulsePreferredTone: String, Codable, CaseIterable, Identifiable {
    case direct
    case gentle
    case strategic
    case pastoral
    case tactical
    case reflective

    var id: String { rawValue }
}

enum BereanPulsePreferredLength: String, Codable, CaseIterable, Identifiable {
    case short
    case balanced
    case deep

    var id: String { rawValue }
}

enum BereanPulseEventType: String, Codable, CaseIterable {
    case viewed
    case expanded
    case liked
    case disliked
    case saved
    case shared
    case hidden
    case actionTapped
    case permissionRequested
    case permissionGranted
    case permissionDenied
    case curateOpened
    case sourceSuppressed
    case topicSuppressed
    case modeSuppressed
    case followUpAsked
}

enum BereanPulseActionType: String, Codable, CaseIterable {
    case askBerean
    case startReflection
    case continueChat
    case openPost
    case openSavedPost
    case openChurch
    case openGroup
    case openPrayerJournal
    case createPrayer
    case createPost
    case draftMessage
    case openFindChurch
    case openDiscoverSearch
    case openReadingPlan
    case openProjectBrief
    case openWellnessCheckIn
    case curatePreferences
    case requestPermission
    case shareCard
    case saveCard
    case hideCard
    case openNotifications
    case openMessages
    case openProfile
}

struct BereanPulseSignal: Identifiable, Codable, Hashable {
    let id: String
    let source: BereanPulsePermissionSource
    let sourceRecordId: String
    let title: String
    let summary: String
    let timestamp: Date
    let sensitivity: BereanPulseSignalSensitivity
    let permissionRequired: Bool
    let permissionGranted: Bool
    let permissionStatus: BereanPulsePermissionStatus
    let hashForDeduplication: String
    let isUserVisible: Bool
    let entityType: String?
    let entityId: String?
    let metadata: [String: String]
}

struct BereanPulseAction: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let type: BereanPulseActionType
    let payload: [String: String]
    let requiresPermission: Bool
    let permissionType: BereanPulsePermissionSource?
}

struct BereanPulseCard: Identifiable, Codable, Hashable {
    let id: String
    let userId: String
    let dateKey: String
    let mode: BereanPulseMode
    let secondaryModes: [BereanPulseMode]
    let title: String
    let subtitle: String
    let whyNow: String
    let whyNowEvidence: [String]
    let insight: String
    let expandedBody: String
    let recommendedActionTitle: String
    let actionType: BereanPulseActionType
    let actionPayload: [String: String]
    let primaryIntent: String
    let sourceSignalIds: [String]
    let confidenceScore: Double
    let urgencyScore: Double
    let relevanceScore: Double
    let matchScore: Double
    let sourceSignals: [BereanPulseSignal]
    let permissionRequirements: [BereanPulsePermissionSource]
    let privacyLevel: BereanPulsePrivacyLevel
    let createdAt: Date
    let updatedAt: Date
    let expiresAt: Date?
    var isSaved: Bool
    var isHidden: Bool
    var feedbackState: BereanPulseFeedbackState

    var primaryAction: BereanPulseAction {
        BereanPulseAction(
            id: "\(id)_primary",
            title: recommendedActionTitle,
            type: actionType,
            payload: actionPayload,
            requiresPermission: !permissionRequirements.isEmpty,
            permissionType: permissionRequirements.first
        )
    }

    var primaryActionIsAvailable: Bool {
        switch actionType {
        case .askBerean, .startReflection, .continueChat, .createPrayer, .createPost, .openFindChurch, .openNotifications, .openMessages, .openProfile:
            return true
        case .openDiscoverSearch:
            return actionPayload["prompt"]?.isEmpty == false
        case .openPost, .openSavedPost:
            return actionPayload["postId"]?.isEmpty == false
        case .openChurch:
            return actionPayload["churchId"]?.isEmpty == false
        case .openGroup:
            return actionPayload["groupId"]?.isEmpty == false
        case .openPrayerJournal:
            return actionPayload["entryId"]?.isEmpty == false
        case .draftMessage:
            return actionPayload["conversationId"]?.isEmpty == false
        case .openReadingPlan:
            return actionPayload["planId"]?.isEmpty == false
        case .openProjectBrief:
            return actionPayload["projectId"]?.isEmpty == false
        case .openWellnessCheckIn:
            return actionPayload["checkInId"]?.isEmpty == false
        case .shareCard:
            return true
        case .curatePreferences, .requestPermission, .saveCard, .hideCard:
            return false
        }
    }

    var unavailableActionExplanation: String? {
        guard !primaryActionIsAvailable else { return nil }
        switch actionType {
        case .openPost, .openSavedPost:
            return String(localized: "This card needs a post identifier before it can open the related post.")
        case .openChurch:
            return String(localized: "This card needs a church identifier before it can open the church profile.")
        case .openGroup:
            return String(localized: "This card needs a group identifier before it can open the related group.")
        case .openPrayerJournal:
            return String(localized: "This card needs a reflection entry identifier before it can open the prayer journal.")
        case .draftMessage:
            return String(localized: "This card needs a conversation identifier before it can draft a follow-up.")
        case .openReadingPlan:
            return String(localized: "This card needs a reading plan identifier before it can open the plan.")
        case .openProjectBrief:
            return String(localized: "This card needs a project identifier before it can open the project brief.")
        case .openWellnessCheckIn:
            return String(localized: "This card needs a check-in identifier before it can open the wellness check-in.")
        case .openDiscoverSearch:
            return String(localized: "This card needs a search prompt before it can continue the discovery.")
        case .curatePreferences:
            return String(localized: "Use the Curate control to update Berean Pulse preferences.")
        case .requestPermission:
            return String(localized: "Berean will ask for permission only when a specific action needs that source.")
        case .saveCard:
            return String(localized: "Use the Save chip on this card to save it.")
        case .hideCard:
            return String(localized: "Use the Hide chip on this card to remove it from Pulse.")
        default:
            return String(localized: "This action needs more card context before Berean can run it.")
        }
    }
}

struct BereanPulsePreference: Codable, Hashable {
    var enabled: Bool
    var preferredModes: [BereanPulseMode]
    var suppressedModes: [BereanPulseMode]
    var preferredTone: BereanPulsePreferredTone
    var preferredLength: BereanPulsePreferredLength
    var morningDeliveryEnabled: Bool
    var notificationsEnabled: Bool
    var appContextAccess: Bool
    var calendarAccess: Bool
    var locationAccess: Bool
    var healthAccess: Bool
    var contactsAccess: Bool
    var churchActivityAccess: Bool
    var prayerJournalAccess: Bool
    var savedPostsAccess: Bool
    var workModeEnabled: Bool

    static let `default` = BereanPulsePreference(
        enabled: true,
        preferredModes: [.all, .spiritual, .founder, .work, .creative],
        suppressedModes: [],
        preferredTone: .strategic,
        preferredLength: .balanced,
        morningDeliveryEnabled: false,
        notificationsEnabled: false,
        appContextAccess: true,
        calendarAccess: false,
        locationAccess: false,
        healthAccess: false,
        contactsAccess: false,
        churchActivityAccess: true,
        prayerJournalAccess: false,
        savedPostsAccess: true,
        workModeEnabled: true
    )
}

struct BereanPulseEvent: Identifiable, Codable, Hashable {
    let id: String
    let cardId: String
    let eventType: BereanPulseEventType
    let mode: BereanPulseMode
    let timestamp: Date
    let metadata: [String: String]
}

struct BereanPulseChatContext: Codable, Hashable {
    let sourceCardId: String
    let sourceSignalsSummary: [String]
    let privacyContext: BereanPulsePrivacyLevel

    func promptPrefix() -> String {
        let signalsText = sourceSignalsSummary.isEmpty ? "" : "Signals: \(sourceSignalsSummary.joined(separator: ", ")). "
        return "This conversation continues a Berean Pulse card. \(signalsText)Privacy: \(privacyContext.rawValue)."
    }
}

enum BereanPulseFeedState: Equatable {
    case loading
    case loaded
    case empty
    case limitedPermissions
    case offlineCached
    case error(String)
    case refreshing
    case cardHidden
    case permissionRequired(BereanPulsePermissionSource)
    case permissionDenied(BereanPulsePermissionSource)
}

struct BereanPulsePermissionPromptContext: Identifiable, Equatable {
    let source: BereanPulsePermissionSource
    let title: String
    let explanation: String

    var id: String { source.rawValue }
}

struct BereanPulseDaySnapshot: Codable {
    let cards: [BereanPulseCard]
    let signals: [BereanPulseSignal]
    let preferences: BereanPulsePreference
    let fetchedAt: Date
    let source: BereanPulseSnapshotSource
    let userId: String
    let dateKey: String
}

enum BereanPulseSnapshotSource: String, Codable {
    case live
    case cache
}
