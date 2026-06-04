// DiscussionParticipationService.swift — AMEN App
import Foundation
import FirebaseRemoteConfig

enum ParticipationTier: String, Codable, Sendable {
    case observer, contributor, champion, leader

    var label: String {
        switch self {
        case .observer:    return "Observer"
        case .contributor: return "Contributor"
        case .champion:    return "Champion"
        case .leader:      return "Discussion Leader"
        }
    }

    var icon: String {
        switch self {
        case .observer:    return "eye"
        case .contributor: return "bubble.left"
        case .champion:    return "star.fill"
        case .leader:      return "crown.fill"
        }
    }
}

struct TierAchievement: Identifiable, Sendable {
    let id = UUID()
    let tier: ParticipationTier
    let unlockedAt: Date
    let reason: String
}

@MainActor
final class DiscussionParticipationService {
    static let shared = DiscussionParticipationService()
    private init() {}

    private(set) var currentTier: ParticipationTier = .observer
    private(set) var achievements: [TierAchievement] = []

    private var isEnabled: Bool {
        RemoteConfig.remoteConfig().configValue(forKey: "discussion_participation").boolValue
    }

    func recordActivity(commentCount: Int, helpfulCount: Int) {
        guard isEnabled else { return }
        let newTier: ParticipationTier
        if helpfulCount >= 10     { newTier = .leader }
        else if helpfulCount >= 5 { newTier = .champion }
        else if commentCount >= 3 { newTier = .contributor }
        else                      { newTier = .observer }
        guard newTier != currentTier else { return }
        achievements.append(TierAchievement(tier: newTier, unlockedAt: Date(), reason: "Active participation"))
        currentTier = newTier
    }
}
