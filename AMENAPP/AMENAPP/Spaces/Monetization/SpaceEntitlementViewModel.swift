// SpaceEntitlementViewModel.swift
// AMENAPP — Spaces Monetization (Agent E)
//
// View model driving the paywall / locked-preview state machine.
// Consumes SpacesEntitlementService and surfaces EntitlementState to views.
//
// State machine:
//   .unknown     → initial
//   .checking    → async check in flight
//   .active      → entitlement status = active
//   .grace       → entitlement status = grace (payment processing / subscription lapsing)
//   .expired     → entitlement status = expired
//   .notRequired → space.accessPolicy == .free

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
    private var observerTask: Task<Void, Never>? = nil

    init(service: SpacesEntitlementService = .shared) {
        self.service = service
    }

    // MARK: - Check

    /// Checks entitlement for the given space and starts a real-time listener.
    /// Called on view appear.
    func check(space: AmenSpace) async {
        guard let spaceId = space.id, !spaceId.isEmpty else { return }

        if !space.accessPolicy.isPaid {
            state = .notRequired
            return
        }

        state = .checking

        guard let uid = Auth.auth().currentUser?.uid else {
            state = .expired
            return
        }

        // Start real-time listener — fires whenever entitlement document changes.
        service.startListening(userId: uid, spaceId: spaceId)

        // Immediate snapshot check so we don't wait for the first Firestore event.
        do {
            let hasActive = try await service.hasActiveEntitlement(spaceId: spaceId)
            if hasActive {
                let cached = service.entitlementsBySpace[spaceId]
                state = entitlementState(from: cached?.status ?? .active)
            } else {
                state = .expired
            }
        } catch {
            state = .expired
        }

        startObservingService(spaceId: spaceId)
    }

    // MARK: - Purchase

    func purchase(space: AmenSpace) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }
        do {
            try await service.purchaseAccess(space: space)
            // State update arrives via the real-time listener.
        } catch {
            purchaseError = error
        }
    }

    // MARK: - Restore

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

    func stopListening(spaceId: String) {
        observerTask?.cancel()
        observerTask = nil
        service.stopListening(spaceId: spaceId)
    }

    // MARK: - Helpers

    private func entitlementState(from status: SpaceEntitlement.EntitlementStatus?) -> EntitlementState {
        switch status {
        case .active:  return .active
        case .grace:   return .grace
        case .expired: return .expired
        case nil:      return .expired
        }
    }

    /// Polls the service's @Published dictionary for changes driven by the Firestore listener.
    private func startObservingService(spaceId: String) {
        observerTask?.cancel()
        observerTask = Task { [weak self] in
            guard let self else { return }
            // Brief yield so the initial check result lands first.
            try? await Task.sleep(nanoseconds: 300_000_000)
            while !Task.isCancelled {
                let cached = service.entitlementsBySpace[spaceId]
                let newState = entitlementState(from: cached?.status)
                if newState != self.state {
                    self.state = newState
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }
}
