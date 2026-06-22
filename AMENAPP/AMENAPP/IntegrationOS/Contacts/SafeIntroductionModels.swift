// SafeIntroductionModels.swift — AMEN IntegrationOS

import Foundation

struct IntroductionRequest: Codable, Identifiable {
    var id: String = UUID().uuidString
    let requesterId: String
    let introducerUid: String
    let targetUid: String
    let message: String?
    let status: IntroductionStatus
    let createdAt: Date
    let resolvedAt: Date?
}

enum IntroductionStatus: String, Codable {
    case pending, accepted, declined, expired
}

struct ContactMatch: Codable, Identifiable {
    var id: String = UUID().uuidString
    let matchedUID: String
    let displayName: String
    let avatarURL: String?
    let mutualConnectionCount: Int
    let alreadyFollowing: Bool
}
