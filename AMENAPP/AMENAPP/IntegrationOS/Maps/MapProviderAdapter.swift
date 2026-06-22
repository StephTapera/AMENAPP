// MapProviderAdapter.swift — AMEN IntegrationOS
// Apple Maps adapter (primary) with Google Maps deep-link fallback.

import Foundation
import MapKit
import FirebaseRemoteConfig

final class AppleMapsAdapter: NSObject, ProviderAdapter {
    let providerId = "apple_maps"
    let capabilities: ProviderCapabilitySet = [.maps]
    let costClass: ProviderCostClass = .free

    private var authorized = false
    private var locationManager: CLLocationManager?

    func authorize(scopes: [ConsentScope]) async throws {
        let manager = CLLocationManager()
        locationManager = manager
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            manager.requestWhenInUseAuthorization()
            authorized = false
            return
        }
        authorized = true
    }

    func refresh() async throws { }

    func revoke() async throws {
        authorized = false
        locationManager = nil
    }

    func fetch(request: ProviderRequest) async throws -> ProviderResponse {
        guard authorized else { throw IntegrationOSError.consentDenied(.locationApproximate) }
        return ProviderResponse(providerId: providerId, payload: [:], statusCode: 200)
    }

    func normalize(payload: ProviderResponse) throws -> ExternalUniversalObject {
        let raw = payload.payload
        return ExternalUniversalObject(
            id: raw["placeId"] as? String ?? UUID().uuidString,
            sourceProviderId: providerId,
            type: .mapPlace,
            title: raw["name"] as? String ?? "Unknown Place",
            subtitle: raw["address"] as? String,
            metadata: [:],
            fetchedAt: Date()
        )
    }

    func health() async -> ProviderHealthStatus {
        return authorized ? .healthy : .unauthorized
    }
}

final class GoogleMapsDeepLinkAdapter: ProviderAdapter {
    let providerId = "google_maps"
    let capabilities: ProviderCapabilitySet = [.maps]
    let costClass: ProviderCostClass = .free

    func authorize(scopes: [ConsentScope]) async throws { }
    func refresh() async throws { }
    func revoke() async throws { }

    func fetch(request: ProviderRequest) async throws -> ProviderResponse {
        guard let query = request.parameters["query"] as? String,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "comgooglemaps://?q=\(encoded)") else {
            throw IntegrationOSError.providerUnavailable(providerId)
        }
        await UIApplication.shared.open(url)
        return ProviderResponse(providerId: providerId, payload: ["opened": true], statusCode: 200)
    }

    func normalize(payload: ProviderResponse) throws -> ExternalUniversalObject {
        ExternalUniversalObject(
            id: UUID().uuidString,
            sourceProviderId: providerId,
            type: .mapPlace,
            title: "Google Maps Result",
            subtitle: nil,
            metadata: [:],
            fetchedAt: Date()
        )
    }

    func health() async -> ProviderHealthStatus {
        let canOpen = await UIApplication.shared.canOpenURL(URL(string: "comgooglemaps://")!)
        return canOpen ? .healthy : .unavailable
    }
}
