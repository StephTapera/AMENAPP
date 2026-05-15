import Foundation
import FirebaseFunctions
import FirebaseAnalytics

@MainActor
final class AmenFeedDirectionService: ObservableObject {
    static let shared = AmenFeedDirectionService()
    private let functions = Functions.functions()
    private init() {}

    // MARK: - Submit Feed Direction

    func submitFeedDirection(_ request: SubmitFeedDirectionRequest) async throws -> SubmitFeedDirectionResponse {
        let payload: [String: Any] = [
            "rawText": request.rawText,
            "composerContext": [
                "source": request.composerContext.source,
                "timezone": request.composerContext.timezone,
                "localHour": request.composerContext.localHour,
                "isSunday": request.composerContext.isSunday,
                "reduceMotionEnabled": request.composerContext.reduceMotionEnabled,
                "reduceTransparencyEnabled": request.composerContext.reduceTransparencyEnabled,
            ],
            "duration": request.duration.rawValue,
            "intensity": request.intensity.rawValue,
            "visibility": request.visibility.rawValue,
            "affectedSurfaces": request.affectedSurfaces.map(\.rawValue),
            "clientDetectionConfidence": request.clientDetectionConfidence,
        ]
        let result = try await functions.httpsCallable("submitFeedDirection").safeCall(payload)
        guard let data = result.data as? [String: Any] else {
            throw NSError(domain: "FeedIntelligence", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        return try decodeResponse(data)
    }

    // MARK: - Explain Why This Post

    func explainWhyThisPost(postId: String) async throws -> WhyThisPostResponse {
        let result = try await functions.httpsCallable("explainWhyThisPost").safeCall(["postId": postId])
        guard let data = result.data as? [String: Any] else {
            throw NSError(domain: "FeedIntelligence", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        return WhyThisPostResponse(
            postId: data["postId"] as? String ?? postId,
            title: data["title"] as? String ?? "Why this post?",
            reasons: data["reasons"] as? [String] ?? ["Part of your general recommendations."],
            feedSignals: data["feedSignals"] as? [String] ?? [],
            preferenceSignals: data["preferenceSignals"] as? [String] ?? [],
            safetyNotes: data["safetyNotes"] as? [String] ?? [],
            canAdjust: data["canAdjust"] as? Bool ?? true
        )
    }

    // MARK: - Adjust Post Recommendation Signal

    func adjustPostRecommendationSignal(postId: String, action: PostRecommendationAction) async throws {
        _ = try await functions.httpsCallable("adjustPostRecommendationSignal")
            .safeCall(["postId": postId, "action": action.rawValue])
        NotificationCenter.default.post(name: .feedIntelligenceDidUpdate, object: nil)
    }

    // MARK: - Get Feed Intelligence Summary

    func getFeedIntelligenceSummary() async throws -> FeedIntelligenceSummary {
        let result = try await functions.httpsCallable("getFeedIntelligenceSummary").safeCall([:])
        guard let data = result.data as? [String: Any] else {
            return .empty
        }
        return decodeSummary(data)
    }

    // MARK: - Reset Feed Preference

    func resetFeedPreference(scope: FeedResetScope) async throws {
        _ = try await functions.httpsCallable("resetFeedPreference").safeCall(["scope": scope.rawValue])
        NotificationCenter.default.post(name: .feedIntelligenceDidUpdate, object: nil)
    }

    // MARK: - Helpers

    private func decodeResponse(_ data: [String: Any]) throws -> SubmitFeedDirectionResponse {
        let affectedSurfacesRaw = data["affectedSurfaces"] as? [String] ?? []
        return SubmitFeedDirectionResponse(
            signalId: data["signalId"] as? String ?? UUID().uuidString,
            interpretedSummary: data["interpretedSummary"] as? String ?? "",
            intentType: FeedDirectionIntentType(rawValue: data["intentType"] as? String ?? "") ?? .unknown,
            topicsIncreased: data["topicsIncreased"] as? [String] ?? [],
            topicsDecreased: data["topicsDecreased"] as? [String] ?? [],
            modesActivated: data["modesActivated"] as? [String] ?? [],
            affectedSurfaces: affectedSurfacesRaw.compactMap { FeedSurface(rawValue: $0) },
            duration: FeedDirectionDuration(rawValue: data["duration"] as? String ?? "") ?? .today,
            intensity: FeedDirectionIntensity(rawValue: data["intensity"] as? String ?? "") ?? .medium,
            safetyNotice: data["safetyNotice"] as? String,
            confirmationTitle: data["confirmationTitle"] as? String ?? "Feed updated",
            confirmationBullets: data["confirmationBullets"] as? [String] ?? []
        )
    }

    private func decodeSummary(_ data: [String: Any]) -> FeedIntelligenceSummary {
        let healthData = data["feedHealth"] as? [String: Any] ?? [:]
        return FeedIntelligenceSummary(
            activeSignals: [],
            activeModes: data["activeModes"] as? [String] ?? [],
            boostedTopics: data["boostedTopics"] as? [String: Double] ?? [:],
            suppressedTopics: data["suppressedTopics"] as? [String: Double] ?? [:],
            feedHealth: FeedHealthState(
                reduceOutrage: healthData["reduceOutrage"] as? Bool ?? false,
                reduceRapidCuts: healthData["reduceRapidCuts"] as? Bool ?? false,
                preferCalmContent: healthData["preferCalmContent"] as? Bool ?? false,
                preserveDiversity: healthData["preserveDiversity"] as? Bool ?? true
            )
        )
    }
}

// MARK: - Supporting Types

enum PostRecommendationAction: String {
    case moreLikeThis = "more_like_this"
    case lessLikeThis = "less_like_this"
    case hideTopic = "hide_topic"
    case hideCreator = "hide_creator"
    case resetRelated = "reset_related"
}

enum FeedResetScope: String {
    case temporary, emotional, creator, topic, all
}

extension FeedIntelligenceSummary {
    static let empty = FeedIntelligenceSummary(
        activeSignals: [], activeModes: [], boostedTopics: [:], suppressedTopics: [:],
        feedHealth: FeedHealthState(reduceOutrage: false, reduceRapidCuts: false, preferCalmContent: false, preserveDiversity: true)
    )
}
