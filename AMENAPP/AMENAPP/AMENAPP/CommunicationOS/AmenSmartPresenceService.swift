// AmenSmartPresenceService.swift
// AMEN App — Smart Collaboration Layer Phase 2
//
// Approximate presence service backed by Firestore (not RTDB).
// The existing RealtimeDatabaseService handles RTDB connectivity; this service
// handles richer Smart Collaboration presence with a hard 30-minute TTL.
//
// Security contract:
//   - Users write ONLY their own presence document.
//   - expiresAt is hard-capped at now + 30 minutes — no long-duration tracking.
//   - Expired snapshots are filtered out of participantPresence.
//   - The calling user's own snapshot is excluded from participantPresence
//     (they manage their own state locally).
//   - States are approximate only — no exact behavioral tracking.
//
// Feature flag: RemoteKillSwitch.shared.smartPresenceEnabled (default OFF).

import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class AmenSmartPresenceService: ObservableObject {

    static let shared = AmenSmartPresenceService()

    /// Other participants' non-expired presence snapshots. Excludes calling user.
    @Published var participantPresence: [AmenThreadPresenceSnapshot] = []
    @Published var error: Error?

    private var presenceListener: ListenerRegistration?

    /// Hard cap on presence duration — 30 minutes.
    private static let maxPresenceDurationSeconds: TimeInterval = 30 * 60

    private init() {}

    // MARK: - Start Listening

    /// Attach a real-time listener for all presence documents in the thread.
    /// Filters out expired snapshots and the calling user's own snapshot.
    /// No-op if `RemoteKillSwitch.shared.smartPresenceEnabled` is OFF.
    func startListening(
        threadId: String,
        threadType: AmenSmartThreadType,
        spaceId: String?,
        channelId: String?
    ) {
        guard RemoteKillSwitch.shared.smartPresenceEnabled else {
            dlog("[SmartPresenceService] smartPresenceEnabled is OFF — skipping listener.")
            return
        }

        stopListening()
        error = nil

        let db = Firestore.firestore()
        let collectionPath = Self.presenceCollectionPath(
            threadId: threadId,
            threadType: threadType,
            spaceId: spaceId,
            channelId: channelId
        )

        guard let collectionPath else {
            dlog("[SmartPresenceService] channel threadType requires spaceId + channelId.")
            return
        }

        let currentUid = Auth.auth().currentUser?.uid

        presenceListener = db.collection(collectionPath).addSnapshotListener { [weak self] snapshot, err in
            guard let self else { return }

            if let err {
                self.error = err
                dlog("[SmartPresenceService] listener error: \(err.localizedDescription)")
                return
            }

            guard let snapshot else { return }

            let now = Date()
            self.participantPresence = snapshot.documents.compactMap { doc -> AmenThreadPresenceSnapshot? in
                guard let snapshotData = try? doc.data(as: AmenThreadPresenceSnapshot.self) else { return nil }

                // Exclude calling user's own presence from the participant list.
                if let currentUid, snapshotData.userId == currentUid { return nil }

                // Filter expired snapshots — approximate presence has a hard TTL.
                guard snapshotData.expiresAt.dateValue() > now else { return nil }

                return snapshotData
            }
        }
    }

    // MARK: - Stop Listening

    func stopListening() {
        presenceListener?.remove()
        presenceListener = nil
        participantPresence = []
        error = nil
    }

    // MARK: - Update Own Presence

    /// Write the calling user's own presence document.
    /// Enforces: expiresAt = min(now + 30 min, any requested expiry).
    /// No-op if `smartPresenceEnabled` is OFF or if the user is not authenticated.
    func updateOwnPresence(
        state: AmenSmartPresenceState,
        threadId: String,
        threadType: AmenSmartThreadType,
        spaceId: String?,
        channelId: String?
    ) async {
        guard RemoteKillSwitch.shared.smartPresenceEnabled else { return }
        guard let currentUid = Auth.auth().currentUser?.uid else { return }

        let ownPresencePath = Self.ownPresencePath(
            threadId: threadId,
            threadType: threadType,
            spaceId: spaceId,
            channelId: channelId,
            userId: currentUid
        )

        guard let ownPresencePath else {
            dlog("[SmartPresenceService] channel threadType requires spaceId + channelId.")
            return
        }

        // Hard cap at 30 minutes from now — no long-duration presence tracking.
        let cappedExpiry = Date().addingTimeInterval(Self.maxPresenceDurationSeconds)

        let data: [String: Any] = [
            "userId": currentUid,
            "state": state.rawValue,
            "updatedAt": FieldValue.serverTimestamp(),
            // Firestore Timestamp from the capped Date.
            "expiresAt": Timestamp(date: cappedExpiry)
        ]

        do {
            try await Firestore.firestore().document(ownPresencePath).setData(data)
            AMENAnalyticsService.shared.track(.smartPresenceUpdated(stateCategory: state.rawValue))
            dlog("[SmartPresenceService] presence updated: \(state.rawValue) expires \(cappedExpiry)")
        } catch {
            dlog("[SmartPresenceService] updateOwnPresence failed: \(error.localizedDescription)")
            self.error = error
        }
    }

    // MARK: - Clear Own Presence

    /// Delete the calling user's presence document when leaving a thread.
    /// No-op if `smartPresenceEnabled` is OFF or if the user is not authenticated.
    func clearOwnPresence(
        threadId: String,
        threadType: AmenSmartThreadType,
        spaceId: String?,
        channelId: String?
    ) async {
        guard RemoteKillSwitch.shared.smartPresenceEnabled else { return }
        guard let currentUid = Auth.auth().currentUser?.uid else { return }

        let ownPresencePath = Self.ownPresencePath(
            threadId: threadId,
            threadType: threadType,
            spaceId: spaceId,
            channelId: channelId,
            userId: currentUid
        )

        guard let ownPresencePath else { return }

        do {
            try await Firestore.firestore().document(ownPresencePath).delete()
            dlog("[SmartPresenceService] own presence cleared for \(threadId)")
        } catch {
            dlog("[SmartPresenceService] clearOwnPresence failed: \(error.localizedDescription)")
            self.error = error
        }
    }

    // MARK: - Path Helpers

    /// Returns the Firestore collection path for all presence documents in a thread.
    private static func presenceCollectionPath(
        threadId: String,
        threadType: AmenSmartThreadType,
        spaceId: String?,
        channelId: String?
    ) -> String? {
        switch threadType {
        case .channel:
            guard let spaceId, let channelId else { return nil }
            // Derive collection path by dropping the userId segment from the document path.
            return "spaces/\(spaceId)/channels/\(channelId)/presence"
        case .dm, .discussion:
            return "conversations/\(threadId)/presence"
        }
    }

    /// Returns the full Firestore document path for the calling user's own presence doc.
    private static func ownPresencePath(
        threadId: String,
        threadType: AmenSmartThreadType,
        spaceId: String?,
        channelId: String?,
        userId: String
    ) -> String? {
        switch threadType {
        case .channel:
            guard let spaceId, let channelId else { return nil }
            return AmenSmartCollaborationPaths.channelPresence(spaceId: spaceId, channelId: channelId, userId: userId)
        case .dm, .discussion:
            return AmenSmartCollaborationPaths.dmPresence(conversationId: threadId, userId: userId)
        }
    }
}
