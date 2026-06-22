// CohortResonanceService.swift — Features/Intelligence/Community
// Finds similar-journey users (cohort) for Premium members who opt into graphToCohorts.
// Used by the discovery + matching surfaces; never surfaces raw signals to other users.
//
// Invariants:
//  • Premium required (SystemCapability.cohortResonance) + ConsentEdge.graphToCohorts
//  • Flag: ctx_cohort_resonance_enabled — default false
//  • Cohort IDs are anonymized before client receipt — server returns opaque profileIDs only
//  • Crisis dampening handled by EntitlementGate

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

// MARK: - CohortResonanceResult

struct CohortResonanceResult: Sendable {
    /// Opaque profile IDs of similar-journey users (no PII)
    let resonantProfileIDs: [String]
    /// Human-readable similarity axes, e.g. ["grief journey", "new parent"]
    let sharedAxes: [String]
    let computedAt: Date
}

// MARK: - CohortResonanceService

final class CohortResonanceService: ObservableObject, @unchecked Sendable {
    static let shared = CohortResonanceService()

    @Published private(set) var result: CohortResonanceResult? = nil
    @Published private(set) var isLoading = false

    private init() {}

    // MARK: - Public API

    func refresh() async {
        guard ContextIntelligenceFlags.cohortResonance else { return }

        let gate = await EntitlementGate.shared.canAccess(.cohortResonance)
        guard gate.allowed else { return }

        let hasEdge = await MainActor.run { ConsentStore.shared.isEnabled(.graphToCohorts) }
        guard hasEdge else { return }

        guard let uid = Auth.auth().currentUser?.uid else { return }

        await MainActor.run { isLoading = true }
        defer { Task { await MainActor.run { self.isLoading = false } } }

        let functions = Functions.functions(region: "us-east1")
        do {
            let callResult = try await functions
                .httpsCallable("findCohortResonance")
                .call(["uid": uid])

            guard let data = callResult.data as? [String: Any] else { return }

            let profileIDs = data["resonantProfileIDs"] as? [String] ?? []
            let axes = data["sharedAxes"] as? [String] ?? []

            let r = CohortResonanceResult(
                resonantProfileIDs: profileIDs,
                sharedAxes: axes,
                computedAt: Date()
            )
            await MainActor.run { self.result = r }
        } catch {
            // Non-fatal — surface remains empty, no upsell shown
        }
    }

    /// Call when the user's graphToCohorts consent changes or after major signal batch
    func invalidate() async {
        await MainActor.run { result = nil }
    }
}
