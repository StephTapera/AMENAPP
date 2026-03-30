
//
//  PrayerLiveActivityService.swift
//  AMENAPP
//
//  Bridges the Prayer feature with the Live Activity / Dynamic Island system.
//
//  Usage:
//    - Call startPrayerSession(for: post) when user long-presses a prayer card
//      or taps "Pray" with intent to focus.
//    - Call startPersonalPrayer() from DailyPrayerView when a prayer moment begins.
//    - The live activity stays alive until markPrayed() or snoozed.
//
//  Handles deep link actions arriving from the Dynamic Island expanded view:
//    amen://prayer?action=prayed&id=...
//    amen://prayer?action=snooze&id=...
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class PrayerLiveActivityService {

    static let shared = PrayerLiveActivityService()
    private init() {}

    // MARK: - Start a Prayer Session Live Activity

    /// Start a Live Activity for a community prayer request.
    func startPrayerSession(
        postId: String,
        authorName: String,
        content: String,
        amenCount: Int
    ) {
        guard LiveActivityManager.shared.isLiveActivitiesAvailable else { return }

        // Trim prayer content to a short title
        let shortTitle = String(content.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)

        LiveActivityManager.shared.startPrayerActivity(
            prayerId: postId,
            authorName: authorName,
            prayerTitle: shortTitle,
            amenCount: amenCount
        )

        // Begin listening for amen count updates
        listenForAmenUpdates(postId: postId)
    }

    /// Start a general personal prayer reminder (no specific post).
    func startPersonalPrayerSession(title: String) {
        guard LiveActivityManager.shared.isLiveActivitiesAvailable else { return }
        LiveActivityManager.shared.startPrayerActivity(
            prayerId: "",
            authorName: "Personal Prayer",
            prayerTitle: title,
            amenCount: 0
        )
    }

    // MARK: - Mark as Prayed (writes to Firestore)

    func markAsPrayed(postId: String) {
        // Update the Live Activity UI first (instant feedback)
        LiveActivityManager.shared.markPrayerAsAnswered()

        // Persist to Firestore
        guard !postId.isEmpty,
              let userId = Auth.auth().currentUser?.uid else { return }

        Task {
            do {
                let db = Firestore.firestore()
                try await db.collection("prayers")
                    .document(postId)
                    .collection("prayedBy")
                    .document(userId)
                    .setData([
                        "userId": userId,
                        "prayedAt": FieldValue.serverTimestamp()
                    ], merge: true)

                // Increment amen count on the post
                try await db.collection("posts").document(postId)
                    .updateData(["amenCount": FieldValue.increment(Int64(1))])
            } catch {
                dlog("⚠️ [PrayerLiveActivity] Failed to mark as prayed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Snooze

    func snoozePrayer() {
        LiveActivityManager.shared.snoozePrayerActivity()
    }

    // MARK: - Handle Deep Link Actions

    /// Called from AMENAPPApp.onOpenURL when an activity deep link fires.
    func handleDeepLink(url: URL) {
        guard url.scheme == "amen", url.host == "prayer" else { return }
        guard let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return }

        let action = queryItems.first(where: { $0.name == "action" })?.value
        let prayerId = queryItems.first(where: { $0.name == "id" })?.value ?? ""

        switch action {
        case "prayed":
            markAsPrayed(postId: prayerId)
        case "snooze":
            snoozePrayer()
        default:
            break
        }
    }

    // MARK: - Real-time Amen Count Listener

    private var amenListener: ListenerRegistration?

    private func listenForAmenUpdates(postId: String) {
        guard !postId.isEmpty else { return }
        amenListener?.remove()

        let db = Firestore.firestore()
        amenListener = db.collection("posts").document(postId)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let data = snapshot?.data(),
                      let count = data["amenCount"] as? Int else { return }
                Task { @MainActor in
                    self?.updateAmenCount(count)
                }
            }
    }

    private func updateAmenCount(_ count: Int) {
        LiveActivityManager.shared.updatePrayerAmenCount(count)
    }

    func stopListening() {
        amenListener?.remove()
        amenListener = nil
    }
}
