//
//  Feature08_ColdThreadRevival.swift
//  AMENAPP
//
//  Cold Thread Revival — on app foreground, reads server-written revivalNudges
//  and generates a private on-device banner for silent cold threads.
//  Never sends a push notification — purely local, ephemeral, privacy-preserving.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import Combine

// MARK: - Model

struct RevivalNudge: Identifiable {
    let id: String          // threadId
    let partnerName: String
    let topic: String
    let daysSilent: Int
    let createdAt: Date
    var shown: Bool
}

// MARK: - Manager

final class ColdThreadRevivalManager: ObservableObject {
    static let shared = ColdThreadRevivalManager()

    @Published var pendingNudge: RevivalNudge?

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    @AppStorage("shownRevivalNudgeIds") private var shownNudgeIdsRaw: String = ""

    private var shownNudgeIds: Set<String> {
        get { Set(shownNudgeIdsRaw.split(separator: ",").map(String.init)) }
        set { shownNudgeIdsRaw = newValue.joined(separator: ",") }
    }

    private init() {}

    // MARK: - Listen (called on app foreground)

    func startListening() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard listener == nil else { return }

        listener = db
            .collection("users").document(uid)
            .collection("revivalNudges")
            .whereField("shown", isEqualTo: false)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self else { return }
                let nudges: [RevivalNudge] = snap?.documents.compactMap { doc in
                    let d = doc.data()
                    return RevivalNudge(
                        id:          doc.documentID,
                        partnerName: d["partnerName"] as? String ?? "Someone",
                        topic:       d["topic"]       as? String ?? "",
                        daysSilent:  d["daysSilent"]  as? Int    ?? 14,
                        createdAt:   (d["createdAt"]  as? Timestamp)?.dateValue() ?? Date(),
                        shown:       d["shown"]       as? Bool   ?? false
                    )
                } ?? []

                // Show only the first unshown nudge per session
                if let nudge = nudges.first(where: { !self.shownNudgeIds.contains($0.id) }) {
                    DispatchQueue.main.async { self.pendingNudge = nudge }
                }
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    // MARK: - Dismiss

    func dismissNudge(_ nudge: RevivalNudge) {
        var ids = shownNudgeIds
        ids.insert(nudge.id)
        shownNudgeIds = ids

        pendingNudge = nil

        // Mark as shown server-side so it isn't returned again
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users").document(uid)
            .collection("revivalNudges").document(nudge.id)
            .updateData(["shown": true])
    }
}
