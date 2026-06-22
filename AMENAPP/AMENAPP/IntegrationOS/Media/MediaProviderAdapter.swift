// MediaProviderAdapter.swift — AMEN IntegrationOS
// Apple Music and Spotify deep-link adapters.

import Foundation
import MediaPlayer
import StoreKit

final class AppleMusicAdapter: ProviderAdapter {
    let providerId = "apple_music"
    let capabilities: ProviderCapabilitySet = [.media]
    let costClass: ProviderCostClass = .free

    private var authorized = false

    func authorize(scopes: [ConsentScope]) async throws {
        let status = await MPMediaLibrary.requestAuthorization()
        authorized = (status == .authorized)
        if !authorized { throw IntegrationOSError.consentDenied(.mediaLibraryRead) }
    }

    func refresh() async throws {
        authorized = MPMediaLibrary.authorizationStatus() == .authorized
    }

    func revoke() async throws {
        authorized = false
    }

    func fetch(request: ProviderRequest) async throws -> ProviderResponse {
        guard authorized else { throw IntegrationOSError.consentDenied(.mediaLibraryRead) }
        let query = MPMediaQuery.songs()
        let items = query.items ?? []
        let payload: [String: Any] = ["count": items.count]
        return ProviderResponse(providerId: providerId, payload: payload, statusCode: 200)
    }

    func normalize(payload: ProviderResponse) throws -> ExternalUniversalObject {
        ExternalUniversalObject(
            id: UUID().uuidString,
            sourceProviderId: providerId,
            type: .mediaTrack,
            title: "Music Library",
            subtitle: nil,
            metadata: [:],
            fetchedAt: Date()
        )
    }

    func health() async -> ProviderHealthStatus {
        switch MPMediaLibrary.authorizationStatus() {
        case .authorized:           return .healthy
        case .denied, .restricted:  return .unauthorized
        default:                    return .unavailable
        }
    }
}

final class SpotifyDeepLinkAdapter: ProviderAdapter {
    let providerId = "spotify"
    let capabilities: ProviderCapabilitySet = [.media]
    let costClass: ProviderCostClass = .free

    func authorize(scopes: [ConsentScope]) async throws { }
    func refresh() async throws { }
    func revoke() async throws { }

    func fetch(request: ProviderRequest) async throws -> ProviderResponse {
        guard let spotifyURI = request.parameters["uri"] as? String,
              let url = URL(string: "spotify:\(spotifyURI)") else {
            throw IntegrationOSError.providerUnavailable(providerId)
        }
        await UIApplication.shared.open(url)
        return ProviderResponse(providerId: providerId, payload: ["opened": true], statusCode: 200)
    }

    func normalize(payload: ProviderResponse) throws -> ExternalUniversalObject {
        ExternalUniversalObject(
            id: UUID().uuidString,
            sourceProviderId: providerId,
            type: .mediaTrack,
            title: "Spotify Track",
            subtitle: nil,
            metadata: [:],
            fetchedAt: Date()
        )
    }

    func health() async -> ProviderHealthStatus {
        let canOpen = await UIApplication.shared.canOpenURL(URL(string: "spotify:")!)
        return canOpen ? .healthy : .unavailable
    }
}
