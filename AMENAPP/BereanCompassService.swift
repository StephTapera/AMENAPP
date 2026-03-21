// BereanCompassService.swift
// AMENAPP
//
// Berean Compass — manipulation pattern detection for DMs.
// Analyzes conversation threads for the 5-stage manipulation arc.
// Privacy-first: never stores message content, only pattern scores.
// Analysis is done via Cloud Function "bereanCompassAnalyze".

import Foundation
import Combine
import FirebaseFunctions

// MARK: - ManipulationStage

enum ManipulationStage: Equatable {
    /// No manipulation pattern detected — no intervention needed.
    case none
    /// A concerning stage was detected. Only stages 1 (isolation) and 2 (identity shift)
    /// trigger a gentle UI intervention. Stage 3+ are detected but escalate quietly.
    case awareness(stage: Int)

    var stageNumber: Int {
        switch self {
        case .none:            return 0
        case .awareness(let s): return s
        }
    }

    var shouldShowUI: Bool {
        switch self {
        case .none:            return false
        case .awareness(let s): return s == 1 || s == 2
        }
    }
}

// MARK: - CompassResource

struct CompassResource: Identifiable, Codable {
    let id: String
    let title: String
    let icon: String
    let deepLink: String

    init(id: String = UUID().uuidString, title: String, icon: String, deepLink: String) {
        self.id = id
        self.title = title
        self.icon = icon
        self.deepLink = deepLink
    }

    // Standard resources surfaced by the Compass
    static let trustCircle = CompassResource(
        title: "Talk to a Trusted Adult",
        icon: "person.crop.circle.badge.checkmark",
        deepLink: "amen://crisis-resources"
    )
    static let safetyGuide = CompassResource(
        title: "Online Safety Guide",
        icon: "shield.fill",
        deepLink: "amen://resources/safety"
    )
    static let counselingLine = CompassResource(
        title: "Crisis Text Line",
        icon: "message.fill",
        deepLink: "amen://crisis-resources"
    )
}

// MARK: - CompassSignal

struct CompassSignal {
    let stage: ManipulationStage
    let interventionMessage: String
    let patterns: [String]
    let resources: [CompassResource]

    var shouldIntervene: Bool { stage.shouldShowUI }

    static let noSignal = CompassSignal(
        stage: .none,
        interventionMessage: "",
        patterns: [],
        resources: []
    )
}

// MARK: - CompassMessage

/// A single message entry prepared for Compass analysis.
/// Only `isFromOtherParty == true` messages are checked for manipulation patterns.
/// Own messages are analyzed only for compliance/dependency responses.
struct CompassMessage {
    let senderUID: String
    let text: String
    let isFromOtherParty: Bool

    // Trim to 200 chars max before sending to Cloud Function — privacy + cost control.
    var trimmedText: String {
        String(text.prefix(200))
    }
}

// MARK: - BereanCompassService

@MainActor
final class BereanCompassService: ObservableObject {

    static let shared = BereanCompassService()

    @Published private(set) var isAnalyzing: Bool = false

    private let functions = Functions.functions()

    private init() {}

    // MARK: - Public API

    /// Analyzes an array of CompassMessages for manipulation arc patterns.
    /// Returns `.noSignal` on any failure (fail-safe — never blocks the chat).
    /// - Parameter messages: The conversation messages to analyze.
    /// - Returns: A `CompassSignal` describing detected patterns and intervention guidance.
    func analyzeConversation(_ messages: [CompassMessage]) async -> CompassSignal {
        guard !messages.isEmpty else { return .noSignal }

        isAnalyzing = true
        defer { isAnalyzing = false }

        // Build the payload — trimmed text, no UIDs sent to server
        let messagePayload: [[String: Any]] = messages.map { msg in
            [
                "text": msg.trimmedText,
                "isFromOther": msg.isFromOtherParty
            ]
        }

        do {
            let result = try await functions
                .httpsCallable("bereanCompassAnalyze")
                .safeCall(["messages": messagePayload])

            guard let data = result.data as? [String: Any] else {
                return .noSignal
            }

            return parseSignal(from: data)

        } catch {
            // Fail-safe: a compass analysis failure should never disrupt chat UX.
            // Log silently, return no signal.
            return .noSignal
        }
    }

    // MARK: - Private Parsing

    private func parseSignal(from data: [String: Any]) -> CompassSignal {
        let stageNumber = (data["stage"] as? Int) ?? 0
        let patternsRaw = (data["patterns"] as? [String]) ?? []
        let intervention = (data["intervention"] as? String) ?? ""
        let resourcesRaw = (data["resources"] as? [[String: String]]) ?? []

        // Map stage number → ManipulationStage
        let stage: ManipulationStage
        if stageNumber <= 0 {
            stage = .none
        } else {
            stage = .awareness(stage: stageNumber)
        }

        // Only surface UI for stage 1–2 as specified
        guard stage.shouldShowUI else {
            return .noSignal
        }

        // Parse resources from Cloud Function response
        let resources: [CompassResource] = resourcesRaw.compactMap { dict in
            guard
                let title = dict["title"],
                let icon = dict["icon"],
                let deepLink = dict["deepLink"]
            else { return nil }
            return CompassResource(title: title, icon: icon, deepLink: deepLink)
        }

        // Fall back to standard resources if the function didn't provide any
        let finalResources = resources.isEmpty
            ? [CompassResource.trustCircle, CompassResource.safetyGuide]
            : resources

        return CompassSignal(
            stage: stage,
            interventionMessage: intervention,
            patterns: patternsRaw,
            resources: finalResources
        )
    }
}
