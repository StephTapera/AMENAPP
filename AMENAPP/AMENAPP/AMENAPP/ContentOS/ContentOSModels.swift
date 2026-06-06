// ContentOSModels.swift
// AMENAPP — ContentOS
//
// Universal data models for the Content Discussion, Approval, and Forwarding OS.
// Every shareable item in Amen becomes a ContentCard. Nothing leaves its original
// context unless the permission engine allows it.

import Foundation
import FirebaseFirestore

// MARK: - Universal Content Card

struct ContentCard: Identifiable {
    let id: String
    let title: String
    let body: String
    let sourceType: ContentSourceType
    let sourceSurface: ContentSurface
    let sourceId: String
    let originalAudience: ContentAudience
    let creatorId: String
    let creatorDisplayName: String?     // nil for anonymous posts — never expose
    let sensitivityScore: Double        // 0.0–1.0; drives approval threshold
    let hasPrayerContent: Bool
    let hasChildContent: Bool
    let hasLocationData: Bool
    let hasMinors: Bool
    let isAnonymous: Bool
    let isPaidContent: Bool
    let isDM: Bool
    let isChurchInternal: Bool
    let createdAt: Date
    var expiresAt: Date?
    var moderationState: ContentModerationState
    var discussionStatus: ContentDiscussionStatus
    var attributionRules: ContentAttributionRules
}

// MARK: - Source Type

enum ContentSourceType: String, CaseIterable {
    case post               = "post"
    case message            = "message"
    case prayerRequest      = "prayer_request"
    case sermonClip         = "sermon_clip"
    case livestreamMoment   = "livestream_moment"
    case churchNote         = "church_note"
    case resource           = "resource"
    case event              = "event"
    case testimony          = "testimony"
    case question           = "question"

    var displayName: String {
        switch self {
        case .post:             return "Post"
        case .message:          return "Message"
        case .prayerRequest:    return "Prayer Request"
        case .sermonClip:       return "Sermon Clip"
        case .livestreamMoment: return "Livestream Moment"
        case .churchNote:       return "Church Note"
        case .resource:         return "Resource"
        case .event:            return "Event"
        case .testimony:        return "Testimony"
        case .question:         return "Question"
        }
    }

    var icon: String {
        switch self {
        case .post:             return "doc.richtext"
        case .message:          return "bubble.left"
        case .prayerRequest:    return "hands.sparkles.fill"
        case .sermonClip:       return "film.stack"
        case .livestreamMoment: return "record.circle"
        case .churchNote:       return "note.text"
        case .resource:         return "books.vertical.fill"
        case .event:            return "calendar.badge.plus"
        case .testimony:        return "star.fill"
        case .question:         return "questionmark.bubble.fill"
        }
    }
}

// MARK: - Surface

enum ContentSurface: String {
    case feed           = "feed"
    case directMessage  = "direct_message"
    case space          = "space"
    case amenConnect    = "amen_connect"
    case churchNotes    = "church_notes"
    case findAChurch    = "find_a_church"
    case livestream     = "livestream"
    case event          = "event"
    case mentorThread   = "mentor_thread"
    case objectHub      = "object_hub"

    var displayName: String {
        switch self {
        case .feed:          return "Feed"
        case .directMessage: return "Direct Message"
        case .space:         return "Amen Space"
        case .amenConnect:   return "Amen Connect"
        case .churchNotes:   return "Church Notes"
        case .findAChurch:   return "Find a Church"
        case .livestream:    return "Livestream"
        case .event:         return "Event"
        case .mentorThread:  return "Mentor Thread"
        case .objectHub:     return "Community Hub"
        }
    }
}

// MARK: - Audience

enum ContentAudience: String, CaseIterable, Codable {
    case `private`      = "private"
    case trustedCircle  = "trusted_circle"
    case smallGroup     = "small_group"
    case churchOnly     = "church_only"
    case spaceMembers   = "space_members"
    case paidMembers    = "paid_members"
    case publicFeed     = "public_feed"

    var displayName: String {
        switch self {
        case .private:       return "Private"
        case .trustedCircle: return "Trusted Circle"
        case .smallGroup:    return "Small Group"
        case .churchOnly:    return "Church Only"
        case .spaceMembers:  return "Space Members"
        case .paidMembers:   return "Paid Members"
        case .publicFeed:    return "Public"
        }
    }

    var isRestricted: Bool {
        switch self {
        case .private, .trustedCircle, .smallGroup, .churchOnly: return true
        case .spaceMembers, .paidMembers, .publicFeed:           return false
        }
    }
}

// MARK: - Actions

enum ContentAction: String, CaseIterable {
    case discussInSpace       = "discuss_in_space"
    case discussInConnect     = "discuss_in_connect"
    case sendToMentor         = "send_to_mentor"
    case sendToSmallGroup     = "send_to_small_group"
    case sendToChurchTeam     = "send_to_church_team"
    case saveToChurchNotes    = "save_to_church_notes"
    case createStudy          = "create_study"
    case createPrayerRoom     = "create_prayer_room"
    case createEventFollowUp  = "create_event_follow_up"
    case forwardDM            = "forward_dm"
    case forwardGroup         = "forward_group"
    case shareExternal        = "share_external"
    case quoteInPost          = "quote_in_post"
    case requestPermission    = "request_permission"

    var displayName: String {
        switch self {
        case .discussInSpace:      return "Discuss in Space"
        case .discussInConnect:    return "Discuss in Connect"
        case .sendToMentor:        return "Send to Mentor"
        case .sendToSmallGroup:    return "Send to Small Group"
        case .sendToChurchTeam:    return "Send to Church Team"
        case .saveToChurchNotes:   return "Save to Church Notes"
        case .createStudy:         return "Create Study"
        case .createPrayerRoom:    return "Create Prayer Room"
        case .createEventFollowUp: return "Create Event Follow-Up"
        case .forwardDM:           return "Forward (DM)"
        case .forwardGroup:        return "Forward to Group"
        case .shareExternal:       return "Share Outside Amen"
        case .quoteInPost:         return "Quote in Post"
        case .requestPermission:   return "Request Permission"
        }
    }

    var icon: String {
        switch self {
        case .discussInSpace:      return "bubble.left.and.text.bubble.right.fill"
        case .discussInConnect:    return "network"
        case .sendToMentor:        return "person.badge.key.fill"
        case .sendToSmallGroup:    return "person.3.fill"
        case .sendToChurchTeam:    return "building.columns.fill"
        case .saveToChurchNotes:   return "note.text.badge.plus"
        case .createStudy:         return "book.closed.fill"
        case .createPrayerRoom:    return "hands.sparkles.fill"
        case .createEventFollowUp: return "calendar.badge.checkmark"
        case .forwardDM:           return "arrowshape.turn.up.right"
        case .forwardGroup:        return "arrowshape.turn.up.right.2.fill"
        case .shareExternal:       return "square.and.arrow.up"
        case .quoteInPost:         return "quote.bubble"
        case .requestPermission:   return "hand.raised.fill"
        }
    }

    var isDestructiveAdjacent: Bool {
        self == .shareExternal
    }
}

// MARK: - Moderation / Discussion State

enum ContentModerationState: String {
    case safe        = "safe"
    case flagged     = "flagged"
    case underReview = "under_review"
    case removed     = "removed"
}

enum ContentDiscussionStatus: String {
    case none      = "none"
    case open      = "open"
    case moderated = "moderated"
    case closed    = "closed"
}

// MARK: - Attribution Rules

struct ContentAttributionRules {
    var requiresAttribution: Bool
    var allowsAnonymous: Bool
    var allowsQuoteOnly: Bool
    var expiresAfterDays: Int?
}

// MARK: - Permission Outcome

enum ContentPermissionOutcome {
    case allowedInstantly
    case allowedWithAttribution
    case allowedAnonymously
    case requiresCreatorApproval
    case requiresSpaceAdminApproval
    case requiresChurchAdminApproval
    case restrictedToSameSpace
    case restrictedToTrustedMembers
    case denied(reason: String)

    var canProceed: Bool {
        if case .denied = self { return false }
        return true
    }

    var requiresApproval: Bool {
        switch self {
        case .requiresCreatorApproval,
             .requiresSpaceAdminApproval,
             .requiresChurchAdminApproval: return true
        default:                           return false
        }
    }

    var displayTitle: String {
        switch self {
        case .allowedInstantly:            return "Allowed"
        case .allowedWithAttribution:      return "Allowed with Attribution"
        case .allowedAnonymously:          return "Allowed Anonymously"
        case .requiresCreatorApproval:     return "Creator Approval Required"
        case .requiresSpaceAdminApproval:  return "Space Admin Approval Required"
        case .requiresChurchAdminApproval: return "Church Admin Approval Required"
        case .restrictedToSameSpace:       return "Same Space Only"
        case .restrictedToTrustedMembers:  return "Trusted Members Only"
        case .denied(let reason):          return reason
        }
    }

    var iconName: String {
        switch self {
        case .allowedInstantly:            return "checkmark.circle.fill"
        case .allowedWithAttribution:      return "checkmark.circle"
        case .allowedAnonymously:          return "person.fill.questionmark"
        case .requiresCreatorApproval,
             .requiresSpaceAdminApproval,
             .requiresChurchAdminApproval: return "lock.fill"
        case .restrictedToSameSpace,
             .restrictedToTrustedMembers:  return "person.2.circle"
        case .denied:                      return "xmark.circle.fill"
        }
    }
}

// MARK: - External Share Risk

struct ExternalShareRisk {
    var exposesPrivateContext: Bool
    var includesNames: Bool
    var includesPrayerDetails: Bool
    var includesLocationOrEvent: Bool
    var includesMinors: Bool
    var wasNotOriginallyPublic: Bool

    var hasAnyRisk: Bool {
        exposesPrivateContext || includesNames || includesPrayerDetails
            || includesLocationOrEvent || includesMinors || wasNotOriginallyPublic
    }

    var riskItems: [String] {
        var items: [String] = []
        if exposesPrivateContext   { items.append("This may expose private context") }
        if includesNames           { items.append("This includes names") }
        if includesPrayerDetails   { items.append("This includes prayer details") }
        if includesLocationOrEvent { items.append("This includes location or event info") }
        if includesMinors          { items.append("This includes minors") }
        if wasNotOriginallyPublic  { items.append("This was not originally public") }
        return items
    }
}

// MARK: - AI Redaction Suggestion

struct ContentRedactionSuggestion: Identifiable {
    let id = UUID()
    let type: RedactionType
    let description: String

    enum RedactionType {
        case removeNames
        case blurFaces
        case removeLocation
        case removePrayerDetails
        case summarize
        case convertToAnonymousTestimony
        case convertToDiscussionPrompt
        case askPermissionFirst

        var icon: String {
            switch self {
            case .removeNames:                 return "person.slash"
            case .blurFaces:                   return "camera.metering.center.weighted"
            case .removeLocation:              return "location.slash"
            case .removePrayerDetails:         return "hands.sparkles"
            case .summarize:                   return "text.quote"
            case .convertToAnonymousTestimony: return "person.fill.questionmark"
            case .convertToDiscussionPrompt:   return "bubble.left.and.text.bubble.right"
            case .askPermissionFirst:          return "hand.raised"
            }
        }

        var displayName: String {
            switch self {
            case .removeNames:                 return "Remove Names"
            case .blurFaces:                   return "Blur Faces"
            case .removeLocation:              return "Remove Locations"
            case .removePrayerDetails:         return "Remove Prayer Details"
            case .summarize:                   return "Summarize Instead"
            case .convertToAnonymousTestimony: return "Convert to Anonymous Testimony"
            case .convertToDiscussionPrompt:   return "Turn into Discussion Prompt"
            case .askPermissionFirst:          return "Ask Permission First"
            }
        }
    }
}

// MARK: - Audit Log Entry

struct ContentAuditEntry {
    let contentId: String
    let contentType: String
    let actorId: String
    let action: String          // "shared", "forwarded", "approved", "denied", "redacted"
    let destination: String?
    let isExternal: Bool
    let timestamp: Date
    let wasAnonymous: Bool
    let approvalOutcome: String?
}

// MARK: - AI Route Suggestion

struct ContentRouteSuggestion: Identifiable {
    let id = UUID()
    let action: ContentAction
    let label: String
    let rationale: String
    let confidence: Double      // 0.0–1.0; drives display order
}

// MARK: - Discussion Mode

enum ContentDiscussionMode: String, CaseIterable {
    case open           = "open"
    case leaderModerated = "leader_moderated"
    case anonymous      = "anonymous"
    case prayerOnly     = "prayer_only"
    case study          = "study"
    case qaMode         = "qa_mode"
    case mentorOnly     = "mentor_only"
    case staffReview    = "staff_review"
    case eventFollowUp  = "event_follow_up"

    var displayName: String {
        switch self {
        case .open:             return "Open Discussion"
        case .leaderModerated:  return "Leader-Moderated"
        case .anonymous:        return "Anonymous"
        case .prayerOnly:       return "Prayer Only"
        case .study:            return "Study Discussion"
        case .qaMode:           return "Q&A Mode"
        case .mentorOnly:       return "Mentor Thread"
        case .staffReview:      return "Staff Review"
        case .eventFollowUp:    return "Event Follow-Up"
        }
    }

    var icon: String {
        switch self {
        case .open:             return "bubble.left.and.bubble.right.fill"
        case .leaderModerated:  return "person.badge.shield.checkmark.fill"
        case .anonymous:        return "person.fill.questionmark"
        case .prayerOnly:       return "hands.sparkles.fill"
        case .study:            return "book.fill"
        case .qaMode:           return "questionmark.bubble.fill"
        case .mentorOnly:       return "person.badge.key.fill"
        case .staffReview:      return "building.columns.fill"
        case .eventFollowUp:    return "calendar.badge.checkmark"
        }
    }
}
