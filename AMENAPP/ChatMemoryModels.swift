import Foundation

// MARK: - Chat Memory Item Type

enum ChatMemoryItemType: String, Codable, CaseIterable {
    case openLoop           // "I'll send you that article"
    case decision           // "We decided to meet on Friday"
    case promise            // "I promise to pray for you"
    case actionItem         // "Need to follow up with pastor"
    case importantDate      // "Her birthday is March 15"
    case calendarCandidate  // "Let's meet tomorrow at 3pm"
    case sharedVerse        // Scripture reference shared
    case prayerRequest      // "Please pray for my mom"
    case recommendation     // "You should check out that book"
    case milestone          // "Congrats on your new job!"
    case followUp           // "Don't forget to ask about..."

    var icon: String {
        switch self {
        case .openLoop:          return "arrow.triangle.2.circlepath"
        case .decision:          return "checkmark.seal"
        case .promise:           return "hand.raised"
        case .actionItem:        return "checklist"
        case .importantDate:     return "calendar.badge.clock"
        case .calendarCandidate: return "calendar.badge.plus"
        case .sharedVerse:       return "text.book.closed"
        case .prayerRequest:     return "hands.sparkles"
        case .recommendation:    return "star.bubble"
        case .milestone:         return "party.popper"
        case .followUp:          return "bell.badge"
        }
    }

    var label: String {
        switch self {
        case .openLoop:          return "Open Loop"
        case .decision:          return "Decision"
        case .promise:           return "Promise"
        case .actionItem:        return "Action Item"
        case .importantDate:     return "Important Date"
        case .calendarCandidate: return "Calendar"
        case .sharedVerse:       return "Shared Verse"
        case .prayerRequest:     return "Prayer Request"
        case .recommendation:    return "Recommendation"
        case .milestone:         return "Milestone"
        case .followUp:          return "Follow Up"
        }
    }

    var tintColor: String {
        switch self {
        case .openLoop, .followUp:          return "F5A623"
        case .decision:                     return "4CD964"
        case .promise, .prayerRequest:      return "6B48FF"
        case .actionItem:                   return "007AFF"
        case .importantDate, .calendarCandidate: return "FF3B30"
        case .sharedVerse:                  return "8B5CF6"
        case .recommendation:               return "34C759"
        case .milestone:                    return "FF9500"
        }
    }
}

// MARK: - Memory Tab

enum ChatMemoryTab: String, CaseIterable, Identifiable {
    case active       = "Active"
    case decisions    = "Decisions"
    case followUps    = "Follow-ups"
    case datesAndPlans = "Dates"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .active:       return "circle.dashed"
        case .decisions:    return "checkmark.seal"
        case .followUps:    return "bell.badge"
        case .datesAndPlans: return "calendar"
        }
    }

    var matchingTypes: [ChatMemoryItemType] {
        switch self {
        case .active:       return [.openLoop, .promise, .actionItem, .prayerRequest, .recommendation]
        case .decisions:    return [.decision, .milestone]
        case .followUps:    return [.followUp, .openLoop]
        case .datesAndPlans: return [.importantDate, .calendarCandidate]
        }
    }
}

// MARK: - Visibility Scope

enum MemoryVisibilityScope: String, Codable {
    case personal   // Only visible to this user
    case shared     // Visible to both participants (explicit opt-in)
    case suggested  // AI-detected, not committed — shown as suggestion
}

// MARK: - Consent State

enum MemoryConsentState: String, Codable {
    case pending    // Not yet acknowledged
    case accepted   // User accepted this memory item
    case dismissed  // User dismissed — don't show again
    case archived   // Resolved / completed
}

// MARK: - Calendar Suggestion State

enum CalendarSuggestionState: String, Codable {
    case none       // Not a calendar-eligible item
    case pending    // Date detected, not yet prompted
    case prompted   // User was shown the calendar prompt
    case added      // Event was created in Calendar
    case dismissed  // User declined calendar add
    case suppressed // Auto-suppressed (past date, etc.)
}

// MARK: - Chat Memory Item

struct ChatMemoryItem: Identifiable, Codable, Equatable {
    let id: String
    let chatId: String
    var sourceMessageIds: [String]
    var type: ChatMemoryItemType
    var title: String
    var summary: String
    var confidence: Double
    var consentState: MemoryConsentState
    var visibility: MemoryVisibilityScope
    var dueDate: Date?
    var calendarState: CalendarSuggestionState
    var calendarEventId: String?
    var participants: [String] // User IDs involved
    var createdAt: Date
    var updatedAt: Date

    static func == (lhs: ChatMemoryItem, rhs: ChatMemoryItem) -> Bool {
        lhs.id == rhs.id && lhs.updatedAt == rhs.updatedAt
    }
}

// MARK: - Chat Memory Settings

struct ChatMemorySettings: Codable {
    var aiSuggestionsEnabled: Bool = true
    var calendarSuggestionsEnabled: Bool = true
    var personalMemoryEnabled: Bool = true
    var sharedMemoryEnabled: Bool = false // Opt-in

    static let `default` = ChatMemorySettings()
}

// MARK: - Chat Memory Suggestion (transient, not persisted)

struct ChatMemorySuggestion: Identifiable, Equatable {
    let id: String
    let type: ChatMemoryItemType
    let title: String
    let summary: String
    let confidence: Double
    let sourceMessageIds: [String]
    let extractedDate: Date?

    init(
        type: ChatMemoryItemType,
        title: String,
        summary: String,
        confidence: Double,
        sourceMessageIds: [String],
        extractedDate: Date? = nil
    ) {
        self.id = UUID().uuidString
        self.type = type
        self.title = title
        self.summary = summary
        self.confidence = confidence
        self.sourceMessageIds = sourceMessageIds
        self.extractedDate = extractedDate
    }

    static func == (lhs: ChatMemorySuggestion, rhs: ChatMemorySuggestion) -> Bool {
        lhs.id == rhs.id
    }
}
