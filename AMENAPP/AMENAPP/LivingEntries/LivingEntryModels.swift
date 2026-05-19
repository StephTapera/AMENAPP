import Foundation
import FirebaseFirestore

enum LivingEntryType: String, Codable, CaseIterable, Sendable {
    case note
    case reminder
    case churchNote
    case sermonInsight
    case prayer
    case followUp
    case reflection
    case task
}

enum LivingEntryIntent: String, Codable, CaseIterable, Sendable {
    case spiritualGrowth
    case churchVisit
    case sermonReflection
    case prayerCare
    case relationship
    case work
    case rest
    case personal
    case unknown
}

enum LivingEntryState: String, Codable, CaseIterable, Sendable {
    case active
    case completed
    case deferred
    case archived
    case needsReflection
    case expired
}

enum LivingEntryTriggerType: String, Codable, CaseIterable, Sendable {
    case time
    case location
    case churchProximity
    case calendar
    case quietMoment
    case afterChurch
    case beforeService
    case userIdle
    case manual
}

enum LivingEntrySourceSurface: String, Codable, CaseIterable, Sendable {
    case churchNotes = "church_notes"
    case findChurch = "find_church"
    case berean
    case home
    case feed
}

enum LivingEntryHelpfulness: String, Codable, CaseIterable, Sendable {
    case helpful
    case mistimed
    case notNeeded = "not_needed"
    case meaningful
}

struct LivingEntryTriggerRule: Codable, Equatable, Hashable, Sendable {
    var type: LivingEntryTriggerType
    var enabled: Bool
    var scheduledAt: Date?
    var locationRadiusMeters: Double?
    var churchId: String?
    var minQuietMinutes: Int?
    var beforeEventMinutes: Int?
    var afterEventMinutes: Int?

    init(
        type: LivingEntryTriggerType,
        enabled: Bool = true,
        scheduledAt: Date? = nil,
        locationRadiusMeters: Double? = nil,
        churchId: String? = nil,
        minQuietMinutes: Int? = nil,
        beforeEventMinutes: Int? = nil,
        afterEventMinutes: Int? = nil
    ) {
        self.type = type
        self.enabled = enabled
        self.scheduledAt = scheduledAt
        self.locationRadiusMeters = locationRadiusMeters
        self.churchId = churchId
        self.minQuietMinutes = minQuietMinutes
        self.beforeEventMinutes = beforeEventMinutes
        self.afterEventMinutes = afterEventMinutes
    }
}

struct LivingEntryContextSnapshot: Codable, Equatable, Hashable, Sendable {
    var localHour: Int
    var dayOfWeek: Int
    var isSunday: Bool
    var isAtChurch: Bool
    var nearbyChurchId: String?
    var recentChurchVisitId: String?
    var quietModeActive: Bool
    var focusModeActive: Bool
    var motionState: String?
    var calendarContext: String?
    var sourceSurface: LivingEntrySourceSurface

    static func current(
        sourceSurface: LivingEntrySourceSurface,
        calendar: Calendar = .current,
        now: Date = Date(),
        isAtChurch: Bool = false,
        nearbyChurchId: String? = nil,
        recentChurchVisitId: String? = nil,
        quietModeActive: Bool = false,
        focusModeActive: Bool = false,
        motionState: String? = nil,
        calendarContext: String? = nil
    ) -> LivingEntryContextSnapshot {
        let localHour = calendar.component(.hour, from: now)
        let dayOfWeek = calendar.component(.weekday, from: now)
        return LivingEntryContextSnapshot(
            localHour: localHour,
            dayOfWeek: dayOfWeek,
            isSunday: dayOfWeek == 1,
            isAtChurch: isAtChurch,
            nearbyChurchId: nearbyChurchId,
            recentChurchVisitId: recentChurchVisitId,
            quietModeActive: quietModeActive,
            focusModeActive: focusModeActive,
            motionState: motionState,
            calendarContext: calendarContext,
            sourceSurface: sourceSurface
        )
    }
}

struct LivingEntry: Identifiable, Codable, Equatable, Sendable {
    @DocumentID var id: String?
    var userId: String
    var type: LivingEntryType
    var intent: LivingEntryIntent
    var state: LivingEntryState
    var title: String
    var body: String
    var churchId: String?
    var churchName: String?
    var sermonTitle: String?
    var scriptureRefs: [String]
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date
    var dueAt: Date?
    var completedAt: Date?
    var deferredUntil: Date?
    var priorityScore: Double
    var gravityScore: Double
    var emotionalWeight: Double
    var regretRisk: Double
    var spiritualWeight: Double
    var lastSurfacedAt: Date?
    var triggerRules: [LivingEntryTriggerRule]
    var contextSnapshot: LivingEntryContextSnapshot
    var aiSummary: String?
    var suggestedNextAction: String?
    var reflectionPrompt: String?
    var reflectionAnswer: String?
    var evolutionVersion: Int

    init(
        id: String? = nil,
        userId: String,
        type: LivingEntryType,
        intent: LivingEntryIntent = .unknown,
        state: LivingEntryState = .active,
        title: String,
        body: String = "",
        churchId: String? = nil,
        churchName: String? = nil,
        sermonTitle: String? = nil,
        scriptureRefs: [String] = [],
        tags: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        dueAt: Date? = nil,
        completedAt: Date? = nil,
        deferredUntil: Date? = nil,
        priorityScore: Double = 0.45,
        gravityScore: Double = 0.45,
        emotionalWeight: Double = 0.3,
        regretRisk: Double = 0.2,
        spiritualWeight: Double = 0.35,
        lastSurfacedAt: Date? = nil,
        triggerRules: [LivingEntryTriggerRule] = [],
        contextSnapshot: LivingEntryContextSnapshot,
        aiSummary: String? = nil,
        suggestedNextAction: String? = nil,
        reflectionPrompt: String? = nil,
        reflectionAnswer: String? = nil,
        evolutionVersion: Int = 1
    ) {
        self.id = id
        self.userId = userId
        self.type = type
        self.intent = intent
        self.state = state
        self.title = title
        self.body = body
        self.churchId = churchId
        self.churchName = churchName
        self.sermonTitle = sermonTitle
        self.scriptureRefs = scriptureRefs
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.dueAt = dueAt
        self.completedAt = completedAt
        self.deferredUntil = deferredUntil
        self.priorityScore = priorityScore
        self.gravityScore = gravityScore
        self.emotionalWeight = emotionalWeight
        self.regretRisk = regretRisk
        self.spiritualWeight = spiritualWeight
        self.lastSurfacedAt = lastSurfacedAt
        self.triggerRules = triggerRules
        self.contextSnapshot = contextSnapshot
        self.aiSummary = aiSummary
        self.suggestedNextAction = suggestedNextAction
        self.reflectionPrompt = reflectionPrompt
        self.reflectionAnswer = reflectionAnswer
        self.evolutionVersion = evolutionVersion
    }

    var stableId: String {
        id ?? "\(userId)-\(title.lowercased())-\(createdAt.timeIntervalSince1970)"
    }

    var previewBody: String {
        body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isChurchRelated: Bool {
        churchId != nil || churchName != nil || type == .churchNote || type == .sermonInsight
    }

    var isDueNow: Bool {
        if let dueAt {
            return dueAt <= Date()
        }
        return false
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case type
        case intent
        case state
        case title
        case body
        case churchId
        case churchName
        case sermonTitle
        case scriptureRefs
        case tags
        case createdAt
        case updatedAt
        case dueAt
        case completedAt
        case deferredUntil
        case priorityScore
        case gravityScore
        case emotionalWeight
        case regretRisk
        case spiritualWeight
        case lastSurfacedAt
        case triggerRules
        case contextSnapshot
        case aiSummary
        case suggestedNextAction
        case reflectionPrompt
        case reflectionAnswer
        case evolutionVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        userId = try container.decodeIfPresent(String.self, forKey: .userId) ?? ""
        type = try container.decodeIfPresent(LivingEntryType.self, forKey: .type) ?? .note
        intent = try container.decodeIfPresent(LivingEntryIntent.self, forKey: .intent) ?? .unknown
        state = try container.decodeIfPresent(LivingEntryState.self, forKey: .state) ?? .active
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        churchId = try container.decodeIfPresent(String.self, forKey: .churchId)
        churchName = try container.decodeIfPresent(String.self, forKey: .churchName)
        sermonTitle = try container.decodeIfPresent(String.self, forKey: .sermonTitle)
        scriptureRefs = try container.decodeIfPresent([String].self, forKey: .scriptureRefs) ?? []
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        dueAt = try container.decodeIfPresent(Date.self, forKey: .dueAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        deferredUntil = try container.decodeIfPresent(Date.self, forKey: .deferredUntil)
        priorityScore = try container.decodeIfPresent(Double.self, forKey: .priorityScore) ?? 0
        gravityScore = try container.decodeIfPresent(Double.self, forKey: .gravityScore) ?? 0
        emotionalWeight = try container.decodeIfPresent(Double.self, forKey: .emotionalWeight) ?? 0.3
        regretRisk = try container.decodeIfPresent(Double.self, forKey: .regretRisk) ?? 0
        spiritualWeight = try container.decodeIfPresent(Double.self, forKey: .spiritualWeight) ?? 0.35
        lastSurfacedAt = try container.decodeIfPresent(Date.self, forKey: .lastSurfacedAt)
        triggerRules = try container.decodeIfPresent([LivingEntryTriggerRule].self, forKey: .triggerRules) ?? []
        contextSnapshot = try container.decodeIfPresent(LivingEntryContextSnapshot.self, forKey: .contextSnapshot)
            ?? .current(sourceSurface: .home)
        aiSummary = try container.decodeIfPresent(String.self, forKey: .aiSummary)
        suggestedNextAction = try container.decodeIfPresent(String.self, forKey: .suggestedNextAction)
        reflectionPrompt = try container.decodeIfPresent(String.self, forKey: .reflectionPrompt)
        reflectionAnswer = try container.decodeIfPresent(String.self, forKey: .reflectionAnswer)
        evolutionVersion = try container.decodeIfPresent(Int.self, forKey: .evolutionVersion) ?? 1
    }
}

struct LivingEntryReflection: Identifiable, Codable, Equatable, Sendable {
    @DocumentID var id: String?
    var entryId: String
    var userId: String
    var answer: String
    var helpfulness: LivingEntryHelpfulness
    var createdAt: Date
    var aiLearningSummary: String?
    var nextTriggerSuggestion: String?
}

struct LivingEntryEvent: Identifiable, Codable, Equatable, Sendable {
    @DocumentID var id: String?
    var entryId: String
    var userId: String
    var eventType: String
    var createdAt: Date
    var metadata: [String: String]
}

enum LivingEntrySection: String, CaseIterable, Identifiable {
    case now
    case today
    case upcoming
    case church
    case prayer
    case needsReflection
    case later

    var id: String { rawValue }

    var title: String {
        switch self {
        case .now: return "Now"
        case .today: return "Today"
        case .upcoming: return "Upcoming"
        case .church: return "Church"
        case .prayer: return "Prayer"
        case .needsReflection: return "Needs Reflection"
        case .later: return "Later"
        }
    }
}
