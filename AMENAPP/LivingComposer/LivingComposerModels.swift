import Foundation
import CoreLocation

// MARK: - Posting Context

enum PostingContext: String, Codable, CaseIterable {
    case gathering      = "gathering"
    case conference     = "conference"
    case church         = "church"
    case traveling      = "traveling"
    case working        = "working"
    case home           = "home"
    case event          = "event"
    case campus         = "campus"
    case unknown        = "unknown"

    var composerMode: ComposerMode {
        switch self {
        case .gathering, .church: return .reflective
        case .conference, .event: return .event
        case .working:            return .collaboration
        case .unknown, .home:     return .standard
        case .campus:             return .standard
        case .traveling:          return .event
        }
    }

    var displayName: String {
        switch self {
        case .gathering:   return "At a Gathering"
        case .conference:  return "Conference"
        case .church:      return "At Church"
        case .traveling:   return "Traveling"
        case .working:     return "Working"
        case .home:        return "Home"
        case .event:       return "At an Event"
        case .campus:      return "On Campus"
        case .unknown:     return "Nearby"
        }
    }
}

// MARK: - Composer Mode

enum ComposerMode: String, Codable, CaseIterable {
    case standard       = "standard"
    case reflective     = "reflective"
    case event          = "event"
    case collaboration  = "collaboration"
    case creator        = "creator"

    var displayName: String {
        switch self {
        case .standard:      return "Post"
        case .reflective:    return "Reflect"
        case .event:         return "Event"
        case .collaboration: return "Collaborate"
        case .creator:       return "Create"
        }
    }

    var systemImage: String {
        switch self {
        case .standard:      return "square.and.pencil"
        case .reflective:    return "leaf.fill"
        case .event:         return "calendar.badge.plus"
        case .collaboration: return "person.2.fill"
        case .creator:       return "sparkles"
        }
    }

    var uiHint: ComposerUIHint {
        switch self {
        case .standard:
            return ComposerUIHint(textPlaceholder: "What's on your mind?", cameraFirst: false, showAudienceSelector: true, showEventTools: false, showCollabTools: false)
        case .reflective:
            return ComposerUIHint(textPlaceholder: "Share a reflection...", cameraFirst: false, showAudienceSelector: false, showEventTools: false, showCollabTools: false)
        case .event:
            return ComposerUIHint(textPlaceholder: "Share this moment...", cameraFirst: true, showAudienceSelector: true, showEventTools: true, showCollabTools: false)
        case .collaboration:
            return ComposerUIHint(textPlaceholder: "Start a discussion...", cameraFirst: false, showAudienceSelector: true, showEventTools: false, showCollabTools: true)
        case .creator:
            return ComposerUIHint(textPlaceholder: "Create something...", cameraFirst: false, showAudienceSelector: true, showEventTools: false, showCollabTools: false)
        }
    }
}

struct ComposerUIHint {
    var textPlaceholder: String
    var cameraFirst: Bool
    var showAudienceSelector: Bool
    var showEventTools: Bool
    var showCollabTools: Bool
}

// MARK: - Composer Intent (social-OS focused; distinct from PostIntent which is faith-focused)

enum ComposerIntent: String, Codable, CaseIterable {
    case shareM          = "share_moment"
    case askQuestion     = "ask_question"
    case teach           = "teach"
    case organize        = "organize"
    case reflect         = "reflect"
    case meetPeople      = "meet_people"
    case startDiscussion = "start_discussion"
    case documentEvent   = "document_event"
    case buildCommunity  = "build_community"
    case saveMemory      = "save_memory"

    var displayName: String {
        switch self {
        case .shareM:          return "Share a Moment"
        case .askQuestion:     return "Ask a Question"
        case .teach:           return "Teach Something"
        case .organize:        return "Organize People"
        case .reflect:         return "Reflect"
        case .meetPeople:      return "Meet People"
        case .startDiscussion: return "Start a Discussion"
        case .documentEvent:   return "Document an Event"
        case .buildCommunity:  return "Build Community"
        case .saveMemory:      return "Save a Memory"
        }
    }

    var systemImage: String {
        switch self {
        case .shareM:          return "camera.fill"
        case .askQuestion:     return "questionmark.circle"
        case .teach:           return "graduationcap"
        case .organize:        return "list.bullet.clipboard"
        case .reflect:         return "leaf"
        case .meetPeople:      return "person.2.circle"
        case .startDiscussion: return "bubble.left.and.bubble.right"
        case .documentEvent:   return "calendar"
        case .buildCommunity:  return "person.3"
        case .saveMemory:      return "bookmark.fill"
        }
    }
}

// MARK: - Audience Route

struct AudienceRoute: Identifiable, Equatable {
    let id: String
    var type: AudienceRouteType
    var label: String
    var subtitle: String?
    var selected: Bool
    var score: Double

    static func personalFeed(score: Double = 1.0) -> AudienceRoute {
        AudienceRoute(id: "personal_feed", type: .personalFeed, label: "Your Feed", subtitle: "Followers see this", selected: true, score: score)
    }

    static func nearbyEvent(eventName: String, score: Double) -> AudienceRoute {
        AudienceRoute(id: "nearby_event_\(eventName)", type: .nearbyEvent, label: eventName, subtitle: "Share with attendees", selected: false, score: score)
    }
}

enum AudienceRouteType: String, Codable {
    case personalFeed     = "personal_feed"
    case nearbyEvent      = "nearby_event"
    case communitySpace   = "community_space"
    case churchSpace      = "church_space"
    case creatorFollowers = "creator_followers"
    case local            = "local"
    case global           = "global"
    case privateCircle    = "private_circle"
}

// MARK: - Composer Suggestion (distinct from SmartSuggestion which is for people suggestions)

struct ComposerSuggestion: Identifiable, Equatable {
    let id: String
    var type: ComposerSuggestionType
    var text: String
    var actionLabel: String?
    var confidence: Double

    static func eventTag(name: String) -> ComposerSuggestion {
        ComposerSuggestion(id: UUID().uuidString, type: .eventTag, text: "Tag this event: \(name)", actionLabel: "Add Tag", confidence: 0.9)
    }
}

enum ComposerSuggestionType: String, Codable {
    case eventTag       = "event_tag"
    case captionAssist  = "caption_assist"
    case audienceHint   = "audience_hint"
    case safetyWarning  = "safety_warning"
    case recapCreate    = "recap_create"
    case privacyAlert   = "privacy_alert"
    case ocrExtract     = "ocr_extract"
    case scriptureRef   = "scripture_ref"
}

typealias SmartSuggestionType = ComposerSuggestionType

// MARK: - Media Analysis Result

struct MediaAnalysisResult: Equatable {
    var detectedType: DetectedMediaType
    var extractedText: String?
    var suggestedCaption: String?
    var suggestedTags: [String]
    var recommendedAudiences: [AudienceRouteType]
    var hasSensitiveContent: Bool
    var sensitivityReason: String?
}

enum DetectedMediaType: String, Codable {
    case whiteboard    = "whiteboard"
    case slides        = "slides"
    case sermon        = "sermon"
    case food          = "food"
    case people        = "people"
    case productDemo   = "product_demo"
    case concert       = "concert"
    case scripture     = "scripture"
    case notes         = "notes"
    case presentation  = "presentation"
    case landscape     = "landscape"
    case eventBadge    = "event_badge"
    case general       = "general"
}

// MARK: - Posting Intelligence Result

struct PostingIntelligenceResult: Equatable {
    var detectedIntent: ComposerIntent
    var suggestedMode: ComposerMode
    var suggestions: [ComposerSuggestion]
    var audienceRoutes: [AudienceRoute]
    var safetyFlags: [PostSafetyFlag]
    var postingContext: PostingContext
    var aiCaption: String?

    static let empty = PostingIntelligenceResult(
        detectedIntent: .shareM,
        suggestedMode: .standard,
        suggestions: [],
        audienceRoutes: [.personalFeed()],
        safetyFlags: [],
        postingContext: .unknown
    )
}

// MARK: - Post Safety Flag (distinct from BereanCoreService.SafetyFlag which is for AI moderation)

struct PostSafetyFlag: Identifiable, Equatable {
    let id: String
    var type: PostSafetyFlagType
    var message: String
    var severity: PostSafetyLevel
}

enum PostSafetyFlagType: String, Codable {
    case locationExposure  = "location_exposure"
    case faceDetected      = "face_detected"
    case sensitiveInfo     = "sensitive_info"
    case emotionalDistress = "emotional_distress"
    case manipulatedMedia  = "manipulated_media"
}

enum PostSafetyLevel: String, Codable {
    case info    = "info"
    case warning = "warning"
    case block   = "block"
}
