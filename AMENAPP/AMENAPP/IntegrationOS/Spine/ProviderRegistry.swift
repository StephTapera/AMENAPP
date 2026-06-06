// ProviderRegistry.swift — AMEN IntegrationOS
// @MainActor registry of all registered provider adapters.

import Foundation
import FirebaseRemoteConfig

@MainActor
final class ProviderRegistry: ObservableObject {
    static let shared = ProviderRegistry()
    private init() {}

    @Published private(set) var adapters: [String: any ProviderAdapter] = [:]
    @Published private(set) var healthReports: [ProviderHealthReport] = []

    private let remoteConfig = RemoteConfig.remoteConfig()
    private let flagKey = "integration_os_enabled"

    var isEnabled: Bool {
        remoteConfig.configValue(forKey: flagKey).boolValue
    }

    // MARK: - Registration

    func register(_ adapter: any ProviderAdapter) {
        guard isEnabled else { return }
        adapters[adapter.providerId] = adapter
    }

    func unregister(providerId: String) {
        adapters.removeValue(forKey: providerId)
    }

    func adapter(for providerId: String) -> (any ProviderAdapter)? {
        adapters[providerId]
    }

    // MARK: - Health Check

    func refreshHealth() async {
        var reports: [ProviderHealthReport] = []
        for (_, adapter) in adapters {
            let status = await adapter.health()
            reports.append(ProviderHealthReport(
                id: adapter.providerId,
                providerId: adapter.providerId,
                status: status,
                lastChecked: Date(),
                latencyMs: nil,
                errorMessage: nil
            ))
        }
        healthReports = reports
    }

    // MARK: - Revoke All

    func revokeAll() async {
        for (_, adapter) in adapters {
            try? await adapter.revoke()
        }
        adapters.removeAll()
    }
}
