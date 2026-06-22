import Foundation
import FirebaseFirestore

// MARK: - Selah Media OS: 4-Mode Shell

/// The four modes of the Selah Media experience.
enum SelahMediaMode: String, CaseIterable, Identifiable {
    case pause    = "Pause"
    case media    = "Media"
    case memory   = "Memory"
    case continue_ = "Continue"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .pause:    return "moon.stars"
        case .media:    return "photo.stack"
        case .memory:   return "brain"
        case .continue_: return "arrow.forward.circle"
        }
    }

    var label: String { rawValue }
}

// MARK: - Intent & Behavioral Signals

enum SelahIntentSignal: String, Codable, CaseIterable {
    case resting
    case seeking
    case creating
    case reflecting
    case connecting
}

enum SelahMeaningCategory: String, Codable, CaseIterable, Identifiable {
    case faith      = "Faith"
    case grace      = "Grace"
    case community  = "Community"
    case identity   = "Identity"
    case mission    = "Mission"
    case worship    = "Worship"
    case rest       = "Rest"
    case nature     = "Nature"
    case family     = "Family"
    case gratitude  = "Gratitude"
    case suffering  = "Suffering"
    case hope       = "Hope"

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .faith:      return "✝️"
        case .grace:      return "🕊️"
        case .community:  return "🤝"
        case .identity:   return "👤"
        case .mission:    return "🌍"
        case .worship:    return "🙌"
        case .rest:       return "🌙"
        case .nature:     return "🌿"
        case .family:     return "❤️"
        case .gratitude:  return "🙏"
        case .suffering:  return "💧"
        case .hope:       return "🌅"
        }
    }
}

// MARK: - Media Items

enum SelahMediaItemType: String, Codable {
    case photo
    case video
    case audio
    case text
}

/// Trust circle visibility tier for a media item.
enum SelahTrustCircleTier: String, Codable {
    case close      = "close"
    case community  = "community"
    case `public`   = "public"
}

struct SelahMeaningTag: Identifiable, Codable, Equatable, Hashable {
    @DocumentID var id: String?
    var category: String        // SelahMeaningCategory rawValue
    var label: String           // free-text label (e.g. "Sunday Gratitude")
    var scriptureRef: String?   // optional anchoring verse
    var confidence: Double      // 0–1, AI-assigned or user-confirmed

    init(
        id: String? = nil,
        category: SelahMeaningCategory,
        label: String,
        scriptureRef: String? = nil,
        confidence: Double = 1.0
    ) {
        self.id = id
        self.category = category.rawValue
        self.label = label
        self.scriptureRef = scriptureRef
        self.confidence = confidence
    }

    var categoryEnum: SelahMeaningCategory {
        SelahMeaningCategory(rawValue: category) ?? .faith
    }
}

struct SelahMediaItem: Identifiable, Codable {
    @DocumentID var id: String?
    var authorId: String
    var type: String                    // SelahMediaItemType rawValue
    var mediaURL: String
    var thumbnailURL: String?
    var caption: String
    var meaningTags: [SelahMeaningTag]
    var scriptureRef: String?
    var trustCircleTier: String         // SelahTrustCircleTier rawValue
    var trustCircleId: String?          // nil = all followers / public
    var commentRoomEnabled: Bool
    var commentRoomMode: String         // SelahCommentRoomMode rawValue
    var likeCount: Int
    var commentCount: Int
    var saveCount: Int
    var createdAt: Date
    var updatedAt: Date

    var itemType: SelahMediaItemType {
        SelahMediaItemType(rawValue: type) ?? .photo
    }

    var tierEnum: SelahTrustCircleTier {
        SelahTrustCircleTier(rawValue: trustCircleTier) ?? .community
    }

    init(
        authorId: String = "",
        type: SelahMediaItemType = .photo,
        mediaURL: String = "",
        thumbnailURL: String? = nil,
        caption: String = "",
        meaningTags: [SelahMeaningTag] = [],
        scriptureRef: String? = nil,
        trustCircleTier: SelahTrustCircleTier = .community,
        trustCircleId: String? = nil,
        commentRoomEnabled: Bool = true,
        commentRoomMode: SelahCommentRoomMode = .open,
        likeCount: Int = 0,
        commentCount: Int = 0,
        saveCount: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.authorId = authorId
        self.type = type.rawValue
        self.mediaURL = mediaURL
        self.thumbnailURL = thumbnailURL
        self.caption = caption
        self.meaningTags = meaningTags
        self.scriptureRef = scriptureRef
        self.trustCircleTier = trustCircleTier.rawValue
        self.trustCircleId = trustCircleId
        self.commentRoomEnabled = commentRoomEnabled
        self.commentRoomMode = commentRoomMode.rawValue
        self.likeCount = likeCount
        self.commentCount = commentCount
        self.saveCount = saveCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Comment Rooms

enum SelahCommentRoomMode: String, Codable {
    case open           // anyone who can see the post
    case trustCircle    // only named trust circle
    case closed         // no comments
}

struct SelahCommentRoomMessage: Identifiable, Codable {
    @DocumentID var id: String?
    var authorId: String
    var authorDisplayName: String
    var text: String
    var scriptureRef: String?
    var createdAt: Date
}

// MARK: - Trust Circles

struct SelahTrustCircle: Identifiable, Codable {
    @DocumentID var id: String?
    var ownerId: String
    var name: String
    var memberIds: [String]
    var emoji: String
    var createdAt: Date
    var updatedAt: Date

    init(
        ownerId: String = "",
        name: String = "",
        memberIds: [String] = [],
        emoji: String = "🤝",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.ownerId = ownerId
        self.name = name
        self.memberIds = memberIds
        self.emoji = emoji
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Memories

/// A semantic memory connecting media items, scripture, and reflections.
struct SelahMediaMemory: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var title: String
    var bodyText: String
    var linkedMediaIds: [String]
    var linkedScriptureRefs: [String]
    var meaningTags: [SelahMeaningTag]
    var intentSignal: String            // SelahIntentSignal rawValue
    var aiSummary: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        userId: String = "",
        title: String = "",
        bodyText: String = "",
        linkedMediaIds: [String] = [],
        linkedScriptureRefs: [String] = [],
        meaningTags: [SelahMeaningTag] = [],
        intentSignal: SelahIntentSignal = .reflecting,
        aiSummary: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.userId = userId
        self.title = title
        self.bodyText = bodyText
        self.linkedMediaIds = linkedMediaIds
        self.linkedScriptureRefs = linkedScriptureRefs
        self.meaningTags = meaningTags
        self.intentSignal = intentSignal.rawValue
        self.aiSummary = aiSummary
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var intentEnum: SelahIntentSignal {
        SelahIntentSignal(rawValue: intentSignal) ?? .reflecting
    }
}

// MARK: - Continuations (Next-Best-Action)

enum SelahContinuationAction: String, Codable, CaseIterable, Identifiable {
    case reflect    = "Reflect"
    case pray       = "Pray"
    case share      = "Share"
    case study      = "Study"
    case create     = "Create"
    case journal    = "Journal"
    case rest       = "Rest"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .reflect:  return "brain.head.profile"
        case .pray:     return "hands.sparkles"
        case .share:    return "square.and.arrow.up"
        case .study:    return "book.fill"
        case .create:   return "paintbrush.pointed"
        case .journal:  return "pencil.line"
        case .rest:     return "moon.zzz"
        }
    }

    var accentColorName: String {
        switch self {
        case .reflect:  return "purple"
        case .pray:     return "blue"
        case .share:    return "orange"
        case .study:    return "teal"
        case .create:   return "pink"
        case .journal:  return "green"
        case .rest:     return "indigo"
        }
    }
}

struct SelahMediaContinuation: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var promptText: String
    var contextSummary: String
    var action: String                  // SelahContinuationAction rawValue
    var linkedMediaId: String?
    var linkedMemoryId: String?
    var linkedLivingEntryId: String?
    var scriptureRef: String?
    var relevanceScore: Double          // 0–1
    var completed: Bool
    var createdAt: Date
    var completedAt: Date?

    init(
        userId: String = "",
        promptText: String = "",
        contextSummary: String = "",
        action: SelahContinuationAction = .reflect,
        linkedMediaId: String? = nil,
        linkedMemoryId: String? = nil,
        linkedLivingEntryId: String? = nil,
        scriptureRef: String? = nil,
        relevanceScore: Double = 0.5,
        completed: Bool = false,
        createdAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.userId = userId
        self.promptText = promptText
        self.contextSummary = contextSummary
        self.action = action.rawValue
        self.linkedMediaId = linkedMediaId
        self.linkedMemoryId = linkedMemoryId
        self.linkedLivingEntryId = linkedLivingEntryId
        self.scriptureRef = scriptureRef
        self.relevanceScore = relevanceScore
        self.completed = completed
        self.createdAt = createdAt
        self.completedAt = completedAt
    }

    var actionEnum: SelahContinuationAction {
        SelahContinuationAction(rawValue: action) ?? .reflect
    }
}

// MARK: - Session Intelligence

/// Transient struct representing the user's current session state.
struct SelahSessionContext {
    var currentMode: SelahMediaMode
    var intentSignal: SelahIntentSignal
    var sessionDurationSeconds: Double
    var mediaViewedCount: Int
    var lastInteractionAt: Date
    var recentMeaningCategories: [SelahMeaningCategory]
    var recentScriptureRefs: [String]
    var isInQuietHours: Bool
    var dayOfWeek: Int              // Calendar.current.component(.weekday, ...)
    var timeOfDay: SelahTimeOfDay

    enum SelahTimeOfDay {
        case earlyMorning, morning, midday, afternoon, evening, lateNight
    }

    static func current(
        mode: SelahMediaMode = .pause,
        sessionStart: Date,
        viewedMedia: [SelahMediaItem],
        isInQuietHours: Bool = false
    ) -> SelahSessionContext {
        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        let timeOfDay: SelahTimeOfDay
        switch hour {
        case 4..<7:  timeOfDay = .earlyMorning
        case 7..<12: timeOfDay = .morning
        case 12..<14: timeOfDay = .midday
        case 14..<18: timeOfDay = .afternoon
        case 18..<22: timeOfDay = .evening
        default:     timeOfDay = .lateNight
        }

        let recentCategories = viewedMedia
            .flatMap { $0.meaningTags }
            .compactMap { SelahMeaningCategory(rawValue: $0.category) }
            .prefix(10)

        return SelahSessionContext(
            currentMode: mode,
            intentSignal: .reflecting,
            sessionDurationSeconds: now.timeIntervalSince(sessionStart),
            mediaViewedCount: viewedMedia.count,
            lastInteractionAt: now,
            recentMeaningCategories: Array(recentCategories),
            recentScriptureRefs: viewedMedia.compactMap { $0.scriptureRef }.prefix(5).map { $0 },
            isInQuietHours: isInQuietHours,
            dayOfWeek: Calendar.current.component(.weekday, from: now),
            timeOfDay: timeOfDay
        )
    }
}

/// The intelligence engine's output context window for a session.
struct SelahContextWindow {
    var dominantCategory: SelahMeaningCategory?
    var suggestedMode: SelahMediaMode
    var suggestedContinuation: SelahContinuationAction
    var restSignalDetected: Bool
    var meaningGraphNodes: [SelahMeaningTag]
    var sessionSummary: String
}

/// A media item paired with a relevance rank score.
struct SelahRankedMedia: Identifiable {
    var id: String { item.id ?? UUID().uuidString }
    var item: SelahMediaItem
    var score: Double
    var matchReason: String
}

// MARK: - Meaning Graph Edge

/// Represents a semantic connection between two media items.
struct SelahMeaningGraphEdge: Identifiable, Codable {
    @DocumentID var id: String?
    var sourceItemId: String
    var targetItemId: String
    var sharedCategories: [String]
    var sharedScriptureRefs: [String]
    var connectionStrength: Double      // 0–1
    var createdAt: Date
}

// MARK: - Creator OS

enum SelahCreatorProjectStatus: String, Codable {
    case draft, composing, reviewing, published, archived
}

struct SelahCreatorProject: Identifiable, Codable {
    @DocumentID var id: String?
    var authorId: String
    var title: String
    var description: String
    var coverMediaId: String?
    var mediaItemIds: [String]
    var meaningTags: [SelahMeaningTag]
    var status: String                  // SelahCreatorProjectStatus rawValue
    var scriptureTheme: String?
    var audienceCircleId: String?
    var createdAt: Date
    var updatedAt: Date
    var publishedAt: Date?

    init(
        authorId: String = "",
        title: String = "",
        description: String = "",
        coverMediaId: String? = nil,
        mediaItemIds: [String] = [],
        meaningTags: [SelahMeaningTag] = [],
        status: SelahCreatorProjectStatus = .draft,
        scriptureTheme: String? = nil,
        audienceCircleId: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        publishedAt: Date? = nil
    ) {
        self.authorId = authorId
        self.title = title
        self.description = description
        self.coverMediaId = coverMediaId
        self.mediaItemIds = mediaItemIds
        self.meaningTags = meaningTags
        self.status = status.rawValue
        self.audienceCircleId = audienceCircleId
        self.scriptureTheme = scriptureTheme
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.publishedAt = publishedAt
    }
}

// MARK: - Outcomes

struct SelahOutcome: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var continuationId: String
    var action: String              // SelahContinuationAction rawValue
    var noteText: String?
    var scriptureRef: String?
    var createdAt: Date
}
