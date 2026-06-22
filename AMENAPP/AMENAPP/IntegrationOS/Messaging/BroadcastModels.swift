// BroadcastModels.swift — AMEN IntegrationOS

import Foundation

struct BroadcastMessage: Codable, Identifiable {
    var id: String = UUID().uuidString
    let senderId: String
    let orgId: String?
    let spaceId: String?
    let channel: BroadcastChannel
    let subject: String?
    let body: String
    let scheduledAt: Date?
    let sentAt: Date?
    let status: BroadcastStatus
    let recipientCount: Int
    let createdAt: Date
}

enum BroadcastChannel: String, Codable, CaseIterable {
    case push = "push"
    case sms = "sms"
    case email = "email"
    case inApp = "in_app"

    var requiresScope: ConsentScope {
        switch self {
        case .push:   return .messagingPush
        case .sms:    return .messagingSMS
        case .email:  return .messagingEmail
        case .inApp:  return .messagingPush
        }
    }

    var displayName: String {
        switch self {
        case .push:   return "Push Notification"
        case .sms:    return "SMS"
        case .email:  return "Email"
        case .inApp:  return "In-App Message"
        }
    }

    var icon: String {
        switch self {
        case .push:   return "bell.fill"
        case .sms:    return "message.fill"
        case .email:  return "envelope.fill"
        case .inApp:  return "app.badge.fill"
        }
    }
}

enum BroadcastStatus: String, Codable {
    case draft, scheduled, sending, sent, failed, cancelled
}
