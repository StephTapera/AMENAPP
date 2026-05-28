// AmenIntegrationModels.swift
// AMEN Integrations Platform — iOS model layer
// Mirrors integrations/types.ts on the backend

import Foundation

// MARK: - Provider

enum AmenIntegrationProvider: String, Codable, CaseIterable, Identifiable {
    case microsoft
    case zoom
    case slack

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .microsoft: return "Microsoft 365"
        case .zoom: return "Zoom"
        case .slack: return "Slack"
        }
    }

    var iconName: String {
        switch self {
        case .microsoft: return "microsoft_logo"
        case .zoom: return "zoom_logo"
        case .slack: return "slack_logo"
        }
    }

    var systemIconFallback: String {
        switch self {
        case .microsoft: return "calendar.badge.plus"
        case .zoom: return "video.fill"
        case .slack: return "bubble.left.and.bubble.right.fill"
        }
    }

    var description: String {
        switch self {
        case .microsoft: return "Schedule gatherings in Outlook and host Teams meetings"
        case .zoom: return "Create prayer rooms and video meetings with Zoom"
        case .slack: return "Send ministry reminders and notifications to your team"
        }
    }

    var supportsGatherings: Bool {
        switch self {
        case .microsoft, .zoom: return true
        case .slack: return false
        }
    }

    var supportsNotifications: Bool {
        switch self {
        case .slack: return true
        case .microsoft, .zoom: return false
        }
    }
}

// MARK: - Connection Status

enum AmenIntegrationStatus: String, Codable {
    case connected
    case expired
    case revoked
    case error
    case pending
    case notConnected

    var isUsable: Bool { self == .connected }

    var displayLabel: String {
        switch self {
        case .connected: return "Connected"
        case .expired: return "Reconnect"
        case .revoked: return "Disconnected"
        case .error: return "Error"
        case .pending: return "Connecting…"
        case .notConnected: return "Not connected"
        }
    }

    var isActionRequired: Bool {
        switch self {
        case .expired, .error: return true
        default: return false
        }
    }
}

// MARK: - Connection Record (from integrationsListConnections callable)

struct AmenIntegrationConnection: Identifiable, Codable {
    let accountId: String
    let provider: AmenIntegrationProvider
    var status: AmenIntegrationStatus
    let isOrgLevel: Bool
    let displayName: String?
    let email: String?
    let workspaceName: String?
    let connectedAt: Double?  // ms since epoch
    let expiresAt: Double?    // ms since epoch

    var id: String { accountId }

    var connectedAtDate: Date? {
        guard let ms = connectedAt else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    var isExpired: Bool {
        guard let ms = expiresAt else { return false }
        return Date(timeIntervalSince1970: ms / 1000) < Date()
    }
}

// MARK: - OAuth Response

struct AmenOAuthStartResponse: Codable {
    let authUrl: String
    let stateToken: String
}

struct AmenOAuthCompleteResponse: Codable {
    let success: Bool?
    let errorCode: String?
    let provider: String?
    let status: String?
    let displayName: String?
    let email: String?
}

// MARK: - AI Suggestions

struct AmenGatheringTitleSuggestion: Identifiable, Codable {
    let title: String
    let rationale: String?
    var id: String { title }
}

struct AmenGatheringAgendaItem: Identifiable, Codable {
    let durationMinutes: Int
    let activity: String
    let scriptureReference: String?
    var id: String { activity }
}

struct AmenGatheringScriptureSuggestion: Identifiable, Codable {
    let reference: String
    let theme: String
    let preview: String
    var id: String { reference }
}

// MARK: - Meeting Link

struct AmenGatheringMeetingLinkResult: Codable {
    let success: Bool?
    let errorCode: String?
    let gatheringId: String?
    let provider: String?
    let joinUrl: String?
    let providerMeetingId: String?
}

// MARK: - Error

enum AmenIntegrationClientError: LocalizedError {
    case authRequired
    case featureDisabled
    case providerNotConnected(AmenIntegrationProvider)
    case providerExpired(AmenIntegrationProvider)
    case providerRateLimited
    case providerTimeout
    case oauthStateMismatch
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .authRequired: return "Sign in required."
        case .featureDisabled: return "This feature is not yet available."
        case .providerNotConnected(let p): return "\(p.displayName) is not connected."
        case .providerExpired(let p): return "\(p.displayName) connection has expired. Please reconnect."
        case .providerRateLimited: return "Too many requests. Please try again shortly."
        case .providerTimeout: return "The connection timed out. Please try again."
        case .oauthStateMismatch: return "Authorization failed. Please try again."
        case .unknown(let code): return "Something went wrong (\(code))."
        }
    }

    static func from(_ errorCode: String, provider: AmenIntegrationProvider? = nil) -> AmenIntegrationClientError {
        switch errorCode {
        case "auth-required": return .authRequired
        case "feature-disabled": return .featureDisabled
        case "provider-not-connected": return provider.map { .providerNotConnected($0) } ?? .unknown(errorCode)
        case "provider-expired": return provider.map { .providerExpired($0) } ?? .unknown(errorCode)
        case "provider-rate-limited": return .providerRateLimited
        case "provider-timeout": return .providerTimeout
        case "oauth-state-invalid", "oauth-state-consumed", "oauth-state-expired": return .oauthStateMismatch
        default: return .unknown(errorCode)
        }
    }
}
