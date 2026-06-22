// CommitmentConnectionService.swift
// AMEN — Commitment Connection Service
//
// Manages CommitmentObject lifecycle in Firestore at commitments/{id}.
// Flag-gated: AMENFeatureFlags.shared.commitmentConnections
// No shame language. Close-the-loop nudge fires exactly once per commitment.

import Foundation
import FirebaseFirestore

@MainActor
final class CommitmentConnectionService: ObservableObject {

    private let db = Firestore.firestore()

    // MARK: - Create

    func createCommitment(
        fromUid: String,
        toUid: String,
        kind: CommitmentKind,
        requestRef: String
    ) async throws -> CommitmentObject {
        guard AMENFeatureFlags.shared.commitmentConnections else {
            throw CommitmentConnectionError.featureDisabled
        }

        let id = UUID().uuidString
        let closeTheLoopAt = Date().addingTimeInterval(7 * 24 * 3600)
        let commitment = CommitmentObject(
            id: id,
            parties: [fromUid, toUid],
            kind: kind,
            loopState: .open,
            closeTheLoopAt: closeTheLoopAt,
            liveActivityEligible: false,
            createdAt: Date(),
            createdBy: fromUid
        )

        let data: [String: Any] = [
            "id": commitment.id,
            "parties": commitment.parties,
            "kind": commitment.kind.rawValue,
            "loopState": commitment.loopState.rawValue,
            "closeTheLoopAt": Timestamp(date: closeTheLoopAt),
            "liveActivityEligible": commitment.liveActivityEligible,
            "createdAt": Timestamp(date: commitment.createdAt),
            "createdBy": commitment.createdBy,
            "requestRef": requestRef
        ]

        try await db.collection("commitments").document(id).setData(data)
        return commitment
    }

    // MARK: - Nudge Scheduling

    func scheduleCloseTheLoopNudge(commitment: CommitmentObject) async {
        guard AMENFeatureFlags.shared.commitmentConnections else { return }
        guard commitment.loopState == .open else { return }

        let updateData: [String: Any] = ["nudgeScheduled": true]
        try? await db.collection("commitments").document(commitment.id).updateData(updateData)
    }

    // MARK: - Complete

    func completeCommitment(id: String) async throws {
        guard AMENFeatureFlags.shared.commitmentConnections else {
            throw CommitmentConnectionError.featureDisabled
        }

        let updateData: [String: Any] = [
            "loopState": CommitmentLoopState.closed.rawValue,
            "completedAt": Timestamp(date: Date())
        ]
        try await db.collection("commitments").document(id).updateData(updateData)

        SelahMomentService().trigger()
    }

    // MARK: - Lapse (gracefully)

    func lapseCommitmentGracefully(id: String) async throws {
        guard AMENFeatureFlags.shared.commitmentConnections else {
            throw CommitmentConnectionError.featureDisabled
        }

        let updateData: [String: Any] = [
            "loopState": CommitmentLoopState.lapsedGracefully.rawValue,
            "lapsedAt": Timestamp(date: Date())
        ]
        try await db.collection("commitments").document(id).updateData(updateData)
    }

    // MARK: - Live Stream

    func commitments(for uid: String) -> AsyncThrowingStream<[CommitmentObject], Error> {
        AsyncThrowingStream { continuation in
            guard AMENFeatureFlags.shared.commitmentConnections else {
                continuation.finish()
                return
            }

            let query = db.collection("commitments")
                .whereField("parties", arrayContains: uid)
                .order(by: "createdAt", descending: true)

            let listener = query.addSnapshotListener { snapshot, error in
                if let error = error {
                    continuation.finish(throwing: error)
                    return
                }
                guard let documents = snapshot?.documents else {
                    continuation.yield([])
                    return
                }

                let decoder = Firestore.Decoder()
                let objects: [CommitmentObject] = documents.compactMap { doc in
                    try? doc.data(as: CommitmentObject.self, decoder: decoder)
                }
                continuation.yield(objects)
            }

            continuation.onTermination = { _ in
                listener.remove()
            }
        }
    }
}

// MARK: - Error

enum CommitmentConnectionError: Error, LocalizedError {
    case featureDisabled

    var errorDescription: String? {
        switch self {
        case .featureDisabled:
            return "Commitment Connections is not available right now."
        }
    }
}
