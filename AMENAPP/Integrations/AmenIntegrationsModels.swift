import Foundation

struct AmenIntegrationAccountSummary: Identifiable, Hashable {
    enum Provider: String, CaseIterable, Identifiable {
        case microsoft
        case zoom
        case slack

        var id: String { rawValue }

        var title: String {
            switch self {
            case .microsoft: "Microsoft 365"
            case .zoom: "Zoom"
            case .slack: "Slack"
            }
        }

        var subtitle: String {
            switch self {
            case .microsoft: "Outlook calendar and Teams meetings"
            case .zoom: "Prayer rooms, mentoring, and gatherings"
            case .slack: "Ministry alerts and staff workflows"
            }
        }

        var symbolName: String {
            switch self {
            case .microsoft: "calendar.badge.clock"
            case .zoom: "video.badge.waveform"
            case .slack: "number"
            }
        }
    }

    enum Status: String, Hashable {
        case connected
        case expired
        case revoked
        case error
        case notConnected

        var label: String {
            switch self {
            case .connected: "Connected"
            case .expired: "Expired"
            case .revoked: "Revoked"
            case .error: "Needs attention"
            case .notConnected: "Not connected"
            }
        }
    }

    let id: String
    let provider: Provider
    let status: Status
    let scopes: [String]
    let workspaceName: String?
    let expiresAtMillis: Double?

    static func placeholder(provider: Provider) -> AmenIntegrationAccountSummary {
        AmenIntegrationAccountSummary(
            id: "placeholder-\(provider.rawValue)",
            provider: provider,
            status: .notConnected,
            scopes: [],
            workspaceName: nil,
            expiresAtMillis: nil
        )
    }
}

struct AmenMeetingDraft: Hashable {
    var provider: AmenIntegrationAccountSummary.Provider
    var accountId: String
    var title: String
    var description: String
    var agenda: String
    var scriptureFocus: String
    var startTime: Date
    var endTime: Date
    var amenSpaceId: String?
    var privacyLevel: String

    static func defaultDraft(provider: AmenIntegrationAccountSummary.Provider, accountId: String) -> AmenMeetingDraft {
        AmenMeetingDraft(
            provider: provider,
            accountId: accountId,
            title: "Prayer Gathering",
            description: "A focused AMEN gathering for prayer, Scripture, and follow-up.",
            agenda: "Welcome\nScripture focus\nPrayer requests\nNext steps",
            scriptureFocus: "Acts 2:42",
            startTime: Date().addingTimeInterval(3600),
            endTime: Date().addingTimeInterval(5400),
            amenSpaceId: nil,
            privacyLevel: "private"
        )
    }
}
