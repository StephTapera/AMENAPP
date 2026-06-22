// SettingsAnalytics.swift
// AMEN — Settings/Safety system · Foundation
//
// Categorical-only analytics for Settings (S6): journal/prayer/message/crisis
// free-text is NEVER sent. Only short, enumerated tokens (keys, booleans, choices)
// are allowed; anything that looks like free text is dropped before logging.

import Foundation
import FirebaseAnalytics

enum SettingsAnalytics {

    /// Max length for any single categorical param value. Longer values are dropped (assumed free text).
    private static let maxValueLength = 40

    /// Log a canonical Settings analytics event with categorical params only.
    static func log(_ name: AnalyticsEventName, params: [String: String] = [:]) {
        Analytics.logEvent(name.rawValue, parameters: sanitized(params))
    }

    /// Strip any value that is too long or contains free-text markers (whitespace runs, newlines).
    private static func sanitized(_ params: [String: String]) -> [String: String] {
        var clean: [String: String] = [:]
        for (key, value) in params {
            guard value.count <= maxValueLength else { continue }
            if value.contains("\n") || value.contains("  ") { continue }
            // Allow short enumerated tokens only (letters, digits, _ . : -).
            let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.:-")
            if value.unicodeScalars.allSatisfy({ allowed.contains($0) }) {
                clean[key] = value
            }
        }
        return clean
    }
}
