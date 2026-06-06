// AmenLiveService.swift
// AMENAPP — Amen Live Firestore service
//
// Manages a real-time Firestore snapshot listener on amen_live_sessions.
// Publishes active sessions for the user's church/org network.
//
// Firestore rules needed (for human operator):
// match /amen_live_sessions/{sessionId} {
//   allow read: if isSignedIn();
//   allow write: if false; // CF Admin SDK only
// }
//
// Usage:
//   AmenLiveService.shared.startListening(for: ["churchId1", "churchId2"])
//   // observe activeSessions via Combine or AmenLiveViewModel
//   AmenLiveService.shared.stopListening()

import Foundation
import FirebaseFirestore
import FirebaseFunctions

// MARK: - AmenLiveServiceError

enum AmenLiveServiceError: LocalizedError {
    case invalidResponse
    case unauthenticated
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:      return "Received an unexpected response from the server."
        case .unauthenticated:      return "You must be signed in to view live sessions."
        case .serverError(let msg): return msg
        }
    }
}

// MARK: - AmenLiveService

/// Real-time Firestore service for amen_live_sessions.
///
/// Maintains one snapshot listener per `startListening` call.
/// The listener is removed on `stopListening` or dealloc.
/// All published writes happen on the MainActor.
@MainActor
final class AmenLiveService: ObservableObject {

    static let shared = AmenLiveService()

    /// Currently active sessions for the user's churches/orgs.
    /// Maximum 3 sessions (server-enforced via getActiveSessions CF; client caps here as well).
    @Published var activeSessions: [AmenLiveSession] = []

    private var listenerRegistration: ListenerRegistration?
    private let functions = Functions.functions()

    private init() {}

    // MARK: - startListening

    /// Attach a Firestore real-time listener for active sessions associated with
    /// the given church/org IDs. Replaces any existing listener.
    ///
    /// - Parameter churchIds: Array of Firestore IDs for the user's churches/orgs.
    ///   Passing an empty array removes any existing listener and clears sessions.
    func startListening(for churchIds: [String]) {
        stopListening()

        guard !churchIds.isEmpty else {
            activeSessions = []
            return
        }

        let db = Firestore.firestore()

        // Firestore `whereField:in:` supports at most 30 values.
        // The user's church list is typically 1–3 churches; slice defensively.
        let safeIds = Array(churchIds.prefix(30))

        let query = db.collection("amen_live_sessions")
            .whereField("isActive", isEqualTo: true)
            .whereField("hostId", in: safeIds)

        listenerRegistration = query.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }

            if let error = error {
                // Log the error but do not surface it to the user — the banner
                // simply stays hidden when live sessions can't be fetched.
                print("[AmenLiveService] Snapshot listener error: \(error.localizedDescription)")
                return
            }

            guard let snapshot = snapshot else { return }

            let sessions: [AmenLiveSession] = snapshot.documents.compactMap { doc in
                self.decodeSession(from: doc)
            }

            // Cap at 3 sessions to avoid overwhelming the banner system.
            // Server-side getActiveSessions also enforces this limit, but
            // we guard here in case the listener returns more.
            Task { @MainActor in
                self.activeSessions = Array(sessions.prefix(3))
            }
        }
    }

    // MARK: - stopListening

    /// Detach the Firestore snapshot listener and clear active sessions.
    func stopListening() {
        listenerRegistration?.remove()
        listenerRegistration = nil
        activeSessions = []
    }

    // MARK: - recordAction

    /// Calls the `recordLiveAction` CF callable to log a user action on a live session.
    ///
    /// - Parameters:
    ///   - sessionId: The Firestore ID of the session.
    ///   - action:    String identifier for the action (e.g., "joined", "prayed").
    ///   - targetId:  The entity ID the action targets (e.g., session.actionTarget).
    func recordAction(sessionId: String, action: String, targetId: String) async throws {
        let callable = functions.httpsCallable("recordLiveAction")
        let payload: [String: Any] = [
            "sessionId": sessionId,
            "action":    action,
            "targetId":  targetId
        ]
        _ = try await callable.call(payload)
    }

    // MARK: - Private helpers

    private func decodeSession(from doc: QueryDocumentSnapshot) -> AmenLiveSession? {
        let data = doc.data()

        guard
            let title       = data["title"] as? String,
            let typeRaw     = data["type"] as? String,
            let type        = AmenLiveType(rawValue: typeRaw),
            let hostId      = data["hostId"] as? String,
            let hostName    = data["hostName"] as? String,
            let startedAt   = data["startedAt"] as? Double,
            let isActive    = data["isActive"] as? Bool,
            let backingId   = data["backingEntityId"] as? String,
            let backingKind = data["backingEntityKind"] as? String,
            let actionLabel = data["actionLabel"] as? String,
            let actionHandler = data["actionHandler"] as? String,
            let actionTarget  = data["actionTarget"] as? String
        else {
            print("[AmenLiveService] Skipping malformed session doc: \(doc.documentID)")
            return nil
        }

        return AmenLiveSession(
            id:                doc.documentID,
            title:             title,
            subtitle:          data["subtitle"] as? String,
            type:              type,
            hostId:            hostId,
            hostName:          hostName,
            startedAt:         startedAt,
            scheduledEndAt:    data["scheduledEndAt"] as? Double,
            isActive:          isActive,
            backingEntityId:   backingId,
            backingEntityKind: backingKind,
            actionLabel:       actionLabel,
            actionHandler:     actionHandler,
            actionTarget:      actionTarget
        )
    }
}
