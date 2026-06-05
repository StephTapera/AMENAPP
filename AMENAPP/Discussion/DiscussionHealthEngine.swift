// DiscussionHealthEngine.swift — AMEN App
import Foundation
import SwiftUI
import FirebaseFirestore
import FirebaseFunctions

enum HealthStatus: String, Codable {
    case healthy, active, heated, escalating, needsReview

    var dotColor: Color {
        switch self {
        case .healthy:     return .green
        case .active:      return Color.accentColor
        case .heated:      return .orange
        case .escalating:  return .red
        case .needsReview: return .purple
        }
    }

    var color: Color { dotColor }

    var icon: String {
        switch self {
        case .healthy:     return "checkmark.circle.fill"
        case .active:      return "flame"
        case .heated:      return "flame.fill"
        case .escalating:  return "exclamationmark.triangle.fill"
        case .needsReview: return "eye.fill"
        }
    }

    var label: String {
        switch self {
        case .healthy:     return "Healthy"
        case .active:      return "Active"
        case .heated:      return "Heated"
        case .escalating:  return "Escalating"
        case .needsReview: return "Needs Review"
        }
    }

    var slowModeNudgeText: String {
        switch self {
        case .heated:      return "This discussion is heating up. Take a breath before responding."
        case .escalating:  return "This discussion needs care. Consider pausing before you post."
        default:           return ""
        }
    }

    var requiresSlowMode: Bool { self == .heated || self == .escalating }
}

extension DiscussionHealthSnapshot {
    var isSlowModeActive: Bool { status.requiresSlowMode }
}

struct DiscussionHealthSnapshot: Codable, Sendable {
    var status: HealthStatus
    var escalationSignals: [String]
    var lastAnalyzedAt: Timestamp?
}

@MainActor
final class DiscussionHealthEngine {
    static let shared = DiscussionHealthEngine()
    private init() {}
    private let db = Firestore.firestore()
    private let functions = Functions.functions()

    var isEnabled: Bool { AMENFeatureFlags.shared.discussionHealthEnabled }

    func listenHealth(
        threadId: String,
        onChange: @escaping (DiscussionHealthSnapshot) -> Void
    ) -> ListenerRegistration {
        db.collection("threads").document(threadId)
            .collection("health").document("current")
            .addSnapshotListener { snap, _ in
                Task { @MainActor in
                    guard let snap, snap.exists,
                          let snapshot = try? snap.data(as: DiscussionHealthSnapshot.self) else { return }
                    onChange(snapshot)
                }
            }
    }

    func analyzeHealth(threadId: String) async {
        guard isEnabled else { return }
        let callable = functions.httpsCallable("analyzeDiscussionHealth")
        _ = try? await callable.call(["threadId": threadId])
    }
}
