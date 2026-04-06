//
//  SupportSignal.swift
//  AMENAPP
//
//  A normalized signal event contributing to the user's support need score.
//  Stored at users/{userId}/support_signals/{signalId}. TTL: 14–30 days.
//  Never stores raw post content — only derived normalized attributes.
//

import Foundation

struct SupportSignal: Identifiable, Codable, Sendable {
    var id: String
    var signalType: SupportSignalType
    var sourceType: String             // "post", "prayer", "note", "behavior", "search"
    var sourceId: String?              // Opaque reference only (no raw content)
    var weight: Double                 // Adjusted weight 0.0–1.0
    var confidence: Double             // Classifier confidence 0.0–1.0
    var themes: [SupportTheme]
    var direction: SignalDirection
    var reasonCode: SupportReasonCode
    var createdAt: Date
    var expiresAt: Date?

    /// Effective contribution after confidence weighting.
    var effectiveWeight: Double {
        weight * confidence
    }

    /// Whether this signal has expired.
    var isExpired: Bool {
        guard let exp = expiresAt else { return false }
        return Date() > exp
    }
}

// MARK: - Factory

extension SupportSignal {
    static func make(
        type: SupportSignalType,
        sourceType: String,
        sourceId: String? = nil,
        themes: [SupportTheme] = [],
        confidence: Double = 0.7,
        reasonCode: SupportReasonCode = .recentVulnerablePost,
        ttlDays: Int = 14
    ) -> SupportSignal {
        SupportSignal(
            id: UUID().uuidString,
            signalType: type,
            sourceType: sourceType,
            sourceId: sourceId,
            weight: type.defaultWeight,
            confidence: confidence,
            themes: themes,
            direction: type.direction,
            reasonCode: reasonCode,
            createdAt: Date(),
            expiresAt: Calendar.current.date(byAdding: .day, value: ttlDays, to: Date())
        )
    }
}
