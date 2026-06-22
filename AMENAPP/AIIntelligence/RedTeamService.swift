// RedTeamService.swift
// AMENAPP
//
// Wave 6 — Red-Team reporting. A real submission flow into a real Firestore
// registry (redTeamReports/). The registry starts EMPTY and fills only with real
// submissions — no seeded "Hall of Fame". Recognition is awarded only by a human
// reviewer (recognitionAwarded is server-written; clients never set it true).
//
// Gated by AMENFeatureFlags.shared.redTeamSurfaceEnabled (default OFF).

import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class RedTeamService: ObservableObject {

    @Published private(set) var myReports: [RedTeamReport] = []
    @Published private(set) var isLoading = false

    private let db = Firestore.firestore()
    private var collection: CollectionReference { db.collection("redTeamReports") }

    func loadMine() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let snapshot = try await collection
                .whereField("reporterId", isEqualTo: uid)
                .order(by: "createdAt", descending: true)
                .getDocuments()
            myReports = snapshot.documents.compactMap { decode($0) }
        } catch {
            dlog("⚠️ [RedTeam] load failed: \(error.localizedDescription)")
        }
    }

    /// Submits a real report. status starts at .submitted; recognitionAwarded is
    /// always false on submit — only a human reviewer can later set it true.
    func submit(category: RedTeamCategory, description: String, reproSteps: String) async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        let payload: [String: Any] = [
            "category": category.rawValue,
            "description": String(description.prefix(2000)),
            "reproSteps": String(reproSteps.prefix(2000)),
            "status": RedTeamStatus.submitted.rawValue,
            "reporterId": uid,
            "recognitionAwarded": false,
            "createdAt": Timestamp(date: Date())
        ]
        do {
            _ = try await collection.addDocument(data: payload)
            await loadMine()
            return true
        } catch {
            dlog("⚠️ [RedTeam] submit failed: \(error.localizedDescription)")
            return false
        }
    }

    private func decode(_ doc: QueryDocumentSnapshot) -> RedTeamReport? {
        let d = doc.data()
        guard
            let categoryRaw = d["category"] as? String, let category = RedTeamCategory(rawValue: categoryRaw),
            let description = d["description"] as? String,
            let statusRaw = d["status"] as? String, let status = RedTeamStatus(rawValue: statusRaw),
            let reporterId = d["reporterId"] as? String
        else { return nil }
        return RedTeamReport(
            id: doc.documentID,
            category: category,
            description: description,
            reproSteps: d["reproSteps"] as? String ?? "",
            status: status,
            reporterId: reporterId,
            recognitionAwarded: d["recognitionAwarded"] as? Bool ?? false
        )
    }
}
