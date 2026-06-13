// CapabilityRegistryStore.swift
// AMEN Capabilities v1 — Client registry store (Wave 1: Lane C)
//
// Fetches the active capability list from the `capabilityRegistry_list` callable.
// Firestore offline persistence handles caching — no custom cache layer needed.
// Flag-gated: returns [] when capabilitiesCoreEnabled is OFF.

import Foundation
import FirebaseFunctions
import FirebaseAuth

// MARK: - CapabilityRegistryStore

@MainActor
final class CapabilityRegistryStore: ObservableObject {

    // MARK: Singleton

    static let shared = CapabilityRegistryStore()

    // MARK: Published state

    @Published private(set) var capabilities: [Capability] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: Error?

    // MARK: Private

    private let functions = Functions.functions(region: "us-central1")

    private init() {}

    // MARK: - Public API

    /// Returns active capabilities for the given surface, filtered client-side.
    /// Callers should call `loadCapabilities(for:)` first to populate the store.
    func capabilities(for surface: CapabilitySurface) -> [Capability] {
        capabilities.filter { $0.surfaces.contains(surface) && $0.status == .active }
    }

    /// Loads capabilities from the backend callable for the given surface.
    /// Results are stored in `capabilities` (full list); `capabilities(for:)` filters client-side.
    /// No-op when `capabilitiesCoreEnabled` flag is OFF — clears existing list.
    func loadCapabilities(for surface: CapabilitySurface) async {
        guard AMENFeatureFlags.shared.capabilitiesCoreEnabled else {
            // Flag is off — clear any stale data and return immediately.
            capabilities = []
            loadError = nil
            return
        }

        guard Auth.auth().currentUser != nil else {
            // Not signed in — silently skip; the picker won't be visible anyway.
            return
        }

        isLoading = true
        loadError = nil

        defer { isLoading = false }

        do {
            let result = try await functions
                .httpsCallable("capabilityRegistry_list")
                .call(["surface": surface.rawValue])

            guard let data = result.data as? [String: Any],
                  let rawList = data["capabilities"] as? [[String: Any]] else {
                loadError = RegistryError.unexpectedResponse
                return
            }

            let decoded = rawList.compactMap { dict -> Capability? in
                decodeCapability(from: dict)
            }

            capabilities = decoded

        } catch {
            loadError = error
        }
    }

    // MARK: - Decoding helper

    /// Decodes a `Capability` from a raw `[String: Any]` dictionary returned by the callable.
    /// Uses `JSONSerialization` → `JSONDecoder` pipeline for robustness.
    private func decodeCapability(from dict: [String: Any]) -> Capability? {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: dict) else {
            return nil
        }
        let decoder = JSONDecoder()
        return try? decoder.decode(Capability.self, from: jsonData)
    }
}

// MARK: - RegistryError

private enum RegistryError: LocalizedError {
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .unexpectedResponse:
            return "Capability registry returned an unexpected response."
        }
    }
}
