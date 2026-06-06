// WhatNeedsAttentionViewModel.swift — AMEN Living Intelligence
// Drives WhatNeedsAttentionView with six fully-rendered UI states.
//
// FORMATION INVARIANT:
//   refresh() must NOT re-fetch from the network. It re-renders the brief
//   that is already in memory. This enforces the digest cadence invariant
//   and eliminates any refresh-reward loop.

import Foundation
import FirebaseAuth

@MainActor
final class WhatNeedsAttentionViewModel: ObservableObject {

    // MARK: - View State

    enum ViewState {
        case loading
        case populated(IntelligenceBrief)
        case empty              // show Prayer Pulse + scripture prompt
        case error(String)
        case offline(IntelligenceBrief?)  // stale brief if available
        case sensitive          // local tragedy → lament frame, opt-in reveal
    }

    @Published var state: ViewState = .loading
    @Published var showSensitiveContent = false

    // MARK: - Private state

    /// In-memory brief; never nil once successfully loaded.
    private var cachedBrief: IntelligenceBrief?
    private let service = IntelligenceService.shared

    // MARK: - Load

    /// Fetches a fresh intelligence brief from the server and updates state.
    /// Filters out cards where backingEntity.verified == false.
    func load() async {
        guard Auth.auth().currentUser != nil else {
            state = .error("You must be signed in to view your brief.")
            return
        }

        state = .loading

        do {
            let brief = try await service.fetchBrief()

            // Filter: only show verified-entity cards
            let verified = brief.cards.filter { $0.backingEntity.verified }

            if verified.isEmpty {
                state = .empty
                return
            }

            // Check if any card requires lament framing
            let hasSensitive = verified.contains { $0.formation.lamentFrame == true }
            if hasSensitive && !showSensitiveContent {
                let filteredBrief = IntelligenceBrief(
                    userId: brief.userId,
                    cards: verified,
                    generatedAt: brief.generatedAt,
                    expiresAt: brief.expiresAt
                )
                cachedBrief = filteredBrief
                state = .sensitive
                return
            }

            let sortedCards = sortedByTierAndRank(verified)
            let finalBrief = IntelligenceBrief(
                userId: brief.userId,
                cards: sortedCards,
                generatedAt: brief.generatedAt,
                expiresAt: brief.expiresAt
            )
            cachedBrief = finalBrief
            state = .populated(finalBrief)

        } catch let error as IntelligenceServiceError {
            handleError(error)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    // MARK: - Refresh (FORMATION INVARIANT: NO new network fetch)

    /// Re-renders the brief that is already in memory.
    /// Does NOT call the network. Does NOT re-rank.
    /// Enforces the formation governor digest cadence invariant.
    func refresh() async {
        guard let brief = cachedBrief else {
            // Nothing cached — fall back to a load
            await load()
            return
        }

        // Re-apply sensitive gate in case showSensitiveContent changed
        let hasSensitive = brief.cards.contains { $0.formation.lamentFrame == true }
        if hasSensitive && !showSensitiveContent {
            state = .sensitive
            return
        }

        // Re-render same brief — no re-sort, no new ranking
        state = .populated(brief)
    }

    // MARK: - Handle Action

    /// Records the action server-side and routes navigation via the handler string.
    /// Navigation side-effects are published so the View can respond.
    func handleAction(_ action: CardAction, cardId: String) async {
        // Record non-critically — ignore errors so UI is never blocked
        try? await service.recordAction(cardId: cardId, rung: action.rung, targetId: action.target)
    }

    // MARK: - Private helpers

    private func sortedByTierAndRank(_ cards: [IntelligenceCard]) -> [IntelligenceCard] {
        cards.sorted {
            if $0.tier.displayOrder != $1.tier.displayOrder {
                return $0.tier.displayOrder < $1.tier.displayOrder
            }
            return $0.rankScore > $1.rankScore
        }
    }

    private func handleError(_ error: IntelligenceServiceError) {
        switch error {
        case .networkError:
            // Go offline with stale brief if available
            state = .offline(cachedBrief)
        case .unauthenticated:
            state = .error("You must be signed in to view your brief.")
        case .serverError(let msg):
            state = .error(msg)
        case .invalidResponse:
            state = .error("Something went wrong. Please try again.")
        }
    }
}
