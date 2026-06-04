// DiscussionHealthEngine.swift — AMEN App
import SwiftUI
import FirebaseRemoteConfig

enum HealthStatus: String, Codable, Sendable {
    case healthy, caution, unhealthy, unknown

    var label: String {
        switch self {
        case .healthy:   return "Healthy"
        case .caution:   return "Caution"
        case .unhealthy: return "Needs Attention"
        case .unknown:   return ""
        }
    }

    var color: Color {
        switch self {
        case .healthy:   return Color(hex: "#4CAF50")
        case .caution:   return Color(hex: "#C9A84C")
        case .unhealthy: return .red
        case .unknown:   return Color.white.opacity(0.3)
        }
    }

    var icon: String {
        switch self {
        case .healthy:   return "heart.fill"
        case .caution:   return "exclamationmark.triangle"
        case .unhealthy: return "xmark.circle"
        case .unknown:   return ""
        }
    }
}

struct DiscussionHealthSnapshot: Sendable {
    let status: HealthStatus
    let commentCount: Int
    let helpfulRatio: Double
    let isSlowModeActive: Bool
    let summary: String
}

@MainActor
final class DiscussionHealthEngine {
    static let shared = DiscussionHealthEngine()
    private init() {}

    private var isEnabled: Bool {
        RemoteConfig.remoteConfig().configValue(forKey: "discussion_health_engine").boolValue
    }

    func snapshot(commentCount: Int, helpfulCount: Int, duplicateFlags: Int) -> DiscussionHealthSnapshot {
        guard isEnabled else {
            return DiscussionHealthSnapshot(
                status: .unknown, commentCount: commentCount,
                helpfulRatio: 0, isSlowModeActive: false, summary: ""
            )
        }
        let ratio = commentCount > 0 ? Double(helpfulCount) / Double(commentCount) : 0
        let isSlowMode = duplicateFlags > 3
        let status: HealthStatus
        if duplicateFlags > 5 { status = .unhealthy }
        else if duplicateFlags > 2 { status = .caution }
        else { status = .healthy }
        let summary = status == .healthy ? "Discussion is going well." : "Consider reviewing recent comments."
        return DiscussionHealthSnapshot(
            status: status, commentCount: commentCount,
            helpfulRatio: ratio, isSlowModeActive: isSlowMode, summary: summary
        )
    }
}
