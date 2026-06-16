// BereanContextRAGService.swift — Features/Intelligence/BereanContext
// Builds a compact context packet from recent ContextBus signals for Berean prompt injection.
//
// Invariants:
//  • Premium-only via SystemCapability.bereanContextInjection + ConsentEdge.graphToBerean
//  • Flag: ctx_berean_context_injection_enabled — default false
//  • Tier-S signals are NEVER included in the packet (ContextBus never forwards them, but we
//    double-check here to be safe on any locally cached signals)
//  • Max 10 signals per packet; oldest-first chronological order
//  • Crisis dampening handled automatically by EntitlementGate

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

// MARK: - BereanContextPacket

struct BereanContextPacket: Sendable {
    let signals: [BereanSignalSummary]
    let generatedAt: Date
    /// Human-readable provenance for display in UI, e.g. "from 3 recent notes and 1 prayer"
    let provenanceLabel: String
}

struct BereanSignalSummary: Codable, Sendable {
    let signalType: String
    let subjectNodeType: String
    let subjectNodeID: String
    let occurredAt: Date
    let payloadSnippet: String
}

// MARK: - BereanContextRAGService

final class BereanContextRAGService: ObservableObject, @unchecked Sendable {
    static let shared = BereanContextRAGService()

    @Published private(set) var latestPacket: BereanContextPacket? = nil

    private init() {}

    // MARK: - Public API

    /// Builds a context packet for Berean injection.
    /// Returns nil if the flag is off, user is not entitled, or consent is withdrawn.
    func buildPacket() async -> BereanContextPacket? {
        guard ContextIntelligenceFlags.bereanContext else { return nil }

        let gate = await EntitlementGate.shared.canAccess(.bereanContextInjection)
        guard gate.allowed else { return nil }

        let hasEdge = await MainActor.run { ConsentStore.shared.isEnabled(.graphToBerean) }
        guard hasEdge else { return nil }

        guard let uid = Auth.auth().currentUser?.uid else { return nil }

        // Fetch recent signals from Firestore (server-side, tier .c/.p only)
        let signals = await fetchRecentSignals(uid: uid, limit: 10)
        guard !signals.isEmpty else { return nil }

        let packet = assemble(signals: signals)
        await MainActor.run { self.latestPacket = packet }
        return packet
    }

    // MARK: - Fetch from Firestore

    private func fetchRecentSignals(uid: String, limit: Int) async -> [BereanSignalSummary] {
        let db = Firestore.firestore()
        let signalTypes: [SignalType] = [
            .noteSaved, .noteThemeDetected, .prayerCreated, .prayerAnswered,
            .studyStarted, .studyCompleted, .verseReflected, .visitVerified
        ]
        let typeValues = signalTypes.map(\.rawValue)

        do {
            let query = db
                .collection("contextSignals").document(uid)
                .collection("signals")
                .whereField("type", in: typeValues)
                .whereField("tierCeiling", isNotEqualTo: TierCeiling.s.rawValue)
                .order(by: "occurredAt", descending: true)
                .limit(to: limit)

            let snapshot = try await query.getDocuments()
            return snapshot.documents.compactMap { doc in
                let data = doc.data()
                guard
                    let type = data["type"] as? String,
                    let tierRaw = data["tierCeiling"] as? String,
                    let tier = TierCeiling(rawValue: tierRaw),
                    tier != .s,                          // double-check: never include Tier-S
                    let ts = data["occurredAt"] as? Timestamp,
                    let refs = data["subjectRefs"] as? [[String: String]],
                    let firstRef = refs.first
                else { return nil }

                let payload = data["payload"] as? [String: Any] ?? [:]
                let snippet = payload.values.first.map { "\($0)" } ?? ""

                return BereanSignalSummary(
                    signalType: type,
                    subjectNodeType: firstRef["nodeType"] ?? "unknown",
                    subjectNodeID: firstRef["nodeID"] ?? "",
                    occurredAt: ts.dateValue(),
                    payloadSnippet: String(snippet.prefix(120))
                )
            }
            .reversed()   // oldest-first
        } catch {
            return []
        }
    }

    // MARK: - Assembly

    private func assemble(signals: [BereanSignalSummary]) -> BereanContextPacket {
        let typeCounts = Dictionary(grouping: signals, by: \.signalType)
            .mapValues(\.count)
        let provenance = typeCounts.map { "\($0.value) \($0.key)" }.joined(separator: ", ")

        return BereanContextPacket(
            signals: signals,
            generatedAt: Date(),
            provenanceLabel: "from " + provenance
        )
    }
}
