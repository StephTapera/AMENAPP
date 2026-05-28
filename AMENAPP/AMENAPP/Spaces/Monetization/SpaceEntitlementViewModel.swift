// SpaceEntitlementViewModel.swift
// AMENAPP — Spaces Monetization (Agent E)
//
// View model that drives the paywall / locked-preview state machine.
// Consumes SpacesEntitlementService and surfaces EntitlementState to views.
//
// State machine:
//   .unknown   → initial
//   .checking  → async check in flight
//   .active    → entitlement status = active
//   .grace     → entitlement status = grace (payment processing / subscription lapsing)
//   .expired   → entitlement status = expired
//   .notRequired → space.accessPolicy == .free
//
// Usage:
//   let vm = SpaceEntitlementViewModel()
//   vm.check(space: space)        // on view appear
//   vm.purchase(space: space)     // on [Unlock Space] tap
//   vm.restore(space: space)      // on [Restore Purchase] tap

import Foundation
import FirebaseAuth

// MARK: - Entitlement State

extension SpaceEntitlementViewModel {
    enum EntitlementState: Equatable {
        case unknown
        case checking
        case active
        case grace
        case expired
        case notRequired
    }
}

// MARK: - SpaceEntitlementViewModel

@MainActor
final class SpaceEntitlementViewModel: ObservableObject {

    // MARK: Published State

    @Published var state: EntitlementState = .unknown
    @Published var isPurchasing: Bool = false
    @Published var purchaseError: Error? = nil

    // MARK: Private

    private let service: SpacesEntitlementService

    init(service: SpacesEntitlementService = .shared) {
        self.service = service
    }

    // MARK: - Check

    /// Checks entitlement for the given space and starts a real-time listener.
    /// Called on view appear.
    func check(space: AmenSpace) async {
        guard let spaceId = space.id, !spaceId.isEmpty else { return }

        // Free spaces need no entitlement
        if !space.accessPolicy.isPaid {
            state = .notRequired
            return
        }

        state = .checking

        guard let uid = Auth.auth().currentUser?.uid else {
            state = .expired
            return
        }

        // Start real-time listener — updates state whenever entitlement changes
        service.startListening(userId: uid, spaceId: spaceId)

        // Observe the service's published dictionary to drive local state
        // (also do an immediate check so we don't wait for the first snapshot)
        do {
            let hasActive = try await service.hasActiveEntitlement(spaceId: spaceId)
            if hasActive {
                // Snapshot check — listener will keep this up to date
                let cachedStatus = service.entitlementsBySpace[spaceId]?.status
                state = entitlementState(from: cachedStatus ?? .active)
            } else {
                state = .expired
            }
        } catch {
            // Treat auth/network errors as expired (paywall shows)
            state = .expired
        }

        // Bind to service's real-time updates via task observation
        observeServiceUpdates(spaceId: spaceId)
    }

    // MARK: - Purchase

    /// Starts the Stripe checkout flow for the space.
    func purchase(space: AmenSpace) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }

        do {
            try await service.purchaseAccess(space: space)
            // State will update via the real-time listener when the webhook fires.
        } catch {
            purchaseError = error
        }
    }

    // MARK: - Restore

    /// Refreshes the entitlement from Firestore (for one-time purchases).
    func restore(space: AmenSpace) async {
        guard let spaceId = space.id, !spaceId.isEmpty else { return }
        state = .checking
        do {
            try await service.restorePurchase(spaceId: spaceId)
            let cached = service.entitlementsBySpace[spaceId]
            state = entitlementState(from: cached?.status)
        } catch {
            purchaseError = error
            state = .expired
        }
    }

    // MARK: - Cleanup

    /// Cancel the listener when the view is torn down.
    func stopListening(spaceId: String) {
        service.stopListening(spaceId: spaceId)
    }

    // MARK: - Private Helpers

    private func entitlementState(from status: SpaceEntitlement.EntitlementStatus?) -> EntitlementState {
        switch status {
        case .active:  return .active
        case .grace:   return .grace
        case .expired: return .expired
        case nil:      return .expired
        }
    }

    /// Polls the service's entitlementsBySpace dictionary.
    /// This is a lightweight Task loop — the actual work is driven by the Firestore listener
    /// in SpacesEntitlementService; we just observe the @Published dictionary.
    private func observeServiceUpdates(spaceId: String) {
        Task { [weak self] in
            guard let self else { return }
            // Brief yield so the initial check completes first
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
            while !Task.isCancelled {
                let cached = service.entitlementsBySpace[spaceId]
                let newState = entitlementState(from: cached?.status)
                if newState != self.state {
                    self.state = newState
                }
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s polling interval
            }
        }
    }
}
