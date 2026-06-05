// CostGovernorService.swift — AMEN IntegrationOS
// Actor that implements CostGovernorProtocol. Tracks per-scope monthly spend.

import Foundation
import FirebaseFirestore
import FirebaseAuth

actor CostGovernorService: CostGovernorProtocol {
    static let shared = CostGovernorService()
    private init() {}

    private let db = Firestore.firestore()
    private var monthlyBudget: Double = 10.0
    private var currentSpend: Double = 0.0
    private var lastResetMonth: String = ""

    // MARK: - CostGovernorProtocol

    func canProceed(scope: ConsentScope, estimatedCost: Double) async -> Bool {
        await ensureResetIfNeeded()
        return (currentSpend + estimatedCost) <= monthlyBudget
    }

    func recordUsage(scope: ConsentScope, actualCost: Double) async {
        currentSpend += actualCost
        await persistUsage(scope: scope, cost: actualCost)
    }

    func currentBudget() async -> Double {
        await ensureResetIfNeeded()
        return monthlyBudget - currentSpend
    }

    func resetMonthly() async {
        currentSpend = 0.0
        lastResetMonth = currentMonthKey()
    }

    // MARK: - Private

    private func ensureResetIfNeeded() async {
        let month = currentMonthKey()
        if month != lastResetMonth {
            await resetMonthly()
        }
    }

    private func currentMonthKey() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM"
        return fmt.string(from: Date())
    }

    private func persistUsage(scope: ConsentScope, cost: Double) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let record: [String: Any] = [
            "uid": uid,
            "scope": scope.rawValue,
            "cost": cost,
            "recordedAt": Timestamp(date: Date()),
            "month": currentMonthKey()
        ]
        try? await db.collection("users").document(uid)
            .collection("integrationCostLedger")
            .addDocument(data: record)
    }
}
