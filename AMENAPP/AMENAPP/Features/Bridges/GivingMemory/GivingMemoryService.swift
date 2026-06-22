// GivingMemoryService.swift
// AMEN — Features/Bridges/GivingMemory
//
// Giving Memory Layer — records completed gifts as timeline milestones.
// Payment rails remain unchanged; this is the memory layer only.
// // STRIPE-DECISION-PENDING: in-app donation rails would attach at markGiftComplete()

import Foundation
import FirebaseAuth
import FirebaseFirestore

actor GivingMemoryService {

    // MARK: - Singleton

    static let shared = GivingMemoryService()

    // MARK: - Install

    /// Wires the ContextBus subscription. Call once from AppDelegate / App init.
    func install() {
        Task {
            let stream = await ContextBus.shared.subscribe(to: [.giftCompleted])
            for await signal in stream {
                let enabled = await MainActor.run { AMENFeatureFlags.ctx_giving_receipts_enabled }
                guard enabled else { continue }
                await recordGift(from: signal)
            }
        }
    }

    // MARK: - Public API

    /// Called when a gift is completed. Writes the timeline milestone and accrues the year summary.
    /// // STRIPE-DECISION-PENDING: payment confirmation data passes through here
    func markGiftComplete(
        giftID: String,
        amount: Double,
        currency: String,
        causeID: String,
        causeName: String,
        orgEIN: String?
    ) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        let year = Calendar.current.component(.year, from: Date())

        // Write timeline milestone
        var milestone: [String: Any] = [
            "giftID": giftID,
            "amount": amount,
            "currency": currency,
            "causeID": causeID,
            "causeName": causeName,
            "completedAt": FieldValue.serverTimestamp(),
            "type": "gift"
        ]
        if let ein = orgEIN {
            milestone["orgEIN"] = ein
        }

        try? await db.collection("givingTimeline")
            .document(uid)
            .collection("milestones")
            .document(giftID)
            .setData(milestone)

        // Accrue to year summary
        let summaryRef = db.collection("givingSummary").document("\(uid)_\(year)")
        try? await summaryRef.setData([
            "uid": uid,
            "year": year,
            "totalAmount": FieldValue.increment(amount),
            "currency": currency,
            "giftCount": FieldValue.increment(Int64(1)),
            "causesSupported": FieldValue.arrayUnion([causeID]),
            "causeNames": FieldValue.arrayUnion([causeName]),
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    // MARK: - Fetch

    func fetchSummary(year: Int) async -> GivingSummary? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        let db = Firestore.firestore()
        let snap = try? await db.collection("givingSummary").document("\(uid)_\(year)").getDocument()
        guard let data = snap?.data() else { return nil }
        return GivingSummary(
            year: year,
            totalAmount: data["totalAmount"] as? Double ?? 0,
            currency: data["currency"] as? String ?? "USD",
            giftCount: data["giftCount"] as? Int ?? 0,
            causesSupported: data["causesSupported"] as? [String] ?? [],
            causeNames: data["causeNames"] as? [String] ?? []
        )
    }

    // MARK: - Private

    private func recordGift(from signal: ContextSignal) async {
        guard
            let giftRef = signal.subjectRefs.first(where: { $0.nodeType == .gift }),
            let causeRef = signal.subjectRefs.first(where: { $0.nodeType == .cause })
        else { return }

        let giftID = giftRef.nodeID
        let causeID = causeRef.nodeID

        guard
            let amountVal = signal.payload["amount"],
            let causeNameVal = signal.payload["causeName"]
        else { return }

        // AnyCodableValue pattern-matched extraction
        guard case .double(let amount) = amountVal else { return }
        guard case .string(let causeName) = causeNameVal else { return }

        var currency = "USD"
        if let currVal = signal.payload["currency"], case .string(let c) = currVal {
            currency = c
        }

        var orgEIN: String?
        if let einVal = signal.payload["orgEIN"], case .string(let ein) = einVal {
            orgEIN = ein
        }

        await markGiftComplete(
            giftID: giftID,
            amount: amount,
            currency: currency,
            causeID: causeID,
            causeName: causeName,
            orgEIN: orgEIN
        )
    }
}

// MARK: - GivingSummary

struct GivingSummary: Codable {
    let year: Int
    let totalAmount: Double
    let currency: String
    let giftCount: Int
    let causesSupported: [String]
    let causeNames: [String]

    var formattedTotal: String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = currency
        return fmt.string(from: NSNumber(value: totalAmount)) ?? "$\(totalAmount)"
    }
}
