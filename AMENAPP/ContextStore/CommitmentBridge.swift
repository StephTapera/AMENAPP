// CommitmentBridge.swift
// AMEN Universal Migration & Context System — Wave 4 (commitment-bridge)
//
// Converts a Context goal facet (category `.goals`, or a faith `spiritualGoal`) into a
// REAL `AmenCommitmentObject` by REUSING the existing Action Intelligence creation path —
// NOT a parallel commitment model.
//
// Reused creation API (no duplicate primitive):
//   Swift:    ActionIntelligenceService.shared.execute(action:analysis:source:)
//   Callable: `executeAmenAction`  (us-central1, App Check enforced)
//   Backend:  createActionObject(...)  → collection `actionIntelligenceObjects`
//             (Backend/functions/src/actionIntelligence.ts)
//
// The source facet is back-linked on the commitment's `source` payload:
//   • source.sourceId      = the originating facet id (UUID string)
//   • source.sourceType    = "context_facet"
//   • source.title         = the facet's machine key  (e.g. "goals.manual", "faith.goal.<n>")
//   • source.sourceText    = the goal's display text
// The backend persists the whole `source` map on the created object, so the origin facet is
// always recoverable from the created Commitment Object.
//
// Constraints honored:
//   • No spiritual ranking — goals are surfaced, never scored/ordered/compared.
//   • Goal facets are Tier C; this affordance never touches Tier-P content. A guard rejects
//     any non-Tier-C facet so a private facet can never be exported into a server object.
//   • Flag-gated: requires contextSystemEnabled AND contextCommitmentBridgeEnabled.
//   • GlassKit surface; all animation via Motion.adaptive.

import SwiftUI
import FirebaseAuth

// MARK: - Errors

enum CommitmentBridgeError: LocalizedError {
    case bridgeDisabled
    case unauthenticated
    case unsupportedFacet          // not a goal facet
    case tierNotServerReadable     // Tier P may never become a server object
    case emptyGoalText

    var errorDescription: String? {
        switch self {
        case .bridgeDisabled:
            return "Commitments aren't available right now."
        case .unauthenticated:
            return "Sign in to make this a commitment."
        case .unsupportedFacet:
            return "Only goals can become commitments."
        case .tierNotServerReadable:
            return "This is private to your device and can't become a shared commitment."
        case .emptyGoalText:
            return "There's nothing to commit to yet."
        }
    }
}

// MARK: - Service

/// Bridges a goal `ContextFacet` into a real `AmenCommitmentObject` via the existing
/// Action Intelligence creation path. Owns NO new model and NO new Cloud Function.
@MainActor
final class CommitmentBridge {
    static let shared = CommitmentBridge()

    private init() {}

    /// True iff a goal facet may be offered the "make a commitment" affordance.
    /// Goals are Tier C; faith spiritual-goal facets are Tier C too (the Tier-P faith key is
    /// `*.areas_needing_support`, which is never a goal). Private (Tier P) facets are excluded.
    static func isBridgeable(_ facet: ContextFacet) -> Bool {
        guard AMENFeatureFlags.shared.contextSystemEnabled,
              AMENFeatureFlags.shared.contextCommitmentBridgeEnabled else { return false }
        guard ContextTierTable.isServerReadable(facet.tier) else { return false }
        return facet.category == .goals || isFaithGoalFacet(facet)
    }

    /// A faith_journey facet whose structured value carries spiritual goals (and is NOT the
    /// Tier-P support facet). Used so individual spiritual goals can also become commitments.
    static func isFaithGoalFacet(_ facet: ContextFacet) -> Bool {
        guard facet.category == .faith_journey else { return false }
        guard ContextTierTable.isServerReadable(facet.tier) else { return false }
        if case let .faithJourney(value) = facet.value {
            return !value.spiritualGoals.isEmpty
        }
        return false
    }

    /// Converts a goal facet into a real Commitment Object, back-linked to the source facet.
    /// - Parameters:
    ///   - facet: the originating Context goal facet (category `.goals` or a faith goal facet).
    ///   - goalText: optional override for the specific goal text (used when a faith facet holds
    ///     multiple `spiritualGoals` and the user commits to one). Defaults to the facet summary.
    /// - Returns: the created object's id + workflow result.
    func makeCommitment(
        from facet: ContextFacet,
        goalText: String? = nil
    ) async throws -> ActionIntelligenceExecutionResult {
        guard AMENFeatureFlags.shared.contextSystemEnabled,
              AMENFeatureFlags.shared.contextCommitmentBridgeEnabled else {
            throw CommitmentBridgeError.bridgeDisabled
        }
        guard Auth.auth().currentUser?.uid != nil else {
            throw CommitmentBridgeError.unauthenticated
        }
        guard facet.category == .goals || Self.isFaithGoalFacet(facet) else {
            throw CommitmentBridgeError.unsupportedFacet
        }
        // Hard stop: a Tier-P facet must never be projected into a server-readable object.
        guard ContextTierTable.isServerReadable(facet.tier) else {
            throw CommitmentBridgeError.tierNotServerReadable
        }

        let text = (goalText ?? facet.value.displaySummary)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw CommitmentBridgeError.emptyGoalText }

        // Back-link the source facet on the source payload. The backend stores the whole
        // `source` map on the created object, so the origin facet id + key are recoverable.
        let source = ActionIntelligenceSourcePayload(
            sourceId: facet.id.uuidString,
            sourceType: "context_facet",
            sourceText: text,
            title: facet.key                    // machine key of the originating facet (backlink)
        )

        // Minimal, honest analysis: a user-initiated commitment with no crisis signal.
        // objectClass `.commitment`, intentKind `.followUp` (a commitment-class intent).
        // privacyTier `.confidential` — goals are Tier C, never the public-community lane.
        let analysis = AmenIntentAnalysis(
            id: UUID().uuidString,
            sourceId: facet.id.uuidString,
            surface: .feedPost,
            privacyTier: .confidential,
            intentKind: .followUp,
            objectClass: .commitment,
            confidence: 1.0,                    // user explicitly asked for this; not a detection
            sensitivityLevel: .standard,
            detectedSignals: ["context_goal_commitment"],
            primaryActions: [],
            secondaryActions: [],
            explanation: "User chose to turn a goal into a personal commitment.",
            shouldRenderCollapsed: false,
            shouldSuppressCapsule: false,
            createdAt: Date()
        )

        // `.followUpdates` routes server-side to the owner-only memory workflow, which calls
        // createActionObject (the shared Commitment primitive). No new CF, no new collection.
        let action = AmenActionSuggestion(
            verb: .followUpdates,
            explanation: "Creates a private commitment from this goal.",
            requiresConfirmation: false,
            createsServerObject: true
        )

        return try await ActionIntelligenceService.shared.execute(
            action: action,
            analysis: analysis,
            source: source
        )
    }
}

// MARK: - Affordance

/// GlassKit affordance shown on goal facets: "Make this a commitment".
/// Hidden entirely unless the facet is bridgeable (flag + Tier-C goal). On success it shows a
/// brief confirmation; failures surface a quiet inline message — never a crash or a streak.
struct ContextMakeCommitmentButton: View {
    let facet: ContextFacet
    /// Optional specific goal text (when a faith facet holds several spiritual goals).
    var goalText: String? = nil
    /// Called with the created object id on success (e.g. to dismiss or refresh).
    var onCommitted: ((String?) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isWorking = false
    @State private var didCommit = false
    @State private var errorMessage: String?

    var body: some View {
        if CommitmentBridge.isBridgeable(facet) {
            VStack(alignment: .leading, spacing: 6) {
                AmenLiquidGlassPillButton(
                    title: title,
                    systemImage: systemImage,
                    isLoading: isWorking,
                    isDisabled: didCommit || isWorking
                ) {
                    commit()
                }
                .accessibilityLabel(didCommit ? "Commitment created" : "Make this goal a commitment")
                .accessibilityHint("Creates a private commitment you can track.")

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
        }
    }

    private var title: String { didCommit ? "Commitment created" : "Make this a commitment" }
    private var systemImage: String { didCommit ? "checkmark.circle" : "flag" }

    private func commit() {
        guard !isWorking, !didCommit else { return }
        errorMessage = nil
        isWorking = true
        Task {
            do {
                let result = try await CommitmentBridge.shared.makeCommitment(
                    from: facet,
                    goalText: goalText
                )
                await MainActor.run {
                    withAnimation(Motion.adaptive(Motion.popToggle)) {
                        isWorking = false
                        didCommit = true
                    }
                    onCommitted?(result.objectId)
                }
            } catch {
                await MainActor.run {
                    withAnimation(Motion.adaptive(Motion.appearEase)) {
                        isWorking = false
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }
}

#if DEBUG
#Preview("Make Commitment Button") {
    let facet = ContextFacet(
        id: UUID(),
        userId: "preview",
        category: .goals,
        key: "goals.manual",
        label: "Goals",
        value: .text("Read the Bible in a year"),
        visibility: .privateVisibility,
        tier: ContextTierTable.tier(for: .goals),
        provenance: Provenance(
            source: .manual,
            sourceLabel: nil,
            extractedAt: nil,
            confidence: nil,
            userApproved: true,
            userEdited: false,
            sanitizationPassId: "preview"
        ),
        createdAt: Date(),
        updatedAt: Date(),
        schemaVersion: 1
    )
    return ContextMakeCommitmentButton(facet: facet)
        .padding()
}
#endif
