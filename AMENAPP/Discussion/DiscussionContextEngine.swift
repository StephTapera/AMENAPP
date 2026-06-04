// DiscussionContextEngine.swift — AMEN App
import Foundation
import FirebaseRemoteConfig

@MainActor
final class DiscussionContextEngine {
    static let shared = DiscussionContextEngine()
    private init() {}

    private var isEnabled: Bool {
        RemoteConfig.remoteConfig().configValue(forKey: "discussion_context_engine").boolValue
    }

    func scoreComment(_ commentId: String, body: String) -> ContextScore {
        guard isEnabled else {
            return ContextScore(commentId: commentId, level: .none, score: 0, reasons: [])
        }
        let score = min(Double(body.count) / 500.0, 1.0)
        let level: ContextLevel = score > 0.6 ? .high : score > 0.3 ? .moderate : .low
        return ContextScore(commentId: commentId, level: level, score: score, reasons: [])
    }
}
