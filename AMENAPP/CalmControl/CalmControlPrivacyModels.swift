import Foundation
import FirebaseFirestore

// MARK: - Privacy Settings
// Firestore path: users/{uid}/privacySettings/main

struct CalmPrivacySettings: Codable {
    var hideFollowerCount: Bool = false
    var hideFollowingCount: Bool = false
    var privateFollowingGraph: Bool = false
    var quietProfileMode: Bool = false
    var disableReadReceipts: Bool = false
    var presenceState: PresenceState = .visible
    var anonymousReflectionEnabled: Bool = false
    var updatedAt: Date = Date()
}

// MARK: - Feed Controls
// Firestore path: users/{uid}/feedControls/main

struct CalmFeedControls: Codable {
    var textOnlyMode: Bool = false
    var hidePhotosVideos: Bool = false
    var hideViralContent: Bool = false
    var noDebateFilter: Bool = false
    var motionReductionFeed: Bool = false
    var audioAutoplayDisabled: Bool = false
    var emotionalEnergyFilter: EmotionalEnergyLevel = .balanced
    var topicSaturations: [String: TopicSaturationLevel] = [:]
    var updatedAt: Date = Date()
}

enum EmotionalEnergyLevel: String, Codable, CaseIterable {
    case calm, balanced, uplifting, varied

    var label: String {
        switch self {
        case .calm:      return "Calm"
        case .balanced:  return "Balanced"
        case .uplifting: return "Uplifting"
        case .varied:    return "Varied"
        }
    }
}

enum TopicSaturationLevel: String, Codable, CaseIterable {
    case hidden, less, normal, more
}

