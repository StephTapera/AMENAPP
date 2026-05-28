// AmenIntegrationViewModel.swift
// AMEN Integrations Platform — view model for Connected Apps screen

import Foundation
import SwiftUI

@MainActor
final class AmenIntegrationViewModel: ObservableObject {

    @Published private(set) var connections: [AmenIntegrationConnection] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: AmenIntegrationClientError?
    @Published var pendingOAuthProvider: AmenIntegrationProvider?
    @Published var showOAuthSheet = false
    @Published var showDisconnectConfirm = false
    @Published var providerToDisconnect: AmenIntegrationProvider?
    @Published private(set) var actionInProgress: AmenIntegrationProvider?

    private let service = AmenIntegrationService.shared

    // MARK: - Load

    func loadConnections() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        do {
            connections = try await service.listConnections()
        } catch let e as AmenIntegrationClientError {
            error = e
        } catch {
            self.error = .unknown(error.localizedDescription)
        }
        isLoading = false
    }

    // MARK: - Connection Status Helpers

    func connection(for provider: AmenIntegrationProvider) -> AmenIntegrationConnection? {
        connections.first { $0.provider == provider }
    }

    func status(for provider: AmenIntegrationProvider) -> AmenIntegrationStatus {
        connection(for: provider)?.status ?? .notConnected
    }

    // MARK: - OAuth

    func startConnect(provider: AmenIntegrationProvider) {
        pendingOAuthProvider = provider
        showOAuthSheet = true
    }

    func handleOAuthCompletion(provider: AmenIntegrationProvider, code: String, stateToken: String) async {
        actionInProgress = provider
        error = nil
        do {
            _ = try await service.completeOAuth(provider: provider, code: code, stateToken: stateToken)
            await loadConnections()
        } catch let e as AmenIntegrationClientError {
            error = e
        } catch {
            self.error = .unknown(error.localizedDescription)
        }
        actionInProgress = nil
        showOAuthSheet = false
    }

    // MARK: - Refresh

    func refresh(provider: AmenIntegrationProvider) async {
        actionInProgress = provider
        error = nil
        do {
            try await service.refreshConnection(provider: provider)
            await loadConnections()
        } catch let e as AmenIntegrationClientError {
            error = e
        } catch {
            self.error = .unknown(error.localizedDescription)
        }
        actionInProgress = nil
    }

    // MARK: - Disconnect

    func confirmDisconnect(provider: AmenIntegrationProvider) {
        providerToDisconnect = provider
        showDisconnectConfirm = true
    }

    func disconnect(provider: AmenIntegrationProvider) async {
        actionInProgress = provider
        error = nil
        do {
            try await service.disconnectProvider(provider: provider)
            await loadConnections()
        } catch let e as AmenIntegrationClientError {
            error = e
        } catch {
            self.error = .unknown(error.localizedDescription)
        }
        actionInProgress = nil
        showDisconnectConfirm = false
    }

    func clearError() { error = nil }

    // MARK: - Display Helpers

    var sortedProviders: [AmenIntegrationProvider] {
        // Connected first, then by name
        AmenIntegrationProvider.allCases.sorted { a, b in
            let aConnected = status(for: a) == .connected
            let bConnected = status(for: b) == .connected
            if aConnected != bConnected { return aConnected }
            return a.displayName < b.displayName
        }
    }
}
