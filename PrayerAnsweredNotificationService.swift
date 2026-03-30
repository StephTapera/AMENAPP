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
