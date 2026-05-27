// AmenGroupPulseService.swift
// AMEN App — Smart Collaboration Layer Phase 2
//
// READ-ONLY service for AI-computed group discussion pulse.
// Only applicable to .channel threadType — DMs do not have pulse.
//
// Feature flag: RemoteKillSwitch.shared.groupDiscussionPulseEnabled (default OFF).

import Foundation
import Combine
import FirebaseFirestore

@MainActor
final class AmenGroupPulseService: ObservableObject {

    static let shared = AmenGroupPulseService()

    @Published var currentPulse: GroupDiscussionPulse?
    @Published var isLoading = false
    @Published var error: Error?

    private var pulseListener: ListenerRegistration?

    private init() {}

    // MARK: - Start Listening

    /// Attach a real-time listener for the channel's pulse/main document.
    /// No-op if `RemoteKillSwitch.shared.groupDiscussionPulseEnabled` is OFF.
    /// threadType must be .channel for pulse to be meaningful.
    func startListening(spaceId: String, channelId: String) {
        guard RemoteKillSwitch.shared.groupDiscussionPulseEnabled else {
            dlog("[GroupPulseService] groupDiscussionPulseEnabled is OFF — skipping listener.")
            return
        }

        stopListening()
        isLoading = true
        error = nil

        let pulsePath = AmenSmartCollaborationPaths.channelPulse(spaceId: spaceId, channelId: channelId)
        let db = Firestore.firestore()

        pulseListener = db.document(pulsePath).addSnapshotListener { [weak self] snapshot, err in
            guard let self else { return }
            self.isLoading = false

            if let err {
                self.error = err
                dlog("[GroupPulseService] listener error: \(err.localizedDescription)")
                return
            }

            guard let snapshot, snapshot.exists else {
                self.currentPulse = nil
                return
            }

            do {
                let pulse = try snapshot.data(as: GroupDiscussionPulse.self)
                self.currentPulse = pulse
                AMENAnalyticsService.shared.track(
                    .groupPulseViewed(urgencyLevel: pulse.urgency.rawValue)
                )
            } catch {
                dlog("[GroupPulseService] decode error: \(error.localizedDescription)")
                self.error = error
            }
        }
    }

    // MARK: - Stop Listening

    func stopListening() {
        pulseListener?.remove()
        pulseListener = nil
        currentPulse = nil
        isLoading = false
        error = nil
    }

    // MARK: - Request Pulse Generation

    /// Trigger server-side pulse generation via Cloud Function.
    /// No-op if `groupDiscussionPulseEnabled` is OFF.
    func requestPulseGeneration(spaceId: String, channelId: String) async {
        guard RemoteKillSwitch.shared.groupDiscussionPulseEnabled else { return }

        let payload: [String: Any] = [
            "spaceId": spaceId,
            "channelId": channelId
        ]

        do {
            _ = try await CloudFunctionsService.shared.call("generateGroupPulse", data: payload)
            dlog("[GroupPulseService] pulse generation requested for channel \(channelId)")
        } catch {
            dlog("[GroupPulseService] pulse generation call failed: \(error.localizedDescription)")
            self.error = error
        }
    }
}
