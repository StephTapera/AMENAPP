// MARK: - Notification Service Ownership
// This service owns: prayerAnswered notifications — calling the onPrayerAnswered Cloud Function
//                    to fan out to all intercessors when a user marks a prayer as answered;
//                    checking NotificationSettingsService for the user's prayerAnswered preference
//                    before dispatching.
// It does NOT own: Any other prayer notification types (prayerReminder, prayerSupported),
//                  in-app notification writes, social-activity notifications, priority scoring,
//                  batching, or push delivery beyond invoking the Cloud Function.
// Canonical routing reference: See NotificationServiceMap.md

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

/// Calls the onPrayerAnswered Cloud Function to notify all intercessors.
final class PrayerAnsweredNotificationService {
    static let shared = PrayerAnsweredNotificationService()
    private init() {}

    private lazy var functions = Functions.functions()

    func notifyPrayerAnswered(prayerPostId: String, testimonyPostId: String, authorId: String) async {
        guard await NotificationSettingsService.shared.preference(for: "prayerAnswered") else { return }
        let callable = functions.httpsCallable("onPrayerAnswered")
        _ = try? await callable.call([
            "prayerPostId": prayerPostId,
            "testimonyPostId": testimonyPostId,
            "authorId": authorId
        ])
    }
}
