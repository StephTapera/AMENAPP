import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

// MARK: - BereanSmartChannelHook
//
// Runs on COMMUNAL and MONITORED channel messages only.
// NEVER reads sacredMessages or keyMaterial subcollections — those are unreadable by design.
//
// Four features (Prompt 5):
//   1. Prayer request detection → offer to author (opt-in, never forced)
//   2. Scripture auto-linking  → reads scriptureRefs written by the Cloud Function
//   3. Group catch-up summary  → on-demand; calls bereanChatProxy
//   4. Host discussion questions → host-only; before/during meetings

@MainActor
final class BereanSmartChannelHook: ObservableObject {
    static let shared = BereanSmartChannelHook()
    private let db = Firestore.firestore()
    private lazy var functions = Functions.functions()

    private init() {}

    // MARK: - 1. Prayer Request Detection

    /// Returns a PrayerRequestOffer if Berean detects a prayer need in the message.
    /// Returns nil on any error or non-prayer content — silent failure is intentional.
    func detectChannelPrayerRequest(in message: CommunalMessage, groupId: String) async -> PrayerRequestOffer? {
        guard message.guardianDecision == .allow || message.guardianDecision == .allowWithSupport else { return nil }
        let data: [String: Any] = [
            "mode": "prayerDetect",
            "message": message.text,
            "groupId": groupId
        ]
        guard let result = try? await functions.httpsCallable("bereanChatProxy").call(data),
              let dict = result.data as? [String: Any],
              let isPrayer = dict["isPrayerRequest"] as? Bool, isPrayer,
              let suggested = dict["suggestedText"] as? String else { return nil }
        return PrayerRequestOffer(message: message, groupId: groupId, suggestedText: suggested)
    }

    /// Saves the prayer request to Firestore and links it back to the source message.
    /// followUpDays: how many days until Berean nudges the author for an update.
    func saveChannelPrayerRequest(_ offer: PrayerRequestOffer, followUpDays: Int = 7) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let followUpAt = Calendar.current.date(byAdding: .day, value: followUpDays, to: Date())
        let ref = db.collection("prayerRequests").document()
        let request = ChannelPrayerRequest(groupId: offer.groupId, authorUid: uid, text: offer.suggestedText,
                                    createdAt: Date(), status: .open, followUpAt: followUpAt,
                                    channelId: offer.message.channelId,
                                    sourceMessageId: offer.message.id ?? "")
        try ref.setData(from: request)
        if let msgId = offer.message.id {
            try await db.collection("channels").document(offer.message.channelId)
                .collection("messages").document(msgId)
                .updateData(["prayerRequestId": ref.documentID])
        }
    }

    func markAnswered(requestId: String) async throws {
        try await db.collection("prayerRequests").document(requestId)
            .updateData(["status": PrayerStatus.answered.rawValue])
    }

    func fetchOpenChannelPrayerRequests(groupId: String) async throws -> [ChannelPrayerRequest] {
        let snap = try await db.collection("prayerRequests")
            .whereField("groupId", isEqualTo: groupId)
            .whereField("status", isEqualTo: PrayerStatus.open.rawValue)
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: ChannelPrayerRequest.self) }
    }

    func listenChannelPrayerRequests(groupId: String, handler: @escaping ([ChannelPrayerRequest]) -> Void) -> ListenerRegistration {
        db.collection("prayerRequests")
            .whereField("groupId", isEqualTo: groupId)
            .whereField("status", isEqualTo: PrayerStatus.open.rawValue)
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .addSnapshotListener { snap, _ in
                handler(snap?.documents.compactMap { try? $0.data(as: ChannelPrayerRequest.self) } ?? [])
            }
    }

    // MARK: - 2. Scripture Auto-linking
    // scriptureRefs are written to CommunalMessage by the Guardian/Berean Cloud Function.
    // This method fetches the verse text for display in ScriptureLinkChip.

    func fetchVerseText(for reference: String) async -> String? {
        let data: [String: Any] = ["mode": "verseText", "reference": reference, "translation": "KJV"]
        guard let result = try? await functions.httpsCallable("bereanChatProxy").call(data),
              let dict = result.data as? [String: Any],
              let text = dict["verseText"] as? String else { return nil }
        return text
    }

    // MARK: - 3. Group Catch-Up

    /// Generates a summary of unread messages in a communal channel.
    /// Includes gist + open prayer requests + key decisions.
    func generateCatchUp(channelId: String, unreadCount: Int) async throws -> String {
        let data: [String: Any] = [
            "mode": "groupCatchUp",
            "channelId": channelId,
            "unreadCount": unreadCount
        ]
        let result = try await functions.httpsCallable("bereanChatProxy").call(data)
        guard let dict = result.data as? [String: Any],
              let summary = dict["summary"] as? String else { throw BereanSmartError.noSummary }
        return summary
    }

    // MARK: - 4. Host Discussion Questions (host-only; suggestions only, never auto-posted)

    func generateDiscussionQuestions(passage: String, groupId: String) async throws -> [String] {
        let data: [String: Any] = [
            "mode": "studyQuestions",
            "passage": passage,
            "groupId": groupId
        ]
        let result = try await functions.httpsCallable("bereanChatProxy").call(data)
        guard let dict = result.data as? [String: Any],
              let questions = dict["questions"] as? [String] else { throw BereanSmartError.noQuestions }
        return questions
    }
}

// MARK: - Errors

enum BereanSmartError: LocalizedError {
    case noSummary, noQuestions

    var errorDescription: String? {
        switch self {
        case .noSummary: return "Couldn't generate a summary right now."
        case .noQuestions: return "Couldn't generate discussion questions right now."
        }
    }
}
