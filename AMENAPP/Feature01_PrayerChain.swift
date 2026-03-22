//
//  Feature01_PrayerChain.swift
//  AMENAPP
//
//  Prayer Chain Relay — long-press any message to start a prayer chain.
//  Members see live prayedBy list with avatar checkmarks.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import Combine

// MARK: - Model

struct PrayerChain: Identifiable {
    let id: String
    let threadId: String
    let requestText: String
    let requesterId: String
    var members: [String]
    var prayedBy: [String]
    let createdAt: Date
}

// MARK: - Manager

final class PrayerChainManager: ObservableObject {
    static let shared = PrayerChainManager()

    @Published var chainsByThread: [String: [PrayerChain]] = [:]

    private let db = Firestore.firestore()
    private var listeners: [String: ListenerRegistration] = [:]

    private init() {}

    // MARK: - Create

    func startPrayerChain(
        threadId: String,
        messageText: String,
        memberIds: [String]
    ) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let chainId = UUID().uuidString
        let data: [String: Any] = [
            "requestText": messageText,
            "requesterId": uid,
            "members":     memberIds,
            "prayedBy":    [],
            "createdAt":   FieldValue.serverTimestamp(),
        ]

        try await db
            .collection("messages").document(threadId)
            .collection("prayerChains").document(chainId)
            .setData(data)

        dlog("✅ [PrayerChain] Started chain \(chainId) in thread \(threadId)")
    }

    // MARK: - Mark Prayed

    func markPrayed(threadId: String, chainId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let chainRef = db
            .collection("messages").document(threadId)
            .collection("prayerChains").document(chainId)

        try await chainRef.updateData([
            "prayedBy":                    FieldValue.arrayUnion([uid]),
            "prayedLog.\(uid)":            FieldValue.serverTimestamp(),
        ])

        dlog("✅ [PrayerChain] \(uid) marked prayed for chain \(chainId)")
    }

    // MARK: - Listen

    func listenToChains(threadId: String) {
        guard listeners[threadId] == nil else { return }

        let listener = db
            .collection("messages").document(threadId)
            .collection("prayerChains")
            .addSnapshotListener { [weak self] snap, error in
                guard let self, let docs = snap?.documents else { return }

                let chains: [PrayerChain] = docs.compactMap { doc in
                    let d = doc.data()
                    return PrayerChain(
                        id:          doc.documentID,
                        threadId:    threadId,
                        requestText: d["requestText"]  as? String   ?? "",
                        requesterId: d["requesterId"]  as? String   ?? "",
                        members:     d["members"]      as? [String] ?? [],
                        prayedBy:    d["prayedBy"]     as? [String] ?? [],
                        createdAt:   (d["createdAt"]   as? Timestamp)?.dateValue() ?? Date()
                    )
                }

                DispatchQueue.main.async {
                    self.chainsByThread[threadId] = chains
                }
            }

        listeners[threadId] = listener
    }

    func stopListening(threadId: String) {
        listeners[threadId]?.remove()
        listeners.removeValue(forKey: threadId)
    }
}
