// ONEFeedModeService.swift
// ONE — World zone feed session manager + context gate tracker.
// P3-D/E | Stub Firestore loader; production replaces loadStub with a Firestore listener.

import Foundation

// MARK: - ONEFeedItemViewModel (presentational; not persisted)

struct ONEFeedItemViewModel: Identifiable {
    let id: String
    let authorDisplayName: String
    let textBody: String
    let provenance: ONEProvenanceLabel
    var reachBudget: ONEReachBudget
    let permissions: ONEMomentPermissions
    let momentType: ONEMomentType
    let createdAt: Date
    let hasVideo: Bool
}

// MARK: - ONEContextGateStatus

struct ONEContextGateStatus {
    var sourceRead: Bool = false
    var watchFraction: Double = 0.0    // passes at >= 0.30
    var provenanceAcknowledged: Bool = false

    var watchPassed: Bool { watchFraction >= 0.30 }
    var allPassed: Bool { sourceRead && watchPassed && provenanceAcknowledged }
}

// MARK: - ONEFeedModeService

@MainActor
final class ONEFeedModeService: ObservableObject {
    @Published var session: ONEFeedSession = .start(mode: .close)
    @Published var items: [ONEFeedItemViewModel] = []
    @Published var isLoading = false
    @Published var contextGateState: [String: ONEContextGateStatus] = [:]
    @Published var userRelayBudget: Int = 20   // weekly; replenished server-side

    // MARK: - Mode

    func switchMode(_ mode: ONEFeedModeKind) {
        session = .start(mode: mode)
        items = []
        loadStub(for: mode)
    }

    // MARK: - Session budget

    func markItemSeen() {
        guard !session.isExhausted else { return }
        session.itemsSeen += 1
    }

    // MARK: - Context gate

    func gateStatus(for id: String) -> ONEContextGateStatus {
        contextGateState[id] ?? ONEContextGateStatus()
    }

    func markSourceRead(for id: String) {
        contextGateState[id, default: ONEContextGateStatus()].sourceRead = true
    }

    func markWatchProgress(_ fraction: Double, for id: String) {
        contextGateState[id, default: ONEContextGateStatus()].watchFraction = fraction
    }

    func markProvenanceAcknowledged(for id: String) {
        contextGateState[id, default: ONEContextGateStatus()].provenanceAcknowledged = true
    }

    func isGatePassed(for id: String) -> Bool {
        gateStatus(for: id).allPassed
    }

    // MARK: - Relay

    func relay(itemID: String) async throws -> Int {
        let remaining = try await ONECallableService.shared.relayMoment(momentID: itemID, toUIDs: [])
        userRelayBudget = max(0, userRelayBudget - 1)
        if let idx = items.firstIndex(where: { $0.id == itemID }) {
            items[idx].reachBudget.sharesRemaining = remaining
            items[idx].reachBudget.totalRelays += 1
        }
        return remaining
    }

    // MARK: - Stub loader

    func loadStub(for mode: ONEFeedModeKind) {
        isLoading = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            self?.items = ONEFeedModeService.stubbedItems(for: mode)
            self?.isLoading = false
        }
    }

    private static func stubbedItems(for mode: ONEFeedModeKind) -> [ONEFeedItemViewModel] {
        let bodies: [String]
        switch mode {
        case .close:
            bodies = [
                "Thinking about our conversation from Sunday — still sitting with it.",
                "Praying for everyone in the group tonight.",
                "Grateful for the witness season we started together."
            ]
        case .create:
            bodies = [
                "New piece dropping next week — subscriber preview is up.",
                "Behind-the-scenes of Sunday's worship set.",
                "Collaborative album from the retreat is now open."
            ]
        case .learn:
            bodies = [
                "Why the Hebrew word for 'community' implies mutual obligation.",
                "A 12-minute reflection on the Sermon on the Mount.",
                "Reading notes from early church fathers on hospitality."
            ]
        case .local:
            bodies = [
                "Anyone joining the community cleanup this Saturday?",
                "Bethel Community Church is hosting a grief support group.",
                "Local food pantry needs volunteers this weekend."
            ]
        case .quiet:
            bodies = [
                "A quiet morning with the Psalms.",
                "One sentence: \"Be still and know.\"",
                "A single photograph of the morning light."
            ]
        }
        let authors = ["Grace A.", "Marcus W.", "Esther L."]
        return bodies.enumerated().map { idx, body in
            ONEFeedItemViewModel(
                id: "\(mode.rawValue)_\(idx)",
                authorDisplayName: authors[idx % authors.count],
                textBody: body,
                provenance: ONEProvenanceLabel(
                    classification: .captured, confidence: 0.92,
                    c2paPayload: nil, attestedAt: nil, processorNote: nil
                ),
                reachBudget: ONEReachBudget(
                    momentID: "\(mode.rawValue)_\(idx)",
                    originalAuthorUID: "stub_\(idx)",
                    sharesRemaining: 3, totalRelays: 4,
                    chainDepth: 1, maxChainDepth: 5
                ),
                permissions: ONEMomentPermissions(),
                momentType: .post,
                createdAt: Date().addingTimeInterval(Double(-idx * 3_600)),
                hasVideo: mode == .create && idx == 1
            )
        }
    }
}
