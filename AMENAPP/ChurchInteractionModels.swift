// ChurchInteractionModels.swift
// AMENAPP
//
// Church Interaction Tracking — Models for the full church discovery-to-return lifecycle.
// Bridges with existing ChurchVisitState, ChurchVisitSession, and VisitPlan models.

import Foundation
import FirebaseFirestore

// MARK: - ChurchPostCardType

/// Types of PostCard drafts users can create for a church.
enum ChurchPostCardType: String, Codable, CaseIterable {
    case invite         = "invite"
    case recommend      = "recommend"
    case gratitude      = "gratitude"
    case testimony      = "testimony"
    case encouragement  = "encouragement"

    var displayName: String {
        switch self {
        case .invite:        return "Invite a Friend"
        case .recommend:     return "Recommend"
        case .gratitude:     return "Share Gratitude"
        case .testimony:     return "Share Testimony"
        case .encouragement: return "Encourage"
        }
    }

    var icon: String {
        switch self {
        case .invite:        return "person.badge.plus"
        case .recommend:     return "hand.thumbsup"
        case .gratitude:     return "heart"
        case .testimony:     return "text.quote"
        case .encouragement: return "hands.sparkles"
        }
    }
}

// MARK: - ChurchInteractionPhase

/// Tracks the user's journey with a church from discovery through return.
/// Bridges to existing ChurchVisitState where applicable.
enum ChurchInteractionPhase: String, Codable, CaseIterable, Comparable {
    case discovered     = "discovered"      // Appeared in search / recommendation results
    case saved          = "saved"           // User saved / bookmarked
    case interested     = "interested"      // User expanded card / viewed profile
    case planning       = "planning"        // User opened First Visit Companion / created visit plan
    case ready          = "ready"           // Checklist mostly complete, visit plan finalized
    case attended       = "attended"        // Visit confirmed (manual or location-based)
    case reflected      = "reflected"       // User completed a reflection note
    case returned       = "returned"        // User attended a second time

    /// Maps to existing ChurchVisitState for backward compatibility
    var visitState: ChurchVisitState {
        switch self {
        case .discovered, .saved, .interested:  return .none
        case .planning, .ready:                 return .planning
        case .attended:                         return .postVisit
        case .reflected:                        return .postVisit
        case .returned:                         return .revisitSuggested
        }
    }

    var displayName: String {
        switch self {
        case .discovered:   return "Discovered"
        case .saved:        return "Saved"
        case .interested:   return "Interested"
        case .planning:     return "Planning Visit"
        case .ready:        return "Ready to Visit"
        case .attended:     return "Attended"
        case .reflected:    return "Reflected"
        case .returned:     return "Returned"
        }
    }

    var icon: String {
        switch self {
        case .discovered:   return "magnifyingglass"
        case .saved:        return "bookmark.fill"
        case .interested:   return "hand.tap"
        case .planning:     return "calendar.badge.plus"
        case .ready:        return "checkmark.circle"
        case .attended:     return "figure.walk.arrival"
        case .reflected:    return "text.book.closed"
        case .returned:     return "arrow.uturn.backward.circle"
        }
    }

    // Comparable conformance for ordered progression
    private var sortOrder: Int {
        switch self {
        case .discovered:   return 0
        case .saved:        return 1
        case .interested:   return 2
        case .planning:     return 3
        case .ready:        return 4
        case .attended:     return 5
        case .reflected:    return 6
        case .returned:     return 7
        }
    }

    static func < (lhs: ChurchInteractionPhase, rhs: ChurchInteractionPhase) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

// MARK: - ChurchVisitChecklist

/// Private preparation checklist for a first visit.
struct ChurchVisitChecklist: Codable, Equatable {
    var gotDirections: Bool
    var enabledQuietMode: Bool
    var invitedFriend: Bool
    var createdNote: Bool
    var preparedPostCard: Bool

    init(
        gotDirections: Bool = false,
        enabledQuietMode: Bool = false,
        invitedFriend: Bool = false,
        createdNote: Bool = false,
        preparedPostCard: Bool = false
    ) {
        self.gotDirections = gotDirections
        self.enabledQuietMode = enabledQuietMode
        self.invitedFriend = invitedFriend
        self.createdNote = createdNote
        self.preparedPostCard = preparedPostCard
    }

    /// Fraction of completed items (0.0–1.0)
    var completionPercentage: Double {
        let items: [Bool] = [gotDirections, enabledQuietMode, invitedFriend, createdNote, preparedPostCard]
        let completed = items.filter { $0 }.count
        return Double(completed) / Double(items.count)
    }

    /// Number of completed items
    var completedCount: Int {
        [gotDirections, enabledQuietMode, invitedFriend, createdNote, preparedPostCard].filter { $0 }.count
    }

    /// Total checklist items
    var totalCount: Int { 5 }

    /// Display items for UI iteration
    var displayItems: [(key: String, label: String, icon: String, isComplete: Bool)] {
        [
            ("gotDirections",    "Get directions",       "location.fill",              gotDirections),
            ("enabledQuietMode", "Enable quiet mode",    "moon.fill",                  enabledQuietMode),
            ("invitedFriend",    "Invite a friend",      "person.2.fill",              invitedFriend),
            ("createdNote",      "Create a note",        "square.and.pencil",          createdNote),
            ("preparedPostCard", "Prepare a PostCard",   "rectangle.portrait.on.rectangle.portrait.fill", preparedPostCard),
        ]
    }

    enum CodingKeys: String, CodingKey {
        case gotDirections = "got_directions"
        case enabledQuietMode = "enabled_quiet_mode"
        case invitedFriend = "invited_friend"
        case createdNote = "created_note"
        case preparedPostCard = "prepared_post_card"
    }
}

// MARK: - ChurchRecommendationReason

/// A human-readable explanation for why a church was recommended.
struct ChurchRecommendationReason: Codable, Identifiable, Equatable {
    var id: String { "\(category.rawValue)_\(shortReason.hashValue)" }
    let shortReason: String      // e.g. "Only 0.8 miles away"
    let longReason: String       // e.g. "This church is very close to your current location, making it easy to attend regularly."
    let category: ReasonCategory
    let score: Double            // 0.0–1.0 contribution from this dimension

    enum ReasonCategory: String, Codable, CaseIterable {
        case distance       = "distance"
        case denomination   = "denomination"
        case theology       = "theology"
        case season         = "season"
        case teaching       = "teaching"
        case community      = "community"

        var icon: String {
            switch self {
            case .distance:     return "location"
            case .denomination: return "building.columns"
            case .theology:     return "book.closed"
            case .season:       return "leaf"
            case .teaching:     return "person.wave.2"
            case .community:    return "person.3"
            }
        }

        var displayName: String {
            switch self {
            case .distance:     return "Proximity"
            case .denomination: return "Denomination"
            case .theology:     return "Theology"
            case .season:       return "Spiritual Season"
            case .teaching:     return "Teaching Style"
            case .community:    return "Community"
            }
        }
    }
}

// MARK: - ChurchInteraction

/// Tracks the full lifecycle of a user's relationship with a specific church.
/// Stored at: users/{uid}/churchInteractions/{churchId}
struct ChurchInteraction: Codable, Identifiable, Equatable {
    var id: String { churchId }
    let userId: String
    let churchId: String
    let churchName: String
    var phase: ChurchInteractionPhase

    // Timestamps for each phase transition
    var discoveredAt: Date?
    var savedAt: Date?
    var interestedAt: Date?
    var planningAt: Date?
    var readyAt: Date?
    var attendedAt: Date?
    var reflectedAt: Date?
    var returnedAt: Date?

    // Linked resources
    var visitPlanId: String?
    var visitSessionId: String?
    var noteIds: [String]
    var reflectionId: String?
    var postCardDraftIds: [String]

    // Preparation
    var checklist: ChurchVisitChecklist

    // Explainability
    var recommendationReasons: [ChurchRecommendationReason]

    // Metadata
    var createdAt: Date
    var updatedAt: Date

    init(
        userId: String,
        churchId: String,
        churchName: String,
        phase: ChurchInteractionPhase = .discovered,
        discoveredAt: Date? = nil,
        savedAt: Date? = nil,
        interestedAt: Date? = nil,
        planningAt: Date? = nil,
        readyAt: Date? = nil,
        attendedAt: Date? = nil,
        reflectedAt: Date? = nil,
        returnedAt: Date? = nil,
        visitPlanId: String? = nil,
        visitSessionId: String? = nil,
        noteIds: [String] = [],
        reflectionId: String? = nil,
        postCardDraftIds: [String] = [],
        checklist: ChurchVisitChecklist = ChurchVisitChecklist(),
        recommendationReasons: [ChurchRecommendationReason] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.userId = userId
        self.churchId = churchId
        self.churchName = churchName
        self.phase = phase
        self.discoveredAt = discoveredAt
        self.savedAt = savedAt
        self.interestedAt = interestedAt
        self.planningAt = planningAt
        self.readyAt = readyAt
        self.attendedAt = attendedAt
        self.reflectedAt = reflectedAt
        self.returnedAt = returnedAt
        self.visitPlanId = visitPlanId
        self.visitSessionId = visitSessionId
        self.noteIds = noteIds
        self.reflectionId = reflectionId
        self.postCardDraftIds = postCardDraftIds
        self.checklist = checklist
        self.recommendationReasons = recommendationReasons
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case churchId = "church_id"
        case churchName = "church_name"
        case phase
        case discoveredAt = "discovered_at"
        case savedAt = "saved_at"
        case interestedAt = "interested_at"
        case planningAt = "planning_at"
        case readyAt = "ready_at"
        case attendedAt = "attended_at"
        case reflectedAt = "reflected_at"
        case returnedAt = "returned_at"
        case visitPlanId = "visit_plan_id"
        case visitSessionId = "visit_session_id"
        case noteIds = "note_ids"
        case reflectionId = "reflection_id"
        case postCardDraftIds = "post_card_draft_ids"
        case checklist
        case recommendationReasons = "recommendation_reasons"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
