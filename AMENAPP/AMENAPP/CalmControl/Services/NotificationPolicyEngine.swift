import Foundation
import FirebaseAuth
import FirebaseFunctions
import SwiftUI

@MainActor
final class NotificationPolicyEngine: ObservableObject {
    static let shared = NotificationPolicyEngine()

    private var uid: String? { Auth.auth().currentUser?.uid }

    private init() {}

    // MARK: - Client-side Eligibility (fast path; server is authoritative)

    func checkEligibility(
        category: AmenRhythmNotificationCategory,
        settings: AmenNotificationSettings,
        rhythm: AmenSpiritualRhythm
    ) -> AmenNotificationEligibility {
        // Sabbath mode suppresses all non-essential categories
        if rhythm.sabbathModeEnabled && !category.isEssential {
            return .suppressed("Sabbath mode is active.")
        }

        // Inactivity pause suppresses all non-essential categories
        if rhythm.notificationsPausedDueToInactivity && !category.isEssential {
            return .suppressed("Notifications paused after 7 days of inactivity.")
        }

        // Quiet hours gate (22:00–07:00) for non-essential categories
        if settings.quietHoursEnabled && isInQuietHours() && !category.isEssential {
            return .suppressed("Quiet hours are active.")
        }

        // User-controlled category toggle
        if !settings.isCategoryEnabled(category) {
            return .suppressed("This notification category is turned off.")
        }

        // Notification intensity gate
        if !intensityAllows(category: category, intensity: settings.intensity) {
            return .suppressed("Current notification intensity setting.")
        }

        return .eligible
    }

    // MARK: - Server-side Eligibility Evaluation

    func evaluateEligibilityOnServer(category: AmenRhythmNotificationCategory) async -> AmenNotificationEligibility {
        guard let uid else { return .suppressed("Not authenticated.") }
        do {
            let callable = Functions.functions().httpsCallable("evaluateNotificationEligibility")
            let result = try await callable.call(["userId": uid, "category": category.rawValue])
            if let dict = result.data as? [String: Any],
               let eligible = dict["eligible"] as? Bool {
                if eligible { return .eligible }
                let reason = dict["reason"] as? String ?? "Not eligible."
                return .suppressed(reason)
            }
            return .eligible
        } catch {
            dlog("⚠️ NotificationPolicyEngine.evaluateEligibilityOnServer: \(error)")
            return .suppressed("Could not verify eligibility.")
        }
    }

    // MARK: - Private Helpers

    /// Returns true when the current hour falls within the fixed quiet window (22:00–07:00).
    private func isInQuietHours() -> Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        let start = 22
        let end = 7
        // Window crosses midnight: active from 22:00 through 06:59
        return hour >= start || hour < end
    }

    private func intensityAllows(
        category: AmenRhythmNotificationCategory,
        intensity: AmenNotificationIntensity
    ) -> Bool {
        switch intensity {
        case .minimal:
            return category == .dailyVerse || category == .quietReturn
        case .balanced:
            return category != .streakReminder && category != .communityDigest
        case .encouraging:
            return category != .communityDigest
        case .activeCommunity:
            return true
        }
    }
}

private func dlog(_ message: String) {
    #if DEBUG
    print(message)
    #endif
}
