// MentorshipIntelligenceService.swift
// AMENAPP — Berean Intelligence OS
//
// Wires Berean AI signals into the Mentorship OS by persisting
// MentorshipMemoryNode records in two places:
//   1. users/{uid}/memoryGraph/{nodeId}         — mentee's private graph
//   2. mentorships/{mentorshipId}/signals/{nodeId} — mentor-side visibility
//
// INVARIANT: ALL mentorship memory nodes carry sensitivity = "SENSITIVE".
//            This is enforced by the MentorshipMemoryNode type itself (immutable
//            constant) and must be backed by the following Firestore rule:
//
//   match /mentorships/{mentorshipId}/signals/{signalId} {
//     allow read: if request.auth.uid == resource.data.uid          // mentee reads own
//              || request.auth.uid == get(/databases/$(database)/documents/
//                 bereanMentorships/$(mentorshipId)).data.mentorUid; // mentor reads mentee
//     allow write: if request.auth.uid == request.resource.data.uid; // only mentee writes
//   }
//
//   match /users/{uid}/memoryGraph/{nodeId} {
//     allow read, write: if request.auth.uid == uid; // no cross-user access
//   }

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Service

@MainActor
final class MentorshipIntelligenceService: ObservableObject {
    static let shared = MentorshipIntelligenceService()

    private let db          = Firestore.firestore()
    private let memoryGraph = BereanMemoryGraphService.shared
    private let bridge      = AmenOSBridge.shared

    private init() {}

    // MARK: - Record Signal

    /// Persists a MentorshipMemoryNode to both the mentee's memory graph and
    /// the mentorship-scoped signals sub-collection (mentor-side visibility).
    ///
    /// Sensitivity is always SENSITIVE — enforced by MentorshipMemoryNode's type.
    func recordSignal(
        _ signal: MentorSignalKind,
        mentorshipId: String,
        uid: String,
        data: [String: String]
    ) async throws {
        let node = MentorshipMemoryNode(
            uid: uid,
            mentorshipId: mentorshipId,
            signalKind: signal,
            data: data
        )

        // 1. Write to the mentee's private memory graph.
        //    BereanMemoryNode wraps the mentorship data; kind = .mentorship
        //    ensures it is labelled correctly in graph queries.
        let graphNode = BereanMemoryNode(
            uid: uid,
            kind: .mentorship,
            data: ["mentorshipId": mentorshipId,
                   "signalKind": signal.rawValue,
                   "nodeId": node.id]
                .merging(data) { existing, _ in existing },
            sensitivity: .sensitive      // INVARIANT — mentorship is always sensitive
        )
        try await memoryGraph.addNode(graphNode)

        // 2. Write the rich MentorshipMemoryNode to the mentorship's signals
        //    sub-collection so the mentor can review it from their side.
        //    Firestore rules (documented above) restrict reads to the mentee
        //    and the paired mentor only.
        try await db
            .collection("mentorships")
            .document(mentorshipId)
            .collection("signals")
            .document(node.id)
            .setData(node.toFirestore())
    }

    // MARK: - Session Completed

    /// Marks a mentoring session complete: records a progressUpdate signal and
    /// fires the Trust OS bridge so CommunityHealthService receives a positive signal.
    func sessionCompleted(mentorshipId: String, uid: String) async {
        do {
            try await recordSignal(
                .progressUpdate,
                mentorshipId: mentorshipId,
                uid: uid,
                data: ["completedAt": "\(Date().timeIntervalSince1970)"]
            )
        } catch {
            // Non-fatal — bridge call still fires even if Firestore write fails.
        }
        bridge.mentoringSessionCompleted(uid: uid)
    }

    // MARK: - Fetch Signals

    /// Returns all MentorshipMemoryNode records for the given mentorship from
    /// the mentee's memory graph (kind == MENTORSHIP && mentorshipId matches).
    func fetchSignals(mentorshipId: String, uid: String) async -> [MentorshipMemoryNode] {
        // Query the mentee's graph for kind == MENTORSHIP, then filter by mentorshipId.
        // Firestore compound index on (kind, mentorshipId) recommended for scale.
        do {
            let snapshot = try await db
                .collection("users")
                .document(uid)
                .collection("memoryGraph")
                .whereField("kind", isEqualTo: BereanMemoryNode.Kind.mentorship.rawValue)
                .whereField("data.mentorshipId", isEqualTo: mentorshipId)
                .getDocuments()
            return snapshot.documents.compactMap { decodeSignalFromGraph($0) }
        } catch {
            // Fallback: read directly from the signals sub-collection.
            return await fetchSignalsFromMentorshipCollection(mentorshipId: mentorshipId, uid: uid)
        }
    }

    /// Returns only .needsAttention and .openQuestion signals from the last 14 days.
    func pendingSignals(mentorshipId: String, uid: String) async -> [MentorshipMemoryNode] {
        let all         = await fetchSignals(mentorshipId: mentorshipId, uid: uid)
        let cutoff      = Date().timeIntervalSince1970 - (14 * 24 * 60 * 60)
        let actionable: Set<MentorSignalKind> = [.needsAttention, .openQuestion]
        return all.filter { $0.createdAt >= cutoff && actionable.contains($0.signalKind) }
    }

    // MARK: - Private helpers

    /// Fallback fetch directly from the mentorship's signals sub-collection.
    private func fetchSignalsFromMentorshipCollection(
        mentorshipId: String,
        uid: String
    ) async -> [MentorshipMemoryNode] {
        do {
            let snapshot = try await db
                .collection("mentorships")
                .document(mentorshipId)
                .collection("signals")
                .whereField("uid", isEqualTo: uid)
                .getDocuments()
            return snapshot.documents.compactMap { decodeSignalDirect($0) }
        } catch {
            return []
        }
    }

    /// Reconstructs a MentorshipMemoryNode from a memoryGraph document.
    private func decodeSignalFromGraph(_ doc: QueryDocumentSnapshot) -> MentorshipMemoryNode? {
        let d = doc.data()
        guard
            let uid           = d["uid"] as? String,
            let data          = d["data"] as? [String: String],
            let mentorshipId  = data["mentorshipId"],
            let signalRaw     = data["signalKind"],
            let signalKind    = MentorSignalKind(rawValue: signalRaw),
            let createdAt     = d["createdAt"] as? TimeInterval,
            let id            = d["id"] as? String
        else { return nil }

        return MentorshipMemoryNode(
            id: id,
            uid: uid,
            mentorshipId: mentorshipId,
            signalKind: signalKind,
            data: data,
            createdAt: createdAt
        )
    }

    /// Reconstructs a MentorshipMemoryNode from the mentorship signals sub-collection.
    private func decodeSignalDirect(_ doc: QueryDocumentSnapshot) -> MentorshipMemoryNode? {
        let d = doc.data()
        guard
            let id           = d["id"] as? String,
            let uid          = d["uid"] as? String,
            let mentorshipId = d["mentorshipId"] as? String,
            let signalRaw    = d["signalKind"] as? String,
            let signalKind   = MentorSignalKind(rawValue: signalRaw),
            let data         = d["data"] as? [String: String],
            let createdAt    = d["createdAt"] as? TimeInterval
        else { return nil }

        return MentorshipMemoryNode(
            id: id,
            uid: uid,
            mentorshipId: mentorshipId,
            signalKind: signalKind,
            data: data,
            createdAt: createdAt
        )
    }
}

// MARK: - MentorshipMemoryNode restore-from-Firestore extension
// The public init generates a fresh UUID + timestamp; decoding from Firestore
// requires preserving the stored id and createdAt.

private extension MentorshipMemoryNode {
    init(id: String, uid: String, mentorshipId: String,
         signalKind: MentorSignalKind, data: [String: String], createdAt: TimeInterval) {
        self.id           = id
        self.uid          = uid
        self.mentorshipId = mentorshipId
        self.signalKind   = signalKind
        self.data         = data
        self.createdAt    = createdAt
    }
}
