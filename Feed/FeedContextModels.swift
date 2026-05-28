import Foundation
import FirebaseFirestore

struct FeedPreferences: Codable {
    var showCrisis: Bool
    var showGiving: Bool
    var showWellness: Bool
    var showSupport: Bool
    var showBibleStudy: Bool
    var priorityTags: [String]
    var muteUsers: [String]
    var blockTags: [String]
    var lastFeedRankingAt: Timestamp?

    static var defaults: FeedPreferences {
        FeedPreferences(
            showCrisis: false,
            showGiving: true,
            showWellness: true,
            showSupport: true,
            showBibleStudy: true,
            priorityTags: [],
            muteUsers: [],
            blockTags: [],
            lastFeedRankingAt: nil
        )
    }
}

struct FeedContextAction: Codable {
    var action: String
    var timestamp: Timestamp?
    var metadata: [String: String]
}

enum FeedPriorityTag: String, CaseIterable {
    case disasterRelief = "Disaster Relief"
    case anxietySupport = "Anxiety Support"
    case grief = "Grief"
    case internationalWork = "International Work"
    case youthMinistry = "Youth Ministry"
    case addictionRecovery = "Addiction Recovery"
    case communityDevelopment = "Community Development"
    case mentalHealth = "Mental Health"
    var rawDisplayName: String { rawValue }
}
