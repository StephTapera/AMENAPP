// AmenSmartContextService.swift
// AMEN App — Smart Collaboration Layer Phase 2
//
// READ-ONLY service for AI-generated thread smart context and summaries.
// Clients never write smartContext or summary documents — these are
// server-side Cloud Function outputs only (rule 1).
//
// Feature flag: RemoteKillSwitch.shared.messagesSmartContextEnabled (default OFF).

import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class AmenSmartContextService: ObservableObject {

    static let shared = AmenSmartContextService()

    @Published var currentContext: AmenThreadSmartContext?
    @Published var currentSummary: AmenSmartCollabSummary?
    @Published var isLoading = false
    @Published var error: Error?

    // Firestore listener registrations — removed in stopListening().
    private var contextListener: ListenerRegistration?
    private var summaryListener: ListenerRegistration?

    // Track whether the first-view analytics event has fired for the current listen session.
    private var hasTrackedContextView = false

    private init() {}

    // MARK: - Start Listening

    /// Attach real-time listeners for smartContext + summary documents.
    /// No-op if `RemoteKillSwitch.shared.messagesSmartContextEnabled` is OFF.
    func startListening(
        threadId: String,
        threadType: AmenSmartThreadType,
        spaceId: String?,
        channelId: String?
    ) {
        guard RemoteKillSwitch.shared.messagesSmartContextEnabled else {
            dlog("[SmartContextService] messagesSmartContextEnabled is OFF — skipping listener.")
            return
        }

        stopListening()
        hasTrackedContextView = false
        isLoading = true
        error = nil

        let db = Firestore.firestore()

        // Resolve Firestore paths based on threadType.
        let contextPath: String
        let summaryPath: String

        switch threadType {
        case .channel:
            guard let spaceId, let channelId else {
                dlog("[SmartContextService] channel threadType requires spaceId + channelId.")
                isLoading = false
                return
            }
            contextPath = AmenSmartCollaborationPaths.channelSmartContext(spaceId: spaceId, channelId: channelId)
            summaryPath = AmenSmartCollaborationPaths.channelSummary(spaceId: spaceId, channelId: channelId)

        case .dm, .discussion:
            contextPath = AmenSmartCollaborationPaths.dmSmartContext(conversationId: threadId)
            summaryPath = AmenSmartCollaborationPaths.dmSummary(conversationId: threadId)
        }

        // Attach smartContext listener.
        contextListener = db.document(contextPath).addSnapshotListener { [weak self] snapshot, err in
            guard let self else { return }
            self.isLoading = false

            if let err {
                self.error = err
                dlog("[SmartContextService] context listener error: \(err.localizedDescription)")
                return
            }

            guard let snapshot, snapshot.exists else {
                self.currentContext = nil
                return
            }

            do {
                let ctx = try snapshot.data(as: AmenThreadSmartContext.self)
                self.currentContext = ctx

                // Track first-view analytics event — no raw text in properties.
                if !self.hasTrackedContextView {
                    self.hasTrackedContextView = true
                    AMENAnalyticsService.shared.track(
                        .smartContextViewed(threadType: threadType.rawValue)
                    )
                }
            } catch {
                dlog("[SmartContextService] context decode error: \(error.localizedDescription)")
                self.error = error
            }
        }

        // Attach summary listener.
        summaryListener = db.document(summaryPath).addSnapshotListener { [weak self] snapshot, err in
            guard let self else { return }

            if let err {
                dlog("[SmartContextService] summary listener error: \(err.localizedDescription)")
                return
            }

            guard let snapshot, snapshot.exists else {
                self.currentSummary = nil
                return
            }

            do {
                let summary = try snapshot.data(as: AmenSmartCollabSummary.self)
                self.currentSummary = summary
            } catch {
                dlog("[SmartContextService] summary decode error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Stop Listening

    /// Remove all active Firestore listeners and reset published state.
    func stopListening() {
        contextListener?.remove()
        contextListener = nil

        summaryListener?.remove()
        summaryListener = nil

        currentContext = nil
        currentSummary = nil
        isLoading = false
        error = nil
        hasTrackedContextView = false
    }

    // MARK: - Request Regeneration

    /// Trigger server-side context regeneration via Cloud Function.
    /// No-op if `messagesSmartContextEnabled` is OFF.
    func requestRegeneration(
        threadId: String,
        threadType: AmenSmartThreadType,
        spaceId: String?,
        channelId: String?
    ) async {
        guard RemoteKillSwitch.shared.messagesSmartContextEnabled else { return }

        var payload: [String: Any] = [
            "threadId": threadId,
            "threadType": threadType.rawValue
        ]
        if let spaceId { payload["spaceId"] = spaceId }
        if let channelId { payload["channelId"] = channelId }

        do {
            _ = try await CloudFunctionsService.shared.call("generateThreadSummary", data: payload)
            AMENAnalyticsService.shared.track(.smartContextRefreshRequested(threadType: threadType.rawValue))
            dlog("[SmartContextService] regeneration requested for \(threadId)")
        } catch {
            dlog("[SmartContextService] regeneration call failed: \(error.localizedDescription)")
            self.error = error
        }
    }
}
