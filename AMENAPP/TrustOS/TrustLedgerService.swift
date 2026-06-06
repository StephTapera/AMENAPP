// TrustLedgerService.swift
// AMENAPP — Trust OS
//
// Writes and reads TrustLedgerEntry records in Firestore.
// Does NOT cross any OS boundary — no behavioral engine reads here.

import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class TrustLedgerService: ObservableObject {
    static let shared = TrustLedgerService()

    @Published var recentEntries: [TrustLedgerEntry] = []

    private let db = Firestore.firestore()

    private init() {}

    // MARK: - Write

    /// Fire-and-forget write of a single ledger entry to Firestore.
    /// Path: users/{uid}/trustLedger
    func writeEntry(_ entry: TrustLedgerEntry) async {
        let ref = db
            .collection("users")
            .document(entry.uid)
            .collection("trustLedger")

        do {
            try await ref.addDocument(data: entry.toFirestore())
        } catch {
            // Ledger writes are best-effort — log silently, never crash.
            print("[TrustLedger] write failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Read

    /// Fetches the most recent `limit` ledger entries for a user, ordered newest-first.
    /// Also updates `recentEntries` on the main actor.
    @discardableResult
    func fetchRecentEntries(uid: String, limit: Int) async -> [TrustLedgerEntry] {
        let ref = db
            .collection("users")
            .document(uid)
            .collection("trustLedger")
            .order(by: "createdAt", descending: true)
            .limit(to: limit)

        do {
            let snapshot = try await ref.getDocuments()
            let entries = snapshot.documents.compactMap { doc -> TrustLedgerEntry? in
                let d = doc.data()
                guard
                    let uid       = d["uid"]         as? String,
                    let action    = d["action"]       as? String,
                    let what      = d["whatChanged"]  as? String,
                    let why       = d["why"]          as? String,
                    let reversible = d["reversible"]  as? Bool,
                    let createdAt = d["createdAt"]    as? TimeInterval
                else { return nil }
                return TrustLedgerEntry(
                    uid: uid,
                    action: action,
                    whatChanged: what,
                    why: why,
                    reversible: reversible,
                    createdAt: createdAt
                )
            }
            recentEntries = entries
            return entries
        } catch {
            print("[TrustLedger] fetch failed: \(error.localizedDescription)")
            return []
        }
    }
}
