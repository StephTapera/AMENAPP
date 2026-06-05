// DiscussionParticipationService.swift — AMEN App
import Foundation
import SwiftUI
import FirebaseFunctions

enum ParticipationTier: String, Codable, CaseIterable {
    case none, observer, participant, contributor, mentor, expert, leader, host

    var displayName: String {
        switch self {
        case .none:        return ""
        case .observer:    return "Observer"
        case .participant: return "Participant"
        case .contributor: return "Contributor"
        case .mentor:      return "Mentor"
        case .expert:      return "Expert"
        case .leader:      return "Community Leader"
        case .host:        return "Host"
        }
    }

    var icon: String {
        switch self {
        case .none:        return ""
        case .observer:    return "eye"
        case .participant: return "bubble.left"
        case .contributor: return "star"
        case .mentor:      return "person.2.circle"
        case .expert:      return "checkmark.seal"
        case .leader:      return "crown"
        case .host:        return "house"
        }
    }

    var color: Color {
        switch self {
        case .none:        return .clear
        case .observer:    return Color.white.opacity(0.4)
        case .participant: return Color.white.opacity(0.6)
        case .contributor: return .blue
        case .mentor:      return .green
        case .expert:      return Color(hex: "#C9A84C")
        case .leader:      return .purple
        case .host:        return Color(hex: "#C9A84C")
        }
    }

    var showsInComposer: Bool { self != .none && self != .observer }
}

@MainActor
final class DiscussionParticipationService {
    static let shared = DiscussionParticipationService()
    private init() {}
    private let functions = Functions.functions()

    var isEnabled: Bool { AMENFeatureFlags.shared.participationTiersEnabled }

    func getTier(threadId: String) async -> ParticipationTier {
        guard isEnabled else { return .none }
        let callable = functions.httpsCallable("computeReputation")
        guard let result = try? await callable.call(["threadId": threadId]),
              let data = result.data as? [String: Any],
              let tierRaw = data["tier"] as? String,
              let tier = ParticipationTier(rawValue: tierRaw) else {
            return .participant
        }
        return tier
    }
}
