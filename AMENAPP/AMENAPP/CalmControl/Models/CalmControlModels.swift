import Foundation
import FirebaseFirestore

// MARK: - PresenceState

enum PresenceState: String, Codable, CaseIterable {
    case visible
    case quiet
    case reflecting
    case focused
    case sabbathing

    var displayName: String {
        switch self {
        case .visible:    return "Visible"
        case .quiet:      return "Quiet"
        case .reflecting: return "Reflecting"
        case .focused:    return "Focused"
        case .sabbathing: return "Sabbathing"
        }
    }

    var icon: String {
        switch self {
        case .visible:    return "eye"
        case .quiet:      return "moon.fill"
        case .reflecting: return "sparkles"
        case .focused:    return "target"
        case .sabbathing: return "sun.max.fill"
        }
    }

    var description: String {
        switch self {
        case .visible:    return "You are fully present and open to interaction."
        case .quiet:      return "You are here, but not looking for conversation."
        case .reflecting: return "You are in a reflective state. Interactions are minimal."
        case .focused:    return "Deep focus mode. Notifications and distractions are reduced."
        case .sabbathing: return "You are resting. Social features are paused."
        }
    }
}

// MARK: - FeedControlSettings

struct FeedControlSettings: Codable {
    var textOnlyMode: Bool
    var hidePhotos: Bool
    var hideVideos: Bool
    var hideViralContent: Bool
    var noDebateFilter: Bool
    var hideFollowerCounts: Bool
    var hideFollowingCounts: Bool
    var privateFollowingGraph: Bool
    var disableReadReceipts: Bool
    var aiFeedNoiseCompression: Bool
    var topicSaturation: [String: Double]
    var updatedAt: Timestamp?

    init(
        textOnlyMode: Bool = false,
        hidePhotos: Bool = false,
        hideVideos: Bool = false,
        hideViralContent: Bool = false,
        noDebateFilter: Bool = false,
        hideFollowerCounts: Bool = true,
        hideFollowingCounts: Bool = true,
        privateFollowingGraph: Bool = false,
        disableReadReceipts: Bool = false,
        aiFeedNoiseCompression: Bool = false,
        topicSaturation: [String: Double] = [:],
        updatedAt: Timestamp? = nil
    ) {
        self.textOnlyMode = textOnlyMode
        self.hidePhotos = hidePhotos
        self.hideVideos = hideVideos
        self.hideViralContent = hideViralContent
        self.noDebateFilter = noDebateFilter
        self.hideFollowerCounts = hideFollowerCounts
        self.hideFollowingCounts = hideFollowingCounts
        self.privateFollowingGraph = privateFollowingGraph
        self.disableReadReceipts = disableReadReceipts
        self.aiFeedNoiseCompression = aiFeedNoiseCompression
        self.topicSaturation = topicSaturation
        self.updatedAt = updatedAt
    }
}

// MARK: - MediaIntensitySettings

struct MediaIntensitySettings: Codable {
    var muteAutoplayVideo: Bool
    var muteAutoplayAudio: Bool
    var reduceMotionFeed: Bool
    var highContrastMode: Bool
    var updatedAt: Timestamp?

    init(
        muteAutoplayVideo: Bool = true,
        muteAutoplayAudio: Bool = true,
        reduceMotionFeed: Bool = false,
        highContrastMode: Bool = false,
        updatedAt: Timestamp? = nil
    ) {
        self.muteAutoplayVideo = muteAutoplayVideo
        self.muteAutoplayAudio = muteAutoplayAudio
        self.reduceMotionFeed = reduceMotionFeed
        self.highContrastMode = highContrastMode
        self.updatedAt = updatedAt
    }
}

// MARK: - AudienceLayer

struct AudienceLayer: Identifiable, Codable {
    var id: String
    var name: String
    var memberUIDs: [String]
    var createdAt: Timestamp?
}

// MARK: - EmotionalEnergyFilter

enum EmotionalEnergyFilter: String, Codable, CaseIterable {
    case all
    case calm
    case uplifting
    case balanced

    var displayName: String {
        switch self {
        case .all:       return "All"
        case .calm:      return "Calm"
        case .uplifting: return "Uplifting"
        case .balanced:  return "Balanced"
        }
    }
}

// MARK: - CalmControlSettings

struct CalmControlSettings: Codable {
    var feed: FeedControlSettings
    var media: MediaIntensitySettings
    var presence: PresenceState
    var emotionalFilter: EmotionalEnergyFilter
    var quietProfileMode: Bool
    var updatedAt: Timestamp?

    static var defaults: CalmControlSettings {
        CalmControlSettings(
            feed: FeedControlSettings(),
            media: MediaIntensitySettings(),
            presence: .visible,
            emotionalFilter: .all,
            quietProfileMode: false,
            updatedAt: nil
        )
    }
}
