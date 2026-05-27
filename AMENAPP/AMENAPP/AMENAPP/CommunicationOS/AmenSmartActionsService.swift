// AmenSmartActionsService.swift
// AMEN App — Smart Collaboration Layer Phase 2
//
// READ-ONLY service for AI-extracted smart actions. Clients may update only
// the `status` field on an action (never any AI-authored content).
//
// Feature flag: RemoteKillSwitch.shared.threadActionExtractionEnabled (default OFF).
// Displayed statuses: .suggested and .accepted only — .dismissed + .completed filtered out.

import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class AmenSmartActionsService: ObservableObject {

    static let shared = AmenSmartActionsService()

    /// Only .suggested and .accepted actions are surfaced to callers.
    @Published var actions: [AmenSmartCollabAction] = []
    @Published var isLoading = false
    @Published var error: Error?

    private var actionsListener: ListenerRegistration?

    private init() {}

    // MARK: - Start Listening

    /// Attach real-time listener for the smartActions sub-collection.
    /// No-op if `RemoteKillSwitch.shared.threadActionExtractionEnabled` is OFF.
    func startListening(
        threadId: String,
        threadType: AmenSmartThreadType,
        spaceId: String?,
        channelId: String?
    ) {
        guard RemoteKillSwitch.shared.threadActionExtractionEnabled else {
            dlog("[SmartActionsService] threadActionExtractionEnabled is OFF — skipping listener.")
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
                dlog("[SmartActionsService] channel threadType requires spaceId + channelId.")
                isLoading = false
                return
            }
            collectionPath = AmenSmartCollaborationPaths.channelSmartActions(spaceId: spaceId, channelId: channelId)

        case .dm, .discussion:
            collectionPath = AmenSmartCollaborationPaths.dmSmartActions(conversationId: threadId)
        }

        actionsListener = db.collection(collectionPath).addSnapshotListener { [weak self] snapshot, err in
            guard let self else { return }
            self.isLoading = false

            if let err {
                self.error = err
                dlog("[SmartActionsService] listener error: \(err.localizedDescription)")
                return
            }

            guard let snapshot else { return }

            let decoded = snapshot.documents.compactMap { doc -> AmenSmartCollabAction? in
                try? doc.data(as: AmenSmartCollabAction.self)
            }

            // Filter: only surface .suggested and .accepted — hide .dismissed and .completed.
            self.actions = decoded.filter { action in
                action.status == .suggested || action.status == .accepted
            }
        }
    }

    // MARK: - Stop Listening

    func stopListening() {
        actionsListener?.remove()
        actionsListener = nil
        actions = []
        isLoading = false
        error = nil
    }

    // MARK: - Update Action Status

    /// Write ONLY the `status` and `updatedAt` fields — never any AI-authored content.
    /// Enforces the read-only contract: callers cannot overwrite AI fields.
    func updateActionStatus(
        _ actionId: String,
        threadId: String,
        threadType: AmenSmartThreadType,
        spaceId: String?,
        channelId: String?,
        newStatus: AmenSmartActionStatus
    ) async {
        guard RemoteKillSwitch.shared.threadActionExtractionEnabled else { return }

        let db = Firestore.firestore()

        let collectionPath: String
        switch threadType {
        case .channel:
            guard let spaceId, let channelId else { return }
            collectionPath = AmenSmartCollaborationPaths.channelSmartActions(spaceId: spaceId, channelId: channelId)
        case .dm, .discussion:
            collectionPath = AmenSmartCollaborationPaths.dmSmartActions(conversationId: threadId)
        }

        // Strict field allowlist — only status + updatedAt. Never any other field.
        let updateData: [String: Any] = [
            "status": newStatus.rawValue,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        do {
            try await db.collection(collectionPath).document(actionId).updateData(updateData)

            // Resolve actionType for analytics from the current in-memory list.
            let actionType = actions.first(where: { $0.id == actionId })?.actionType.rawValue ?? "unknown"

            switch newStatus {
            case .accepted:
                AMENAnalyticsService.shared.track(.smartActionAccepted(actionType: actionType))
            case .dismissed:
                AMENAnalyticsService.shared.track(.smartActionDismissed(actionType: actionType))
            default:
                break
            }

            dlog("[SmartActionsService] action \(actionId) status updated to \(newStatus.rawValue)")
        } catch {
            dlog("[SmartActionsService] status update failed: \(error.localizedDescription)")
            self.error = error
        }
    }

    // MARK: - Request Extraction

    /// Trigger server-side action extraction via Cloud Function.
    /// No-op if `threadActionExtractionEnabled` is OFF.
    func requestExtraction(
        threadId: String,
        threadType: AmenSmartThreadType,
        spaceId: String?,
        channelId: String?
    ) async {
        guard RemoteKillSwitch.shared.threadActionExtractionEnabled else { return }

        var payload: [String: Any] = [
            "threadId": threadId,
            "threadType": threadType.rawValue
        ]
        if let spaceId { payload["spaceId"] = spaceId }
        if let channelId { payload["channelId"] = channelId }

        do {
            _ = try await CloudFunctionsService.shared.call("extractThreadActions", data: payload)
            dlog("[SmartActionsService] extraction requested for \(threadId)")
        } catch {
            dlog("[SmartActionsService] extraction call failed: \(error.localizedDescription)")
            self.error = error
        }
    }
}
