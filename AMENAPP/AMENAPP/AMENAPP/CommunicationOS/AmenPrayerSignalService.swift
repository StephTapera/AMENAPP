// AmenPrayerSignalService.swift
// AMEN App — Smart Collaboration Layer Phase 2
//
// Privacy-first service for AI-detected prayer signals.
//
// Privacy contract (enforced in snapshot filter):
//   - requestorId is NEVER exposed unless the caller IS the requestor.
//   - Only approved + non-anonymous signals from others are surfaced.
//   - prayerTheme is a category string only — raw prayer text is never stored here.
//   - requestorId is redacted to "[private]" for all non-owner signals.
//   - SmartContextSafety.requiresExplicitOptIn(.prayerSignal) == true — no auto-amplify.
//
// Feature flag: AMENFeatureFlags.shared.threadPrayerDetectionEnabled (default OFF).

import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class AmenPrayerSignalService: ObservableObject {

    static let shared = AmenPrayerSignalService()

    /// Privacy-filtered signals: caller sees own signals in full + others' only when
    /// approved AND non-anonymous, with requestorId redacted to "[private]".
    @Published var visibleSignals: [AmenThreadPrayerSignal] = []
    @Published var isLoading = false
    @Published var error: Error?

    private var signalsListener: ListenerRegistration?

    private init() {}

    // MARK: - Start Listening

    /// Attach real-time listener for the prayerSignals sub-collection.
    /// No-op if `AMENFeatureFlags.shared.threadPrayerDetectionEnabled` is OFF.
    func startListening(
        threadId: String,
        threadType: AmenSmartThreadType,
        spaceId: String?,
        channelId: String?
    ) {
        guard AMENFeatureFlags.shared.threadPrayerDetectionEnabled else {
            dlog("[PrayerSignalService] threadPrayerDetectionEnabled is OFF — skipping listener.")
            return
        }

        stopListening()
        isLoading = true
        error = nil

        let db = Firestore.firestore()

        let collectionPath: String
        switch threadType {
        case .channel:
            guard let spaceId, let channelId else {
                dlog("[PrayerSignalService] channel threadType requires spaceId + channelId.")
                isLoading = false
                return
            }
            collectionPath = AmenSmartCollaborationPaths.channelPrayerSignals(spaceId: spaceId, channelId: channelId)

        case .dm, .discussion:
            collectionPath = AmenSmartCollaborationPaths.dmPrayerSignals(conversationId: threadId)
        }

        signalsListener = db.collection(collectionPath).addSnapshotListener { [weak self] snapshot, err in
            guard let self else { return }
            self.isLoading = false

            if let err {
                self.error = err
                dlog("[PrayerSignalService] listener error: \(err.localizedDescription)")
                return
            }

            guard let snapshot else { return }

            let docs = snapshot.documents.compactMap { doc -> AmenThreadPrayerSignal? in
                try? doc.data(as: AmenThreadPrayerSignal.self)
            }

            // PRIVACY FILTER: Never expose requestorId unless caller IS the requestor.
            let currentUid = Auth.auth().currentUser?.uid
            self.visibleSignals = docs.compactMap { signal in
                if signal.requestorId == currentUid {
                    // Full access to own signal — requestorId is visible to its owner.
                    return signal
                }
                // For others: only show if approved AND non-anonymous.
                guard signal.moderationStatus == .approved,
                      !signal.isAnonymous else { return nil }
                // Return a copy with requestorId redacted — never expose to third parties.
                var redacted = signal
                redacted.requestorId = "[private]"
                return redacted
            }
        }
    }

    // MARK: - Stop Listening

    func stopListening() {
        signalsListener?.remove()
        signalsListener = nil
        visibleSignals = []
        isLoading = false
        error = nil
    }

    // MARK: - Request Detection

    /// Trigger server-side prayer signal detection for a specific message.
    /// No-op if `threadPrayerDetectionEnabled` is OFF.
    func requestDetection(
        threadId: String,
        threadType: AmenSmartThreadType,
        spaceId: String?,
        channelId: String?,
        messageId: String
    ) async {
        guard AMENFeatureFlags.shared.threadPrayerDetectionEnabled else { return }

        // No raw message text in the payload — only IDs.
        var payload: [String: Any] = [
            "threadId": threadId,
            "threadType": threadType.rawValue,
            "messageId": messageId
        ]
        if let spaceId { payload["spaceId"] = spaceId }
        if let channelId { payload["channelId"] = channelId }

        do {
            _ = try await CloudFunctionsService.shared.call("detectPrayerSignal", data: payload)
            dlog("[PrayerSignalService] detection requested for message \(messageId)")
        } catch {
            dlog("[PrayerSignalService] detection call failed: \(error.localizedDescription)")
            self.error = error
        }
    }

    // MARK: - Delete Own Signal

    /// A user may delete only their own signal document.
    /// No-op if `threadPrayerDetectionEnabled` is OFF.
    func deleteOwnSignal(
        signalId: String,
        threadId: String,
        threadType: AmenSmartThreadType,
        spaceId: String?,
        channelId: String?
    ) async {
        guard AMENFeatureFlags.shared.threadPrayerDetectionEnabled else { return }

        // Safety: only proceed if the caller is authenticated.
        guard let currentUid = Auth.auth().currentUser?.uid else { return }

        // Verify the signal belongs to the caller before attempting deletion.
        guard let signal = visibleSignals.first(where: { $0.id == signalId }),
              signal.requestorId == currentUid else {
            dlog("[PrayerSignalService] deleteOwnSignal: caller does not own signal \(signalId).")
            return
        }

        let db = Firestore.firestore()

        let collectionPath: String
        switch threadType {
        case .channel:
            guard let spaceId, let channelId else { return }
            collectionPath = AmenSmartCollaborationPaths.channelPrayerSignals(spaceId: spaceId, channelId: channelId)
        case .dm, .discussion:
            collectionPath = AmenSmartCollaborationPaths.dmPrayerSignals(conversationId: threadId)
        }

        do {
            try await db.collection(collectionPath).document(signalId).delete()
            AMENAnalyticsService.shared.track(.prayerSignalDismissed)
            dlog("[PrayerSignalService] signal \(signalId) deleted by owner.")
        } catch {
            dlog("[PrayerSignalService] delete failed: \(error.localizedDescription)")
            self.error = error
        }
    }
}
