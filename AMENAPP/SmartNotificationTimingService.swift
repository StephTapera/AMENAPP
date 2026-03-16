//
//  SmartNotificationTimingService.swift
//  AMENAPP
//
//  Feature 9: Smart Notification Timing — sends pushes 30 min before
//  user's peak usage window based on historical open patterns.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

class SmartNotificationTimingService {
    static let shared = SmartNotificationTimingService()

    private let db = Firestore.firestore()
    private let cacheKey = "peakUsageHour"

    private init() {}

    // MARK: - Track App Opens

    /// Call on every app open to build usage pattern.
    func trackAppOpen() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let hour = Calendar.current.component(.hour, from: Date())
        let day = Calendar.current.component(.weekday, from: Date())

        Task {
            try? await db.collection("users").document(uid)
                .collection("usagePatterns").document("opens")
                .setData([
                    "hourCounts.\(hour)": FieldValue.increment(Int64(1)),
                    "dayCounts.\(day)": FieldValue.increment(Int64(1)),
                    "lastOpen": FieldValue.serverTimestamp(),
                    "totalOpens": FieldValue.increment(Int64(1)),
                ], merge: true)
        }
    }

    // MARK: - Get Optimal Send Time

    /// Returns the optimal hour (0-23) to send a notification.
    func getOptimalSendHour() async -> Int {
        // Check local cache
        if let cached = UserDefaults.standard.object(forKey: cacheKey) as? Int {
            return max(0, cached - 1) // 1 hour before peak (conservative approach)
        }

        guard let uid = Auth.auth().currentUser?.uid else { return 9 } // Default 9 AM

        do {
            let doc = try await db.collection("users").document(uid)
                .collection("usagePatterns").document("opens")
                .getDocument()

            guard let data = doc.data(),
                  let hourCounts = data["hourCounts"] as? [String: Int] else {
                return 9
            }

            // Find the hour with the most opens
            let peakHour = hourCounts.max { $0.value < $1.value }?.key ?? "9"
            let peak = Int(peakHour) ?? 9

            // Send 30 min before peak = previous hour
            let sendHour = peak > 0 ? peak - 1 : 23
            UserDefaults.standard.set(sendHour, forKey: cacheKey)
            return sendHour
        } catch {
            return 9
        }
    }

    /// Whether now is a good time to show an in-app nudge.
    func isNearPeakUsage() async -> Bool {
        let optimalHour = await getOptimalSendHour()
        let currentHour = Calendar.current.component(.hour, from: Date())
        return abs(currentHour - optimalHour) <= 1
    }
}
