//
//  PrayerRequestLiveActivityManager.swift
//  AMENAPP
//
//  Manages push-driven Prayer Request Live Activities (Phase 2) and
//  push-to-start token observation (Phase 3, iOS 17.2+).
//  Distinct from PrayerLiveActivityService to avoid touching the legacy
//  posts/{id}.amenCount / amen://prayer?action=… path.
//
//  Phase 2 — startActivity(for:) requests an activity with pushType: .token,
//  then persists the APNs push token to Firestore so the server can send
//  live-activity updates when prayingCount changes.
//
//  Phase 3 — observePushToStartTokens() reads pushToStartTokenUpdates for
//  PrayerRequestAttributes and writes each token to users/{uid}/ptsTokens
//  so onPrayerRequestCreated can start the activity on a user's device
//  without opening the app.
//

import Foundation
import ActivityKit
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class PrayerRequestLiveActivityManager {
    static let shared = PrayerRequestLiveActivityManager()
    private init() {}

    private var activitiesById: [String: ActivityKit.Activity<PrayerRequestAttributes>] = [:]
    private var tokenObservers: [String: Task<Void, Never>] = [:]
    private var pushToStartObserver: Task<Void, Never>?

    // MARK: - Phase 2: Start activity for a given request

    func startActivity(for requestId: String, requesterName: String, title: String,
                       initialCount: Int = 0) async {
        guard AMENFeatureFlags.shared.liveActivityPrayerRequestEnabled,
              ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // End any running activity for this request id first.
        await endActivity(for: requestId)

        let attrs = PrayerRequestAttributes(requestId: requestId,
                                            requesterName: requesterName,
                                            title: title)
        let state = PrayerRequestAttributes.ContentState(
            prayingCount: initialCount,
            encouragementCount: 0,
            isAnswered: false
        )

        guard let activity = try? ActivityKit.Activity.request(
            attributes: attrs,
            content: .init(state: state, staleDate: nil),
            pushType: .token
        ) else { return }

        activitiesById[requestId] = activity

        // Observe push token updates and persist each one to Firestore.
        tokenObservers[requestId] = Task { [weak self] in
            for await tokenData in activity.pushTokenUpdates {
                await self?.persistPushToken(tokenData, requestId: requestId)
            }
        }
    }

    // MARK: - Phase 2: End activity

    func endActivity(for requestId: String) async {
        guard let activity = activitiesById[requestId] else { return }
        tokenObservers[requestId]?.cancel()
        tokenObservers[requestId] = nil
        await activity.end(nil, dismissalPolicy: .immediate)
        activitiesById[requestId] = nil

        // Remove the push token from Firestore so APNs stops delivering to this device.
        await deletePushToken(requestId: requestId)
    }

    // MARK: - Phase 3: Push-to-Start token observation (iOS 17.2+)

    @available(iOS 17.2, *)
    func observePushToStartTokens() {
        guard AMENFeatureFlags.shared.liveActivityPushToStartEnabled else { return }
        pushToStartObserver?.cancel()
        pushToStartObserver = Task { [weak self] in
            for await tokenData in ActivityKit.Activity<PrayerRequestAttributes>.pushToStartTokenUpdates {
                await self?.persistPushToStartToken(tokenData)
            }
        }
    }

    func stopObservingPushToStartTokens() {
        pushToStartObserver?.cancel()
        pushToStartObserver = nil
    }

    // MARK: - Private helpers

    private func persistPushToken(_ tokenData: Data, requestId: String) async {
        let hex = tokenData.map { String(format: "%02x", $0) }.joined()
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try? await Firestore.firestore()
            .collection("prayerRequests").document(requestId)
            .collection("liveActivityTokens").document(hex)
            .setData(["uid": uid, "at": FieldValue.serverTimestamp()], merge: true)
    }

    private func deletePushToken(requestId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let tokens = try? await Firestore.firestore()
            .collection("prayerRequests").document(requestId)
            .collection("liveActivityTokens")
            .whereField("uid", isEqualTo: uid)
            .getDocuments()
        for doc in tokens?.documents ?? [] {
            try? await doc.reference.delete()
        }
    }

    @available(iOS 17.2, *)
    private func persistPushToStartToken(_ tokenData: Data) async {
        let hex = tokenData.map { String(format: "%02x", $0) }.joined()
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try? await Firestore.firestore()
            .collection("users").document(uid)
            .collection("ptsTokens").document(hex)
            .setData(["at": FieldValue.serverTimestamp()], merge: true)
    }
}
