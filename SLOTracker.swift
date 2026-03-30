//
//  SLOTracker.swift
//  AMENAPP
//
//  Feature 60: Error Budget Tracking — tracks SLOs (Service Level Objectives)
//  for auth, messaging, feed, and Berean. Alerts when thresholds are breached.
//
//  SLOs:
//  - Auth success rate: 99.9%
//  - Message delivery rate: 99.5%
//  - Feed load success: 99.8%
//  - Berean response success: 95.0%
//

import Foundation
import FirebaseFirestore

class SLOTracker {
    static let shared = SLOTracker()

    private var events: [String: (successes: Int, failures: Int)] = [:]
    private let db = Firestore.firestore()

    private init() {}

    enum SLOCategory: String {
        case auth = "auth"
        case messaging = "messaging"
        case feedLoad = "feedLoad"
        case berean = "berean"
        case imageLoad = "imageLoad"

        var target: Double {
            switch self {
            case .auth:      return 0.999
            case .messaging: return 0.995
            case .feedLoad:  return 0.998
            case .berean:    return 0.950
            case .imageLoad: return 0.990
            }
        }
    }

    // MARK: - Track Events

    func trackSuccess(_ category: SLOCategory) {
        var entry = events[category.rawValue] ?? (successes: 0, failures: 0)
        entry.successes += 1
        events[category.rawValue] = entry
    }

    func trackFailure(_ category: SLOCategory) {
        var entry = events[category.rawValue] ?? (successes: 0, failures: 0)
        entry.failures += 1
        events[category.rawValue] = entry

        // Check if SLO is breached
        checkSLO(category)
    }

    // MARK: - SLO Check

    private func checkSLO(_ category: SLOCategory) {
        guard let entry = events[category.rawValue] else { return }
        let total = entry.successes + entry.failures
        guard total >= 10 else { return } // Need minimum sample size

        let successRate = Double(entry.successes) / Double(total)
        if successRate < category.target {
            // SLO breached — log to Crashlytics
            CrashlyticsIntegration.setAppState(
                key: "slo_breach_\(category.rawValue)",
                value: String(format: "%.2f%% (target: %.1f%%)", successRate * 100, category.target * 100)
            )
            dlog("🚨 SLO BREACH: \(category.rawValue) at \(String(format: "%.2f%%", successRate * 100)) (target: \(String(format: "%.1f%%", category.target * 100)))")
        }
    }

    // MARK: - Flush to Firestore (periodic)

    /// Flush accumulated SLO data to Firestore for dashboard monitoring.
    func flushToFirestore() async {
        guard !events.isEmpty else { return }

        let dateKey = ISO8601DateFormatter().string(from: Date()).prefix(10) // YYYY-MM-DD

        for (category, entry) in events {
            let total = entry.successes + entry.failures
            guard total > 0 else { continue }

            try? await db.collection("sloMetrics").document("\(dateKey)_\(category)").setData([
                "category": category,
                "date": String(dateKey),
                "successes": entry.successes,
                "failures": entry.failures,
                "successRate": Double(entry.successes) / Double(total),
                "updatedAt": FieldValue.serverTimestamp(),
            ], merge: true)
        }
    }

    /// Get current success rate for a category.
    func successRate(for category: SLOCategory) -> Double? {
        guard let entry = events[category.rawValue] else { return nil }
        let total = entry.successes + entry.failures
        guard total > 0 else { return nil }
        return Double(entry.successes) / Double(total)
    }
}
