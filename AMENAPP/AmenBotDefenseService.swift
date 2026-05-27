//
//  AmenBotDefenseService.swift
//  AMENAPP
//
//  Client-side bot defense integration.
//  Evaluates bot score before high-velocity actions.
//  Presents CAPTCHA challenge to suspected bots.
//  Strips bot engagement from ranking on client feed.
//

import Foundation
import SwiftUI
import FirebaseFunctions

@MainActor
final class AmenBotDefenseService: ObservableObject {

    static let shared = AmenBotDefenseService()

    private let functions = Functions.functions()
    private let flags = AmenSafetyFeatureFlags.shared

    @Published var currentBotScore: BotScore = .humanLikely
    @Published var requiresChallenge: Bool = false
    @Published var challengeCompleted: Bool = false

    // Recent comment texts for similarity check
    private var recentComments: [String] = []

    private init() {}

    // MARK: - Evaluate before action

    func evaluateBeforeAction(
        type: BotActionType,
        deviceId: String? = nil
    ) async -> BotEvaluationOutcome {
        guard flags.botDefenseEnabled else { return .proceed }

        let params: [String: Any] = [
            "actionType": type.rawValue,
            "deviceId": deviceId as Any,
            "recentCommentTexts": recentComments.suffix(10),
        ]

        do {
            let result = try await functions.httpsCallable("evaluateBotScore").call(params)
            guard let data = result.data as? [String: Any] else { return .proceed }

            let scoreStr = data["botScore"] as? String ?? "human_likely"
            let score = BotScore(rawValue: scoreStr) ?? .humanLikely
            let needsChallenge = data["requiresChallenge"] as? Bool ?? false
            let throttled = data["throttled"] as? Bool ?? false

            currentBotScore = score
            requiresChallenge = needsChallenge && flags.botChallengeEnabled

            if needsChallenge { return .challengeRequired }
            if throttled { return .throttled }
            return .proceed
        } catch {
            return .proceed
        }
    }

    // MARK: - Track recent comments for similarity detection

    func trackComment(_ text: String) {
        recentComments.append(text)
        if recentComments.count > 20 { recentComments.removeFirst() }
    }

    // MARK: - Challenge completion

    func markChallengeCompleted() {
        challengeCompleted = true
        requiresChallenge = false
    }
}

// MARK: - Types

enum BotActionType: String {
    case follow  = "follow"
    case like    = "like"
    case comment = "comment"
    case dm      = "dm"
    case post    = "post"
    case repost  = "repost"
}

enum BotEvaluationOutcome {
    case proceed
    case throttled
    case challengeRequired
}
